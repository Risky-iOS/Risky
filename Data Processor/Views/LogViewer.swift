import SwiftUI

/// Scrolling log viewer showing the most recent entries from the
/// shared ``LogCollector``.
struct LogViewer: View {
  private static let timeFormat: Date.FormatStyle = .dateTime
    .hour(.twoDigits(amPM: .omitted))
    .minute(.twoDigits)
    .second(.twoDigits)

  let entries: [LogEntry]

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(entries) { entry in
            row(for: entry)
              .id(entry.id)
          }
        }
        .padding(.horizontal, 4)
      }
      .frame(minHeight: 180)
      .background(.background.secondary, in: .rect(cornerRadius: 6))
      .onChange(of: entries.count) { _, _ in
        if let last = entries.last {
          withAnimation(nil) {
            proxy.scrollTo(last.id, anchor: .bottom)
          }
        }
      }
    }
  }

  private func row(for entry: LogEntry) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(entry.timestamp, format: Self.timeFormat)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
      Text(severityLabel(entry.severity))
        .font(.caption2.monospaced().bold())
        .foregroundStyle(severityColor(entry.severity))
        .frame(width: 56, alignment: .leading)
      Text(entry.message)
        .font(.caption.monospaced())
        .textSelection(.enabled)
    }
  }

  private func severityLabel(_ severity: LogEntry.Severity) -> String {
    switch severity {
      case .debug: "DEBUG"
      case .info: "INFO"
      case .notice: "NOTICE"
      case .warning: "WARN"
      case .error: "ERROR"
    }
  }

  private func severityColor(_ severity: LogEntry.Severity) -> Color {
    switch severity {
      case .debug: .secondary
      case .info: .primary
      case .notice: .blue
      case .warning: .orange
      case .error: .red
    }
  }
}

#Preview("Empty") {
  LogViewer(entries: [])
    .padding()
    .frame(width: 600, height: 240)
}

#Preview("Mixed severities") {
  LogViewer(entries: PreviewHelper.sampleLogEntries)
    .padding()
    .frame(width: 600, height: 240)
}
