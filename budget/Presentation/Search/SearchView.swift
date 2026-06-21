import SwiftUI
import SwiftData

/// Recherche globale de transactions. Présentée en plein écran depuis le Dashboard.
/// Débounce la frappe, filtre par type/statut/montant/date, pagine par offset.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session

    private static let pageLimit = 30

    @State private var query = ""
    @State private var typeFilter: SearchService.TypeFilter = .all
    @State private var statusFilter: SearchService.StatusFilter = .all
    @State private var amountMinText = ""
    @State private var amountMaxText = ""
    @State private var dateFrom: Date?
    @State private var dateTo: Date?
    @State private var showFilters = false

    @State private var items: [SearchService.Item] = []
    @State private var total = 0
    @State private var summary: SearchService.Summary?
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var loadError: String?
    @State private var didSearch = false

    @State private var editTarget: TransactionItem?

    @FocusState private var searchFocused: Bool

    // MARK: — Clé de recherche (déclenche un reload débounché)

    private struct SearchKey: Equatable {
        let q: String
        let type: SearchService.TypeFilter
        let status: SearchService.StatusFilter
        let min: String
        let max: String
        let from: Date?
        let to: Date?
    }

    private var searchKey: SearchKey {
        SearchKey(
            q: query, type: typeFilter, status: statusFilter,
            min: amountMinText, max: amountMaxText, from: dateFrom, to: dateTo
        )
    }

    private var amountMin: Decimal? { parseAmount(amountMinText) }
    private var amountMax: Decimal? { parseAmount(amountMaxText) }

    private var hasAnyFilter: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
            || typeFilter != .all
            || statusFilter != .all
            || amountMin != nil
            || amountMax != nil
            || dateFrom != nil
            || dateTo != nil
    }

    private var activeFilterCount: Int {
        var n = 0
        if amountMin != nil { n += 1 }
        if amountMax != nil { n += 1 }
        if dateFrom != nil { n += 1 }
        if dateTo != nil { n += 1 }
        return n
    }

    // MARK: — Groupement par mois

    private struct MonthGroup: Identifiable {
        let id: Date
        let items: [SearchService.Item]
    }

    private var monthGroups: [MonthGroup] {
        let calendar = Calendar.current
        let dated = items.compactMap { item -> (Date, SearchService.Item)? in
            guard let date = item.parsedDate else { return nil }
            return (calendar.startOfMonth(for: date), item)
        }
        return Dictionary(grouping: dated, by: \.0)
            .map { MonthGroup(id: $0.key, items: $0.value.map(\.1)) }
            .sorted { $0.id > $1.id }
    }

    // MARK: — Body

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            filterControls
            Divider().overlay(Color.budgetBorder)
            content
        }
        .background(Color.budgetBg)
        .task(id: searchKey) { await runSearch() }
        .sheet(item: $editTarget) { item in
            switch item {
            case .expense(let expense): ExpenseFormView(expense: expense)
            case .income(let income):   IncomeFormView(income: income)
            }
        }
        .onAppear { searchFocused = true }
    }

    // MARK: — Barre de recherche

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.budgetTextMute)
                TextField(NSLocalizedString("Rechercher une transaction…", comment: ""), text: $query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .foregroundStyle(Color.budgetText)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.budgetTextFaint)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.budgetSurfaceMute))

            Button { dismiss() } label: {
                Text("Fermer")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.budgetText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: — Filtres

    private var filterControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Picker("Type", selection: $typeFilter) {
                    ForEach(SearchService.TypeFilter.allCases, id: \.self) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.segmented)

                Button { withAnimation(.snappy) { showFilters.toggle() } } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(activeFilterCount == 0 ? Color.budgetText : .white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(activeFilterCount == 0 ? Color.budgetSurfaceMute : Color.budgetPrimary))
                        if activeFilterCount > 0 {
                            Text("\(activeFilterCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .background(Circle().fill(Color.budgetAccent))
                                .offset(x: 4, y: -4)
                        }
                    }
                }
            }

            Picker("Statut", selection: $statusFilter) {
                ForEach(SearchService.StatusFilter.allCases, id: \.self) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)

            if showFilters {
                advancedFilters
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var advancedFilters: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                amountField(NSLocalizedString("Min", comment: ""), text: $amountMinText)
                Text("—").foregroundStyle(Color.budgetTextFaint)
                amountField(NSLocalizedString("Max", comment: ""), text: $amountMaxText)
            }
            HStack(spacing: 10) {
                dateField(NSLocalizedString("Du", comment: ""), date: $dateFrom)
                dateField(NSLocalizedString("Au", comment: ""), date: $dateTo)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func amountField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(.subheadline)
            .padding(.horizontal, 10)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.budgetSurfaceMute))
    }

    @ViewBuilder
    private func dateField(_ label: String, date: Binding<Date?>) -> some View {
        let binding = Binding(
            get: { date.wrappedValue ?? Date() },
            set: { date.wrappedValue = $0 }
        )
        HStack(spacing: 6) {
            if date.wrappedValue == nil {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Color.budgetTextMute)
                Spacer()
                Image(systemName: "calendar")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.budgetTextFaint)
                    .overlay {
                        DatePicker("", selection: binding, displayedComponents: .date)
                            .labelsHidden()
                            .blendMode(.destinationOver)
                    }
            } else {
                DatePicker("", selection: binding, displayedComponents: .date)
                    .labelsHidden()
                Spacer(minLength: 0)
                Button { date.wrappedValue = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.budgetTextFaint)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.budgetSurfaceMute))
    }

    // MARK: — Contenu

    @ViewBuilder
    private var content: some View {
        if !hasAnyFilter {
            placeholder(
                emoji: "🔍",
                text: NSLocalizedString("Recherche une transaction par libellé, montant ou date.", comment: "")
            )
        } else if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            placeholder(emoji: "⚠️", text: loadError)
        } else if didSearch && items.isEmpty {
            placeholder(
                emoji: "🤷",
                text: NSLocalizedString("Aucun résultat.", comment: "")
            )
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        List {
            Section {
                summaryHeader
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(monthGroups) { group in
                Section {
                    ForEach(group.items) { item in
                        SearchResultRow(item: item)
                            .listRowBackground(Color.budgetSurface)
                            .listRowSeparatorTint(Color.budgetBorder.opacity(0.6))
                            .contentShape(Rectangle())
                            .onTapGesture { resolveAndEdit(item) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    delete(item)
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                                Button {
                                    duplicate(item)
                                } label: {
                                    Label("Dupliquer", systemImage: "plus.square.on.square")
                                }
                                .tint(Color.budgetPrimary)
                            }
                    }
                } header: {
                    Text(AppDateFormatter.monthYear(group.id).uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(1.0)
                        .foregroundStyle(Color.budgetTextMute)
                        .textCase(nil)
                }
            }

            if hasMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .onAppear { Task { await loadMore() } }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    private var summaryHeader: some View {
        HStack(spacing: 8) {
            Text(String(format: NSLocalizedString("%d résultat(s)", comment: ""), total))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.budgetText)
            if let summary {
                if summary.expensesCount > 0 {
                    Text("·").foregroundStyle(Color.budgetTextFaint)
                    Text(AmountFormatter.full(-summary.expensesTotal, signed: true))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.budgetDanger)
                }
                if summary.incomesCount > 0 {
                    Text(AmountFormatter.full(summary.incomesTotal, signed: true))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.budgetPrimary)
                }
            }
            Spacer()
        }
    }

    private func placeholder(emoji: String, text: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Text(emoji).font(.system(size: 40))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.budgetTextMute)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Chargement

    private func runSearch() async {
        guard hasAnyFilter else {
            items = []; total = 0; summary = nil; hasMore = false; didSearch = false; loadError = nil
            return
        }
        // Débounce : annulé si searchKey change avant la fin du sleep.
        try? await Task.sleep(for: .milliseconds(350))
        if Task.isCancelled { return }
        await load(reset: true)
    }

    private func load(reset: Bool) async {
        if reset { isLoading = true } else { isLoadingMore = true }
        defer { isLoading = false; isLoadingMore = false }

        let offset = reset ? 0 : items.count
        do {
            let response = try await SearchService.search(
                q: query, type: typeFilter, status: statusFilter,
                amountMin: amountMin, amountMax: amountMax,
                dateFrom: dateFrom, dateTo: dateTo,
                limit: Self.pageLimit, offset: offset
            )
            if reset {
                items = response.items
            } else {
                items += response.items
            }
            total = response.total
            summary = response.summary
            hasMore = response.hasMore
            loadError = nil
            didSearch = true
        } catch {
            if reset { items = []; total = 0; summary = nil; hasMore = false }
            loadError = error.localizedDescription
            didSearch = true
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        await load(reset: false)
    }

    // MARK: — Édition

    /// Résout le modèle local par serverId pour éditer/dupliquer/supprimer.
    /// Limite phase 1 : seules les transactions présentes en local (mois synchronisés) sont actionnables.
    private func localExpense(_ serverId: Int) -> Expense? {
        var fd = FetchDescriptor<Expense>(predicate: #Predicate { $0.serverId == serverId })
        fd.fetchLimit = 1
        return try? modelContext.fetch(fd).first
    }

    private func localIncome(_ serverId: Int) -> IncomeEntry? {
        var fd = FetchDescriptor<IncomeEntry>(predicate: #Predicate { $0.serverId == serverId })
        fd.fetchLimit = 1
        return try? modelContext.fetch(fd).first
    }

    private func resolveAndEdit(_ item: SearchService.Item) {
        if item.isIncome {
            if let income = localIncome(item.serverId) { editTarget = .income(income) }
        } else {
            if let expense = localExpense(item.serverId) { editTarget = .expense(expense) }
        }
    }

    private func delete(_ item: SearchService.Item) {
        if item.isIncome {
            guard let income = localIncome(item.serverId) else { return }
            PushService.deleteIncome(income, session: session, context: modelContext)
        } else {
            guard let expense = localExpense(item.serverId) else { return }
            PushService.deleteExpense(expense, session: session, context: modelContext)
        }
        items.removeAll { $0.id == item.id }
        total = max(0, total - 1)
    }

    private func duplicate(_ item: SearchService.Item) {
        if item.isIncome {
            guard let i = localIncome(item.serverId) else { return }
            let copy = IncomeEntry(
                incomeCategory: i.incomeCategory,
                amount: i.amount,
                label: i.label,
                receivedAt: i.receivedAt,
                accountingMonth: i.accountingMonth,
                status: i.status,
                notes: i.notes
            )
            copy.household = i.household
            PushService.markForUpload(&copy.syncStatus, household: copy.household)
            modelContext.insert(copy)
        } else {
            guard let e = localExpense(item.serverId) else { return }
            let copy = Expense(
                category: e.category,
                subcategory: e.subcategory,
                amount: e.amount,
                label: e.label,
                spentAt: e.spentAt,
                accountingMonth: e.accountingMonth,
                status: e.status,
                tags: e.tags,
                notes: e.notes
            )
            copy.household = e.household
            PushService.markForUpload(&copy.syncStatus, household: copy.household)
            modelContext.insert(copy)
        }
        try? modelContext.save()
        PushService.afterLocalChange(session: session, context: modelContext)
    }

    private func parseAmount(_ text: String) -> Decimal? {
        let normalized = text
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }
}

// MARK: — Ligne de résultat

private struct SearchResultRow: View {
    let item: SearchService.Item

    var body: some View {
        HStack(spacing: 12) {
            Text(item.categoryEmoji ?? (item.isIncome ? "💸" : "📦"))
                .font(.system(size: 18))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.budgetSurfaceMute))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.budgetText)
                        .lineLimit(1)
                    if item.statusEnum == .planned {
                        Text("Prévu")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.budgetAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.budgetAccent.opacity(0.12)))
                    }
                }
                HStack(spacing: 4) {
                    Text(item.categoryName ?? NSLocalizedString("Sans catégorie", comment: ""))
                    if let date = item.parsedDate {
                        Text("·")
                        Text(AppDateFormatter.dayMonth(date))
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.budgetTextMute)
            }

            Spacer()

            Text(AmountFormatter.full(item.signedAmount, signed: true))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(item.isIncome ? Color.budgetPrimary : Color.budgetDanger)
        }
        .opacity(item.statusEnum == .planned ? 0.7 : 1)
    }
}
