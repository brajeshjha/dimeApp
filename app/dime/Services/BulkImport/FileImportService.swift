import Foundation
import UniformTypeIdentifiers

/// Errors that can arise during file import.
enum ImportError: LocalizedError {
    case unsupportedFileType(String)
    case unreadableFile
    case emptyFile
    case parseFailure(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let ext):
            return "The file type \".\(ext)\" is not supported. Please upload a .csv, .xlsx, .xls, or .pdf file."
        case .unreadableFile:
            return "We couldn't read the file. It may be corrupted or password-protected."
        case .emptyFile:
            return "The file appears to be empty. Please check the file and try again."
        case .parseFailure(let reason):
            return "We had trouble understanding the file: \(reason)"
        }
    }
}

/// High-level service that detects file type and delegates to the right parser.
final class FileImportService {

    private let csvParser: CSVImportParser
    private let pdfParser: PDFImportParser

    init(csvParser: CSVImportParser = CSVImportParser(),
         pdfParser: PDFImportParser = PDFImportParser()) {
        self.csvParser = csvParser
        self.pdfParser = pdfParser
    }

    /// Supported UTTypes for the document picker.
    static let supportedTypes: [UTType] = [
        .commaSeparatedText,                              // .csv
        UTType(filenameExtension: "xlsx") ?? .data,       // .xlsx
        UTType(filenameExtension: "xls")  ?? .data,       // .xls  ← distinct from xlsx
        .pdf                                              // .pdf
    ]

    /// Parse a file URL and return an array of `ImportedTransaction`.
    /// Throws `ImportError` on failure.
    func parse(url: URL) throws -> [ImportedTransaction] {
        let ext = url.pathExtension.lowercased()

        // Security-scoped resource access (files from Files.app / iCloud Drive)
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        switch ext {
        case "csv":
            return try csvParser.parse(url: url, fileType: .csv)
        case "xlsx":
            return try csvParser.parse(url: url, fileType: .xlsx)  // Open XML path
        case "xls":
            return try csvParser.parse(url: url, fileType: .xls)   // Legacy XLS path — distinct
        case "pdf":
            return try pdfParser.parse(url: url)
        default:
            throw ImportError.unsupportedFileType(ext)
        }
    }
}
