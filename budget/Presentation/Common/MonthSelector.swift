import SwiftUI

struct MonthSelector<Subtitle: View>: View {
    @Binding var month: Date
    @ViewBuilder var subtitle: () -> Subtitle

    var body: some View {
        HStack {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.budgetText)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.budgetSurfaceMute))
            }
            Spacer()
            VStack(spacing: 2) {
                Text(AppDateFormatter.monthYear(month))
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(Color.budgetText)
                subtitle()
            }
            Spacer()
            Button { shift(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.budgetText)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.budgetSurfaceMute))
            }
        }
    }

    private func shift(_ delta: Int) {
        if let newMonth = Calendar.current.date(byAdding: .month, value: delta, to: month) {
            month = Calendar.current.startOfMonth(for: newMonth)
        }
    }
}

extension MonthSelector where Subtitle == EmptyView {
    init(month: Binding<Date>) {
        self.init(month: month) { EmptyView() }
    }
}
