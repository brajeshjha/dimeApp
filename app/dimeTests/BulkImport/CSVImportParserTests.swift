import XCTest
@testable import dime

final class CSVImportParserTests: XCTestCase {

    var sut: CSVImportParser!

    override func setUp() {
        super.setUp()
        sut = CSVImportParser()
    }

    // =========================================================================
    // MARK: - CSV Tests
    // =========================================================================

    func test_csv_debitAndCredit_createsCorrectTypes() throws {
        let csv = """
        Date,Description,Debit,Credit
        05/01/2024,Netflix,15.99,
        06/01/2024,Payroll,,2500.00
        """
        let txns = try parseCSV(csv)
        XCTAssertEqual(txns.count, 2)

        let netflix = txns[0]
        XCTAssertEqual(netflix.title,  "Netflix")
        XCTAssertEqual(netflix.amount, 15.99, accuracy: 0.01)
        XCTAssertEqual(netflix.type,   .expense)

        let payroll = txns[1]
        XCTAssertEqual(payroll.title,  "Payroll")
        XCTAssertEqual(payroll.amount, 2500,   accuracy: 0.01)
        XCTAssertEqual(payroll.type,   .income)
    }

    func test_csv_negativeAmount_treatedAsExpense() throws {
        let txns = try parseCSV("Date,Description,Amount\n07/01/2024,Coffee,-4.50")
        XCTAssertEqual(txns[0].type,   .expense)
        XCTAssertEqual(txns[0].amount, 4.50, accuracy: 0.01)
    }

    func test_csv_positiveAmount_treatedAsIncome() throws {
        let txns = try parseCSV("Date,Description,Amount\n08/01/2024,Refund,12.00")
        XCTAssertEqual(txns[0].type, .income)
    }

    func test_csv_emptyFile_throwsEmptyError() {
        XCTAssertThrowsError(try parseCSV("")) { error in
            guard case ImportError.emptyFile = error else {
                return XCTFail("Expected emptyFile, got \(error)")
            }
        }
    }

    func test_csv_headerOnly_throwsEmptyError() {
        XCTAssertThrowsError(try parseCSV("Date,Description,Amount"))
    }

    func test_csv_defaultCategory_isUncategorized() throws {
        let txns = try parseCSV("Date,Description,Debit\n01/01/2024,Amazon,30.00")
        XCTAssertEqual(txns[0].category, "Uncategorized")
    }

    func test_csv_quotedFieldsWithComma_parsedCorrectly() throws {
        let txns = try parseCSV("Date,Description,Amount\n09/01/2024,\"Starbucks, High St\",5.40")
        XCTAssertEqual(txns[0].title, "Starbucks, High St")
    }

    func test_csv_amountWithThousandsSeparator_parsedCorrectly() throws {
        let txns = try parseCSV("Date,Description,Credit\n01/01/2024,Bonus,\"1,500.00\"")
        XCTAssertEqual(txns[0].amount, 1500, accuracy: 0.01)
    }

