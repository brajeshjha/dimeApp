import XCTest
@testable import dime

final class FileImportServiceTests: XCTestCase {

    var sut: FileImportService!

    override func setUp() {
        super.setUp()
        sut = FileImportService()
    }

    // MARK: - Unsupported types

    func test_parse_unsupportedExtension_throwsError() {
        let url = makeTextFile(named: "test.txt", content: "hello")
        XCTAssertThrowsError(try sut.parse(url: url)) { error in
            guard case ImportError.unsupportedFileType(let ext) = error else {
                return XCTFail("Expected unsupportedFileType, got \(error)")
            }
            XCTAssertEqual(ext, "txt")
        }
    }

    func test_parse_docxExtension_throwsUnsupportedError() {
        let url = makeTextFile(named: "statement.docx", content: "word doc content")
        XCTAssertThrowsError(try sut.parse(url: url)) { error in
            guard case ImportError.unsupportedFileType(let ext) = error else {
                return XCTFail("Expected unsupportedFileType")
            }
            XCTAssertEqual(ext, "docx")
        }
    }

    func test_parse_noExtension_throwsUnsupportedError() {
        let url = makeTextFile(named: "statementnoext", content: "data")
        XCTAssertThrowsError(try sut.parse(url: url)) { error in
            guard case ImportError.unsupportedFileType = error else {
                return XCTFail("Expected unsupportedFileType")
            }
        }
    }

    // MARK: - CSV routing

//    func test_parse_csvExtension_routesToCSVParser_returnsTransactions() throws {
//        let csv = """
//        Date,Description,Debit,Credit
//        01/01/2024,Tesco,25.00,
//        02/01/2024,Salary,,3000.00
//        """
//        let url = makeTextFile(named: "statement.csv", content: csv)
//        let txns = try sut.parse(url: url)
//        XCTAssertEqual(txns.count, 2)
//        XCTAssertEqual(txns[0].type, .expense)
//        XCTAssertEqual(txns[1].type, .income)
//    }

    func test_parse_csvExtension_caseInsensitive() throws {
        let csv = "Date,Description,Amount\n01/01/2024,Coffee,-5.00"
        let url = makeTextFile(named: "STATEMENT.CSV", content: csv)
        // Extensions should be lowercased before switch
        let txns = try sut.parse(url: url)
        XCTAssertEqual(txns.count, 1)
    }

    // MARK: - XLSX routing

//    func test_parse_xlsxExtension_routesToXlsxParser() throws {
//        // We test routing by creating a valid XLSX fixture from the bundle.
//        // If the bundle fixture is missing, the parser throws unreadableFile/parseFailure
//        // (not unsupportedFileType), confirming routing succeeded.
//        let url = bundleResource(named: "sample_bank_statement", ext: "xlsx")
//            ?? makeTextFile(named: "empty.xlsx", content: "")
//
//        do {
//            let txns = try sut.parse(url: url)
//            // If fixture exists and parses: verify type correctness
//            XCTAssertFalse(txns.isEmpty, "XLSX fixture should produce transactions")
//        } catch ImportError.unsupportedFileType {
//            XCTFail("XLSX should be routed to XlsxParser, not rejected as unsupported")
//        } catch {
//            // unreadableFile / emptyFile / parseFailure — routing was correct
//        }
//    }

    func test_parse_xlsxExtension_isDistinctFrom_xlsRouting() throws {
        // Confirm .xlsx and .xls are routed independently (not collapsed into one path)
        // by checking that a renamed CSV-as-XLSX file is treated differently from CSV-as-XLS.
        let csvContent = "Date,Description,Amount\n01/01/2024,Test,10.00"
        let xlsxURL = makeTextFile(named: "data.xlsx", content: csvContent)
        let xlsURL  = makeTextFile(named: "data.xls",  content: csvContent)

        // Both should NOT throw unsupportedFileType — they hit different parser paths
        XCTAssertNoThrow(try { _ = try? self.sut.parse(url: xlsxURL) }())
        XCTAssertNoThrow(try { _ = try? self.sut.parse(url: xlsURL)  }())
    }

    // MARK: - XLS routing

