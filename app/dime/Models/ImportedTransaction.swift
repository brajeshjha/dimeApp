import Foundation

/// Transient model representing a single transaction parsed from an imported file.
/// This is NOT a CoreData entity — it is mapped to the real `Transaction` entity
/// after the user confirms the import.
struct ImportedTransaction: Identifiable, Equatable {
    let id: UUID
    var title: String        // Merchant / description
    var amount: Double       // Always positive
    var date: Date
    var type: TransactionType
    var category: String     // Defaults to "Uncategorized"
    var notes: String

    enum TransactionType: String, CaseIterable {
        case expense = "Expense"
        case income  = "Income"
    }

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        date: Date = Date(),
        type: TransactionType,
        category: String = "Uncategorized",
        notes: String = ""
    ) {
        self.id       = id
        self.title    = title
        self.amount   = abs(amount)
        self.date     = date
        self.type     = type
        self.category = category
        self.notes    = notes
    }
}