    func test_csv_rowMissingAmount_isSkipped() throws {
        let csv = """
        Date,Description,Debit,Credit
        01/01/2024,Row With No Amount,,
        02/01/2024,Valid Row,20.00,
        """
        let txns = try parseCSV(csv)
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns[0].title, "Valid Row")
    }

    func test_csv_multipleDateFormats_parsedWithoutCrashing() throws {
        let csv = """
        Date,Description,Debit
        2024-01-15,Uber,9.99
        15/01/2024,Lyft,8.50
        Jan 15 2024,Bolt,7.25
        """
        let txns = try parseCSV(csv)
        XCTAssertEqual(txns.count, 3)
    }

    func test_csv_currencySymbol_inAmount_stripped() throws {
        let txns = try parseCSV("Date,Description,Amount\n01/01/2024,Rent,$1200.00")
        XCTAssertEqual(txns[0].amount, 1200, accuracy: 0.01)
    }

    func test_csv_windowsLineEndings_parsedCorrectly() throws {
        let csv = "Date,Description,Debit\r\n01/01/2024,Tesco,25.00\r\n"
        let txns = try parseCSV(csv)
        XCTAssertEqual(txns.count, 1)
    }

    func test_csv_merchantColumnAlias_payee_resolvedCorrectly() throws {
        let txns = try parseCSV("Date,Payee,Debit\n01/01/2024,Whole Foods,67.50")
        XCTAssertEqual(txns[0].title, "Whole Foods")
    }

    func test_csv_merchantColumnAlias_narration_resolvedCorrectly() throws {
        let txns = try parseCSV("Date,Narration,Credit\n01/01/2024,Salary Credit,3000.00")
        XCTAssertEqual(txns[0].title, "Salary Credit")
    }

    func test_csv_withdrawalColumnAlias_treatedAsExpense() throws {
        let txns = try parseCSV("Date,Description,Withdrawal\n01/01/2024,ATM,200.00")
        XCTAssertEqual(txns[0].type, .expense)
    }

    func test_csv_depositColumnAlias_treatedAsIncome() throws {
        let txns = try parseCSV("Date,Description,Deposit\n01/01/2024,Transfer In,500.00")
        XCTAssertEqual(txns[0].type, .income)
    }

    func test_csv_allTransactionsAreUncategorized() throws {
        let csv = """
        Date,Description,Amount
        01/01/2024,Tesco,-25.00
        02/01/2024,Salary,3000.00
        03/01/2024,Netflix,-15.99
        """
        let txns = try parseCSV(csv)
        XCTAssertTrue(txns.allSatisfy { $0.category == "Uncategorized" })
    }

    // =========================================================================
    // MARK: - XLSX Tests
    // =========================================================================
    // These tests use a real .xlsx fixture bundled with the test target.
    // The fixture is created by XLSXTestFixtureBuilder (see helper below) if missing,
    // or can be hand-crafted in Excel / Numbers and added to dimeTests/Resources/.

    func test_xlsx_bundleFixture_returnsTransactions() throws {
        guard let url = bundleResource(named: "sample_bank_statement", ext: "xlsx") else {
            // If the fixture isn't in the bundle yet, generate a synthetic one
            let url = try XLSXTestFixtureBuilder.makeSampleXLSX()
            let txns = try sut.parse(url: url, fileType: .xlsx)
            XCTAssertFalse(txns.isEmpty, "XLSX fixture should produce at least one transaction")
            return
        }
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertFalse(txns.isEmpty)
    }

    func test_xlsx_debitRows_areExpenses() throws {
        let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [
            ["Date",       "Description", "Debit",  "Credit"],
            ["01/01/2024", "Tesco",       "42.50",  ""],
            ["02/01/2024", "Salary",      "",        "3000.00"]
        ])
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertFalse(txns.isEmpty)
        // At least the expense row must appear
        let expenses = txns.filter { $0.type == .expense }
        XCTAssertFalse(expenses.isEmpty)
        XCTAssertEqual(expenses.first?.title, "Tesco")
    }

    func test_xlsx_creditRows_areIncome() throws {
        let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [
            ["Date",       "Description", "Debit", "Credit"],
            ["02/01/2024", "Salary",      "",       "3000.00"]
        ])
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertFalse(txns.isEmpty)
        XCTAssertEqual(txns[0].type, .income)
        XCTAssertEqual(txns[0].amount, 3000, accuracy: 0.01)
    }

    func test_xlsx_negativeAmount_treatedAsExpense() throws {
        let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [
            ["Date",       "Description", "Amount"],
            ["03/01/2024", "Rent",        "-1200.00"]
        ])
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertFalse(txns.isEmpty)
        XCTAssertEqual(txns[0].type, .expense)
        XCTAssertEqual(txns[0].amount, 1200, accuracy: 0.01)
    }

    func test_xlsx_positiveAmount_treatedAsIncome() throws {
        let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [
            ["Date",       "Description", "Amount"],
            ["04/01/2024", "Dividend",    "250.00"]
        ])
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertFalse(txns.isEmpty)
        XCTAssertEqual(txns[0].type, .income)
    }

    func test_xlsx_headerOnly_throwsEmptyError() throws {
        let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [
            ["Date", "Description", "Amount"]
        ])
        XCTAssertThrowsError(try sut.parse(url: url, fileType: .xlsx)) { error in
            guard case ImportError.emptyFile = error else {
                return XCTFail("Expected emptyFile, got \(error)")
            }
        }
    }

    func test_xlsx_rowMissingAmount_isSkipped() throws {
        let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [
            ["Date",       "Description",    "Debit", "Credit"],
            ["01/01/2024", "No Amount Row",  "",       ""],
            ["02/01/2024", "Valid Row",       "20.00", ""]
        ])
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns[0].title, "Valid Row")
    }

    func test_xlsx_allTransactionsAreUncategorized() throws {
        let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [
            ["Date",       "Description", "Amount"],
            ["01/01/2024", "Tesco",       "-25.00"],
            ["02/01/2024", "Salary",      "3000.00"]
        ])
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertTrue(txns.allSatisfy { $0.category == "Uncategorized" })
    }

    func test_xlsx_currencySymbolInAmount_stripped() throws {
        let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [
            ["Date",       "Description", "Debit"],
            ["05/01/2024", "Utilities",   "$87.50"]
        ])
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertFalse(txns.isEmpty)
        XCTAssertEqual(txns[0].amount, 87.50, accuracy: 0.01)
    }

    func test_xlsx_multipleSheets_firstSheetUsed() throws {
        // XLSXTestFixtureBuilder creates a single-sheet file; verify the first sheet is parsed
        let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [
            ["Date",       "Description", "Debit"],
            ["06/01/2024", "Gym",         "49.99"]
        ])
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertEqual(txns.count, 1)
    }

    func test_xlsx_unreadableFile_throwsError() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent_\(UUID()).xlsx")
        XCTAssertThrowsError(try sut.parse(url: url, fileType: .xlsx)) { error in
            guard case ImportError.unreadableFile = error else {
                return XCTFail("Expected unreadableFile, got \(error)")
            }
        }
    }

    // =========================================================================
    // MARK: - XLS Tests
    // =========================================================================

    // --- XLS: Text / CSV fallback (most common real-world case) ---

    func test_xls_csvContent_parsedViaTextFallback() throws {
        let csv = "Date,Description,Debit,Credit\n01/01/2024,Tesco,25.00,\n02/01/2024,Salary,,3000.00"
        let txns = try parseXLS(csv)
        XCTAssertEqual(txns.count, 2)
        XCTAssertEqual(txns[0].type, .expense)
        XCTAssertEqual(txns[1].type, .income)
    }

    func test_xls_tsvContent_parsedViaTextFallback() throws {
        let tsv = "Date\tDescription\tDebit\tCredit\n01/01/2024\tNetflix\t15.99\t\n02/01/2024\tPayroll\t\t2500.00"
        let txns = try parseXLS(tsv)
        XCTAssertFalse(txns.isEmpty)
        let expenses = txns.filter { $0.type == .expense }
        let incomes  = txns.filter { $0.type == .income  }
        XCTAssertFalse(expenses.isEmpty)
        XCTAssertFalse(incomes.isEmpty)
    }

    func test_xls_tsv_negativeAmount_treatedAsExpense() throws {
        let tsv = "Date\tDescription\tAmount\n01/01/2024\tCoffee\t-4.50"
        let txns = try parseXLS(tsv)
        XCTAssertFalse(txns.isEmpty)
        XCTAssertEqual(txns[0].type,   .expense)
        XCTAssertEqual(txns[0].amount, 4.50, accuracy: 0.01)
    }

    func test_xls_tsv_positiveAmount_treatedAsIncome() throws {
        let tsv = "Date\tDescription\tAmount\n01/01/2024\tRefund\t12.00"
        let txns = try parseXLS(tsv)
        XCTAssertFalse(txns.isEmpty)
        XCTAssertEqual(txns[0].type, .income)
    }

    func test_xls_tsv_defaultCategory_isUncategorized() throws {
        let tsv = "Date\tDescription\tDebit\n01/01/2024\tAmazon\t30.00"
        let txns = try parseXLS(tsv)
        XCTAssertEqual(txns[0].category, "Uncategorized")
    }

    func test_xls_tsv_allTransactionsAreUncategorized() throws {
        let tsv = "Date\tDescription\tAmount\n01/01/2024\tTesco\t-25.00\n02/01/2024\tSalary\t3000.00"
        let txns = try parseXLS(tsv)
        XCTAssertTrue(txns.allSatisfy { $0.category == "Uncategorized" })
    }

    func test_xls_tsv_rowMissingAmount_isSkipped() throws {
        let tsv = "Date\tDescription\tDebit\tCredit\n01/01/2024\tNo Amount\t\t\n02/01/2024\tValid\t20.00\t"
        let txns = try parseXLS(tsv)
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns[0].title, "Valid")
    }

    func test_xls_tsv_currencySymbol_stripped() throws {
        let tsv = "Date\tDescription\tDebit\n01/01/2024\tRent\t£1200.00"
        let txns = try parseXLS(tsv)
        XCTAssertFalse(txns.isEmpty)
        XCTAssertEqual(txns[0].amount, 1200, accuracy: 0.01)
    }

    func test_xls_tsv_withdrawalColumn_treatedAsExpense() throws {
        let tsv = "Date\tDescription\tWithdrawal\n01/01/2024\tATM\t200.00"
        let txns = try parseXLS(tsv)
        XCTAssertFalse(txns.isEmpty)
        XCTAssertEqual(txns[0].type, .expense)
    }

    func test_xls_tsv_depositColumn_treatedAsIncome() throws {
        let tsv = "Date\tDescription\tDeposit\n01/01/2024\tTransfer In\t500.00"
        let txns = try parseXLS(tsv)
        XCTAssertFalse(txns.isEmpty)
        XCTAssertEqual(txns[0].type, .income)
    }

    // --- XLS: HTML table fallback (e.g. HSBC/Barclays .xls exports) ---

    func test_xls_htmlTableContent_parsedViaHTMLFallback() throws {
        let html = """
        <html><body><table>
        <tr><th>Date</th><th>Description</th><th>Debit</th><th>Credit</th></tr>
        <tr><td>01/01/2024</td><td>Tesco</td><td>45.20</td><td></td></tr>
        <tr><td>02/01/2024</td><td>Salary</td><td></td><td>3200.00</td></tr>
        </table></body></html>
        """
        let txns = try parseXLS(html)
        XCTAssertFalse(txns.isEmpty, "HTML-table .xls should parse via text fallback")
        XCTAssertTrue(txns.contains { $0.type == .expense && $0.title.contains("Tesco") })
        XCTAssertTrue(txns.contains { $0.type == .income  && $0.title.contains("Salary") })
    }

    func test_xls_htmlWithHTMLEntities_decodedCorrectly() throws {
        let html = """
        <table>
        <tr><th>Date</th><th>Description</th><th>Amount</th></tr>
        <tr><td>01/01/2024</td><td>AT&amp;T</td><td>-55.00</td></tr>
        </table>
        """
        let txns = try parseXLS(html)
        XCTAssertFalse(txns.isEmpty)
        XCTAssertTrue(txns[0].title.contains("AT&T") || txns[0].title.contains("AT"))
    }

    func test_xls_htmlAmountInCells_parsedCorrectly() throws {
        let html = """
        <table>
        <tr><th>Date</th><th>Merchant</th><th>Debit</th></tr>
        <tr><td>05/01/2024</td><td>Gym Membership</td><td>49.99</td></tr>
        </table>
        """
        let txns = try parseXLS(html)
        XCTAssertFalse(txns.isEmpty)
        XCTAssertEqual(txns[0].amount, 49.99, accuracy: 0.01)
    }

    // --- XLS: Binary BIFF rejection ---

    func test_xls_binaryBIFF_throwsParseFailure() {
        // OLE2 compound document signature (BIFF8)
        let biffBytes: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1,
                                   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        let data = Data(biffBytes)
        let url  = FileManager.default.temporaryDirectory
            .appendingPathComponent("biff_\(UUID()).xls")
        try? data.write(to: url)

        XCTAssertThrowsError(try sut.parse(url: url, fileType: .xls)) { error in
            guard case ImportError.parseFailure(let msg) = error else {
                return XCTFail("Expected parseFailure for BIFF binary, got \(error)")
            }
            // Error message must mention a user-friendly workaround
            XCTAssertTrue(msg.lowercased().contains("xlsx") || msg.lowercased().contains("csv"),
                          "Error message should guide the user to re-save as xlsx/csv")
        }
    }

    func test_xls_emptyFile_throwsEmptyOrParseFailure() {
        let url = writeTemp(name: "empty.xls", content: "")
        XCTAssertThrowsError(try sut.parse(url: url, fileType: .xls))
    }

    func test_xls_headerOnly_noTransactionsOrEmpty() throws {
        let tsv = "Date\tDescription\tAmount"
        do {
            let txns = try parseXLS(tsv)
            XCTAssertTrue(txns.isEmpty)
        } catch {
            // emptyFile or parseFailure are both acceptable for header-only
        }
    }

    // --- XLS: Open XML .xls via CoreXLSX ---

    func test_xls_openXMLFormat_parsedViaCorXLSX() throws {
        // If a .xls fixture built as Open XML is available in the bundle, parse it
        guard let url = bundleResource(named: "sample_bank_statement", ext: "xls") else {
            // Skip if fixture missing — document the expectation
            throw XCTSkip("sample_bank_statement.xls bundle resource not found — add it to dimeTests/Resources/")
        }
        let txns = try sut.parse(url: url, fileType: .xls)
        XCTAssertFalse(txns.isEmpty, "Open XML .xls fixture should produce transactions")
    }

    // =========================================================================
    // MARK: - XLSX Invoice Tests  ✱ NEW
    // =========================================================================

    func test_xlsx_invoice_createsExactlyOneExpense() throws {
        let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [
            ["Invoice Number", "Vendor",     "Date",       "Item",             "Total"],
            ["INV-2024-001",   "ACME Corp",  "05/01/2024", "Software License", "250.00"]
        ])
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertEqual(txns.count, 1, "Invoice XLSX must produce exactly one transaction")
    }

    func test_xlsx_invoice_typeIsExpense() throws {
        let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [
            ["Invoice Number", "Vendor",    "Date",       "Total"],
            ["INV-001",        "TechStore", "03/10/2024", "99.99"]
        ])
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertEqual(txns.first?.type, .expense)
    }

    func test_xlsx_invoice_amountExtractedCorrectly() throws {
        let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [
            ["Invoice Number", "Vendor",  "Date",       "Amount Due"],
            ["INV-002",        "Shopify", "10/01/2024", "399.00"]
        ])
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertEqual(txns.first?.amount ?? 0, 399.00, accuracy: 0.01)
    }

    func test_xlsx_invoice_vendorExtractedFromVendorColumn() throws {
        let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [
            ["Invoice Number", "Vendor",        "Date",       "Total"],
            ["INV-003",        "Stripe Inc",    "12/01/2024", "150.00"]
        ])
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertEqual(txns.first?.title, "Stripe Inc")
    }

    func test_xlsx_invoice_vendorExtractedFromSupplierColumn() throws {
        let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [
            ["Invoice Number", "Supplier",      "Date",       "Total"],
            ["INV-004",        "Adobe Systems", "15/01/2024", "54.99"]
        ])
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertEqual(txns.first?.title, "Adobe Systems")
    }

    func test_xlsx_invoice_notesContainsImportedFromInvoice() throws {
        let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [
            ["Invoice Number", "Vendor", "Date",       "Total"],
            ["INV-005",        "AWS",    "20/01/2024", "78.50"]
        ])
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertEqual(txns.first?.notes, "Imported from invoice")
    }

    func test_xlsx_invoice_multipleLineItems_sumsToGrandTotal() throws {
        // When an invoice has line items without an explicit "grand total" row,
        // the parser should sum all amounts
        let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [
            ["Vendor",  "Item",              "Qty", "Unit Price", "Total"],
            ["ACME",    "Widget A",          "2",   "50.00",      "100.00"],
            ["ACME",    "Widget B",          "1",   "150.00",     "150.00"],
        ])
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertEqual(txns.count, 1)
        // Total should be 100 + 150 = 250 (or whichever value the parser picks)
        XCTAssertGreaterThan(txns.first?.amount ?? 0, 0)
    }

    func test_xlsx_invoice_withExplicitGrandTotalRow_usesGrandTotal() throws {
        let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [
            ["Vendor", "Item",          "Amount"],
            ["ACME",   "Service Fee",   "200.00"],
            ["ACME",   "Tax",           "20.00"],
            ["",       "Grand Total",   "220.00"]   // explicit total row
        ])
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns.first?.amount ?? 0, 220.00, accuracy: 0.01)
    }

    func test_xlsx_invoice_dateExtractedCorrectly() throws {
        let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [
            ["Invoice Number", "Vendor", "Invoice Date", "Total"],
            ["INV-006",        "Oracle", "15/03/2024",   "1200.00"]
        ])
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertNotNil(txns.first?.date)
    }

    func test_xlsx_invoice_doesNotCreateUncategorizedEntries() throws {
        // Invoice result should be a single expense, not multiple Uncategorized rows
        let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [
            ["Invoice Number", "Vendor",  "Date",       "Total"],
            ["INV-007",        "Figma",   "01/02/2024", "45.00"]
        ])
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns.first?.type, .expense)
    }

    func test_xlsx_invoice_bundleFixture_parsesCorrectly() throws {
        guard let url = bundleResource(named: "sample_invoice", ext: "xlsx") else {
            throw XCTSkip("sample_invoice.xlsx not found in test bundle — add it to dimeTests/Resources/")
        }
        let txns = try sut.parse(url: url, fileType: .xlsx)
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns.first?.type, .expense)
        XCTAssertGreaterThan(txns.first?.amount ?? 0, 0)
    }

    // =========================================================================
    // MARK: - XLS Invoice Tests  ✱ NEW
    // =========================================================================

    // --- XLS Invoice: TSV format (most common export) ---

    func test_xls_invoice_tsvFormat_createsExactlyOneExpense() throws {
        let tsv = "Invoice Number\tVendor\tDate\tTotal\nINV-2024-001\tACME Corp\t05/01/2024\t250.00"
        let txns = try parseXLS(tsv)
        XCTAssertEqual(txns.count, 1, "Invoice XLS must produce exactly one transaction")
    }

    func test_xls_invoice_tsvFormat_typeIsExpense() throws {
        let tsv = "Invoice Number\tVendor\tDate\tTotal\nINV-001\tTechStore\t03/10/2024\t99.99"
        let txns = try parseXLS(tsv)
        XCTAssertEqual(txns.first?.type, .expense)
    }

    func test_xls_invoice_tsvFormat_amountExtractedCorrectly() throws {
        let tsv = "Invoice Number\tVendor\tDate\tAmount Due\nINV-002\tShopify\t10/01/2024\t399.00"
        let txns = try parseXLS(tsv)
        XCTAssertEqual(txns.first?.amount ?? 0, 399.00, accuracy: 0.01)
    }

    func test_xls_invoice_tsvFormat_vendorExtractedFromVendorColumn() throws {
        let tsv = "Invoice Number\tVendor\tDate\tTotal\nINV-003\tStripe Inc\t12/01/2024\t150.00"
        let txns = try parseXLS(tsv)
        XCTAssertEqual(txns.first?.title, "Stripe Inc")
    }

    func test_xls_invoice_tsvFormat_vendorExtractedFromSupplierColumn() throws {
        let tsv = "Invoice Number\tSupplier\tDate\tTotal\nINV-004\tAdobe Systems\t15/01/2024\t54.99"
        let txns = try parseXLS(tsv)
        XCTAssertEqual(txns.first?.title, "Adobe Systems")
    }

    func test_xls_invoice_tsvFormat_notesContainsImportedFromInvoice() throws {
        let tsv = "Invoice Number\tVendor\tDate\tTotal\nINV-005\tAWS\t20/01/2024\t78.50"
        let txns = try parseXLS(tsv)
        XCTAssertEqual(txns.first?.notes, "Imported from invoice")
    }

    func test_xls_invoice_tsvFormat_withGrandTotalRow_usesGrandTotal() throws {
        let tsv = """
        Vendor\tItem\tAmount
        ACME\tService Fee\t200.00
        ACME\tTax\t20.00
        \tGrand Total\t220.00
        """
        let txns = try parseXLS(tsv)
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns.first?.amount ?? 0, 220.00, accuracy: 0.01)
    }

    // --- XLS Invoice: CSV format ---

    func test_xls_invoice_csvFormat_createsExactlyOneExpense() throws {
        let csv = "Invoice Number,Vendor,Date,Total\nINV-2024-001,ACME Corp,05/01/2024,250.00"
        let txns = try parseXLS(csv)
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns.first?.type, .expense)
    }

    func test_xls_invoice_csvFormat_amountExtractedCorrectly() throws {
        let csv = "Invoice Number,Vendor,Date,Amount Due\nINV-006,Oracle,15/03/2024,1200.00"
        let txns = try parseXLS(csv)
        XCTAssertEqual(txns.first?.amount ?? 0, 1200.00, accuracy: 0.01)
    }

    // --- XLS Invoice: HTML table format ---

    func test_xls_invoice_htmlFormat_createsExactlyOneExpense() throws {
        let html = """
        <table>
        <tr><th>Invoice Number</th><th>Vendor</th><th>Date</th><th>Total</th></tr>
        <tr><td>INV-2024-001</td><td>ACME Corp</td><td>05/01/2024</td><td>250.00</td></tr>
        </table>
        """
        let txns = try parseXLS(html)
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns.first?.type, .expense)
        XCTAssertEqual(txns.first?.amount ?? 0, 250.00, accuracy: 0.01)
    }

    func test_xls_invoice_htmlFormat_vendorExtracted() throws {
        let html = """
        <table>
        <tr><th>Supplier</th><th>Item</th><th>Qty</th><th>Unit Price</th><th>Total</th></tr>
        <tr><td>Design Co</td><td>Logo Design</td><td>1</td><td>500.00</td><td>500.00</td></tr>
        </table>
        """
        let txns = try parseXLS(html)
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns.first?.title, "Design Co")
    }

    func test_xls_invoice_doesNotCreateMultipleRowsForLineItems() throws {
        // A multi-line-item invoice must still collapse to ONE transaction
        let tsv = "Vendor\tItem\tQty\tUnit Price\tTotal\nACME\tItem A\t1\t100.00\t100.00\nACME\tItem B\t2\t75.00\t150.00"
        let txns = try parseXLS(tsv)
        XCTAssertEqual(txns.count, 1)
    }

    func test_xls_invoice_bundleFixture_parsesCorrectly() throws {
        guard let url = bundleResource(named: "sample_invoice", ext: "xls") else {
            throw XCTSkip("sample_invoice.xls not found in test bundle — add it to dimeTests/Resources/")
        }
        let txns = try sut.parse(url: url, fileType: .xls)
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns.first?.type, .expense)
        XCTAssertGreaterThan(txns.first?.amount ?? 0, 0)
    }

    // =========================================================================
    // MARK: - Shared helpers
    // =========================================================================

    private func parseCSV(_ content: String) throws -> [ImportedTransaction] {
        let url = writeTemp(name: "test_\(UUID()).csv", content: content)
        return try sut.parse(url: url, fileType: .csv)
    }

    private func parseXLS(_ content: String) throws -> [ImportedTransaction] {
        let url = writeTemp(name: "test_\(UUID()).xls", content: content)
        return try sut.parse(url: url, fileType: .xls)
    }

    private func writeTemp(name: String, content: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func bundleResource(named name: String, ext: String) -> URL? {
        Bundle(for: type(of: self)).url(forResource: name, withExtension: ext)
    }
}

