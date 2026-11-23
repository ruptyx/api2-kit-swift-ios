import SwiftUI

/// Every result the demo has shown, newest first. A row reopens its result screen.
@MainActor
struct HistoryView: View {
    let records: [PaymentRecord]
    let onClear: () -> Void

    var body: some View {
        List(records) { record in
            NavigationLink(value: Route.result(record.id)) {
                HStack(spacing: 12) {
                    Image(systemName: record.outcome.symbol)
                        .font(.title2)
                        .foregroundStyle(record.outcome.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.outcome.title)
                        Text(summary(of: record))
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .overlay {
            if records.isEmpty {
                ContentUnavailableView(
                    "No payments yet", systemImage: "clock",
                    description: Text("Every result is kept here, so it can be opened again."))
            }
        }
        .navigationTitle("Payment history")
        .toolbar {
            Button("Clear", role: .destructive, action: onClear)
                .disabled(records.isEmpty)
        }
    }

    /// `KNET · KWD 0.250 · 23 Nov 2026 at 14:02`
    private func summary(of record: PaymentRecord) -> String {
        [
            record.flow.title,
            record.amount.map { "KWD \($0)" },
            record.date.formatted(date: .abbreviated, time: .shortened),
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
