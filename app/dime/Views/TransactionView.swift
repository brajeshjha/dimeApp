//
//  TransactionView.swift
//  xpenz
//
//  Created by Rafael Soh on 14/5/22.
//

import Combine
import CoreData
import Foundation
import PDFKit
import Popovers
import SwiftUI
import UniformTypeIdentifiers

struct TransactionView: View {
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "income = %d", false)) private
    var expenseCategories: FetchedResults<Category>
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "income = %d", true)) private
    var incomeCategories: FetchedResults<Category>

    @Environment(\.managedObjectContext) var moc
    @EnvironmentObject var dataController: DataController
    @Environment(\.dismiss) var dismiss

    @Environment(\.colorScheme) var colorScheme
    var boldText: Bool {
        UIAccessibility.isBoldTextEnabled
    }

    @AppStorage("topEdge", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var topEdge:
    Double = 20

    @State private var note = ""
    @State var category: Category?
    @State private var date = Date.now
    @State private var repeatType = 0
    @State private var repeatCoefficient = 1
    @State private var showRecurring = false
    @State var income = false

    var transactionTypeString: String {
        if income {
            return "Income"
        } else {
            return "Expense"
        }
    }

    @State var showCategoryPicker = false
    @State var showCategorySheet = false

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var currency: String = Locale.current.currencyCode!
    var currencySymbol: String {
        return Locale.current.localizedCurrencySymbol(forCurrencyCode: currency)!
    }

    @State var showingDatePicker = false
    @State var showingCategoryView = false

    // toasts
    @State var showToast = false
    @State var toastTitle = ""
    @State var toastImage = ""

    @State private var showFileImporter = false
    @State private var showImportReview = false
    @State private var importedTransactions: [ImportedTransaction] = []

    // shaking category error
    @State var categoryButtonTextColor = Color.SubtitleText
    @State var categoryButtonBackgroundColor = Color.clear
    @State var categoryButtonOutlineColor = Color.Outline
    @State var shake: Bool = false

    @ObservedObject var keyboardHeightHelper = KeyboardHeightHelper()

    @AppStorage(
        "firstTransactionViewLaunch", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var firstLaunch: Bool = true

    // edit mode
    let toEdit: Transaction?

    // delete mode

    @State var toDelete: Transaction?
    @State var deleteMode = false

    @AppStorage("bottomEdge", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var bottomEdge: Double = 15

    @State private var offset: CGFloat = 0

    let repeatOverlays = ["D", "W", "M"]
    let numberArray = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

    var repeatButtonAccessibility: String {
        if repeatType == 1 {
            return "transaction recurs daily, button to edit recurring duration"
        } else if repeatType == 2 {
            return "transaction recurs weekly, button to edit recurring duration"
        } else if repeatType == 3 {
            return "transaction recurs monthly, button to edit recurring duration"
        } else {
            return "button to make transaction recurring"
        }
    }

    var dateString: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"
        return dateFormatter.string(from: date)
    }

    var showTime: Bool {
        let roundedFont = UIFont.rounded(ofSize: fontSize, weight: .semibold)

        let attributes = [NSAttributedString.Key.font: roundedFont]

        let dateSize: CGSize

        if isDateToday(date: date) {
            dateSize = (("Today, " + getDateString(date: date)) as NSString).size(
                withAttributes: attributes)
        } else {
            dateSize = (getDateString(date: date) as NSString).size(withAttributes: attributes)
        }

        let categorySize = (category?.fullName ?? "X Category").size(withAttributes: attributes)
        let timeSize = (getTimeString(date: date) as NSString).size(withAttributes: attributes)

        let screenWidth: CGFloat

        if boldText {
            screenWidth = (UIScreen.main.bounds.width - 200)
        } else {
            screenWidth = (UIScreen.main.bounds.width - 150)
        }

        if (dateSize.width + categorySize.width + timeSize.width) > screenWidth {
            return false
        } else {
            return true
        }
    }

    @AppStorage("colourScheme", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var colourScheme: Int = 0

    @Environment(\.colorScheme) var systemColorScheme

    var darkMode: Bool {
        (colourScheme == 0 && systemColorScheme == .dark) || colourScheme == 2
    }

    var backgroundColor: Color {
        if darkMode {
            return Color("AlwaysDarkBackground")
        } else {
            return Color("AlwaysLightBackground")
        }
    }

    @State var showPicker = false
    @State var animateIcon = false

    @Namespace var animation

    @State var swipingOffset: CGFloat = 0
    @GestureState var isDragging = false

    // show recommendations

    @State var textFieldFocused: Bool = false

    @AppStorage(
        "showTransactionRecommendations", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var showRecommendations: Bool = false

    var suggestedTransactions: [Transaction] {
        return dataController.getSuggestedNotes(searchQuery: note, category: category, income: income)
    }

    var showingNotePicker: Bool {
        return note != "" && toEdit == nil && !suggestedTransactions.isEmpty && textFieldFocused
        && showRecommendations
    }

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var fontSize: CGFloat {
        switch dynamicTypeSize {
        case .xSmall:
            return 14
        case .small:
            return 15
        case .medium:
            return 16
        case .large:
            return 17
        case .xLarge:
            return 19
        case .xxLarge:
            return 21
        case .xxxLarge:
            return 23
        default:
            return 23
        }
    }

    var widthOfCategoryButton: CGFloat {
        let fontSize = UIFont.getBodyFontSize(dynamicTypeSize: dynamicTypeSize)

        return "Category".widthOfRoundedString(size: fontSize, weight: .semibold) + 50
    }

    var capsuleWidth: CGFloat {
        if dynamicTypeSize > .xLarge {
            return 120
        } else {
            return 100
        }
    }

    @State private var price: Double = 0
    @AppStorage("numberEntryType", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var numberEntryType: Int = 1
    @State var isEditingDecimal = false
    @State var decimalValuesAssigned: AssignedDecimal = .none
    @State private var priceString: String = "0"

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 8) {
                // income/expense picker
                VStack {
                    if showToast {
                        HStack(spacing: 6.5) {
                            Image(systemName: toastImage)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundColor(Color.AlertRed)

                            Text(toastTitle)
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .lineLimit(1)
                                .foregroundColor(Color.AlertRed)
                        }
                        .padding(8)
                        .background(
                            Color.AlertRed.opacity(0.23),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .transition(AnyTransition.opacity.combined(with: .move(edge: .top)))
                        .frame(maxWidth: dynamicTypeSize > .xLarge ? 250 : 200)
                    } else {
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.SecondaryBackground)
                                .frame(width: capsuleWidth)
                                .offset(x: swipingOffset)

                            HStack(spacing: 0) {
                                Text("Expense")
                                    .font(.system(.body, design: .rounded).weight(.semibold))

                                    .lineLimit(1)
                                    .foregroundColor(income == false ? Color.PrimaryText : Color.SubtitleText)
                                    .padding(6)
                                    .frame(width: capsuleWidth)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        DispatchQueue.main.async {
                                            withAnimation(.easeIn(duration: 0.15)) {
                                                income = false
                                                swipingOffset = 0
                                            }
                                        }
                                    }

                                Text("transaction-view-income-picker")
                                    .font(.system(.body, design: .rounded).weight(.semibold))

                                    .lineLimit(1)
                                //                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundColor(income == true ? Color.PrimaryText : Color.SubtitleText)
                                    .padding(6)
                                    .frame(width: capsuleWidth)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        DispatchQueue.main.async {
                                            withAnimation(.easeIn(duration: 0.15)) {
                                                income = true
                                                swipingOffset = capsuleWidth
                                            }
                                        }
                                    }
                            }
                        }
                        .padding(3)
                        .fixedSize(horizontal: true, vertical: true)
                        .overlay(Capsule().stroke(Color.Outline.opacity(0.4), lineWidth: 1.3))
                    }
                }
                //                .frame(height: 50, alignment: .top)
                .frame(maxWidth: .infinity)
                .overlay {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                            //                                .font(.system(size: 16, weight: .semibold))
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                                .foregroundColor(Color.SubtitleText)
                                .padding(7)
                                .background(Color.SecondaryBackground, in: Circle())
                                .contentShape(Circle())
                        }

                        Spacer()

                        Menu {
                            Button {
                                showFileImporter = true
                            } label: {
                                Label("Upload File", systemImage: "square.and.arrow.up")
                            }

                            Button {
                                showRecurring = true
                            } label: {
                                Label(repeatType > 0 ? "Edit Recurring" : "Make Recurring", systemImage: "repeat")
                            }

                            if toEdit != nil {
                                Button(role: .destructive) {
                                    toDelete = toEdit
                                    deleteMode = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                                .foregroundColor(Color.SubtitleText)
                                .padding(7)
                                .background(Color.SecondaryBackground, in: Circle())
                                .contentShape(Circle())
                        }
                        .accessibilityLabel("More options")
                        .popover(
                            present: $showRecurring,
                            attributes: {
                                $0.position = .absolute(
                                    originAnchor: .bottom,
                                    popoverAnchor: .top
                                )
                                $0.rubberBandingMode = .none
                                $0.sourceFrameInset = UIEdgeInsets(top: 0, left: 0, bottom: -10, right: 0)
                                $0.presentation.animation = .easeInOut(duration: 0.2)
                                $0.dismissal.animation = .easeInOut(duration: 0.3)
                            }
                        ) {
                            RecurringPickerView(
                                repeatType: $repeatType, repeatCoefficient: $repeatCoefficient,
                                showMenu: $showRecurring, showPicker: $showPicker)
                        } background: {
                            backgroundColor.opacity(0.6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, topEdge)

                ZStack {
                    // swipe to change between income and expense
                    Color.PrimaryBackground
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .simultaneousGesture(
                            DragGesture()
                                .updating(
                                    $isDragging,
                                    body: { _, state, _ in
                                        state = true
                                    }
                                )
                                .onChanged { gesture in
                                    let swipe = gesture.translation.width

                                    if income {
                                        if swipe < 0 {
                                            swipingOffset = max(-capsuleWidth, -pow(abs(swipe), 0.8)) + capsuleWidth
                                        }

                                    } else {
                                        if swipe > 0 {
                                            swipingOffset = min(capsuleWidth, pow(swipe, 0.8))
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    if income {
                                        if swipingOffset < (capsuleWidth / 2) {
                                            withAnimation {
                                                swipingOffset = 0
                                                income = false
                                            }
                                        } else {
                                            withAnimation {
                                                swipingOffset = capsuleWidth
                                            }
                                        }
                                    } else {
                                        if swipingOffset > (capsuleWidth / 2) {
                                            withAnimation {
                                                swipingOffset = capsuleWidth
                                                income = true
                                            }
                                        } else {
                                            withAnimation {
                                                swipingOffset = 0
                                            }
                                        }
                                    }
                                }
                        )

                    // number display and note view
                    VStack(spacing: 8) {
                        NumberPadTextView(price: $price, isEditingDecimal: $isEditingDecimal, decimalValuesAssigned: $decimalValuesAssigned)
                        NoteView(note: $note, focused: $textFieldFocused)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showingNotePicker {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestedTransactions, id: \.self) { transaction in
                                Button {
                                    note = transaction.wrappedNote
                                    withAnimation {
                                        if price == 0 {
                                            price = transaction.wrappedAmount
                                        }
                                        if category == nil {
                                            category = transaction.category
                                        }
                                    }
                                    self.hideKeyboard()
                                } label: {
                                    HStack(spacing: 3) {
                                        Text(transaction.wrappedNote)
                                            .foregroundStyle(Color.PrimaryText)
                                            .lineLimit(1)
                                            .padding(.vertical, 3.5)
                                            .padding(.horizontal, 7)

                                        Text("\(currencySymbol)\(Int(round(transaction.wrappedAmount)))")
                                            .lineLimit(1)
                                            .foregroundStyle(Color(hex: transaction.wrappedColour))
                                            .padding(.vertical, 3.5)
                                            .padding(.horizontal, 5)
                                            .background(
                                                Color(hex: transaction.wrappedColour).opacity(0.23),
                                                in: RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                                    }
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .padding(5)
                                    .background(
                                        Color.SecondaryBackground,
                                        in: RoundedRectangle(cornerRadius: 11.5, style: .continuous))
                                }
                            }
                        }
                    }
                    .padding(.bottom, 5)
                } else {
                    HStack(spacing: 8) {
                        HStack(spacing: 7) {
                            Group {
                                if date < Date.now {
                                    Image(systemName: "calendar")
                                } else {
                                    if #available(iOS 17.0, *) {
                                        Image(systemName: "rays")
                                            .symbolEffect(
                                                .variableColor.iterative.dimInactiveLayers.nonReversing,
                                                options: .repeating, value: animateIcon)
                                    } else {
                                        Image(systemName: "slowmo")
                                            .foregroundColor(Color.SubtitleText)
                                    }
                                }
                            }
                            .foregroundColor(Color.SubtitleText)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))

                            Group {
                                if isDateToday(date: date) {
                                    Text("Today, \(getDateString(date: date))")
                                        .lineLimit(1)
                                } else {
                                    Text(getDateString(date: date))
                                        .lineLimit(1)
                                }
                            }
                            .font(.system(.body, design: .rounded).weight(.semibold))

                            if showTime {
                                Spacer()

                                Text(getTimeString(date: date))
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                            }
                        }
                        .foregroundColor(Color.PrimaryText)
                        .padding(.vertical, 8.5)
                        .padding(.horizontal, 10)
                        .animation(.default, value: isDateToday(date: date))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                                .strokeBorder(Color.Outline, lineWidth: 1.5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIApplication.shared.endEditing()
                            showingDatePicker = true
                        }

                        if (expenseCategories.count == 0 && !income) || (incomeCategories.count == 0 && income) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))

                                Text("Category")
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 8.5)
                            .padding(.horizontal, 10)
                            .foregroundColor(categoryButtonTextColor)
                            .background(
                                categoryButtonBackgroundColor,
                                in: RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                            )
                            .contentShape(Rectangle())
                            .overlay(
                                RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                                    .strokeBorder(categoryButtonOutlineColor, lineWidth: 1.5)
                            )
                            .drawingGroup()
                            .offset(x: shake ? -5 : 0)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                showCategorySheet = true
                            }
                        } else {

                            Group {
                                if showCategoryPicker {
                                    HStack(spacing: 10) {

                                        Text("Close")
                                            .font(.system(.body, design: .rounded).weight(.semibold))
                                            .lineLimit(1)

//                                        Image(systemName: "xmark.circle.fill")
//                                            .font(.system(.footnote, design: .rounded).weight(.bold))
                                    }
                                    .padding(.vertical, 8.5)
                                    .padding(.horizontal, 10)
                                    .frame(width: widthOfCategoryButton)
                                    .foregroundColor(Color.AlertRed)
                                    .background(Color.AlertRed.opacity(0.23),
                                        in: RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                                    )
                                } else {
                                    if let unwrappedCategory = category {
                                        HStack(spacing: 5) {
                                            Text(unwrappedCategory.wrappedEmoji)
                                                .font(.system(.footnote, design: .rounded).weight(.semibold))

                                            Text(unwrappedCategory.wrappedName)
                                                .font(.system(.body, design: .rounded).weight(.semibold))
                                                .lineLimit(1)
                                        }
                                        .padding(.vertical, 8.5)
                                        .padding(.horizontal, 10)
                                        .foregroundColor(Color(hex: unwrappedCategory.wrappedColour))
                                        .background(
                                            Color(hex: unwrappedCategory.wrappedColour).opacity(0.35),
                                            in: RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                                        )
    //                                    .popover(
    //                                        present: $showCategoryPicker,
    //                                        attributes: {
    //                                            $0.position = .absolute(
    //                                                originAnchor: .topRight,
    //                                                popoverAnchor: .bottomRight
    //                                            )
    //                                            $0.rubberBandingMode = .none
    //                                            $0.sourceFrameInset = UIEdgeInsets(top: -10, left: 0, bottom: 0, right: 0)
    //                                            $0.presentation.animation = .easeInOut(duration: 0.2)
    //                                            $0.dismissal.animation = .easeInOut(duration: 0.3)
    //                                        }
    //                                    ) {
    //                                        CategoryPickerView(
    //                                            category: $category, showPicker: $showCategoryPicker,
    //                                            showSheet: $showCategorySheet, income: income, darkMode: darkMode
    //                                        )
    //                                        .environment(\.managedObjectContext, self.moc)
    //                                    } background: {
    //                                        backgroundColor.opacity(0.6)
    //                                    }
                                    } else {
                                        HStack(spacing: 5.5) {
                                            if #available(iOS 17.0, *) {
                                                Image(systemName: "circle.grid.2x2")
                                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                                    .symbolEffect(
                                                        .bounce.up.byLayer, options: .repeating.speed(0.5),
                                                        value: showCategoryPicker)
                                            } else {
                                                Image(systemName: "circle.grid.2x2")
                                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                            }

                                            Text("Category")
                                                .font(.system(.body, design: .rounded).weight(.semibold))
                                                .lineLimit(1)
                                        }
                                        .padding(.vertical, 8.5)
                                        .padding(.horizontal, 10)
                                        .frame(width: widthOfCategoryButton)
                                        .foregroundColor(categoryButtonTextColor)
                                        .background(
                                            categoryButtonBackgroundColor,
                                            in: RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                                                .strokeBorder(categoryButtonOutlineColor, lineWidth: 1.5)
                                        )
                                        .drawingGroup()
                                        .offset(x: shake ? -5 : 0)
    //                                    .popover(
    //                                        present: $showCategoryPicker,
    //                                        attributes: {
    //                                            $0.position = .absolute(
    //                                                originAnchor: .topRight,
    //                                                popoverAnchor: .bottomRight
    //                                            )
    //                                            $0.rubberBandingMode = .none
    //                                            $0.sourceFrameInset = UIEdgeInsets(top: -10, left: 0, bottom: 0, right: 0)
    //                                            $0.presentation.animation = .easeInOut(duration: 0.2)
    //                                            $0.dismissal.animation = .easeInOut(duration: 0.3)
    //                                        }
    //                                    ) {
    //                                        CategoryPickerView(
    //                                            category: $category, showPicker: $showCategoryPicker,
    //                                            showSheet: $showCategorySheet, income: income, darkMode: darkMode
    //                                        )
    //                                        .environment(\.managedObjectContext, self.moc)
    //                                    } background: {
    //                                        backgroundColor.opacity(0.6)
    //                                    }
                                    }
                                }

                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut) {
                                    showCategoryPicker.toggle()
                                }

                            }
                        }
                    }
                    .padding(.bottom, 5)
                }

                // date and category picker

                if showCategoryPicker {
                    NewCategoryPickerView(
                        category: $category, showPicker: $showCategoryPicker,
                        showSheet: $showCategorySheet, income: income
                    )
                    .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
                } else {
                    NumberPad(
                        price: $price,
                        category: $category,
                        isEditingDecimal: $isEditingDecimal,
                        decimalValuesAssigned: $decimalValuesAssigned,
                        showingNotePicker: showingNotePicker
                    ) {
                        submit()
                    }
                    .transition(AnyTransition.move(edge: .leading).combined(with: .opacity))
                }

            }
            .padding(17)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.PrimaryBackground)
            .onTapGesture {
                self.hideKeyboard()
            }
            .fullScreenCover(isPresented: $deleteMode) {
                ZStack(alignment: .bottom) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            deleteMode = false
                            toDelete = nil
                        }

                    VStack(alignment: .leading, spacing: 1.5) {
                        Text("Delete Expense?")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundColor(.PrimaryText)

                        Text("This action cannot be undone.")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.SubtitleText)
                            .padding(.bottom, 15)

                        Button {
                            deleteMode = false

                            withAnimation {
                                if let itemToDelete = toDelete {
                                    moc.delete(itemToDelete)
                                }
                                dataController.save()
                            }

                            dismiss()

                        } label: {
                            Text("Delete")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(height: 45)
                                .frame(maxWidth: .infinity)
                                .background(
                                    Color.AlertRed, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .padding(.bottom, 8)

                        Button {
                            withAnimation(.easeOut(duration: 0.7)) {
                                deleteMode = false
                                toDelete = nil
                            }

                        } label: {
                            Text("Cancel")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(Color.PrimaryText.opacity(0.9))
                                .frame(height: 45)
                                .frame(maxWidth: .infinity)
                                .background(
                                    Color.SecondaryBackground,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                    .padding(13)
                    .background(
                        RoundedRectangle(cornerRadius: 13).fill(Color.PrimaryBackground).shadow(
                            color: systemColorScheme == .dark ? Color.clear : Color.gray.opacity(0.25), radius: 6)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13).stroke(
                            systemColorScheme == .dark ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1.3)
                    )
                    .offset(y: offset)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                if gesture.translation.height < 0 {
                                    offset = gesture.translation.height / 3
                                } else {
                                    offset = gesture.translation.height
                                }
                            }
                            .onEnded { value in
                                if value.translation.height > 20 {
                                    deleteMode = false
                                    toDelete = nil
                                } else {
                                    withAnimation {
                                        offset = 0
                                    }
                                }
                            }
                    )
                    .padding(.horizontal, 17)
                    .padding(.bottom, bottomEdge == 0 ? 12 : bottomEdge - 3)
                }
                .edgesIgnoringSafeArea(.all)
                .background(BackgroundBlurView())
            }
            .overlay {
                ZStack(alignment: .bottom) {
                    GeometryReader { _ in
                        EmptyView()
                    }
                    .background(Color.black)
                    .opacity(showingDatePicker ? 0.3 : 0)
                    .onTapGesture {
                        showingDatePicker = false
                    }

                    DatePicker("Date", selection: $date)
                        .datePickerStyle(.graphical)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
                        .padding(17)
                        .onChange(of: dateString) { _ in

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showingDatePicker = false
                            }

                            if date > Date.now {
                                animateIcon = true
                            } else {
                                animateIcon = false
                            }
                        }
                        .padding(.bottom, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .opacity(showingDatePicker ? 1 : 0)
                .allowsHitTesting(showingDatePicker)
                .animation(.easeOut(duration: 0.25), value: showingDatePicker)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .animation(.easeOut(duration: 0.2), value: showToast)
        .ignoresSafeArea(.keyboard, edges: .all)
        .frame(maxHeight: .infinity)
        .background(Color.PrimaryBackground)
        .edgesIgnoringSafeArea(.all)
        .onChange(of: showToast) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
        .onChange(of: income) { _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            category = nil
        }
        .onChange(of: isDragging) { _ in
            if !isDragging {
                if income {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        swipingOffset = capsuleWidth
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        swipingOffset = 0
                    }
                }
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                if let transaction = toEdit {
                    repeatType = Int(transaction.recurringType)
                    repeatCoefficient = Int(transaction.recurringCoefficient)
                    price = transaction.wrappedAmount

                    if transaction.wrappedAmount.truncatingRemainder(dividingBy: 1) > 0 && numberEntryType == 2 {
                        isEditingDecimal = true
                        decimalValuesAssigned = .second
                    }

                    if transaction.wrappedDate > Date.now {
                        animateIcon = true
                    }
                }
            }
        }
        .sheet(isPresented: $showCategorySheet) {
            CategoryView(mode: .transaction, income: income)
        }
        .sheet(isPresented: $showPicker) {
            if #available(iOS 16.0, *) {
                CustomRecurringView(
                    repeatType: $repeatType, repeatCoefficient: $repeatCoefficient, showPicker: $showPicker
                )
                .presentationDetents([.height(230)])
            } else {
                CustomRecurringView(
                    repeatType: $repeatType, repeatCoefficient: $repeatCoefficient, showPicker: $showPicker)
            }
        }
        .sheet(isPresented: $showImportReview) {
            if #available(iOS 16.0, *) {
                ImportReviewSheet(transactions: importedTransactions, currencySymbol: currencySymbol)
                    .presentationDetents([.medium, .large])
            } else {
                ImportReviewSheet(transactions: importedTransactions, currencySymbol: currencySymbol)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: importContentTypes
        ) { result in
            handleImportResult(result)
        }
        .onChange(of: dynamicTypeSize) { _ in
            if income {
                swipingOffset = capsuleWidth
            }
        }
    }

    func isDateToday(date: Date) -> Bool {
        let calendar = Calendar.current

        return calendar.isDateInToday(date)
    }

    func getDateString(date: Date) -> String {
        let formatter = DateFormatter()

        if isDateToday(date: date) {
            formatter.dateFormat = "d MMM"

            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "E, d MMM"

            return formatter.string(from: date)
        }
    }

    func getTimeString(date: Date) -> String {
        let formatter = DateFormatter()

        formatter.dateFormat = "HH:mm"

        return formatter.string(from: date)
    }

    func toggleFieldColors() {
        if categoryButtonTextColor == Color.AlertRed
            || categoryButtonBackgroundColor == Color.AlertRed.opacity(0.23) {
            withAnimation(.linear) {
                categoryButtonTextColor = Color.SubtitleText
                categoryButtonBackgroundColor = Color.clear
                categoryButtonOutlineColor = Color.Outline
            }
        } else {
            withAnimation(.easeOut(duration: 1.0)) {
                categoryButtonTextColor = Color.AlertRed
                categoryButtonBackgroundColor = Color.AlertRed.opacity(0.23)
                categoryButtonOutlineColor = Color.AlertRed
            }
            withAnimation(.easeInOut(duration: 0.1).repeatCount(5)) {
                shake = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    shake = false
                }
                withAnimation(.easeOut(duration: 0.6)) {
                    categoryButtonTextColor = Color.SubtitleText
                    categoryButtonBackgroundColor = Color.clear
                    categoryButtonOutlineColor = Color.Outline
                }
            }
        }

    }

    func submit() {
        let generator = UINotificationFeedbackGenerator()

        if price == 0 && category == nil {
            toastImage = "questionmark.app"
            toastTitle = "Incomplete Entry"
            showToast = true
            toggleFieldColors()

            generator.notificationOccurred(.error)

            return
        } else if price == 0 {
            toastImage = "centsign.circle"
            toastTitle = "Missing Amount"
            showToast = true
            generator.notificationOccurred(.error)
            return
        } else if category == nil {
            toastImage = "tray"
            toastTitle = "Missing Category"
            showToast = true

            toggleFieldColors()

            generator.notificationOccurred(.error)
            return
        }

        generator.notificationOccurred(.success)

        if let editedTransaction = toEdit {
            if note.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
                editedTransaction.note = category!.wrappedName
            } else {
                editedTransaction.note = note.trimmingCharacters(in: .whitespaces)
            }

            if let unwrappedCategory = category {
                editedTransaction.category = unwrappedCategory
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    editedTransaction.amount = price
                    editedTransaction.date = date
                    editedTransaction.income = income

                    let calendar = Calendar(identifier: .gregorian)

                    editedTransaction.day =
                    calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date) ?? Date.now

                    let dateComponents = calendar.dateComponents([.month, .year], from: date)

                    editedTransaction.month = calendar.date(from: dateComponents) ?? Date.now

                    if repeatType > 0 {
                        editedTransaction.onceRecurring = true
                        editedTransaction.recurringType = Int16(repeatType)
                        editedTransaction.recurringCoefficient = Int16(repeatCoefficient)

                        dataController.updateRecurringTransaction(transaction: editedTransaction)
                    } else {
                        editedTransaction.onceRecurring = false
                        editedTransaction.recurringType = Int16(repeatType)
                        editedTransaction.recurringCoefficient = Int16(repeatCoefficient)
                    }

                    dataController.save()
                }
            }

            dismiss()

            return
        }

        let transaction = Transaction(context: moc)

        if note.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            transaction.note = category?.wrappedName ?? ""
        } else {
            transaction.note = note.trimmingCharacters(in: .whitespaces)
        }

        transaction.income = income

        if let unwrappedCategory = category {
            transaction.category = unwrappedCategory
        }

        transaction.amount = price
        transaction.date = date
        transaction.id = UUID()

        let calendar = Calendar(identifier: .gregorian)

        transaction.day = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date) ?? Date.now

        let dateComponents = calendar.dateComponents([.month, .year], from: date)

        transaction.month = calendar.date(from: dateComponents) ?? Date.now

        if repeatType > 0 {
            transaction.onceRecurring = true
            transaction.recurringType = Int16(repeatType)
            transaction.recurringCoefficient = Int16(repeatCoefficient)
            dataController.updateRecurringTransaction(transaction: transaction)
        }

        try? moc.save()

        dismiss()
    }

    private var importContentTypes: [UTType] {
        [
            UTType(filenameExtension: "csv"),
            UTType.pdf,
            UTType(filenameExtension: "xls"),
            UTType(filenameExtension: "xlsx")
        ].compactMap { $0 }
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            processImport(url: url)
        case .failure:
            showImportError(message: "Couldn't import that file.")
        }
    }

    private func processImport(url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer {
            if needsAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let result = try parseImportFile(url: url)
            applyImport(result)
        } catch {
            showImportError(message: error.localizedDescription)
        }
    }

    private func applyImport(_ result: ImportParseResult) {
        guard !result.transactions.isEmpty else {
            showImportError(message: "No transactions were found.")
            return
        }

        let incomeCategory = ensureUncategorizedCategory(income: true)
        let expenseCategory = ensureUncategorizedCategory(income: false)

        result.transactions.forEach { item in
            let category = item.income ? incomeCategory : expenseCategory
            _ = dataController.newTransaction(
                note: item.note,
                category: category,
                income: item.income,
                amount: item.amount,
                date: item.date,
                repeatType: 0,
                repeatCoefficient: 1,
                delay: false
            )
        }

        importedTransactions = result.transactions
        showImportReview = true
    }

    private func showImportError(message: String) {
        toastImage = "exclamationmark.triangle.fill"
        toastTitle = message
        showToast = true
    }

    private func parseImportFile(url: URL) throws -> ImportParseResult {
        let fileExtension = url.pathExtension.lowercased()

        if fileExtension == "pdf" {
            return try parsePdfImport(url: url)
        }

        if ["csv", "xls", "xlsx"].contains(fileExtension) {
            let data = try Data(contentsOf: url)
            guard let text = decodeText(from: data) else {
                throw ImportError.unreadableFile
            }

            let rows = parseDelimitedRows(from: text)
            guard !rows.isEmpty else {
                throw ImportError.noTransactions
            }

            if let invoice = parseInvoiceCSV(rows: rows) {
                return ImportParseResult(transactions: [invoice], kind: .invoice)
            }

            let statementTransactions = parseStatementCSV(rows: rows)
            guard !statementTransactions.isEmpty else {
                throw ImportError.noTransactions
            }

            return ImportParseResult(transactions: statementTransactions, kind: .statement)
        }

        throw ImportError.unsupportedFile
    }

    private func parsePdfImport(url: URL) throws -> ImportParseResult {
        guard let document = PDFDocument(url: url) else {
            throw ImportError.unreadableFile
        }

        let text = (0 ..< document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw ImportError.unreadableFile
        }

        let statementTransactions = parseStatementPDF(text: text)
        if statementTransactions.count >= 2 {
            return ImportParseResult(transactions: statementTransactions, kind: .statement)
        }

        if let invoice = parseInvoicePDF(text: text) {
            return ImportParseResult(transactions: [invoice], kind: .invoice)
        }

        throw ImportError.noTransactions
    }

    private func parseStatementCSV(rows: [[String]]) -> [ImportedTransaction] {
        guard let header = rows.first else {
            return []
        }

        let normalizedHeader = header.map { normalizeHeader($0) }
        var dateIndex = index(in: normalizedHeader, matches: ["date", "posted", "transaction date"])
        var noteIndex = index(in: normalizedHeader, matches: ["description", "merchant", "payee", "memo", "note", "details", "narrative", "name"])
        var amountIndex = index(in: normalizedHeader, matches: ["amount", "amt", "value"])
        var debitIndex = index(in: normalizedHeader, matches: ["debit", "withdrawal", "paid out"])
        var creditIndex = index(in: normalizedHeader, matches: ["credit", "deposit", "paid in"])
        let typeIndex = index(in: normalizedHeader, matches: ["type", "transaction type"])
        let categoryIndex = index(in: normalizedHeader, matches: ["category"])

        let dataRows = Array(rows.dropFirst())

        if dateIndex == nil {
            dateIndex = detectColumnIndex(in: dataRows) { parseDate(from: $0) != nil }
        }

        if amountIndex == nil && debitIndex == nil && creditIndex == nil {
            amountIndex = detectColumnIndex(in: dataRows) { parseAmount(from: $0) != nil }
        }

        if noteIndex == nil {
            let excluded = Set([dateIndex, amountIndex, debitIndex, creditIndex].compactMap { $0 })
            noteIndex = detectNoteColumn(in: dataRows, excluding: excluded)
        }

        return dataRows.compactMap { row in
            let dateValue = value(in: row, at: dateIndex)
            let noteValue = value(in: row, at: noteIndex)
            let typeValue = value(in: row, at: typeIndex)?.lowercased() ?? ""
            let categoryValue = value(in: row, at: categoryIndex)?.lowercased() ?? ""

            if noteValue?.lowercased().contains("opening balance") == true || categoryValue.contains("balance") {
                return nil
            }

            guard let parsedDate = parseDate(from: dateValue) else {
                return nil
            }

            var amount: Double?
            var incomeFlag: Bool?

            if let debitValue = value(in: row, at: debitIndex), let debitAmount = parseAmount(from: debitValue), debitAmount > 0 {
                amount = debitAmount
                incomeFlag = false
            } else if let creditValue = value(in: row, at: creditIndex), let creditAmount = parseAmount(from: creditValue), creditAmount > 0 {
                amount = creditAmount
                incomeFlag = true
            } else if let amountValue = value(in: row, at: amountIndex), let parsedAmount = parseAmount(from: amountValue) {
                amount = abs(parsedAmount)
                if parsedAmount < 0 {
                    incomeFlag = false
                } else if typeValue.contains("debit") || typeValue.contains("withdraw") || typeValue.contains("purchase") {
                    incomeFlag = false
                } else if typeValue.contains("credit") || typeValue.contains("deposit") || typeValue.contains("refund") {
                    incomeFlag = true
                } else {
                    incomeFlag = parsedAmount >= 0
                }
            }

            guard let finalAmount = amount, finalAmount > 0, let isIncome = incomeFlag else {
                return nil
            }

            let note = noteValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalNote = (note?.isEmpty == false) ? note! : "Imported Transaction"

            return ImportedTransaction(
                note: finalNote,
                amount: finalAmount,
                date: parsedDate,
                income: isIncome
            )
        }
    }

    private func parseInvoiceCSV(rows: [[String]]) -> ImportedTransaction? {
        guard let header = rows.first, rows.count >= 2 else {
            return nil
        }

        let lowerHeader = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let headerText = lowerHeader.joined(separator: " ")
        let looksLikeInvoice = headerText.contains("invoice") || headerText.contains("bill")

        let dataRows = rows.dropFirst()
        guard dataRows.count == 1 || looksLikeInvoice else {
            return nil
        }

        guard let row = dataRows.first else {
            return nil
        }

        let dateIndex = index(in: lowerHeader, matches: ["date", "invoice date", "bill date"])
        let noteIndex = index(in: lowerHeader, matches: ["vendor", "from", "merchant", "payee", "description", "note", "details", "name"])
        let amountIndex = index(in: lowerHeader, matches: ["amount", "total", "balance", "due", "amt", "value"])

        let noteValue = value(in: row, at: noteIndex)
        let dateValue = value(in: row, at: dateIndex)
        let amountValue = value(in: row, at: amountIndex) ?? row.last

        guard let rawAmountValue = amountValue, let amount = parseAmount(from: rawAmountValue) else {
            return nil
        }

        let note = noteValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNote = (note?.isEmpty == false) ? note! : "Invoice"
        let finalDate = parseDate(from: dateValue) ?? Date.now

        return ImportedTransaction(
            note: finalNote,
            amount: abs(amount),
            date: finalDate,
            income: false
        )
    }

    private func parseStatementPDF(text: String) -> [ImportedTransaction] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var transactions: [ImportedTransaction] = []

        for line in lines {
            guard let dateString = extractDateString(from: line), let date = parseDate(from: dateString) else {
                continue
            }

            let amounts = extractAmounts(from: line)
            guard !amounts.isEmpty else { continue }

            let transactionAmount = amounts.count >= 2 ? amounts[amounts.count - 2] : amounts[0]
            let incomeFlag = inferIncome(from: line, amount: transactionAmount)
            let note = extractNote(from: line, dateString: dateString, amounts: amounts)

            transactions.append(
                ImportedTransaction(
                    note: note,
                    amount: abs(transactionAmount),
                    date: date,
                    income: incomeFlag
                )
            )
        }

        return transactions
    }

    private func parseInvoicePDF(text: String) -> ImportedTransaction? {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let vendor = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Invoice"
        let amount = extractLabeledAmount(from: lines, labels: [
            "total due", "amount due", "balance due", "total", "amount"
        ]) ?? extractAmount(from: text)

        guard let finalAmount = amount else {
            return nil
        }

        let date = parseDate(from: text) ?? Date.now

        return ImportedTransaction(
            note: vendor,
            amount: abs(finalAmount),
            date: date,
            income: false
        )
    }

    private func parseDelimitedRows(from text: String) -> [[String]] {
        guard let delimiter = detectDelimiter(in: text) else {
            return []
        }

        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]

            if char == "\"" {
                let nextIndex = text.index(after: index)
                if inQuotes && nextIndex < text.endIndex && text[nextIndex] == "\"" {
                    currentField.append("\"")
                    index = nextIndex
                } else {
                    inQuotes.toggle()
                }
            } else if char == delimiter && !inQuotes {
                currentRow.append(currentField.trimmingCharacters(in: .whitespacesAndNewlines))
                currentField = ""
            } else if (char == "\n" || char == "\r") && !inQuotes {
                if char == "\r" {
                    let nextIndex = text.index(after: index)
                    if nextIndex < text.endIndex && text[nextIndex] == "\n" {
                        index = nextIndex
                    }
                }

                currentRow.append(currentField.trimmingCharacters(in: .whitespacesAndNewlines))
                currentField = ""

                if currentRow.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    rows.append(currentRow)
                }
                currentRow = []
            } else {
                currentField.append(char)
            }

            index = text.index(after: index)
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField.trimmingCharacters(in: .whitespacesAndNewlines))
            if currentRow.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                rows.append(currentRow)
            }
        }

        return rows
    }

    private func detectDelimiter(in text: String) -> Character? {
        guard let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) else {
            return nil
        }

        let candidates: [Character] = [",", "\t", ";", "|"]
        var best: (delimiter: Character, count: Int)?

        for delimiter in candidates {
            let count = firstLine.filter { $0 == delimiter }.count
            if count > (best?.count ?? 0) {
                best = (delimiter, count)
            }
        }

        return best?.count ?? 0 > 0 ? best?.delimiter : nil
    }

    private func decodeText(from data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .utf16) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        return nil
    }

    private func parseAmount(from value: String) -> Double? {
        let sanitized = value
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: "€", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var negative = false
        var working = sanitized

        if working.hasPrefix("(") && working.hasSuffix(")") {
            negative = true
            working = working.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        }

        if working.hasPrefix("-") {
            negative = true
            working = working.replacingOccurrences(of: "-", with: "")
        }

        guard let number = Double(working) else {
            return nil
        }

        return negative ? -number : number
    }

    private func extractAmounts(from text: String) -> [Double] {
        let pattern = "[-]?\\(?\\$?\\d{1,3}(?:,\\d{3})*(?:\\.\\d{2})?\\)?|\\$?\\d+(?:\\.\\d{2})?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        return matches.compactMap { match -> Double? in
            guard let matchRange = Range(match.range, in: text) else {
                return nil
            }
            let token = String(text[matchRange])
            if token.count == 4, let year = Double(token), year >= 1900, year <= 2100 {
                return nil
            }
            return parseAmount(from: token)
        }
    }

    private func extractAmount(from text: String) -> Double? {
        extractAmounts(from: text).last
    }

    private func parseDate(from value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let formats = [
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "yyyy.MM.dd",
            "MM/dd/yyyy",
            "M/d/yyyy",
            "MM-dd-yyyy",
            "M-d-yyyy",
            "dd/MM/yyyy",
            "d/M/yyyy",
            "dd-MM-yyyy",
            "d-M-yyyy",
            "d MMM yyyy",
            "MMM d, yyyy",
            "MMM d yyyy"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        if let inferred = parseDateWithoutYear(from: value) {
            return inferred
        }

        let tokens = value
            .replacingOccurrences(of: ",", with: "")
            .split(separator: " ")
            .map { String($0) }

        for index in tokens.indices {
            let token = tokens[index]
            for format in formats {
                formatter.dateFormat = format
                if let date = formatter.date(from: token) {
                    return date
                }
            }

            if index + 1 < tokens.count {
                let combined = token + " " + tokens[index + 1]
                for format in formats {
                    formatter.dateFormat = format
                    if let date = formatter.date(from: combined) {
                        return date
                    }
                }
            }

            if index + 2 < tokens.count {
                let combined = token + " " + tokens[index + 1] + " " + tokens[index + 2]
                for format in formats {
                    formatter.dateFormat = format
                    if let date = formatter.date(from: combined) {
                        return date
                    }
                }
            }
        }

        return nil
    }

    private func parseDateWithoutYear(from value: String) -> Date? {
        let parts = value
            .split(separator: "/")
            .map { String($0) }

        guard parts.count == 2,
              let first = Int(parts[0]),
              let second = Int(parts[1]) else {
            return nil
        }

        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: Date.now)

        let month = min(max(first, 1), 12)
        let day = min(max(second, 1), 31)

        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private func inferIncome(from line: String, amount: Double) -> Bool {
        if amount < 0 {
            return false
        }

        let lower = line.lowercased()
        if lower.contains("credit") || lower.contains("deposit") || lower.contains("refund") || lower.contains("interest") {
            return true
        }
        if lower.contains("debit") || lower.contains("withdraw") || lower.contains("purchase") || lower.contains("payment") || lower.contains("atm") {
            return false
        }

        return amount >= 0
    }

    private func extractNote(from line: String, date: Date, amount: Double) -> String {
        var note = line
        if let dateString = formatDate(date) {
            note = note.replacingOccurrences(of: dateString, with: "")
        }

        let amountString = String(format: "%.2f", abs(amount))
        note = note.replacingOccurrences(of: amountString, with: "")

        let cleaned = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Imported Transaction" : cleaned
    }

    private func extractNote(from line: String, dateString: String, amounts: [Double]) -> String {
        var note = line
        note = note.replacingOccurrences(of: dateString, with: "")

        amounts.forEach { amount in
            let amountString = String(format: "%.2f", abs(amount))
            note = note.replacingOccurrences(of: amountString, with: "")
        }

        let cleaned = note
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? "Imported Transaction" : cleaned
    }

    private func formatDate(_ date: Date) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func extractLabeledAmount(from lines: [String], labels: [String]) -> Double? {
        for line in lines {
            let lower = line.lowercased()
            if labels.contains(where: { lower.contains($0) }) {
                let amounts = extractAmounts(from: line)
                if let amount = amounts.last {
                    return amount
                }
            }
        }
        return nil
    }

    private func extractDateString(from line: String) -> String? {
        let pattern = "\\b\\d{1,2}/\\d{1,2}/\\d{2,4}\\b|\\b\\d{1,2}/\\d{1,2}\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let matchRange = Range(match.range, in: line) else {
            return nil
        }

        return String(line[matchRange])
    }

    private func index(in header: [String], matches keywords: [String]) -> Int? {
        let normalizedKeywords = keywords.map { normalizeHeader($0) }
        for (index, value) in header.enumerated() {
            if normalizedKeywords.contains(where: { value.contains($0) }) {
                return index
            }
        }
        return nil
    }

    private func normalizeHeader(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "\u{feff}", with: "")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let filtered = cleaned.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " }
        let normalized = String(filtered)
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized
    }

    private func detectColumnIndex(in rows: [[String]], predicate: (String) -> Bool) -> Int? {
        let columnCount = rows.map { $0.count }.max() ?? 0
        guard columnCount > 0 else { return nil }

        var bestIndex: Int?
        var bestScore = 0

        for index in 0..<columnCount {
            let score = rows.compactMap { index < $0.count ? $0[index] : nil }
                .filter { predicate($0) }
                .count

            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        return bestScore > 0 ? bestIndex : nil
    }

    private func detectNoteColumn(in rows: [[String]], excluding excluded: Set<Int>) -> Int? {
        let columnCount = rows.map { $0.count }.max() ?? 0
        guard columnCount > 0 else { return nil }

        var bestIndex: Int?
        var bestScore = 0

        for index in 0..<columnCount where !excluded.contains(index) {
            let score = rows.compactMap { index < $0.count ? $0[index] : nil }
                .filter { $0.rangeOfCharacter(from: .letters) != nil }
                .count

            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        return bestScore > 0 ? bestIndex : nil
    }

    private func value(in row: [String], at index: Int?) -> String? {
        guard let index = index, index < row.count else {
            return nil
        }
        return row[index]
    }

    private func ensureUncategorizedCategory(income: Bool) -> Category {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "income = %d AND name =[c] %@", income, "Uncategorized")

        if let existing = try? moc.fetch(request).first {
            return existing
        }

        let category = Category(context: moc)
        category.name = "Uncategorized"
        category.emoji = "❓"
        category.dateCreated = Date.now
        category.id = UUID()
        category.income = income

        if income {
            category.colour = "IncomeGreen"
        } else {
            category.colour = nextExpenseColor()
        }

        category.order = nextCategoryOrder(income: income)
        dataController.save()

        return category
    }

    private func nextCategoryOrder(income: Bool) -> Int64 {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Category.order, ascending: true)]
        request.predicate = NSPredicate(format: "income = %d", income)

        let results = (try? moc.fetch(request)) ?? []
        return (results.last?.order ?? 0) + 1
    }

    private func nextExpenseColor() -> String {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.predicate = NSPredicate(format: "income = %d", false)
        let categories = (try? moc.fetch(request)) ?? []
        let usedColors = Set(categories.map { $0.wrappedColour })

        if let available = Color.colorArray.first(where: { !usedColors.contains($0) }) {
            return available
        }

        return Color.colorArray.first ?? "#279AF4"
    }

    init(toEdit: Transaction? = nil) {
        if let transaction = toEdit {
            _note = State(initialValue: transaction.wrappedNote)

            if let unwrappedCategory = transaction.category {
                _category = State(initialValue: unwrappedCategory)
            }

            _income = State(initialValue: transaction.income)

            if transaction.income {
                _swipingOffset = State(initialValue: 100)
            }

            _date = State(initialValue: transaction.date ?? Date.now)
        }
        self.toEdit = toEdit
    }

    init(category: Category? = nil) {
        if let unwrappedCategory = category {
            _income = State(initialValue: false)
            _category = State(initialValue: unwrappedCategory)
        }

        toEdit = nil
    }
}

