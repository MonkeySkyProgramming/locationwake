import Foundation

/// Resolves non-SwiftUI text through the same String Catalog as SwiftUI views.
///
/// SwiftUI's `Text` and `Button` string literals are discovered automatically,
/// but messages assembled in services, accessibility values, and model helpers
/// need an explicit lookup.
enum AppStrings {
    static func text(_ key: String) -> String {
        String(localized: .init(key), table: "Localizable")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: text(key),
            locale: .current,
            arguments: arguments
        )
    }
}
