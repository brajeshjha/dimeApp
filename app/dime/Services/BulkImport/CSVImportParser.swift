import Foundation
import CoreXLSX   // SPM: https://github.com/CoreOffice/CoreXLSX

/// Parses CSV, XLSX, and XLS files into ImportedTransaction arrays.
///
/// # XLS support note
/// CoreXLSX only supports the modern Open XML (.xlsx) format.
/// True binary BIFF8 (.xls) files require a dedicated BIFF parser that is not
/// included in this implementation. However, many tools export `.xls` files
/// that are actually XML-based SpreadsheetML or plain TSV — those ARE handled
/// by the fallback text parser below. If a genuine BIFF binary is supplied, the
/// parser throws `ImportError.parseFailure` with an actionable message asking
/// the user to re-save the file as `.xlsx` or `.csv`.
final class CSVImportParser {

    // MARK: - FileType

    /// Explicit file type passed from FileImportService.
    enum FileType {
        case csv
        case xlsx   // Open XML — handled by CoreXLSX
        case xls    // Legacy — attempted via CoreXLSX first, then text fallback
    }

    // MARK: - Public entry point

    func parse(url: URL, fileType: FileType) throws -> [ImportedTransaction] {
        switch fileType {
        case .csv:
            return try parseCSV(url: url)
        case .xlsx:
            return try parseXLSX(url: url)
        case .xls:
            return try parseXLS(url: url)
        }
    }

    // MARK: - CSV

