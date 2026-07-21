import Foundation

/// Shared shorthand for resolving localized resources in non-View code paths.
func localized(_ resource: LocalizedStringResource) -> String {
    String(localized: resource)
}

func localizedFormat(_ resource: LocalizedStringResource, _ arguments: CVarArg...) -> String {
    String(format: String(localized: resource), arguments: arguments)
}