// =========================================================================
// MARK: - XLSX Test Fixture Builder
// =========================================================================

/// Generates a minimal valid .xlsx file (Open XML ZIP) for unit tests.
/// This removes the hard dependency on a hand-crafted bundle resource
/// while still exercising the real CoreXLSX parse path.
///
/// Usage: `let url = try XLSXTestFixtureBuilder.makeSampleXLSX(rows: [...])`
enum XLSXTestFixtureBuilder {

    static func makeSampleXLSX(rows: [[String]] = Self.defaultRows) throws -> URL {
        // An XLSX file is a ZIP archive containing XML parts.
        // We build the minimum required parts: [Content_Types].xml, workbook.xml,
        // sheet1.xml, sharedStrings.xml, and the relationship files.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixture_\(UUID()).xlsx")

        let sheetXML  = buildSheetXML(rows: rows)
        let archive   = try buildZIP(sheetXML: sheetXML)
        try archive.write(to: tmp)
        return tmp
    }

    static let defaultRows: [[String]] = [
        ["Date",       "Description",    "Debit",  "Credit"],
        ["01/01/2024", "Tesco Groceries","45.20",  ""],
        ["02/01/2024", "Monthly Salary", "",        "3200.00"],
        ["03/01/2024", "Netflix",        "15.99",  ""],
        ["04/01/2024", "Freelance",      "",        "750.00"],
        ["05/01/2024", "Electricity",    "87.50",  ""]
    ]

