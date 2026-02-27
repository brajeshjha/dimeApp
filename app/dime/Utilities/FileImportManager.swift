//
//  FileImportManager.swift
//  dime
//
//  Created for bulk import feature
//

import Foundation
import UniformTypeIdentifiers
import PDFKit

class FileImportManager {
    
    /// Parse a file and return imported transactions
    static func parseFile(from url: URL) async -> FileImportResult {
        // Start accessing security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Determine file type from extension
        let fileExtension = url.pathExtension.lowercased()
        
        let result: FileImportResult
        switch fileExtension {
        case "csv":
            result = await parseCSV(from: url)
        case "xlsx", "xls":
            result = await parseExcel(from: url)
        case "pdf":
            result = await parsePDF(from: url)
        default:
            result = .failure(.unsupportedFileType)
        }
        
        return result
    }
    
    // MARK: - CSV Parser
    
    private static func parseCSV(from url: URL) async -> FileImportResult {
        do {
            // Read file contents
            let contents = try String(contentsOf: url, encoding: .utf8)
            let lines = contents.components(separatedBy: .newlines).filter { 
                !$0.trimmingCharacters(in: .whitespaces).isEmpty 
            }
            
            guard lines.count > 0 else {
                return .failure(.noDataFound)
            }
            
            var transactions: [ImportedTransaction] = []
            
            // Try each line as a potential transaction
            for (index, line) in lines.enumerated() {
                let columns = parseCSVLine(line)
                
                // Skip lines with too few columns
                if columns.count < 2 {
                    continue
                }
                
                // Try to parse as transaction
                if let transaction = parseLineAsTransaction(columns: columns, lineNumber: index) {
                    transactions.append(transaction)
                }
            }
            
            if transactions.isEmpty {
                return .failure(.parsingError("Could not find any valid transactions. Please ensure your CSV has columns for date, description, and amount."))
            }
            
            return .success(transactions)
            
        } catch {
            return .failure(.fileReadError)
        }
    }
    
    private static func parseLineAsTransaction(columns: [String], lineNumber: Int) -> ImportedTransaction? {
        // Skip header lines
        let firstCol = columns[0].lowercased()
        if firstCol.contains("date") || firstCol.contains("transaction") || firstCol.contains("description") || 
           firstCol.contains("debit") || firstCol.contains("credit") {
            return nil
        }
        
        // Try to find date column
        var dateCol: Int? = nil
        var date: Date? = nil
        
        for (index, column) in columns.enumerated() {
            if let parsedDate = parseDate(from: column) {
                dateCol = index
                date = parsedDate
                break
            }
        }
        
        guard let transactionDate = date, let dateIndex = dateCol else {
            return nil
        }
        
        // Try to find amount columns
        var amounts: [(index: Int, value: Double)] = []
        for (index, column) in columns.enumerated() {
            if index == dateIndex {
                continue
            }
            
            if let amount = parseAmount(from: column) {
                amounts.append((index, amount))
            }
        }
        
        guard !amounts.isEmpty else {
            return nil
        }
        
        // Determine description (text column that's not date or amount)
        var description = ""
        for (index, column) in columns.enumerated() {
            if index == dateIndex {
                continue
            }
            if amounts.contains(where: { $0.index == index }) {
                continue
            }
            let trimmed = column.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && trimmed.count > 1 {
                description += trimmed + " "
            }
        }
        description = description.trimmingCharacters(in: .whitespaces)
        
        if description.isEmpty {
            description = "Transaction"
        }
        
        // Determine if income or expense
        // If there are 2 amount columns, likely debit and credit
        if amounts.count >= 2 {
            // Sort by column index to maintain order
            let sortedAmounts = amounts.sorted { $0.index < $1.index }
            let first = sortedAmounts[0].value
            let second = sortedAmounts[1].value
            
            // One column should be 0 or empty, the other has the amount
            if first > 0.01 && second < 0.01 {
                // First column has amount (usually debit = expense)
                return ImportedTransaction(date: transactionDate, amount: first, note: description, isIncome: false)
            } else if second > 0.01 && first < 0.01 {
                // Second column has amount (usually credit = income)
                return ImportedTransaction(date: transactionDate, amount: second, note: description, isIncome: true)
            } else if first > 0.01 {
                // Both have values, use first as expense
                return ImportedTransaction(date: transactionDate, amount: first, note: description, isIncome: false)
            } else if second > 0.01 {
                // Only second has value
                return ImportedTransaction(date: transactionDate, amount: second, note: description, isIncome: true)
            }
        } else if let firstAmount = amounts.first {
            // Single amount column - check for negative or look for income keywords
            let lowerDesc = description.lowercased()
            let isIncome = lowerDesc.contains("credit") || lowerDesc.contains("deposit") || 
                          lowerDesc.contains("income") || lowerDesc.contains("salary")
            
            return ImportedTransaction(date: transactionDate, amount: firstAmount.value, note: description, isIncome: isIncome)
        }
        
        return nil
    }
    