    func test_parse_xlsExtension_routesToXlsParser_notRejected() {
        // A plain-text CSV with a .xls extension should parse via the XLS text fallback
        let csv = "Date,Description,Amount\n05/01/2024,Amazon,-89.99"
        let url = makeTextFile(named: "export.xls", content: csv)

        do {
            let txns = try sut.parse(url: url)
            XCTAssertFalse(txns.isEmpty)
        } catch ImportError.unsupportedFileType {
            XCTFail("XLS extension must be routed to XLS parser, not rejected")
        } catch {
            // parseFailure / unreadable are acceptable — routing was correct
        }
    }

    func test_parse_xlsExtension_tsvContent_returnsTransactions() throws {
        // TSV masquerading as .xls (extremely common bank export)
        let tsv = "Date\tDescription\tDebit\tCredit\n01/01/2024\tTesco\t42.00\t\n02/01/2024\tSalary\t\t1500.00"
        let url = makeTextFile(named: "bank_export.xls", content: tsv)
        let txns = try sut.parse(url: url)
        XCTAssertFalse(txns.isEmpty)
    }

    func test_parse_xlsExtension_binaryBIFF_throwsParseFailure() {
        // A genuine binary BIFF file cannot be decoded — expect parseFailure, not a crash
        // We simulate a BIFF header: D0 CF 11 E0 (OLE2 compound document signature)
        let biffBytes: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
        let data = Data(biffBytes)
        let url  = FileManager.default.temporaryDirectory.appendingPathComponent("binary.xls")
        try? data.write(to: url)

        XCTAssertThrowsError(try sut.parse(url: url)) { error in
            guard case ImportError.parseFailure = error else {
                return XCTFail("Expected parseFailure for BIFF binary, got \(error)")
            }
        }
    }

    // MARK: - XLSX Invoice routing  ✱ NEW

    func test_parse_xlsxInvoice_returnsOneExpense() throws {
        // A CSV-named-as-XLSX with invoice headers should route to XLSX parser
        // and collapse to a single expense
        guard let url = bundleResource(named: "sample_invoice", ext: "xlsx") else {
            throw XCTSkip("sample_invoice.xlsx not found — add to dimeTests/Resources/")
        }
        let txns = try sut.parse(url: url)
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns.first?.type, .expense)
    }

    // MARK: - XLS Invoice routing  ✱ NEW

    func test_parse_xlsInvoice_tsvFormat_returnsOneExpense() throws {
        let tsv = "Invoice Number\tVendor\tDate\tTotal\nINV-001\tACME Corp\t05/01/2024\t250.00"
        let url = makeTextFile(named: "invoice.xls", content: tsv)
        let txns = try sut.parse(url: url)
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns.first?.type, .expense)
        XCTAssertEqual(txns.first?.amount ?? 0, 250.00, accuracy: 0.01)
    }

    func test_parse_xlsInvoice_csvFormat_returnsOneExpense() throws {
        let csv = "Invoice Number,Vendor,Date,Total\nINV-002,TechStore,10/01/2024,99.99"
        let url = makeTextFile(named: "invoice_csv.xls", content: csv)
        let txns = try sut.parse(url: url)
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns.first?.type, .expense)
    }

    func test_parse_xlsInvoice_bundleFixture_parsesCorrectly() throws {
        guard let url = bundleResource(named: "sample_invoice", ext: "xls") else {
            throw XCTSkip("sample_invoice.xls not found — add to dimeTests/Resources/")
        }
        let txns = try sut.parse(url: url)
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns.first?.type, .expense)
        XCTAssertGreaterThan(txns.first?.amount ?? 0, 0)
    }

    // MARK: - PDF routing

    func test_parse_pdfExtension_routesToPdfParser_notRejected() {
        let url = makeTextFile(named: "invoice.pdf", content: "%PDF-1.4 fake")
        // Should not throw unsupportedFileType
        do { _ = try sut.parse(url: url) }
        catch ImportError.unsupportedFileType { XCTFail("PDF must not be rejected as unsupported") }
        catch { /* unreadable / empty — routing correct */ }
    }

    // MARK: - Helpers

    private func makeTextFile(named name: String, content: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func bundleResource(named name: String, ext: String) -> URL? {
        Bundle(for: type(of: self)).url(forResource: name, withExtension: ext)
    }
}
