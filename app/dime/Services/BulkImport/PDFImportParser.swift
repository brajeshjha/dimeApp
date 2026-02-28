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
        var transactionCount = 0
        
        // Split into lines and process each line
        let lines = text.components(separatedBy: "\n")
        
        for line in lines {
            // Skip empty lines and header lines
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            // Look for date pattern anywhere in the line (not just at start)
            guard let dateMatch = try? NSRegularExpression(pattern: #"(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}|\d{4}[\/\-]\d{2}[\/\-]\d{2})"#)
                .firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let dateRange = Range(dateMatch.range(at: 1), in: line) else {
                continue
            }
            
            let dateStr = String(line[dateRange])
            
            // Extract everything after the date (don't trim yet - we need spacing info)
            let afterDate = String(line[dateRange.upperBound...])
            
            // Find all numbers in the line (potential amounts)
            let numberPattern = #"([\-\+]?\d{1,3}(?:,\d{3})*(?:\.\d{2})?)"#
            guard let numberRegex = try? NSRegularExpression(pattern: numberPattern) else {
                continue
            }
            let numbers = numberRegex.matches(in: afterDate, range: NSRange(afterDate.startIndex..., in: afterDate))
            guard !numbers.isEmpty else {
                continue
            }
            
            // The first number is usually the debit or credit amount, not the balance
            let firstNumber = numbers[0]
            guard let amountRange = Range(firstNumber.range(at: 1), in: afterDate) else { continue }
            let amtStr = String(afterDate[amountRange]).replacingOccurrences(of: ",", with: "")
            guard let amount = Double(amtStr) else { continue }
            
            // Extract description (everything between date and first number)
            let descEnd = amountRange.lowerBound
            let descriptionRaw = String(afterDate[..<descEnd])
            let description = descriptionRaw.trimmingCharacters(in: .whitespaces)
            
            // Determine transaction type based on spacing and position
            // In bank statements with "Debit Credit Balance" columns:
            // - Debit column appears first (shorter spacing before number)
            // - Credit column appears later (more spacing before number)
            let type: ImportedTransaction.TransactionType
            
            if amount < 0 {
                // Negative amounts are always expenses
                type = .expense
            } else if numbers.count >= 2 {
                // Multiple numbers suggest "Debit Credit Balance" format
                // Analyze the spacing to determine which column the first number is in
                let firstNumRange = amountRange
                let firstNumPosition = afterDate.distance(from: afterDate.startIndex, to: firstNumRange.lowerBound)
                
                if let secondNumRange = Range(numbers[1].range(at: 1), in: afterDate) {
                    // Calculate gap between first and second number
                    let gapBetweenNumbers = afterDate.distance(from: firstNumRange.upperBound, to: secondNumRange.lowerBound)
                    
                    // Heuristic: In "Debit Credit Balance" format:
                    // - Large gap between numbers suggests: first=debit(expense), last=balance
                    //   Example: "25.00             475.00" (many spaces)
                    // - Small gap suggests: first=credit(income), last=balance
                    //   Example: "3000.00  3475.00" (few spaces)
                    // Use threshold of 4 spaces to distinguish
                    type = gapBetweenNumbers > 4 ? .expense : .income
                } else {
                    // Fallback: use first number position
                    type = firstNumPosition > 35 ? .income : .expense
                }
            } else {
                // Single number - analyze position to guess column
                let firstNumPosition = afterDate.distance(from: afterDate.startIndex, to: amountRange.lowerBound)
                // If number appears late in line, likely in credit column
                type = firstNumPosition > 35 ? .income : .expense
            }

            let date = parseDate(dateStr) ?? Date()

            transactions.append(ImportedTransaction(
                title:  description.isEmpty ? "Unknown" : description,
                amount: abs(amount),
                date:   date,
                type:   type
            ))
            transactionCount += 1
        }
        
        // Fallback: if we found exactly 2 transactions and couldn't determine types reliably,
        // assume first is expense (debit) and second is income (credit) for bank statements
        if transactions.count == 2 {
            // Check if our heuristics gave us both types or same type twice
            let hasExpense = transactions.contains { $0.type == .expense }
            let hasIncome = transactions.contains { $0.type == .income }
            
            if !hasExpense || !hasIncome {
                // We don't have both types - apply fallback rule
                transactions[0] = ImportedTransaction(
                    title: transactions[0].title,
                    amount: transactions[0].amount,
                    date: transactions[0].date,
                    type: .expense
                )
                transactions[1] = ImportedTransaction(
                    title: transactions[1].title,
                    amount: transactions[1].amount,
                    date: transactions[1].date,
                    type: .income
                )
            }
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
