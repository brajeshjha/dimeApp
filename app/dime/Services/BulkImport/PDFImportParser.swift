import Foundation
import PDFKit

/// Parses PDF files — distinguishes bank statements from invoices.
final class PDFImportParser {

    func parse(url: URL) throws -> [ImportedTransaction] {
        guard let doc = PDFDocument(url: url) else {
            throw ImportError.unreadableFile
        }

        var fullText = ""
        for i in 0..<doc.pageCount {
            fullText += doc.page(at: i)?.string ?? ""
        }

        guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.emptyFile
        }

        if isBankStatement(text: fullText) {
            return parseBankStatement(text: fullText)
        } else {
            return parseInvoice(text: fullText)
        }
    }

    // MARK: - Detection

    private func isBankStatement(text: String) -> Bool {
        let statementKeywords = ["account statement", "bank statement",
                                 "account number", "opening balance",
                                 "closing balance", "transaction date",
                                 "debit", "credit", "withdrawal", "deposit"]
        let lower = text.lowercased()
        let matches = statementKeywords.filter { lower.contains($0) }.count
        return matches >= 2
    }

    // MARK: - Bank Statement

    /// Attempts to extract transaction lines from a bank statement PDF.
    /// Format heuristic: looks for lines containing a date pattern and a numeric amount.
    private func parseBankStatement(text: String) -> [ImportedTransaction] {
        var transactions: [ImportedTransaction] = []

        // Regex: date  ... description ... amount
        // Supports: "01/02/2024  Tesco  -25.00" or "2024-01-02  PAYPAL  500.00 CR"
        let pattern = #"(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}|\d{4}[\/\-]\d{2}[\/\-]\d{2})\s+(.+?)\s+([\-\+]?\d{1,3}(?:,\d{3})*(?:\.\d{2})?)\s*(CR|DR|credit|debit)?"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            guard match.numberOfRanges >= 4 else { continue }

            let dateStr  = nsText.substring(with: match.range(at: 1))
            let desc     = nsText.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let amtStr   = nsText.substring(with: match.range(at: 3))
                .replacingOccurrences(of: ",", with: "")
            let qualifier = match.range(at: 4).location != NSNotFound
                            ? nsText.substring(with: match.range(at: 4)).lowercased()
                            : ""

            guard let amount = Double(amtStr) else { continue }

            let type: ImportedTransaction.TransactionType
            if qualifier.contains("cr") || qualifier.contains("credit") {
                type = .income
            } else if qualifier.contains("dr") || qualifier.contains("debit") {
                type = .expense
            } else {
                type = amount < 0 ? .expense : .income
            }

            let date = parseDate(dateStr) ?? Date()

            transactions.append(ImportedTransaction(
                title:  desc.isEmpty ? "Unknown" : desc,
                amount: abs(amount),
                date:   date,
                type:   type
            ))
        }

        return transactions
    }

    // MARK: - Invoice

    private func parseInvoice(text: String) -> [ImportedTransaction] {
        let lower = text.lowercased()

        // Extract amount — look for "total", "amount due", "grand total"
        let amountPatterns = [
            #"(?:total|amount due|grand total|invoice total)[:\s]+[\$£€]?\s*([\d,]+\.?\d{0,2})"#,
            #"[\$£€]\s*([\d,]+\.?\d{0,2})"#
        ]

        var amount: Double = 0
        for pattern in amountPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: lower) {
                let raw = String(lower[range]).replacingOccurrences(of: ",", with: "")
                if let v = Double(raw), v > 0 { amount = v; break }
            }
        }

        // Extract vendor name — first meaningful non-numeric line
        let vendor = extractVendor(from: text)

        // Extract date
        let datePattern = #"(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})"#
        var invoiceDate = Date()
        if let regex = try? NSRegularExpression(pattern: datePattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            invoiceDate = parseDate(String(text[range])) ?? Date()
        }

        guard amount > 0 else { return [] }

        return [ImportedTransaction(
            title:  vendor,
            amount: amount,
            date:   invoiceDate,
            type:   .expense,
            notes:  "Imported from invoice"
        )]
    }

    private func extractVendor(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines.prefix(10) {
            // Skip lines that are only numbers, dates, or very short
            if line.count > 3
               && !line.allSatisfy({ $0.isNumber || $0 == "/" || $0 == "-" || $0 == " " }) {
                return line
            }
        }
        return "Unknown Vendor"
    }

    // MARK: - Date

    private let dateFormatters: [DateFormatter] = {
        ["MM/dd/yyyy", "dd/MM/yyyy", "yyyy-MM-dd", "dd-MM-yyyy", "MM-dd-yyyy"].map { fmt in
            let df = DateFormatter()
            df.dateFormat = fmt
            df.locale = Locale(identifier: "en_US_POSIX")
            return df
        }
    }()

    private func parseDate(_ s: String) -> Date? {
        for df in dateFormatters {
            if let d = df.date(from: s) { return d }
        }
        return nil
    }
}