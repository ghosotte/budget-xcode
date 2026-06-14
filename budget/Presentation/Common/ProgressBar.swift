import SwiftUI

struct ProgressBar: View {
    let ratio: Double
    var color: Color = .budgetPrimary

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.budgetSurfaceMute)
                Capsule()
                    .fill(color)
                    .frame(width: max(geo.size.width * ratio, ratio > 0 ? 6 : 0))
            }
        }
        .frame(height: 6)
    }
}
