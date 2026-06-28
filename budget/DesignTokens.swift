import SwiftUI
import UIKit
import BudgetKit

extension Color {
    static let budgetBg           = Color(light: "#FAFAF8", dark: "#141413")
    static let budgetSurface      = Color(light: "#FFFFFF", dark: "#1E1E1C")
    static let budgetSurfaceMute  = Color(light: "#F2F0EA", dark: "#2A2A27")
    static let budgetBorder       = Color(light: "#E7E4DB", dark: "#33322E")
    static let budgetPrimary      = Color(light: "#4A7C59", dark: "#6FA57E")
    static let budgetPrimarySoft  = Color(light: "#E8EFE7", dark: "#243528")
    static let budgetAccent       = Color(light: "#D97706", dark: "#E8923B")
    static let budgetDanger       = Color(light: "#C0392B", dark: "#E06052")
    static let budgetText         = Color(light: "#1A1A1A", dark: "#F2F1ED")
    static let budgetTextMute     = Color(light: "#6B6A65", dark: "#A4A39C")
    static let budgetTextFaint    = Color(light: "#9B9A93", dark: "#6F6E68")
}

enum AppTheme: String, CaseIterable {
    case system, light, dark

    /// `LocalizedStringKey` pour que `Text(theme.label)` passe par le bundle surchargé
    /// (`LocalizedBundle`) et suive la langue du foyer.
    var label: LocalizedStringKey {
        switch self {
        case .system: return "Système"
        case .light:  return "Clair"
        case .dark:   return "Sombre"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}
