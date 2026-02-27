import XCTest
import PDFKit
@testable import dime

final class PDFImportParserTests: XCTestCase {

    var sut: PDFImportParser!

    override func setUp() {
        super.setUp()
        sut = PDFImportParser()
    }

    // MARK: - Invoice detection

    func test_parseInvoice_returnsExpense() throws {
        let text = """
        ACME Corp
        Invoice #12345
        Date: 01/15/2024
        Total: $250.00
        """
        let url = makePDF(text: text)
        let txns = try sut.parse(url: url)
        XCTAssertEqual(txns.count, 1)
        XCTAssertEqual(txns[0].type, .expense)
        XCTAssertEqual(txns[0].amount, 250.0, accuracy: 0.01)
    }

    func test_parseInvoice_vendorExtracted() throws {
        let text = """
        TechStore Ltd
        Invoice Date: 03/10/2024
        Amount Due: $99.99
        """
        let url = makePDF(text: text)
        let txns = try sut.parse(url: url)
        XCTAssertFalse(txns[0].title.isEmpty)
    }

    // MARK: - Bank statement detection

    func test_parseBankStatement_debitsAreExpenses() throws {
        let text = """
        Account Statement
        Account Number: 1234567890
        Transaction Date  Description            Debit    Credit   Balance
        01/01/2024        Tesco                  25.00             475.00
        02/01/2024        Salary                          3000.00  3475.00
        """
        let url = makePDF(text: text)
        let txns = try sut.parse(url: url)
        // Should have at least one expense and one income
        XCTAssertTrue(txns.contains { $0.type == .expense })
        XCTAssertTrue(txns.contains { $0.type == .income })
    }

    // MARK: - Error cases

    func test_parse_emptyPDF_throwsError() {
        let url = makePDF(text: "")
        XCTAssertThrowsError(try sut.parse(url: url))
    }

    func test_parse_invalidURL_throwsError() {
        let url = URL(fileURLWithPath: "/nonexistent/file.pdf")
        XCTAssertThrowsError(try sut.parse(url: url)) { error in
            guard case ImportError.unreadableFile = error else {
                return XCTFail("Expected unreadableFile")
            }
        }
    }

    // MARK: - Helpers

    private func makePDF(text: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID()).pdf")

        guard !text.isEmpty else {
            // Write a valid but text-free PDF
            let doc = PDFDocument()
            doc.insert(PDFPage(), at: 0)
            doc.write(to: url)
            return url
        }

        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: 595, height: 842),
            format: format
        )
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12)
            ]
            text.draw(in: CGRect(x: 36, y: 36, width: 523, height: 770),
                      withAttributes: attrs)
        }
        try? data.write(to: url)
        return url
    }
}