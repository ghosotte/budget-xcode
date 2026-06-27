import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case depenses, entrees
        var id: String { rawValue }
        var label: String {
            switch self {
            case .depenses: return NSLocalizedString("Dépenses", comment: "")
            case .entrees:  return NSLocalizedString("Entrées", comment: "")
            }
        }
    }

    private struct MonthTotal: Identifiable {
        let month: Date
        let total: Decimal
        var id: Date { month }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session

    @Query private var households: [Household]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \IncomeCategory.sortOrder) private var incomeCategories: [IncomeCategory]
    @Query private var expenses: [Expense]
    @Query private var incomeEntries: [IncomeEntry]

    @State private var tab = Tab.depenses
    @State private var fromDate: Date?
    @State private var selectedCategoryIds: Set<UUID> = []
    @State private var selectedIncomeCategoryIds: Set<UUID> = []
    @State private var showFilters = false
    @State private var chartSelection: Date?
    @State private var path = NavigationPath()
    @State private var remoteOverview: HistoryService.Overview?
    @State private var isLoadingOverview = false

    private var household: Household? {
        households.first(where: \.isDefault) ?? households.first
    }

    // MARK: — Calcul fromDate auto-détecté

    private var autoFromDate: Date {
        let calendar = Calendar.current
        let candidates: [Date] = {
            switch tab {
            case .depenses:
                return expenses.filter { $0.household == household }.map(\.spentAt)
            case .entrees:
                return incomeEntries.filter { $0.household == household }.map(\.receivedAt)
            }
        }()
        if let min = candidates.min() {
            return calendar.startOfMonth(for: min)
        }
        // 12 mois par défaut si pas de data
        return calendar.date(byAdding: .month, value: -11, to: calendar.startOfMonth(for: .now)) ?? .now
    }

    private var effectiveFromDate: Date {
        Calendar.current.startOfMonth(for: fromDate ?? autoFromDate)
    }

    private var monthsRange: [Date] {
        let calendar = Calendar.current
        let from = effectiveFromDate
        let to = calendar.startOfMonth(for: .now)
        var months: [Date] = []
        var m = from
        while m <= to {
            months.append(m)
            guard let next = calendar.date(byAdding: .month, value: 1, to: m) else { break }
            m = next
        }
        return months
    }

    // MARK: — Totals par mois

    private var monthlyTotals: [MonthTotal] {
        if let overview = remoteOverview {
            return overview.monthly.map { MonthTotal(month: $0.date, total: $0.decimalTotal) }
        }
        return monthsRange.map { month in
            let total: Decimal
            switch tab {
            case .depenses:
                total = expenses.filter { e in
                    e.household == household
                        && e.effectiveMonth == month
                        && e.status == .real
                        && (selectedCategoryIds.isEmpty || (e.category.map { selectedCategoryIds.contains($0.id) } ?? false))
                }.reduce(Decimal(0)) { $0 + $1.amount }
            case .entrees:
                total = incomeEntries.filter { i in
                    i.household == household
                        && i.effectiveMonth == month
                        && i.status == .real
                        && (selectedIncomeCategoryIds.isEmpty || (i.incomeCategory.map { selectedIncomeCategoryIds.contains($0.id) } ?? false))
                }.reduce(Decimal(0)) { $0 + $1.amount }
            }
            return MonthTotal(month: month, total: total)
        }
    }

    private var nonZeroTotals: [Decimal] {
        monthlyTotals.map(\.total).filter { $0 > 0 }
    }

    private var maxItem: MonthTotal? {
        monthlyTotals.filter { $0.total > 0 }.max(by: { $0.total < $1.total })
    }

    private var minItem: MonthTotal? {
        monthlyTotals.filter { $0.total > 0 }.min(by: { $0.total < $1.total })
    }

    private var averageTotal: Decimal {
        guard !nonZeroTotals.isEmpty else { return 0 }
        return nonZeroTotals.reduce(0, +) / Decimal(nonZeroTotals.count)
    }

    private var maxValue: Decimal { maxItem?.total ?? 0 }
    private var hasData: Bool { !nonZeroTotals.isEmpty }

    // MARK: — Breakdown par catégorie

    private struct CategoryGroup: Identifiable {
        let id: UUID
        let name: String
        let emoji: String
        let total: Decimal
        let avg: Decimal
        let pct: Double
        let subcategories: [SubcategoryGroup]
    }

    private struct SubcategoryGroup: Identifiable {
        let id: UUID
        let name: String
        let emoji: String
        let total: Decimal
        let avg: Decimal
    }

    private var categoryGroups: [CategoryGroup] {
        if let overview = remoteOverview {
            return overview.categories.map { c in
                CategoryGroup(
                    id: UUID(),
                    name: c.name,
                    emoji: c.emoji,
                    total: c.decimalTotal,
                    avg: c.decimalAvg,
                    pct: c.pct,
                    subcategories: c.subcategories.map { s in
                        SubcategoryGroup(
                            id: UUID(),
                            name: s.name,
                            emoji: s.emoji,
                            total: s.decimalTotal,
                            avg: s.decimalAvg
                        )
                    }
                )
            }
        }
        let monthsCount = max(monthsRange.count, 1)
        switch tab {
        case .depenses:
            let filtered = expenses.filter { e in
                e.household == household
                    && e.status == .real
                    && monthsRange.contains(e.effectiveMonth)
                    && (selectedCategoryIds.isEmpty || (e.category.map { selectedCategoryIds.contains($0.id) } ?? false))
            }
            let totalAll = filtered.reduce(Decimal(0)) { $0 + $1.amount }
            guard totalAll > 0 else { return [] }

            let byCategory = Dictionary(grouping: filtered) { $0.category }
            return byCategory.compactMap { (cat, items) -> CategoryGroup? in
                let total = items.reduce(Decimal(0)) { $0 + $1.amount }
                guard total > 0 else { return nil }
                let avg = total / Decimal(monthsCount)
                let pct = NSDecimalNumber(decimal: total / totalAll).doubleValue * 100

                let subItems: [SubcategoryGroup] = {
                    // Groupe par `id` (UUID) plutôt que par l'objet @Model : clé scalaire Hashable triviale,
                    // évite de surcharger le solver de types sur cette expression imbriquée.
                    let withSub = items.filter { $0.subcategory != nil }
                    let bySub = Dictionary(grouping: withSub) { $0.subcategory!.id }
                    return bySub.compactMap { (_, subItems) -> SubcategoryGroup? in
                        guard let sub = subItems.first?.subcategory else { return nil }
                        let subTotal = subItems.reduce(Decimal(0)) { $0 + $1.amount }
                        guard subTotal > 0 else { return nil }
                        return SubcategoryGroup(
                            id: sub.id,
                            name: sub.displayName,
                            emoji: sub.emoji,
                            total: subTotal,
                            avg: subTotal / Decimal(monthsCount)
                        )
                    }.sorted { $0.total > $1.total }
                }()

                return CategoryGroup(
                    id: cat?.id ?? UUID(),
                    name: cat?.displayName ?? NSLocalizedString("Sans catégorie", comment: ""),
                    emoji: cat?.emoji ?? "",
                    total: total,
                    avg: avg,
                    pct: pct,
                    subcategories: subItems
                )
            }.sorted { $0.total > $1.total }
        case .entrees:
            let filtered = incomeEntries.filter { i in
                i.household == household
                    && i.status == .real
                    && monthsRange.contains(i.effectiveMonth)
                    && (selectedIncomeCategoryIds.isEmpty || (i.incomeCategory.map { selectedIncomeCategoryIds.contains($0.id) } ?? false))
            }
            let totalAll = filtered.reduce(Decimal(0)) { $0 + $1.amount }
            guard totalAll > 0 else { return [] }

            let byCategory = Dictionary(grouping: filtered) { $0.incomeCategory }
            return byCategory.compactMap { (cat, items) -> CategoryGroup? in
                let total = items.reduce(Decimal(0)) { $0 + $1.amount }
                guard total > 0 else { return nil }
                let avg = total / Decimal(monthsCount)
                let pct = NSDecimalNumber(decimal: total / totalAll).doubleValue * 100
                return CategoryGroup(
                    id: cat?.id ?? UUID(),
                    name: cat?.displayName ?? NSLocalizedString("Sans catégorie", comment: ""),
                    emoji: cat?.emoji ?? "",
                    total: total,
                    avg: avg,
                    pct: pct,
                    subcategories: []
                )
            }.sorted { $0.total > $1.total }
        }
    }
    private var activeFilterCount: Int {
        tab == .depenses ? selectedCategoryIds.count : selectedIncomeCategoryIds.count
    }

    // MARK: — Body

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    tabSwitcher
                    if showFilters { filterPanel }
                    if hasData {
                        statsCard
                        chartCard
                        if !categoryGroups.isEmpty {
                            breakdownCard
                        }
                        Text("Touche un mois pour voir son détail.")
                            .font(.caption)
                            .foregroundStyle(Color.budgetTextFaint)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
            .background(Color.budgetBg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Date.self) { month in
                BilanView(month: month)
                    .navigationTitle("Bilan · \(AppDateFormatter.monthYear(month))")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .tint(.budgetPrimary)
        .task(id: TaskKey(tab: tab, from: effectiveFromDate, cats: selectedCategoryIds.count + selectedIncomeCategoryIds.count)) {
            await loadOverview()
            for m in monthsRange.suffix(3).reversed() {
                await MonthSyncService.refreshMonth(m, session: session, context: modelContext)
            }
        }
        .onChange(of: chartSelection) {
            if let selection = chartSelection {
                let month = Calendar.current.startOfMonth(for: selection)
                chartSelection = nil
                if monthlyTotals.first(where: { $0.month == month })?.total ?? 0 > 0 {
                    path.append(month)
                }
            }
        }
    }

    private struct TaskKey: Equatable {
        let tab: Tab
        let from: Date
        let cats: Int
    }

    private func loadOverview() async {
        guard session.isAuthenticated,
              let household = household,
              !household.isAnonymous,
              !household.isOrphan,
              household.serverId != nil else {
            remoteOverview = nil
            return
        }
        isLoadingOverview = true
        defer { isLoadingOverview = false }

        let catIds: [Int] = {
            switch tab {
            case .depenses:
                return categories
                    .filter { selectedCategoryIds.contains($0.id) }
                    .compactMap(\.serverId)
            case .entrees:
                return incomeCategories
                    .filter { selectedIncomeCategoryIds.contains($0.id) }
                    .compactMap(\.serverId)
            }
        }()

        do {
            remoteOverview = try await HistoryService.fetchOverview(
                tab: tab.rawValue,
                from: effectiveFromDate,
                categories: catIds
            )
        } catch {
            remoteOverview = nil
        }
    }

    private var header: some View {
        HStack {
            Text("Historique")
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(Color.budgetText)
            Spacer()
            Text("depuis \(AppDateFormatter.monthYear(effectiveFromDate)) · \(monthsRange.count) mois")
                .font(.caption)
                .foregroundStyle(Color.budgetTextMute)
        }
    }

    private var tabSwitcher: some View {
        HStack(spacing: 10) {
            Picker("Vue", selection: $tab) {
                ForEach(Tab.allCases) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.segmented)

            Button {
                showFilters.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Filtres")
                        .font(.subheadline.weight(.medium))
                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.budgetPrimary))
                    }
                }
                .foregroundStyle(activeFilterCount > 0 ? Color.budgetPrimary : Color.budgetText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(activeFilterCount > 0 ? Color.budgetPrimary : Color.budgetBorder, lineWidth: 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(activeFilterCount > 0 ? Color.budgetPrimarySoft : Color.budgetSurface)
                        )
                )
            }
        }
    }

    // MARK: — Filter panel

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CALCULER DEPUIS LE")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.budgetTextMute)
                Spacer()
                DatePicker(
                    "",
                    selection: Binding(
                        get: { fromDate ?? autoFromDate },
                        set: { fromDate = $0 }
                    ),
                    in: ...Date.now,
                    displayedComponents: .date
                )
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().overlay(Color.budgetBorder.opacity(0.6))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    if tab == .depenses {
                        ForEach(categories) { cat in
                            categoryRow(
                                emoji: cat.emoji,
                                name: cat.displayName,
                                isOn: selectedCategoryIds.contains(cat.id)
                            ) {
                                toggle(selectedCategoryIds, id: cat.id) { newSet in
                                    selectedCategoryIds = newSet
                                }
                            }
                        }
                    } else {
                        ForEach(incomeCategories) { cat in
                            categoryRow(
                                emoji: cat.emoji,
                                name: cat.displayName,
                                isOn: selectedIncomeCategoryIds.contains(cat.id)
                            ) {
                                toggle(selectedIncomeCategoryIds, id: cat.id) { newSet in
                                    selectedIncomeCategoryIds = newSet
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 260)

            HStack(spacing: 10) {
                Button {
                    if tab == .depenses { selectedCategoryIds.removeAll() }
                    else { selectedIncomeCategoryIds.removeAll() }
                    fromDate = nil
                } label: {
                    Text("Réinitialiser")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.budgetTextMute)
                }
                Spacer()
                Button {
                    showFilters = false
                } label: {
                    Text("Fermer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.budgetPrimary))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(cardBackground)
    }

    @ViewBuilder
    private func categoryRow(emoji: String, name: String, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? Color.budgetPrimary : Color.budgetTextFaint)
                Text("\(emoji.isEmpty ? "" : emoji + " ")\(name)")
                    .font(.subheadline)
                    .foregroundStyle(Color.budgetText)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.clear)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.budgetBorder.opacity(0.4)).frame(height: 0.5)
        }
    }

    private func toggle(_ set: Set<UUID>, id: UUID, save: (Set<UUID>) -> Void) {
        var copy = set
        if copy.contains(id) { copy.remove(id) } else { copy.insert(id) }
        save(copy)
    }

    // MARK: — Stats

    private var statsCard: some View {
        HStack(spacing: 0) {
            statColumn(label: "MOYENNE", value: averageTotal, monthLabel: nil)
            Divider().overlay(Color.budgetBorder.opacity(0.6))
            statColumn(
                label: "MAX",
                value: maxItem?.total ?? 0,
                monthLabel: maxItem.map { AppDateFormatter.monthYear($0.month) },
                tint: Color.budgetDanger
            )
            Divider().overlay(Color.budgetBorder.opacity(0.6))
            statColumn(
                label: "MIN",
                value: minItem?.total ?? 0,
                monthLabel: minItem.map { AppDateFormatter.monthYear($0.month) },
                tint: Color.budgetPrimary
            )
        }
        .padding(.vertical, 14)
        .background(cardBackground)
    }

    private func statColumn(label: LocalizedStringKey, value: Decimal, monthLabel: String?, tint: Color = .budgetText) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Color.budgetTextMute)
            Text(AmountFormatter.kpi(value))
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let monthLabel {
                Text(monthLabel)
                    .font(.caption2)
                    .foregroundStyle(Color.budgetTextMute)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: — Graphique

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tab == .entrees ? "ENTRÉES RÉELLES PAR MOIS" : "DÉPENSES RÉELLES PAR MOIS")
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Color.budgetTextMute)

            Chart(monthlyTotals) { item in
                BarMark(
                    x: .value("Mois", item.month, unit: .month),
                    y: .value("Total", (item.total as NSDecimalNumber).doubleValue)
                )
                .foregroundStyle(barColor(for: item.total))
                .cornerRadius(4)
            }
            .chartXSelection(value: $chartSelection)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                        .font(.caption2)
                        .foregroundStyle(Color.budgetTextMute)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Color.budgetBorder.opacity(0.5))
                    AxisValueLabel()
                        .font(.caption2)
                        .foregroundStyle(Color.budgetTextMute)
                }
            }
            .frame(height: 220)
        }
        .padding(16)
        .background(cardBackground)
    }

    private func barColor(for value: Decimal) -> Color {
        guard maxValue > 0 else { return Color.budgetPrimary }
        let pct = NSDecimalNumber(decimal: value / maxValue).doubleValue
        if tab == .entrees { return Color.budgetPrimary }
        if pct >= 0.85 { return Color.budgetDanger }
        if pct >= 0.60 { return Color.budgetAccent }
        return Color.budgetPrimary
    }

    // MARK: — Breakdown card

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MOYENNE PAR CATÉGORIE")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.budgetTextMute)
                Text("depuis \(AppDateFormatter.monthYear(effectiveFromDate)) · \(monthsRange.count) mois")
                    .font(.caption2)
                    .foregroundStyle(Color.budgetTextFaint)
            }
            .padding(16)

            Divider().overlay(Color.budgetBorder.opacity(0.6))

            VStack(spacing: 0) {
                ForEach(categoryGroups) { group in
                    categoryBreakdownRow(group)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.budgetBorder.opacity(0.4)).frame(height: 0.5)
                        }
                }
            }
        }
        .background(cardBackground)
    }

    @ViewBuilder
    private func categoryBreakdownRow(_ group: CategoryGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(group.emoji.isEmpty ? "" : group.emoji + " ")\(group.name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.budgetText)
                Spacer()
                Text("\(AmountFormatter.kpi(group.total)) total")
                    .font(.caption)
                    .foregroundStyle(Color.budgetTextMute)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(AmountFormatter.kpi(group.avg))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.budgetText)
                    Text("/mois")
                        .font(.caption2)
                        .foregroundStyle(Color.budgetTextFaint)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.budgetSurfaceMute)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.budgetPrimary)
                        .frame(width: geo.size.width * CGFloat(min(group.pct, 100) / 100))
                }
            }
            .frame(height: 6)

            if !group.subcategories.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(group.subcategories) { sub in
                        HStack {
                            Text("\(sub.emoji.isEmpty ? "↳ " : sub.emoji + " ")\(sub.name)")
                                .font(.caption)
                                .foregroundStyle(Color.budgetTextMute)
                            Spacer()
                            Text("\(AmountFormatter.kpi(sub.avg))/mois")
                                .font(.caption)
                                .foregroundStyle(Color.budgetTextMute)
                        }
                    }
                }
                .padding(.leading, 12)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(tab == .entrees ? "💰" : "📈")
                .font(.system(size: 40))
            Text(tab == .entrees ? "Aucune entrée sur la période." : "Aucune dépense sur la période.")
                .font(.subheadline)
                .foregroundStyle(Color.budgetTextMute)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.budgetSurface)
            .stroke(Color.budgetBorder, lineWidth: 1)
    }
}
