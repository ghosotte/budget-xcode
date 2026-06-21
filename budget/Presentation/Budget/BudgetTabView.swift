import SwiftUI
import SwiftData

struct BudgetTabView: View {
    enum Mode: String, CaseIterable {
        case budget, bilan

        var label: String {
            switch self {
            case .budget: return NSLocalizedString("Budget", comment: "")
            case .bilan:  return NSLocalizedString("Bilan", comment: "")
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session
    @State private var month = Calendar.current.startOfMonth(for: .now)
    @State private var mode = Mode.budget

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                MonthSelector(month: $month) {
                    Text(mode == .budget ? "Budget mensuel" : "Budget vs réel")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.budgetTextMute)
                }
                Picker("Vue", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)

            switch mode {
            case .budget: BudgetView(month: month)
            case .bilan:  BilanView(month: month)
            }
        }
        .background(Color.budgetBg)
        .task(id: month) {
            await MonthSyncService.refreshMonth(month, session: session, context: modelContext)
        }
    }
}