struct ImportedTransaction: Identifiable {
    let id = UUID()
    let note: String
    let amount: Double
    let date: Date
    let income: Bool
}

enum ImportSourceType {
    case statement
    case invoice
}

struct ImportParseResult {
    let transactions: [ImportedTransaction]
    let kind: ImportSourceType
}

enum ImportError: LocalizedError {
    case unreadableFile
    case unsupportedFile
    case noTransactions

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "We couldn't read that file."
        case .unsupportedFile:
            return "That file type isn't supported."
        case .noTransactions:
            return "No transactions were found."
        }
    }
}

struct ImportReviewSheet: View {
    let transactions: [ImportedTransaction]
    let currencySymbol: String

    @Environment(\.dismiss) var dismiss

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.SubtitleText)
                        .padding(7)
                        .background(Color.SecondaryBackground, in: Circle())
                        .contentShape(Circle())
                }

                Spacer()

                Text("Imported Transactions")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundColor(Color.PrimaryText)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.IncomeGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.IncomeGreen.opacity(0.23), in: Capsule())
                }
            }

            if transactions.isEmpty {
                Text("No transactions to review.")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundColor(Color.SubtitleText)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(transactions) { transaction in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(transaction.note)
                                        .font(.system(.body, design: .rounded).weight(.semibold))
                                        .foregroundColor(Color.PrimaryText)
                                        .lineLimit(1)

                                    Text(dateFormatter.string(from: transaction.date))
                                        .font(.system(.caption, design: .rounded).weight(.medium))
                                        .foregroundColor(Color.SubtitleText)
                                }

                                Spacer()

                                Text("\(currencySymbol)\(String(format: "%.2f", transaction.amount))")
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .foregroundColor(transaction.income ? Color.IncomeGreen : Color.AlertRed)
                            }
                            .padding(10)
                            .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.PrimaryBackground)
    }
}