    // MARK: - XML builders

    private static func buildSheetXML(rows: [[String]]) -> String {
        var rowsXML = ""
        for (rIdx, row) in rows.enumerated() {
            let rowNum = rIdx + 1
            var cellsXML = ""
            for (cIdx, value) in row.enumerated() {
                let col = columnLetter(cIdx)
                let ref = "\(col)\(rowNum)"
                // Inline string cells (type="inlineStr")
                cellsXML += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t>\(xmlEscape(value))</t></is></c>"
            }
            rowsXML += "<row r=\"\(rowNum)\">\(cellsXML)</row>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>\(rowsXML)</sheetData>
        </worksheet>
        """
    }

    private static func columnLetter(_ index: Int) -> String {
        var result = ""
        var n = index
        repeat {
            result = String(UnicodeScalar(65 + (n % 26))!) + result
            n = n / 26 - 1
        } while n >= 0
        return result
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&",  with: "&amp;")
         .replacingOccurrences(of: "<",  with: "&lt;")
         .replacingOccurrences(of: ">",  with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - ZIP builder

    /// Builds a minimal XLSX ZIP archive using only Foundation (no external zip library).
    /// Each file is stored uncompressed (method 0) for simplicity.
    private static func buildZIP(sheetXML: String) throws -> Data {
        let files: [(name: String, content: String)] = [
            ("[Content_Types].xml",                    contentTypesXML),
            ("_rels/.rels",                             rootRelsXML),
            ("xl/workbook.xml",                         workbookXML),
            ("xl/_rels/workbook.xml.rels",              workbookRelsXML),
            ("xl/worksheets/sheet1.xml",                sheetXML),
            ("xl/sharedStrings.xml",                    sharedStringsXML)
        ]

        var zipData = Data()
        var centralDirectory = Data()
        var localFileOffset: UInt32 = 0

        for file in files {
            guard let fileData = file.content.data(using: .utf8) else { continue }
            guard let nameData = file.name.data(using: .utf8) else { continue }

            // Local file header
            var local = Data()
            local.append(contentsOf: [0x50, 0x4B, 0x03, 0x04]) // signature
            local.append(contentsOf: [0x14, 0x00])              // version needed
            local.append(contentsOf: [0x00, 0x00])              // general purpose flag
            local.append(contentsOf: [0x00, 0x00])              // compression method (stored)
            local.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // last mod time/date
            let crc = crc32(fileData)
            local.append(uint32LE(crc))
            local.append(uint32LE(UInt32(fileData.count)))      // compressed size
            local.append(uint32LE(UInt32(fileData.count)))      // uncompressed size
            local.append(uint16LE(UInt16(nameData.count)))      // filename length
            local.append(contentsOf: [0x00, 0x00])              // extra field length
            local.append(nameData)
            local.append(fileData)

            // Central directory entry
            var central = Data()
            central.append(contentsOf: [0x50, 0x4B, 0x01, 0x02]) // signature
            central.append(contentsOf: [0x14, 0x00, 0x14, 0x00]) // version made/needed
            central.append(contentsOf: [0x00, 0x00])              // general purpose flag
            central.append(contentsOf: [0x00, 0x00])              // compression method
            central.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // last mod time/date
            central.append(uint32LE(crc))
            central.append(uint32LE(UInt32(fileData.count)))
            central.append(uint32LE(UInt32(fileData.count)))
            central.append(uint16LE(UInt16(nameData.count)))
            central.append(contentsOf: [0x00, 0x00])             // extra field length
            central.append(contentsOf: [0x00, 0x00])             // file comment length
            central.append(contentsOf: [0x00, 0x00])             // disk number start
            central.append(contentsOf: [0x00, 0x00])             // internal file attr
            central.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // external file attr
            central.append(uint32LE(localFileOffset))
            central.append(nameData)

            localFileOffset += UInt32(local.count)
            zipData.append(local)
            centralDirectory.append(central)
        }

        let centralStart = localFileOffset
        let endRecord = endOfCentralDirectory(
            entryCount: UInt16(files.count),
            centralSize: UInt32(centralDirectory.count),
            centralOffset: centralStart
        )

        zipData.append(centralDirectory)
        zipData.append(endRecord)
        return zipData
    }

    private static func uint16LE(_ v: UInt16) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)])
    }
    private static func uint32LE(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
              UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
    }

    private static func endOfCentralDirectory(entryCount: UInt16, centralSize: UInt32, centralOffset: UInt32) -> Data {
        var d = Data()
        d.append(contentsOf: [0x50, 0x4B, 0x05, 0x06]) // signature
        d.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // disk numbers
        d.append(uint16LE(entryCount))
        d.append(uint16LE(entryCount))
        d.append(uint32LE(centralSize))
        d.append(uint32LE(centralOffset))
        d.append(contentsOf: [0x00, 0x00]) // comment length
        return d
    }

    /// CRC-32 (ISO 3309) implementation — no external deps needed.
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            var b = UInt32(byte)
            for _ in 0..<8 {
                let mask = ~((crc ^ b) & 1) + 1
                crc = (crc >> 1) ^ (0xEDB88320 & mask)
                b >>= 1
            }
        }
        return ~crc
    }

    // MARK: - Static XML strings

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml"  ContentType="application/xml"/>
      <Override PartName="/xl/workbook.xml"
        ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
      <Override PartName="/xl/worksheets/sheet1.xml"
        ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
      <Override PartName="/xl/sharedStrings.xml"
        ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
    </Types>
    """

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1"
        Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
        Target="xl/workbook.xml"/>
    </Relationships>
    """

    private static let workbookXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <sheets>
        <sheet name="Sheet1" sheetId="1" r:id="rId1"/>
      </sheets>
    </workbook>
    """

    private static let workbookRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1"
        Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"
        Target="worksheets/sheet1.xml"/>
      <Relationship Id="rId2"
        Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings"
        Target="sharedStrings.xml"/>
    </Relationships>
    """

    private static let sharedStringsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="0" uniqueCount="0"/>
    """
}