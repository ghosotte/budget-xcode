import SwiftUI

struct SyncStatusBadge: View {
    @State private var monitor = NetworkMonitor.shared

    var body: some View {
        Image(systemName: monitor.isOnline ? "checkmark.icloud" : "icloud.slash")
            .font(.caption2)
            .foregroundStyle(monitor.isOnline ? Color.budgetPrimary : Color.budgetTextMute)
            .accessibilityLabel(monitor.isOnline ? "En ligne" : "Hors ligne")
    }
}
