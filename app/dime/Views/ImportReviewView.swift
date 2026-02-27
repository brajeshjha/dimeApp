//
//  ImportReviewView.swift
//  dime
//
//  Created for bulk import feature
//

import SwiftUI

struct ImportReviewView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataController: DataController
    
    let importedTransactions: [ImportedTransaction]
    var onImport: () -> Void
    
    @State private var isImporting = false
    @State private var showSuccessMessage = false
    
    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) 
    var currency: String = Locale.current.currencyCode!
    
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? "$"
    }
    
    var totalExpenses: Double {
        importedTransactions.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount }
    }
    
    var totalIncome: Double {
        importedTransactions.filter { $0.isIncome }.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Summary header
                VStack(spacing: 12) {
                    Text("Review Import")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundColor(Color.PrimaryText)
                    
                    HStack(spacing: 20) {
                        VStack(spacing: 4) {
                            Text("\(importedTransactions.count)")
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .foregroundColor(Color.PrimaryText)
                            Text("Transactions")
                                .font(.system(.caption, design: .rounded).weight(.medium))
                                .foregroundColor(Color.SubtitleText)
                        }
                        
                        if totalExpenses > 0 {
                            VStack(spacing: 4) {
                                Text("\(currencySymbol)\(Int(totalExpenses))")
                                    .font(.system(.title3, design: .rounded).weight(.bold))
                                    .foregroundColor(Color.AlertRed)
                                Text("Expenses")
                                    .font(.system(.caption, design: .rounded).weight(.medium))
                                    .foregroundColor(Color.SubtitleText)
                            }
                        }
                        
                        if totalIncome > 0 {
                            VStack(spacing: 4) {
                                Text("\(currencySymbol)\(Int(totalIncome))")
                                    .font(.system(.title3, design: .rounded).weight(.bold))
                                    .foregroundColor(Color.IncomeGreen)
                                Text("Income")
                                    .font(.system(.caption, design: .rounded).weight(.medium))
                                    .foregroundColor(Color.SubtitleText)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.SecondaryBackground)
                
                // Transaction list
                List {
                    ForEach(importedTransactions) { transaction in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(transaction.note)
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .foregroundColor(Color.PrimaryText)
                                    .lineLimit(1)
                                
                                Text(formatDate(transaction.date))
                                    .font(.system(.caption, design: .rounded).weight(.medium))
                                    .foregroundColor(Color.SubtitleText)
                            }
                            
                            Spacer()
                            
                            Text("\(transaction.isIncome ? "+" : "-")\(currencySymbol)\(formatAmount(transaction.amount))")
                                .font(.system(.body, design: .rounded).weight(.bold))
                                .foregroundColor(transaction.isIncome ? Color.IncomeGreen : Color.AlertRed)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
                
                // Import button
                VStack(spacing: 12) {
                    Text("All transactions will be imported as Uncategorized. You can categorize them later.")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundColor(Color.SubtitleText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button {
                        importTransactions()
                    } label: {
                        if isImporting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("Import \(importedTransactions.count) Transaction\(importedTransactions.count == 1 ? "" : "s")")
                                .font(.system(.body, design: .rounded).weight(.bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .background(Color.blue)
                    .cornerRadius(12)
                    .disabled(isImporting)
                    .padding(.horizontal)
                    
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundColor(Color.SubtitleText)
                    }
                    .padding(.bottom)
                }
            }
            .navigationBarHidden(true)
        }
        .alert("Success!", isPresented: $showSuccessMessage) {
            Button("OK") {
                onImport()
                dismiss()
            }
        } message: {
            Text("\(importedTransactions.count) transaction\(importedTransactions.count == 1 ? "" : "s") imported successfully!")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = amount.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
    }
    
    private func importTransactions() {
        isImporting = true
        
        // Import each transaction
        DispatchQueue.global(qos: .userInitiated).async {
            for transaction in importedTransactions {
                // Create transaction with no category (will appear as uncategorized)
                _ = dataController.newTransaction(
                    note: transaction.note,
                    category: nil, // No category = uncategorized
                    income: transaction.isIncome,
                    amount: transaction.amount,
                    date: transaction.date,
                    repeatType: 0,
                    repeatCoefficient: 1,
                    delay: false
                )
            }
            
            DispatchQueue.main.async {
                isImporting = false
                showSuccessMessage = true
            }
        }
    }
}

struct ImportReviewView_Previews: PreviewProvider {
    static var previews: some View {
        ImportReviewView(
            importedTransactions: [
                ImportedTransaction(date: Date(), amount: 50.00, note: "Groceries", isIncome: false),
                ImportedTransaction(date: Date(), amount: 1000.00, note: "Salary", isIncome: true),
                ImportedTransaction(date: Date(), amount: 25.50, note: "Coffee", isIncome: false)
            ],
            onImport: {}
        )
        .environmentObject(DataController.shared)
    }
}
