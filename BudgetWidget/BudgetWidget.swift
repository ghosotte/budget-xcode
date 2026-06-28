//
//  BudgetWidget.swift
//  BudgetWidget
//
//  Widget récap : solde actuel + prévisionnel du foyer sélectionné (mois courant).
//

import WidgetKit
import SwiftUI
import SwiftData
import BudgetKit

// MARK: — Timeline entry

struct BudgetEntry: TimelineEntry {
    let date: Date
    let state: State

    enum State {
        case unconfigured                                   // aucun foyer choisi → invite à configurer
        case ready(foyerName: String, currencyCode: String, balance: BalanceResult)
    }

    static let unconfigured = BudgetEntry(date: .now, state: .unconfigured)

    static let placeholder = BudgetEntry(
        date: .now,
        state: .ready(
            foyerName: "Foyer",
            currencyCode: "EUR",
            balance: BalanceResult(
                current: 1234, projected: 980,
                realExpenses: 0, realIncome: 0, plannedExpenses: 0,
                pendingIncome: 0, budgetExpenses: 0, budgetIncome: 0,
                hasAnyData: true
            )
        )
    )
}

// MARK: — Provider

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BudgetEntry { .placeholder }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> BudgetEntry {
        await entry(for: configuration)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<BudgetEntry> {
        let entry = await entry(for: configuration)
        // Recalcul au prochain « cutoff » (minuit) : la bascule réel/prévu dépend de la date.
        // L'app force aussi un reload après chaque mutation (WidgetCenter.reloadAllTimelines()).
        return Timeline(entries: [entry], policy: .after(TransactionStatus.cutoff()))
    }

    @MainActor
    private func entry(for configuration: ConfigurationAppIntent) -> BudgetEntry {
        guard let foyerId = configuration.foyer?.id else { return .unconfigured }

        let context = ModelContext(SharedStore.makeContainer())
        let month = Calendar.current.startOfMonth(for: .now)

        guard let household = try? context.fetch(
            FetchDescriptor<Household>(predicate: #Predicate { $0.id == foyerId })
        ).first else { return .unconfigured }

        let expenses = (try? context.fetch(FetchDescriptor<Expense>(predicate: Expense.monthPredicate(month)))) ?? []
        let incomes = (try? context.fetch(FetchDescriptor<IncomeEntry>(predicate: IncomeEntry.monthPredicate(month)))) ?? []
        let budgetLines = (try? context.fetch(FetchDescriptor<BudgetExpenseLine>(predicate: BudgetExpenseLine.activeMonthPredicate(month)))) ?? []
        let budgetIncomes = (try? context.fetch(FetchDescriptor<BudgetIncome>(predicate: BudgetIncome.activeMonthPredicate(month)))) ?? []

        let balance = BalanceCalculator.compute(
            household: household, month: month,
            expenses: expenses, incomes: incomes,
            budgetExpenseLines: budgetLines, budgetIncomes: budgetIncomes
        )

        return BudgetEntry(
            date: .now,
            state: .ready(foyerName: household.name, currencyCode: household.currencyCode, balance: balance)
        )
    }
}

// MARK: — Formatting

private func formatAmount(_ amount: Decimal, currencyCode: String) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    let n = f.string(from: amount as NSDecimalNumber) ?? "0"
    return "\(n) \(Currency.symbol(for: currencyCode))"
}

// MARK: — Views

struct BudgetWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Provider.Entry

    var body: some View {
        switch entry.state {
        case .unconfigured:
            UnconfiguredView()
        case let .ready(foyerName, currencyCode, balance):
            switch family {
            case .accessoryRectangular:
                LockScreenView(currencyCode: currencyCode, balance: balance)
            case .systemMedium:
                MediumView(foyerName: foyerName, currencyCode: currencyCode, balance: balance)
            default:
                SmallView(foyerName: foyerName, currencyCode: currencyCode, balance: balance)
            }
        }
    }
}

private struct UnconfiguredView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "house")
                .font(.title3)
            Text("Choisir un foyer")
                .font(.caption)
                .multilineTextAlignment(.center)
            Text("Appui long → Modifier")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SmallView: View {
    let foyerName: String
    let currencyCode: String
    let balance: BalanceResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(foyerName.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("Solde actuel")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatAmount(balance.current, currencyCode: currencyCode))
                .font(.title2.weight(.bold))
                .foregroundStyle(balance.current >= 0 ? .primary : Color.red)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Divider()
            Text("Prévisionnel")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatAmount(balance.projected, currencyCode: currencyCode))
                .font(.callout.weight(.semibold))
                .foregroundStyle(balance.projected >= 0 ? .primary : Color.red)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct MediumView: View {
    let foyerName: String
    let currencyCode: String
    let balance: BalanceResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(foyerName.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                metric("Solde actuel", balance.current, emphasized: true)
                metric("Prévisionnel", balance.projected, emphasized: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                actionButton("Dépense", systemImage: "minus", url: "budget://add/expense")
                actionButton("Revenu", systemImage: "plus", url: "budget://add/income")
            }
            .frame(width: 110)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func actionButton(_ title: String, systemImage: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.caption2.weight(.bold))
                Text(title).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func metric(_ label: String, _ value: Decimal, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(formatAmount(value, currencyCode: currencyCode))
                .font(emphasized ? .title2.weight(.bold) : .title3.weight(.semibold))
                .foregroundStyle(value >= 0 ? .primary : Color.red)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LockScreenView: View {
    let currencyCode: String
    let balance: BalanceResult

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Solde")
                Spacer()
                Text(formatAmount(balance.current, currencyCode: currencyCode))
                    .fontWeight(.semibold)
            }
            HStack {
                Text("Prév.")
                Spacer()
                Text(formatAmount(balance.projected, currencyCode: currencyCode))
            }
            .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

// MARK: — Widget

struct BudgetWidget: Widget {
    let kind: String = "BudgetWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            BudgetWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Solde")
        .description("Solde actuel et prévisionnel du foyer choisi.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

#Preview(as: .systemSmall) {
    BudgetWidget()
} timeline: {
    BudgetEntry.placeholder
    BudgetEntry.unconfigured
}
