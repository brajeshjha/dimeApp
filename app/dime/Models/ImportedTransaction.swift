//
//  ImportedTransaction.swift
//  dime
//
//  Created for bulk import feature
//

import Foundation

/// Represents a transaction parsed from an imported file before it's saved to Core Data
struct ImportedTransaction: Identifiable {
    let id = UUID()
    var date: Date
    var amount: Double
    var note: String
    var isIncome: Bool
    var category: String? // Will be nil for uncategorized
    
    init(date: Date, amount: Double, note: String, isIncome: Bool, category: String? = nil) {
        self.date = date
        self.amount = amount
        self.note = note
        self.isIncome = isIncome
        self.category = category
    }
}

/// Represents the result of file import parsing
enum FileImportResult {
    case success([ImportedTransaction])
    case failure(FileImportError)
}

/// Errors that can occur during file import
enum FileImportError: LocalizedError {
    case unsupportedFileType
    case fileReadError
    case parsingError(String)
    case noDataFound
    case invalidFormat
    
    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "This file type is not supported. Please upload a .csv, .xlsx, .xls, or .pdf file."
        case .fileReadError:
            return "Unable to read the file. Please try again or use a different file."
        case .parsingError(let details):
            return "Error parsing file: \(details)"
        case .noDataFound:
            return "No transaction data found in the file."
        case .invalidFormat:
            return "The file format is invalid or corrupted. Please check the file and try again."
        }
    }
}
