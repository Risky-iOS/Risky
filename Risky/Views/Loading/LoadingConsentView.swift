import SwiftUI

/// First screen the loader shows. Explains why the download is needed,
/// gives the pilot the option to defer when there's already a usable (but
/// expired) cache, and kicks off the download.
struct LoadingConsentView: View {
  @Environment(NavDataLoaderViewModel.self)
  private var loader

  private var titleString: String {
    if loader.canSkip {
      return String(
        localized: "Your airport database is out of date. Would you like to update it?"
      )
    }
    return String(
      localized: "You need to download airport data before you can use this app."
    )
  }

  var body: some View {
    VStack(alignment: .center, spacing: 20) {
      Image(systemName: "airplane.departure")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(maxWidth: 96, alignment: .center)
        .foregroundStyle(.tint)
        .accessibilityHidden(true)

      Text(titleString)
        .multilineTextAlignment(.center)

      Text(
        "This will download the latest FAA airport, runway, and approach data. New data is published every 28 days."
      )
      .font(.footnote)
      .padding(.horizontal, 20)
      .multilineTextAlignment(.leading)

      if loader.networkIsExpensive {
        Text("Warning: You are on a slow or metered network.")
          .foregroundStyle(.red)
          .font(.footnote)
          .padding(.horizontal, 20)
          .multilineTextAlignment(.center)
      }

      HStack(spacing: 20) {
        Button(String(localized: "Download Airport Data")) {
          loader.load()
        }
        .accessibilityIdentifier("downloadDataButton")

        if loader.canSkip {
          Button(String(localized: "Defer Until Later")) {
            loader.loadLater()
          }
          .accessibilityIdentifier("deferDataButton")
        }
      }
    }
    .padding()
  }
}

#Preview("No data") {
  LoadingConsentView()
    .environment(MockNavDataLoaderViewModel.factory(scenario: .noData))
}

#Preview("Out of date") {
  LoadingConsentView()
    .environment(MockNavDataLoaderViewModel.factory(scenario: .outOfDate))
}

#Preview("Out of date, expensive network") {
  LoadingConsentView()
    .environment(MockNavDataLoaderViewModel.factory(scenario: .outOfDateExpensive))
}
