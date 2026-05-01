import SwiftUI

/// Presents an error sheet whenever `error` becomes non-nil.
///
/// Companion to ``NavDataLoaderViewModel/error`` — the loader writes its
/// thrown error to the binding, the modifier reflects that into a modal
/// sheet, and dismissing the sheet clears the binding so a subsequent
/// failure can re-present.
struct WithErrorSheet: ViewModifier {
  @Binding var error: Swift.Error?

  func body(content: Content) -> some View {
    content
      .sheet(
        item: Binding(
          get: { error.map(IdentifiableError.init) },
          set: { newValue in if newValue == nil { error = nil } }
        )
      ) { wrapped in
        ErrorSheetContent(error: wrapped.error)
      }
  }

  private struct IdentifiableError: Identifiable {
    let id = UUID()
    let error: Swift.Error
  }

  private struct ErrorSheetContent: View {
    let error: Swift.Error

    @Environment(\.dismiss)
    private var dismiss

    private var localized: LocalizedError? { error as? LocalizedError }

    var body: some View {
      VStack(spacing: 16) {
        Image(systemName: "exclamationmark.triangle.fill")
          .resizable()
          .scaledToFit()
          .frame(width: 48, height: 48)
          .foregroundStyle(.yellow)
          .accessibilityHidden(true)

        Text(localized?.errorDescription ?? error.localizedDescription)
          .font(.headline)
          .multilineTextAlignment(.center)

        if let reason = localized?.failureReason {
          Text(reason)
            .multilineTextAlignment(.center)
        }

        if let suggestion = localized?.recoverySuggestion {
          Text(suggestion)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }

        Button(String(localized: "OK")) { dismiss() }
          .buttonStyle(.borderedProminent)
      }
      .padding()
      .presentationDetents([.medium])
    }
  }
}

extension View {
  func withErrorSheet(error: Binding<Swift.Error?>) -> some View {
    modifier(WithErrorSheet(error: error))
  }
}