    private func parseCSV(url: URL) throws -> [ImportedTransaction] {
        // Try UTF-8 first, then fall back to ISO-8859-1 (common in bank exports)
        let raw: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            raw = utf8
        } else if let latin = try? String(contentsOf: url, encoding: .isoLatin1) {
            raw = latin
        } else {
            throw ImportError.unreadableFile
        }

        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.emptyFile
        }

        // Normalise line endings (\r\n, \r, \n)
        let normalised = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r",   with: "\n")

        let rows = normalised
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard rows.count > 1 else { throw ImportError.emptyFile }

        let headers = parseCSVRow(rows[0]).map { $0.lowercased() }
        let dataRows = rows.dropFirst().map { parseCSVRow($0) }
        // Invoice-aware dispatcher: returns one invoice expense or many bank rows
        return buildTransactions(headers: headers, dataRows: Array(dataRows))
    }

    /// RFC-4180 CSV row parser — handles quoted fields, escaped quotes ("").
    private func parseCSVRow(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var prevChar: Character = "\0"

        for char in line {
            if char == "\"" {
                if inQuotes && prevChar == "\"" {
                    // Escaped quote inside quoted field
                    current.append("\"")
                }
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
            prevChar = char
        }
        fields.append(current)
        return fields
    }

    // MARK: - XLSX (Open XML via CoreXLSX)

    private func parseXLSX(url: URL) throws -> [ImportedTransaction] {
        guard let file = XLSXFile(filepath: url.path) else {
            throw ImportError.unreadableFile
        }

        let workbooks: [Workbook]
        do { workbooks = try file.parseWorkbooks() }
        catch { throw ImportError.parseFailure("Could not read workbook: \(error.localizedDescription)") }

        guard let workbook = workbooks.first else {
            throw ImportError.parseFailure("No workbooks found in the file.")
        }

        guard
            let paths = try? file.parseWorksheetPathsAndNames(workbook: workbook),
            let firstPath = paths.first?.path
        else {
            throw ImportError.parseFailure("No worksheets found in the file.")
        }

        guard let ws = try? file.parseWorksheet(at: firstPath) else {
            throw ImportError.parseFailure("Could not read the first worksheet.")
        }

        // SharedStrings may be absent in files with only inline strings
        let sharedStrings = try? file.parseSharedStrings()

        let rows = ws.data?.rows ?? []
        guard rows.count > 1 else { throw ImportError.emptyFile }

        // Row index 0 → column headers
        let headers = rows[0].cells.map { cell -> String in
            cellStringValue(cell, sharedStrings: sharedStrings).lowercased()
        }

        let dataRows = rows.dropFirst().map { row in
            row.cells.map { cellStringValue($0, sharedStrings: sharedStrings) }
        }

        // Invoice-aware dispatcher: returns either one invoice expense or many bank rows
        return buildTransactions(headers: headers, dataRows: Array(dataRows))
    }

    /// Resolves a cell's display value, handling shared-string indices and inline strings.
    private func cellStringValue(_ cell: Cell, sharedStrings: SharedStrings?) -> String {
        // 1. Try shared strings first (most common for files with shared string table)
        if let ss = sharedStrings, let v = cell.stringValue(ss) { return v }
        // 2. Try inline strings (used by test fixtures and some Excel files)
        if let inlineStr = cell.inlineString?.text { return inlineStr }
        // 3. Fall back to numeric/date cells which store their value in `cell.value`
        return cell.value ?? ""
    }

    // MARK: - XLS (Legacy .xls — best-effort)

    /// Attempts to parse a `.xls` file using a three-step strategy:
    ///
    /// 1. Try CoreXLSX — succeeds for XML-based `.xls` (SpreadsheetML) files.
    /// 2. Try UTF-8 / Latin-1 text parse — succeeds for `.xls` files that are
    ///    actually tab-separated values or CSV saved with a `.xls` extension
    ///    (a very common Excel export pattern).
    /// 3. Throw `parseFailure` with an actionable message for true BIFF binaries.
    private func parseXLS(url: URL) throws -> [ImportedTransaction] {
        // Step 1: Try CoreXLSX (works for SpreadsheetML .xls)
        if let file = XLSXFile(filepath: url.path),
           let workbooks = try? file.parseWorkbooks(),
           let workbook = workbooks.first,
           let paths = try? file.parseWorksheetPathsAndNames(workbook: workbook),
           let firstPath = paths.first?.path,
           let ws = try? file.parseWorksheet(at: firstPath) {
            let sharedStrings = try? file.parseSharedStrings()
            let rows = ws.data?.rows ?? []
            if rows.count > 1 {
                let headers = rows[0].cells.map {
                    cellStringValue($0, sharedStrings: sharedStrings).lowercased()
                }
                let dataRows = rows.dropFirst().map { row in
                    row.cells.map { cellStringValue($0, sharedStrings: sharedStrings) }
                }
                // Invoice-aware dispatcher
                let txns = buildTransactions(headers: headers, dataRows: Array(dataRows))
                if !txns.isEmpty { return txns }
            }
        }

        // Step 2: Try SpreadsheetML XML format (Microsoft Excel XML)
        let xmlResult = try? parseSpreadsheetML(url: url)
        if let txns = xmlResult, !txns.isEmpty {
            return txns
        }

        // Step 3: Try reading as tab-separated or comma-separated plain text
        //         (Excel "Save As .xls" from older versions often produces TSV/HTML)
        let textResult = try? parseXLSAsText(url: url)
        if let txns = textResult, !txns.isEmpty {
            return txns
        }

        // Step 3: Binary BIFF format — cannot parse without a native library
        throw ImportError.parseFailure(
            "This .xls file uses an older binary format (BIFF) that cannot be read directly. " +
            "Please open it in Excel or Numbers and re-save as .xlsx or .csv, then import again."
        )
    }

    /// Reads a `.xls` file as plain text and attempts tab-separated or CSV parsing.
    /// Many `.xls` exports from web banking portals are actually HTML tables or TSV
    /// masquerading as `.xls`.
    private func parseXLSAsText(url: URL) throws -> [ImportedTransaction] {
        let raw: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            raw = utf8
        } else if let latin = try? String(contentsOf: url, encoding: .isoLatin1) {
            raw = latin
        } else {
            throw ImportError.unreadableFile
        }

        let normalised = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r",   with: "\n")

        // Strip HTML tags if file is an HTML table export
        let stripped = stripHTML(normalised)

        let lines = stripped
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count > 1 else { return [] }

        // Detect delimiter: tab or comma
        let delimiter: Character = lines[0].contains("\t") ? "\t" : ","
        let splitRow: (String) -> [String] = { line in
            line.components(separatedBy: String(delimiter))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        let headers = splitRow(lines[0]).map { $0.lowercased() }
        let dataRows = lines.dropFirst().map { splitRow($0) }
        // Invoice-aware dispatcher
        return buildTransactions(headers: headers, dataRows: Array(dataRows))
    }

    /// Removes HTML tags from a string (for HTML-table .xls exports).
    private func stripHTML(_ html: String) -> String {
        guard html.contains("<") else { return html }
        var result = html
        // Replace table-row/cell boundaries with tab/newline for structure
        result = result.replacingOccurrences(of: "</tr>", with: "\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "</td>", with: "\t", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "</th>", with: "\t", options: .caseInsensitive)
        // Strip all remaining tags
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>") {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        // Decode common HTML entities
        result = result
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#39;",  with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return result
    }

    /// Parses Microsoft Excel SpreadsheetML XML format (.xls files saved as XML).
    /// This handles the legacy XML format with <Workbook>, <Worksheet>, <Table>, <Row>, <Cell> structure.
    private func parseSpreadsheetML(url: URL) throws -> [ImportedTransaction] {
        guard let data = try? Data(contentsOf: url),
              let xmlString = String(data: data, encoding: .utf8) else {
            throw ImportError.unreadableFile
        }
        
        // Quick check if this is SpreadsheetML format
        guard xmlString.contains("urn:schemas-microsoft-com:office:spreadsheet") else {
            return []
        }
        
        let parser = SpreadsheetMLParser()
        guard let rows = parser.parse(xmlString: xmlString), !rows.isEmpty else {
            return []
        }
        
        // Find the header row - look for a row containing typical column names
        let headerKeywords = ["date", "description", "amount", "debit", "credit", 
                              "transaction", "merchant", "vendor", "balance"]
        var headerIndex: Int?
        
        for (i, row) in rows.enumerated() {
            let rowLower = row.map { $0.lowercased() }
            let matchCount = rowLower.filter { cell in
                headerKeywords.contains { cell.contains($0) }
            }.count
            
            // If at least 2 columns match header keywords, consider this the header row
            if matchCount >= 2 {
                headerIndex = i
                break
            }
        }
        
        guard let headerIdx = headerIndex, headerIdx < rows.count - 1 else {
            return []
        }
        
        let headers = rows[headerIdx].map { $0.lowercased() }
        let dataRows = Array(rows[(headerIdx + 1)...])
        
        return buildTransactions(headers: headers, dataRows: dataRows)
    }

    // MARK: - Invoice vs. Statement detection

    /// Returns true when the header row looks like an invoice rather than a bank statement.
    ///
    /// Invoice signals: columns named "invoice", "vendor", "supplier", "bill",
    /// "item", "qty", "quantity", "unit price", "subtotal", "tax", "due".
    /// Bank statement signals: "debit", "credit", "withdrawal", "deposit", "balance".
    ///
    /// We count hits for each side and return invoice=true when invoice signals
    /// outnumber bank signals.
    private func isInvoice(headers: [String]) -> Bool {
        let invoiceSignals = ["invoice", "vendor", "supplier", "bill to",
                              "item", "qty", "quantity", "unit price",
                              "subtotal", "tax", "due date", "amount due",
                              "grand total", "line total"]
        let bankSignals    = ["debit", "credit", "withdrawal", "deposit",
                              "balance", "transaction", "dr", "cr"]

        let joined = headers.joined(separator: " ")
        let invoiceHits = invoiceSignals.filter { joined.contains($0) }.count
        let bankHits    = bankSignals.filter    { joined.contains($0) }.count
        return invoiceHits > bankHits
    }

    // MARK: - Invoice parsing (XLSX / XLS)

    /// Collapses all rows of an invoice spreadsheet into a **single** expense transaction.
    ///
    /// Strategy:
    /// 1. Find the grand total — looks for a "total", "amount due", "grand total",
    ///    or "subtotal" column; if multiple rows have amounts, sums line items or
    ///    takes the last/largest value (whichever looks like a summary row).
    /// 2. Extract vendor from a "vendor", "supplier", "bill to", or "name" column,
    ///    or from an "invoice number" column as a fallback label.
    /// 3. Extract date from any "date", "invoice date", or "due date" column.
    /// 4. Returns a single `.expense` transaction with `notes: "Imported from invoice"`.
    private func parseInvoiceFromRows(headers: [String], dataRows: [[String]]) -> ImportedTransaction? {
        func value(inRow cols: [String], for keys: [String]) -> String? {
            for key in keys {
                if let idx = headers.firstIndex(where: { $0.contains(key) }),
                   idx < cols.count {
                    let v = cols[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !v.isEmpty { return v }
                }
            }
            return nil
        }

        // --- Grand total ---
        // Prefer a row that has a "total" or "amount due" label in any column,
        // otherwise sum all line-item amounts.
        let totalKeys = ["total", "amount due", "grand total", "invoice total",
                         "subtotal", "amount", "sum"]
        var grandTotal: Double = 0

        // First pass: look for a dedicated total row (where a label column says "total"
        // and an amount column has the number)
        for cols in dataRows {
            let rowText = cols.joined(separator: " ").lowercased()
            let isTotalRow = ["total", "amount due", "grand total", "invoice total"]
                .contains { rowText.contains($0) }
            if isTotalRow {
                // Pick the last numeric value in the row as the total
                for col in cols.reversed() {
                    if let v = parseAmount(col), v > 0 {
                        grandTotal = v
                        break
                    }
                }
                if grandTotal > 0 { break }
            }
        }

        // Second pass: if no explicit total row found, sum all amount/total column values
        if grandTotal == 0 {
            for cols in dataRows {
                if let amtStr = value(inRow: cols, for: totalKeys),
                   let v = parseAmount(amtStr), v > 0 {
                    grandTotal += v
                }
            }
        }

        guard grandTotal > 0 else { return nil }

        // --- Vendor ---
        var vendor = "Unknown Vendor"
        let vendorKeys = ["vendor", "supplier", "bill to", "sold to",
                          "company", "name", "from", "merchant"]
        for cols in dataRows {
            if let v = value(inRow: cols, for: vendorKeys), !v.isEmpty {
                vendor = v
                break
            }
        }
        // Fallback: use invoice number as part of title
        if vendor == "Unknown Vendor" {
            for cols in dataRows {
                if let inv = value(inRow: cols, for: ["invoice"]), !inv.isEmpty {
                    vendor = inv
                    break
                }
            }
        }

        // --- Date ---
        var invoiceDate = Date()
        let dateKeys = ["invoice date", "date", "issue date", "due date"]
        outer: for cols in dataRows {
            if let dateStr = value(inRow: cols, for: dateKeys),
               let d = parseDate(dateStr) {
                invoiceDate = d
                break outer
            }
        }

        return ImportedTransaction(
            title:  vendor,
            amount: grandTotal,
            date:   invoiceDate,
            type:   .expense,
            notes:  "Imported from invoice"
        )
    }

    // MARK: - Shared mapping logic

    /// Top-level dispatcher: given headers + all data rows, returns either
    /// bank-statement transactions (multiple) or a single invoice expense.
    private func buildTransactions(headers: [String], dataRows: [[String]]) -> [ImportedTransaction] {
        if isInvoice(headers: headers) {
            return parseInvoiceFromRows(headers: headers, dataRows: dataRows)
                .map { [$0] } ?? []
        }
        return dataRows.compactMap { cols in
            try? buildBankTransaction(headers: headers, cols: cols)
        }
    }

    /// Maps a single header+column row to a bank-statement `ImportedTransaction`.
    /// Supports the most common bank statement column name variations.
    private func buildBankTransaction(headers: [String], cols: [String]) throws -> ImportedTransaction? {
        func value(for keys: [String]) -> String? {
            for key in keys {
                if let idx = headers.firstIndex(where: { $0.contains(key) }),
                   idx < cols.count {
                    let v = cols[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !v.isEmpty { return v }
                }
            }
            return nil
        }

        // --- Amount resolution ---
        // Bank statements may have separate debit/credit columns OR a single amount column.
        let debitStr  = value(for: ["debit", "withdrawal", "payment", "dr"])
        let creditStr = value(for: ["credit", "deposit", "cr"])
        let amtStr    = value(for: ["amount", "sum", "value", "total"])

        let debitAmt  = debitStr.flatMap  { parseAmount($0) } ?? 0
        let creditAmt = creditStr.flatMap { parseAmount($0) } ?? 0
        let singleAmt = amtStr.flatMap    { parseAmount($0) }

        let amount: Double
        let type: ImportedTransaction.TransactionType

        if debitAmt > 0 {
            amount = debitAmt; type = .expense
        } else if creditAmt > 0 {
            amount = creditAmt; type = .income
        } else if let s = singleAmt {
            amount = abs(s)
            type   = s < 0 ? .expense : .income
        } else {
            return nil   // No recognisable amount → skip row
        }

        // --- Description ---
        let title = value(for: ["description", "merchant", "narration", "details", "payee", "memo"])
                    ?? value(for: ["name"]) ?? "Unknown"

        // --- Date ---
        let dateStr = value(for: ["date", "transaction date", "posted", "value date"])
        let date    = dateStr.flatMap { parseDate($0) } ?? Date()

        return ImportedTransaction(title: title, amount: amount, date: date, type: type)
    }

    // Keep the old name as a private shim so existing call sites inside
    // parseCSV / parseXLSAsText still compile unchanged.
    private func buildTransaction(headers: [String], cols: [String]) throws -> ImportedTransaction? {
        try buildBankTransaction(headers: headers, cols: cols)
    }

    // MARK: - Helpers

    /// Strips currency symbols, thousands separators and parses to Double.
    private func parseAmount(_ raw: String) -> Double? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "¥", with: "")
        return Double(cleaned)
    }

    private let dateFormatters: [DateFormatter] = {
        ["yyyy-MM-dd", "MM/dd/yyyy", "dd/MM/yyyy",
         "dd-MM-yyyy", "MM-dd-yyyy", "dd MMM yyyy",
         "MMM dd yyyy", "yyyyMMdd", "MM/dd/yy", "dd/MM/yy"].map { fmt in
            let df = DateFormatter()
            df.dateFormat = fmt
            df.locale = Locale(identifier: "en_US_POSIX")
            return df
        }
    }()

    private func parseDate(_ string: String) -> Date? {
        let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
        for fmt in dateFormatters {
            if let d = fmt.date(from: cleaned) { return d }
        }
        return nil
    }
}

// MARK: - SpreadsheetML XML Parser

/// Parses Microsoft Excel SpreadsheetML XML format using XMLParser.
/// This is a SAX-style parser that extracts rows and cells from the XML structure.
private class SpreadsheetMLParser: NSObject, XMLParserDelegate {
    private var rows: [[String]] = []
    private var currentRow: [String] = []
    private var currentCellData: String = ""
    private var isInCell = false
    private var isInData = false
    
    func parse(xmlString: String) -> [[String]]? {
        guard let data = xmlString.data(using: .utf8) else { return nil }
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return nil }
        return rows
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "Row":
            currentRow = []
        case "Cell":
            isInCell = true
            currentCellData = ""
        case "Data":
            isInData = true
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInData {
            currentCellData += string
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "Row":
            // Only add non-empty rows
            if !currentRow.isEmpty {
                rows.append(currentRow)
            }
        case "Cell":
            currentRow.append(currentCellData.trimmingCharacters(in: .whitespacesAndNewlines))
            isInCell = false
        case "Data":
            isInData = false
        default:
            break
        }
    }
}
