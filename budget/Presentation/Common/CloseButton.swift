import SwiftUI

/// Bouton de fermeture circulaire pour les modales (remplace « Annuler » / « Fermer »).
struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.budgetTextMute)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.budgetSurfaceMute))
        }
        .accessibilityLabel("Fermer")
    }
}
