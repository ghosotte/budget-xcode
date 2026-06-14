import SwiftUI

struct SyncErrorBanner: View {
    @State private var store = SyncErrorStore.shared

    var body: some View {
        if let message = store.lastError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.budgetDanger)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Synchronisation interrompue")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.budgetText)
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(Color.budgetTextMute)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    store.clear()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.budgetTextMute)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.budgetDanger.opacity(0.08))
                    .stroke(Color.budgetDanger.opacity(0.3), lineWidth: 1)
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}