    private static func parseCSVLine(_ line: String) -> [String] {
        var columns: [String] = []
        var currentColumn = ""
        var insideQuotes = false
        
        for char in line {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                columns.append(currentColumn.trimmingCharacters(in: .whitespaces))
                currentColumn = ""
            } else {
                currentColumn.append(char)
            }
        }
        columns.append(currentColumn.trimmingCharacters(in: .whitespaces))
        
        return columns
    }
    
    // MARK: - Excel Parser
    
    private static func parseExcel(from url: URL) async -> FileImportResult {
        // Try multiple approaches to read Excel files
        
        // Approach 1: Try reading as UTF-8 text
        if let contents = try? String(contentsOf: url, encoding: .utf8), !contents.isEmpty {
            if contents.contains("\t") {
                let result = await parseTSV(contents: contents)
                if case .success = result {
                    return result
                }
            }
            if contents.contains(",") {
                let result = await parseCSVContents(contents: contents)
                if case .success = result {
                    return result
                }
            }
        }
        
        // Approach 2: Try UTF-16
        if let contents = try? String(contentsOf: url, encoding: .utf16), !contents.isEmpty {
            if contents.contains("\t") {
                let result = await parseTSV(contents: contents)
                if case .success = result {
                    return result
                }
            }
            if contents.contains(",") {
                let result = await parseCSVContents(contents: contents)
                if case .success = result {
                    return result
                }
            }
        }
        
        // Approach 3: Try reading as Data and convert
        if let data = try? Data(contentsOf: url) {
            // Try different encodings
            let encodings: [String.Encoding] = [.utf8, .utf16, .ascii, .isoLatin1, .windowsCP1252]
            
            for encoding in encodings {
                if let contents = String(data: data, encoding: encoding), !contents.isEmpty {
                    if contents.contains("\t") {
                        let result = await parseTSV(contents: contents)
                        if case .success = result {
                            return result
                        }
                    }
                    if contents.contains(",") {
                        let result = await parseCSVContents(contents: contents)
                        if case .success = result {
                            return result
                        }
                    }
                }
            }
        }
        
        // If all attempts fail, suggest CSV export
        return .failure(.parsingError("Could not read Excel file. Please export your Excel file as CSV (.csv) and try again."))
    }
    
    private static func parseTSV(contents: String) async -> FileImportResult {
        let lines = contents.components(separatedBy: .newlines).filter { 
            !$0.trimmingCharacters(in: .whitespaces).isEmpty 
        }
        
        guard lines.count > 0 else {
            return .failure(.noDataFound)
        }
        
        var transactions: [ImportedTransaction] = []
        
        for line in lines {
            let columns = line.components(separatedBy: "\t").map { 
                $0.trimmingCharacters(in: .whitespaces) 
            }
            
            if let transaction = parseLineAsTransaction(columns: columns, lineNumber: 0) {
                transactions.append(transaction)
            }
        }
        
        if transactions.isEmpty {
            return .failure(.noDataFound)
        }
        
        return .success(transactions)
    }
    
    private static func parseCSVContents(contents: String) async -> FileImportResult {
        let lines = contents.components(separatedBy: .newlines).filter { 
            !$0.trimmingCharacters(in: .whitespaces).isEmpty 
        }
        
        guard lines.count > 0 else {
            return .failure(.noDataFound)
        }
        
        var transactions: [ImportedTransaction] = []
        
        for line in lines {
            let columns = parseCSVLine(line)
            
            if let transaction = parseLineAsTransaction(columns: columns, lineNumber: 0) {
                transactions.append(transaction)
            }
        }
        
        if transactions.isEmpty {
            return .failure(.noDataFound)
        }
        
        return .success(transactions)
    }
    
    // MARK: - PDF Parser
    
    private static func parsePDF(from url: URL) async -> FileImportResult {
        guard let pdfDocument = PDFDocument(url: url) else {
            return .failure(.fileReadError)
        }
        
        var fullText = ""
        for i in 0..<pdfDocument.pageCount {
            if let page = pdfDocument.page(at: i) {
                if let text = page.string {
                    fullText += text + "\n"
                }
            }
        }
        
        // Try to parse as bank statement first
        let statementResult = parseStatementPDF(text: fullText)
        if case .success = statementResult {
            return statementResult
        }
        
        // Try to parse as invoice
        return parseInvoicePDF(text: fullText)
    }
    
    private static func parseInvoicePDF(text: String) -> FileImportResult {
        var totalAmount: Double? = nil
        var invoiceDate: Date? = nil
        var vendor = ""
        
        let lines = text.components(separatedBy: .newlines)
        
        // Look for total amount
        for line in lines {
            let lowerLine = line.lowercased()
            
            if (lowerLine.contains("total") || lowerLine.contains("amount") || lowerLine.contains("balance")) && totalAmount == nil {
                if let amount = extractAmount(from: line) {
                    totalAmount = amount
                }
            }
            
            if lowerLine.contains("date") && invoiceDate == nil {
                if let date = extractDateFromLine(line) {
                    invoiceDate = date
                }
            }
            
            // Try to extract vendor from first few non-empty lines
            if vendor.isEmpty {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.count > 3 && trimmed.count < 100 && !lowerLine.contains("invoice") && !lowerLine.contains("date") {
                    vendor = trimmed
                }
            }
        }
        
        guard let amount = totalAmount else {
            return .failure(.parsingError("Could not find amount in PDF. Please try exporting as CSV."))
        }
        
        let date = invoiceDate ?? Date()
        let note = vendor.isEmpty ? "Invoice" : vendor
        
        let transaction = ImportedTransaction(
            date: date,
            amount: amount,
            note: note,
            isIncome: false
        )
        
        return .success([transaction])
    }
    
    private static func parseStatementPDF(text: String) -> FileImportResult {
        let lines = text.components(separatedBy: .newlines)
        var transactions: [ImportedTransaction] = []
        
        // Try to find transaction table in the PDF
        var inTransactionSection = false
        
        for line in lines {
            // Skip empty and very short lines
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.count < 5 {
                continue
            }
            
            let lowerLine = trimmed.lowercased()
            
            // Detect start of transaction section
            if lowerLine.contains("date") && (lowerLine.contains("description") || lowerLine.contains("particulars") || lowerLine.contains("debit") || lowerLine.contains("credit")) {
                inTransactionSection = true
                continue
            }
            
            // Detect end of transaction section
            if lowerLine.contains("total") || lowerLine.contains("balance") || lowerLine.contains("summary") {
                if !transactions.isEmpty {
                    break
                }
            }
            
            // Try to parse line as transaction
            if let date = extractDateFromLine(line) {
                if let amount = extractAmount(from: line) {
                    // Determine if income or expense
                    // Look for keywords or column position
                    let isIncome = lowerLine.contains("credit") || 
                                   lowerLine.contains("deposit") || 
                                   lowerLine.contains("cr ") ||
                                   lowerLine.contains(" cr")
                    
                    // Extract description by removing date and amount
                    var description = line
                    
                    // Try to remove date string
                    let words = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    var descWords: [String] = []
                    
                    for word in words {
                        // Skip if it's a date
                        if parseDate(from: word) != nil {
                            continue
                        }
                        // Skip if it's an amount
                        if parseAmount(from: word) != nil {
                            continue
                        }
                        // Skip common keywords
                        if word.lowercased() == "cr" || word.lowercased() == "dr" || 
                           word.lowercased() == "debit" || word.lowercased() == "credit" {
                            continue
                        }
                        descWords.append(word)
                    }
                    
                    description = descWords.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    
                    if description.isEmpty {
                        description = isIncome ? "Deposit" : "Withdrawal"
                    }
                    
                    transactions.append(ImportedTransaction(
                        date: date,
                        amount: amount,
                        note: description,
                        isIncome: isIncome
                    ))
                }
            }
        }
        
        if transactions.isEmpty {
            return .failure(.noDataFound)
        }
        
        return .success(transactions)
    }
    
    // MARK: - Helper Functions
    
    private static func parseDate(from string: String) -> Date? {
        let cleaned = string.trimmingCharacters(in: .whitespaces)
        
        // Try 4-digit year formats first
        let dateFormats4Digit = [
            "yyyy-MM-dd",
            "MM/dd/yyyy",
            "dd/MM/yyyy",
            "dd-MM-yyyy",
            "MM-dd-yyyy",
            "yyyy/MM/dd",
            "dd.MM.yyyy",
            "MMM dd, yyyy",
            "dd MMM yyyy",
            "d/M/yyyy",
            "M/d/yyyy",
            "d-M-yyyy",
            "M-d-yyyy",
            "MMM d, yyyy",
            "d MMM, yyyy"
        ]
        
        for format in dateFormats4Digit {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = formatter.date(from: cleaned) {
                return date
            }
        }
        
        // Try 2-digit year formats
        let dateFormats2Digit = [
            "dd/MM/yy",
            "MM/dd/yy",
            "dd-MM-yy",
            "MM-dd-yy",
            "d/M/yy",
            "M/d/yy",
            "dd.MM.yy",
            "MMM dd, yy",
            "dd MMM yy",
            "d MMM yy"
        ]
        
        for format in dateFormats2Digit {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            // For 2-digit years, assume current century
            formatter.defaultDate = Date()
            if let date = formatter.date(from: cleaned) {
                // Adjust for proper century (assume 00-30 = 2000s, 31-99 = 1900s)
                let calendar = Calendar.current
                let year = calendar.component(.year, from: date)
                if year < 100 {
                    // This shouldn't happen with proper formatter, but just in case
                    let adjustedYear = year < 31 ? 2000 + year : 1900 + year
                    var components = calendar.dateComponents([.month, .day], from: date)
                    components.year = adjustedYear
                    if let adjustedDate = calendar.date(from: components) {
                        return adjustedDate
                    }
                }
                return date
            }
        }
        
        return nil
    }
    
    private static func parseAmount(from string: String) -> Double? {
        // Remove common currency symbols and whitespace
        var cleaned = string.trimmingCharacters(in: .whitespaces)
        
        // If empty or just whitespace, return nil
        if cleaned.isEmpty {
            return nil
        }
        
        cleaned = cleaned.replacingOccurrences(of: "$", with: "")
        cleaned = cleaned.replacingOccurrences(of: "€", with: "")
        cleaned = cleaned.replacingOccurrences(of: "£", with: "")
        cleaned = cleaned.replacingOccurrences(of: "¥", with: "")
        cleaned = cleaned.replacingOccurrences(of: "₹", with: "")
        cleaned = cleaned.replacingOccurrences(of: " ", with: "")
        
        // Handle parentheses (negative numbers)
        let isNegative = cleaned.contains("(") || cleaned.contains("-")
        cleaned = cleaned.replacingOccurrences(of: "(", with: "")
        cleaned = cleaned.replacingOccurrences(of: ")", with: "")
        cleaned = cleaned.replacingOccurrences(of: "-", with: "")
        
        // Remove commas
        cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        
        // If nothing left, return nil (was likely just currency symbol or dash)
        if cleaned.isEmpty {
            return nil
        }
        
        // Try to parse as double
        if let amount = Double(cleaned) {
            // Accept 0 as valid, but return nil for negative
            return amount >= 0 ? amount : nil
        }
        
        return nil
    }
    
    private static func extractAmount(from text: String) -> Double? {
        // Find all potential amounts in the text
        let pattern = "[\\$€£¥₹]?\\s*[\\(\\-]?[0-9,]+\\.?[0-9]*[\\)]?"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = text as NSString
            let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            
            var maxAmount: Double = 0
            
            for result in results {
                let matchString = nsString.substring(with: result.range)
                if let amount = parseAmount(from: matchString), amount > maxAmount {
                    maxAmount = amount
                }
            }
            
            if maxAmount > 0 {
                return maxAmount
            }
        }
        return nil
    }
    
    private static func extractDateFromLine(_ line: String) -> Date? {
        // Try to find a date in the line
        let words = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        for word in words {
            if let date = parseDate(from: word) {
                return date
            }
        }
        
        // Try combinations of 2-3 words
        for i in 0..<words.count-1 {
            let twoWords = words[i] + " " + words[i+1]
            if let date = parseDate(from: twoWords) {
                return date
            }
        }
        
        for i in 0..<words.count-2 {
            let threeWords = words[i] + " " + words[i+1] + " " + words[i+2]
            if let date = parseDate(from: threeWords) {
                return date
            }
        }
        
        return nil
    }
    
    private static func formatDateForRemoval(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
