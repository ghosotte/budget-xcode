import SwiftUI
import SwiftData

/// Sélecteur de catégorie / sous-catégorie en une seule fenêtre.
///
/// Présente une grille de catégories. Toucher une catégorie qui possède des
/// sous-catégories ouvre un second écran pour choisir la sous-catégorie ;
/// sinon la catégorie est sélectionnée directement.
struct CategoryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @Binding var category: Category?
    @Binding var subcategory: Subcategory?

    @State private var search = ""
    @State private var path: [Category] = []

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    private var filtered: [Category] {
        let active = categories.filter(\.isActive)
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return active }
        return active.filter { cat in
            cat.displayName.localizedCaseInsensitiveContains(q)
                || cat.subcategories.contains { $0.displayName.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    CategoryCell(emoji: "🚫", name: NSLocalizedString("Aucune", comment: ""), selected: category == nil) {
                        category = nil
                        subcategory = nil
                        dismiss()
                    }
                    ForEach(filtered) { cat in
                        CategoryCell(emoji: cat.emoji, name: cat.displayName, selected: cat == category) {
                            select(cat)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.budgetBg)
            .searchable(text: $search, prompt: "Recherche")
            .navigationTitle("Catégorie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { dismiss() }
                }
            }
            .navigationDestination(for: Category.self) { cat in
                SubcategoryPickerView(
                    parent: cat,
                    category: $category,
                    subcategory: $subcategory,
                    onDone: { dismiss() }
                )
            }
        }
        .tint(.budgetPrimary)
    }

    private func select(_ cat: Category) {
        if cat.subcategories.isEmpty {
            category = cat
            subcategory = nil
            dismiss()
        } else {
            path.append(cat)
        }
    }
}

/// Second écran : choix de la sous-catégorie d'une catégorie donnée.
private struct SubcategoryPickerView: View {
    let parent: Category
    @Binding var category: Category?
    @Binding var subcategory: Subcategory?
    let onDone: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    private var subs: [Subcategory] {
        parent.subcategories.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                // Sélectionner la catégorie seule, sans sous-catégorie.
                CategoryCell(
                    emoji: parent.emoji,
                    name: NSLocalizedString("Toute la catégorie", comment: ""),
                    selected: category == parent && subcategory == nil
                ) {
                    category = parent
                    subcategory = nil
                    onDone()
                }
                ForEach(subs) { sub in
                    CategoryCell(
                        emoji: sub.emoji.isEmpty ? parent.emoji : sub.emoji,
                        name: sub.displayName,
                        selected: subcategory == sub
                    ) {
                        category = parent
                        subcategory = sub
                        onDone()
                    }
                }
            }
            .padding(20)
        }
        .background(Color.budgetBg)
        .navigationTitle(parent.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Sélecteur de catégorie de revenu (pas de sous-catégorie) — même charte que la
/// dépense pour rester homogène.
struct IncomeCategoryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \IncomeCategory.sortOrder) private var categories: [IncomeCategory]

    @Binding var incomeCategory: IncomeCategory?

    @State private var search = ""

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    private var filtered: [IncomeCategory] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return categories }
        return categories.filter { $0.displayName.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    CategoryCell(emoji: "🚫", name: NSLocalizedString("Aucune", comment: ""), selected: incomeCategory == nil) {
                        incomeCategory = nil
                        dismiss()
                    }
                    ForEach(filtered) { cat in
                        CategoryCell(emoji: cat.emoji, name: cat.displayName, selected: cat == incomeCategory) {
                            incomeCategory = cat
                            dismiss()
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.budgetBg)
            .searchable(text: $search, prompt: "Recherche")
            .navigationTitle("Catégorie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { dismiss() }
                }
            }
        }
        .tint(.budgetPrimary)
    }
}

/// Cellule ronde réutilisable pour la grille de catégories / sous-catégories.
private struct CategoryCell: View {
    let emoji: String
    let name: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(selected ? Color.budgetPrimarySoft : Color.budgetSurfaceMute)
                    .frame(width: 64, height: 64)
                    .overlay {
                        Text(emoji).font(.system(size: 28))
                    }
                    .overlay {
                        if selected {
                            Circle().strokeBorder(Color.budgetPrimary, lineWidth: 2)
                        }
                    }
                Text(name)
                    .font(.caption)
                    .foregroundStyle(Color.budgetText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
