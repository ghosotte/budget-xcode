import BudgetKit

// `Category` (modèle BudgetKit) entre en collision avec un type système homonyme une fois
// importé depuis un module. Une déclaration same-module masque les types importés : cet alias
// rend tous les `Category` nus de l'app non ambigus, sans qualifier chaque usage ni chaque keypath.
typealias Category = BudgetKit.Category