struct FilteredSearchNewTransactionView: View {
    @FetchRequest<Transaction> private var transactions: FetchedResults<Transaction>

    var searchQuery: String
    var category: Category?

    var body: some View {
        ScrollView(.horizontal) {
            if transactions.count > 0 && category != nil {
                HStack {
                    ForEach(filterOutDupes(day: transactions)) { transaction in
                        Text(transaction.wrappedNote)
                    }
                }
            }
        }
    }

    init(searchQuery: String, category: Category?) {
        let beginPredicate = NSPredicate(
            format: "%K BEGINSWITH[cd] %@", #keyPath(Transaction.note), searchQuery)
        let containPredicate = NSPredicate(
            format: "%K CONTAINS[cd] %@", #keyPath(Transaction.note), searchQuery)
        let compound = NSCompoundPredicate(orPredicateWithSubpredicates: [
            beginPredicate, containPredicate
        ])

        if let unwrappedCategory = category {
            let categoryPredicate = NSPredicate(
                format: "%K == %@", #keyPath(Transaction.category), unwrappedCategory)

            let andPredicate = NSCompoundPredicate(
                type: .and, subpredicates: [compound, categoryPredicate])

            _transactions = FetchRequest<Transaction>(
                sortDescriptors: [
                    SortDescriptor(\.date, order: .reverse)
                ], predicate: andPredicate)
        } else {
            _transactions = FetchRequest<Transaction>(
                sortDescriptors: [
                    SortDescriptor(\.date, order: .reverse)
                ], predicate: compound)
        }

        self.searchQuery = searchQuery
        self.category = category
    }

    func filterOutDupes(day: FetchedResults<Transaction>) -> [Transaction] {
        var seen = [Transaction]()
        let filtered = day.filter { entity -> Bool in
            if seen.contains(where: { $0.wrappedNote == entity.wrappedNote }) {
                return false
            } else {
                seen.append(entity)
                return true
            }
        }

        return filtered
    }
}

struct NumPadButton: ButtonStyle {
    public func makeBody(configuration: Self.Configuration) -> some View {
        return configuration.label
            .scaleEffect(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.3), value: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

func getDollarOffset(big: CGFloat, small: CGFloat) -> CGFloat {
    let bigFont = UIFont.rounded(ofSize: big, weight: .regular)
    let smallFont = UIFont.rounded(ofSize: small, weight: .light)

    return bigFont.capHeight - smallFont.capHeight - 1
}

struct CategoryPickerView: View {
    @Binding var category: Category?
    @Binding var showPicker: Bool
    @Binding var showingCategoryView: Bool
    @FetchRequest private var categories: FetchedResults<Category>

    let initialCategory: Category?

    var darkMode: Bool

    var backgroundColor: Color {
        if darkMode {
            return Color("AlwaysDarkBackground")
        } else {
            return Color("AlwaysLightBackground")
        }
    }

    var secondaryBackgroundColor: Color {
        if darkMode {
            return Color("AlwaysDarkSecondaryBackground")
        } else {
            return Color("AlwaysLightSecondaryBackground")
        }
    }

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var heightOfScrollView: Double {
        let fontSize = UIFont.getBodyFontSize(dynamicTypeSize: dynamicTypeSize)

        let font = UIFont.rounded(ofSize: fontSize, weight: .semibold)

        if categories.count == 1 && initialCategory != nil {
            return font.lineHeight + 14.1
        }

        if initialCategory != nil {
            let height = Double(min(6, categories.count)) * (font.lineHeight + 14.1)
            let gap = Double(min(5, categories.count - 1)) * 8.0
            return height + gap
        } else {
            let height = Double(min(6, categories.count + 1)) * (font.lineHeight + 14.1)
            let gap = Double(min(5, categories.count)) * 8.0
            return height + gap
        }
    }

    var body: some View {
        //        VStack(alignment: .trailing, spacing: 8) {

        //            if categories.count > 1 || category == nil {
        HStack {
            Color.clear
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    showPicker = false
                }

            VStack(
                alignment: .trailing, spacing: (categories.count == 1 && initialCategory != nil) ? 0 : 8
            ) {
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Edit")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .foregroundColor(darkMode ? Color("AlwaysLightBackground") : Color("AlwaysDarkBackground"))
                .background(
                    RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                        .fill(
                            darkMode
                            ? Color("AlwaysDarkSecondaryBackground") : Color("AlwaysLightSecondaryBackground"))
                )
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .onTapGesture {
                    let impactMed = UIImpactFeedbackGenerator(style: .light)
                    impactMed.impactOccurred()
                    showPicker = false
                    showingCategoryView = true
                }

                ScrollView(showsIndicators: false) {
                    ScrollViewReader { value in
                        VStack(alignment: .trailing, spacing: 8) {
                            ForEach(categories) { item in
                                if item != initialCategory {
                                    HStack(spacing: 7) {
                                        Text(item.wrappedEmoji)
                                            .font(.system(.footnote, design: .rounded))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                        //                                                    .font(.system(size: 14))
                                        Text(item.wrappedName)
                                            .font(.system(.body, design: .rounded).weight(.semibold))
                                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                        //                                                    .font(.system(size: 17.5, weight: .semibold, design: .rounded))
                                            .lineLimit(1)
                                    }
                                    .id(item.id)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .foregroundColor(
                                        darkMode ? Color("AlwaysLightBackground") : Color("AlwaysDarkBackground")
                                    )
                                    .background(
                                        item == category ? secondaryBackgroundColor : backgroundColor,
                                        in: RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                                    )
                                    .contentShape(Rectangle())
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                                            .strokeBorder(
                                                darkMode ? Color("AlwaysDarkOutline") : Color("AlwaysLightOutline"),
                                                style: StrokeStyle(lineWidth: 1.5))
                                    }
                                    .onTapGesture {
                                        if category == item {
                                            category = nil
                                        } else {
                                            category = item
                                        }

                                        showPicker = false
                                        //
                                    }
                                }
                            }
                        }
                        .onAppear {
                            if let last = categories.last {
                                if category == last && categories.count > 2 {
                                    value.scrollTo(categories[categories.count - 2].id)
                                } else {
                                    value.scrollTo(last.id)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: heightOfScrollView)
        //            }
    }

    init(
        category: Binding<Category?>?, showPicker: Binding<Bool>, showSheet: Binding<Bool>,
        income: Bool, darkMode: Bool
    ) {
        _categories = FetchRequest<Category>(
            sortDescriptors: [
                SortDescriptor(\.order, order: .reverse)
            ], predicate: NSPredicate(format: "income = %d", income))
        self.darkMode = darkMode
        initialCategory = category?.wrappedValue
        _category = category ?? Binding.constant(nil)
        _showPicker = showPicker
        _showingCategoryView = showSheet
    }
}

struct NoteView: View {
    @Binding var note: String
    @Binding var focused: Bool

    @FocusState private var textFocused: Bool
    let characterLimit = 50

    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var noteWidth: CGFloat {
        let fontSize: CGFloat = UIFont.getBodyFontSize(dynamicTypeSize: dynamicTypeSize)
        //        let fontSize: CGFloat = fontSize
        let systemFont = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let roundedFont: UIFont
        if let descriptor = systemFont.fontDescriptor.withDesign(.rounded) {
            roundedFont = UIFont(descriptor: descriptor, size: fontSize)
        } else {
            roundedFont = systemFont
        }

        let attributes = [NSAttributedString.Key.font: roundedFont]

        let size = (note as NSString).size(withAttributes: attributes)

        let placeholder = String(localized: "Add Note")
        let placeholderSize = (placeholder as NSString).size(withAttributes: attributes)

        if !note.isEmpty {
            return size.width + 2
        } else {
            return placeholderSize.width
        }

        //        return max(size.width + 2, (placeholderSize.width + 1))
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "text.alignleft")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            //                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.SubtitleText)

            ZStack(alignment: .leading) {
                TextField("", text: $note)
                    .onReceive(Just(note)) { _ in limitText(characterLimit) }
                    .focused($textFocused)
                    .foregroundColor(Color.PrimaryText)

                if note.isEmpty {
                    Text("Add Note")
                        .foregroundColor(Color.SubtitleText)
                }
            }
            .font(.system(.body, design: .rounded).weight(.semibold))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            //            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .frame(width: min(noteWidth, UIScreen.main.bounds.width / 1.5), alignment: .center)
        }
        .onTapGesture {
            textFocused = true
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                .stroke(Color.Outline, lineWidth: 1.5)
        )
        .onChange(of: textFocused) { newValue in
            focused = newValue
        }
    }

    func limitText(_ upper: Int) {
        if note.count > upper {
            note = String(note.prefix(upper))
        }
    }
}

struct RecurringPickerView: View {
    @Namespace var animation
    @Binding var repeatType: Int
    @Binding var repeatCoefficient: Int
    @Binding var showMenu: Bool

    @Binding var showPicker: Bool

    let stringArray = ["none", "daily", "weekly", "monthly"]
    let stringArray2 = ["", "days", "weeks", "months"]

    @AppStorage("bottomEdge", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var bottomEdge: Double = 15

    @State private var offset: CGFloat = 0

    @State var holdingType = 0
    @State var holdingCoefficient = 0

    @AppStorage("colourScheme", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime"))
    var colourScheme: Int = 0

    @Environment(\.colorScheme) var systemColorScheme

    var darkMode: Bool {
        (colourScheme == 0 && systemColorScheme == .dark) || colourScheme == 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(stringArray, id: \.self) { string in
                HStack {
                    Text(LocalizedStringKey(string))
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .lineLimit(1)
                    Spacer()

                    if repeatType == (stringArray.firstIndex(of: string) ?? 0) && repeatCoefficient == 1 {
                        Image(systemName: "checkmark")
                            .font(.system(.footnote, design: .rounded).weight(.medium))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        //                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                //                .font(.system(size: 18, weight: .medium, design: .rounded))
                .padding(5)
                .background {
                    if repeatType == (stringArray.firstIndex(of: string) ?? 0) && repeatCoefficient == 1 {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                darkMode
                                ? Color("AlwaysDarkSecondaryBackground") : Color("AlwaysLightSecondaryBackground")
                            )
                            .matchedGeometryEffect(id: "TAB", in: animation)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if repeatType == (stringArray.firstIndex(of: string) ?? 0) && repeatCoefficient == 1 {
                        showMenu = false
                    } else {
                        withAnimation(.easeIn(duration: 0.15)) {
                            repeatType = (stringArray.firstIndex(of: string) ?? 0)
                            repeatCoefficient = 1
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showMenu = false
                        }
                    }
                }
            }

            HStack {
                if repeatCoefficient == 1 {
                    Text("custom")
                } else {
                    if repeatType == 1 {
                        Text(String(repeatCoefficient) + " " + String(localized: "\(repeatCoefficient) days"))
                    } else if repeatType == 2 {
                        Text(String(repeatCoefficient) + " " + String(localized: "\(repeatCoefficient) weeks"))
                    } else if repeatType == 3 {
                        Text(String(repeatCoefficient) + " " + String(localized: "\(repeatCoefficient) months"))
                    }
                }

                Spacer()

                if repeatCoefficient > 1 {
                    Image(systemName: "checkmark")
                        .font(.system(.footnote, design: .rounded).weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    //                        .font(.system(size: 14, weight: .medium))
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.system(.body, design: .rounded).weight(.medium))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            //            .font(.system(size: 18, weight: .medium, design: .rounded))
            .padding(5)
            .background {
                if repeatCoefficient > 1 {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            darkMode
                            ? Color("AlwaysDarkSecondaryBackground") : Color("AlwaysLightSecondaryBackground")
                        )
                        .matchedGeometryEffect(id: "TAB", in: animation)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if repeatCoefficient == 1 {
                    repeatCoefficient = 2
                    repeatType = 2

                    holdingType = repeatType
                    holdingCoefficient = repeatCoefficient
                }

                withAnimation {
                    showPicker = true
                }
            }
            .onChange(of: showPicker) { newValue in
                // holdingType != repeatType || holdingCoefficient != repeatCoefficient
                if !newValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showMenu = false
                    }
                }
            }
        }
        .foregroundColor(darkMode ? Color("AlwaysLightBackground") : Color("AlwaysDarkBackground"))
        .padding(4)
        .frame(width: 150)
        .background(
            RoundedRectangle(cornerRadius: 9).fill(
                darkMode ? Color("AlwaysDarkBackground") : Color("AlwaysLightBackground")
            ).shadow(color: darkMode ? Color.clear : Color.gray.opacity(0.25), radius: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9).stroke(
                darkMode ? Color.gray.opacity(0.1) : Color.clear, lineWidth: 1.3))
    }
}

struct CustomRecurringView: View {
    @Binding var repeatType: Int
    @Binding var repeatCoefficient: Int
    @Binding var showPicker: Bool

    @Environment(\.colorScheme) var systemColorScheme
    var stringArray: [String] {
        return [
            "", "\(holdingCoefficient) days", "\(holdingCoefficient) weeks",
            "\(holdingCoefficient) months"
        ]
    }

    @Environment(\.dismiss) var dismiss

    @State var holdingType = 0
    @State var holdingCoefficient = 0

    var body: some View {
        VStack(spacing: 35) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    //                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.SubtitleText)
                        .padding(7)
                        .background(Color.SecondaryBackground, in: Circle())
                        .contentShape(Circle())
                }

                Spacer()

                Text("Custom Interval")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                //                    .font(.system(size: 18, weight: .semibold, design: .rounded))

                Spacer()

                Button {
                    repeatType = holdingType
                    repeatCoefficient = holdingCoefficient

                    UIImpactFeedbackGenerator(style: .light).impactOccurred()

                    dismiss()

                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    //                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.IncomeGreen)
                        .padding(7)
                        .background(Color.IncomeGreen.opacity(0.23), in: Circle())
                        .contentShape(Circle())
                }
            }

            HStack(spacing: 10) {
                Text("Repeats every")
                    .font(.system(size: 23, weight: .medium, design: .rounded))
                    .foregroundColor(Color.PrimaryText)
                    .padding(.trailing, 3)

                VStack {
                    Button {
                        holdingCoefficient += 1
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.SubtitleText)
                            .padding(7)
                            .background(
                                Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Circle())
                            .opacity(holdingCoefficient == 30 ? 0.25 : 1)
                    }
                    .disabled(holdingCoefficient == 30)

                    Text("\(holdingCoefficient)")
                        .font(.system(size: 23, weight: .medium, design: .rounded))
                        .padding(7)
                        .background {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.SecondaryBackground)
                                .frame(width: 40, height: 40)
                        }

                    Button {
                        holdingCoefficient -= 1
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.SubtitleText)
                            .padding(7)
                            .background(
                                Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Circle())
                            .opacity(holdingCoefficient == 2 ? 0.25 : 1)
                    }
                    .disabled(holdingCoefficient == 2)
                }

                VStack {
                    Button {
                        holdingType -= 1
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.SubtitleText)
                            .padding(7)
                            .background(
                                Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Circle())
                            .opacity(holdingType == 1 ? 0.25 : 1)
                    }
                    .disabled(holdingType == 1)

                    Group {
                        if holdingType == 1 {
                            Text("\(holdingCoefficient) days")
                        } else if holdingType == 2 {
                            Text("\(holdingCoefficient) weeks")
                        } else if holdingType == 3 {
                            Text("\(holdingCoefficient) months")
                        }
                    }
                    .font(.system(size: 23, weight: .medium, design: .rounded))
                    .padding(7)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.SecondaryBackground)
                            .frame(height: 40)
                    }

                    Button {
                        holdingType += 1
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.SubtitleText)
                            .padding(7)
                            .background(
                                Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Circle())
                            .opacity(holdingType == 3 ? 0.25 : 1)
                    }
                    .disabled(holdingType == 3)
                }
            }
            .padding(.bottom, 20)
        }
        .padding(13)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            holdingType = repeatType
            holdingCoefficient = repeatCoefficient
        }
    }
}

struct ButtonView: View {
    let number: Int
    let size: CGSize

    var body: some View {
        Text("\(number)")
            .font(.system(size: 34, weight: .regular, design: .rounded))
            .frame(width: size.width * 0.3, height: size.height * 0.22)
            .background(Color.SecondaryBackground)
            .foregroundColor(Color.PrimaryText)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
