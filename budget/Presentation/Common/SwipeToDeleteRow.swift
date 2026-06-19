import SwiftUI

/// Ligne avec geste swipe-vers-la-gauche révélant un bouton Supprimer.
/// Pour les listes custom (VStack) où `List.swipeActions` n'est pas disponible.
struct SwipeToDeleteRow<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @GestureState private var dragging = false

    private let actionWidth: CGFloat = 76

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: actionWidth)
                    .frame(maxHeight: .infinity)
            }
            .background(Color.budgetDanger)
            .opacity(offset < 0 ? 1 : 0)

            content
                .background(Color.budgetSurface)
                .offset(x: offset)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 18)
                        .updating($dragging) { _, state, _ in state = true }
                        .onChanged { value in
                            // N'agir que sur un swipe à dominante horizontale.
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            let base = offset <= -actionWidth ? -actionWidth : 0
                            offset = min(0, max(-actionWidth, base + value.translation.width))
                        }
                        .onEnded { value in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                offset = value.translation.width < -actionWidth / 2 ? -actionWidth : 0
                            }
                        }
                )
        }
        .clipped()
    }
}
