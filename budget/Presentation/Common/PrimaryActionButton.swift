import SwiftUI

/// Bouton de validation principal, pleine largeur, à placer en bas d'une modale
/// via `.safeAreaInset(edge: .bottom)`.
struct PrimaryActionButton: View {
    let title: LocalizedStringKey
    var enabled: Bool = true
    var working: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .opacity(working ? 0 : 1)
                if working {
                    ProgressView()
                        .tint(.white)
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.budgetPrimary))
        }
        .disabled(!enabled || working)
        .opacity(enabled ? 1 : 0.45)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }
}
