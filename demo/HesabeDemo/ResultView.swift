import HesabeUI
import SwiftUI

/// The screen every payment ends on: how it ended, what Hesabe recorded, whether the
/// server agrees, and Hesabe's answers in full.
@MainActor
struct ResultView: View {
    let record: PaymentRecord
    /// True while Hesabe is being asked about this payment.
    let isChecking: Bool
    /// Starts the same payment again with a new session. `nil` when the home screen is
    /// where it starts again.
    var onRetry: (() -> Void)?
    /// Asks Hesabe again, from the device and from the server. `nil` when there is no
    /// token to ask by.
    var onCheckAgain: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section { header }
            Section("Payment details") { rows(paymentDetails) }
            Section("Bank and gateway details") {
                rows(gatewayDetails, whenEmpty: "Hesabe has no transaction for this session.")
            }
            Section("Verification") { verification }
            Section("Raw response") { rawResponses }
            Section { actions }
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Status

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: record.outcome.symbol)
                .font(.system(size: 56))
                .foregroundStyle(record.outcome.color)
            Text(record.outcome.title)
                .font(.title2.bold())
            Text(record.outcome.meaning)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Details

    /// One labelled value. Those Hesabe gave nothing for are left off the screen.
    private struct Detail: Identifiable {
        let label: String
        let value: String?
        var id: String { label }

        init(_ label: String, _ value: String?) {
            self.label = label
            self.value = value
        }
    }

    private var paymentDetails: [Detail] {
        [
            Detail("Amount", record.amount.map { "KWD \($0)" }),
            Detail("Method", record.transaction?.paymentType),
            Detail("Card", record.transaction?.maskedCard ?? savedCardName),
            Detail("Order reference", record.reference),
            Detail("Payment ID", record.transaction?.paymentID ?? record.charge?.paymentId),
            Detail("Transaction ID", record.transaction?.transactionID ?? record.charge?.transactionId),
            Detail("Payment token", record.token),
            // Hesabe's own clock, which is Kuwait time with no zone.
            Detail("Date and time", record.transaction?.datetime ?? record.charge?.paidOn),
            Detail("Started with", record.flow.title),
        ]
    }

    private var gatewayDetails: [Detail] {
        [
            Detail("Status", record.transaction?.status),
            Detail("Result code", record.charge?.status),
            Detail("Auth code", record.charge?.auth),
            Detail("Track ID", record.transaction?.trackID ?? record.charge?.trackId),
            Detail("Terminal", record.transaction?.terminal),
            Detail("Card type", record.transaction?.cardType),
            Detail("Response message", record.message),
        ]
    }

    private var savedCardName: String? {
        if case .savedCard(let name) = record.flow { return name }
        return nil
    }

    /// One row for each detail Hesabe gave a value for.
    @ViewBuilder
    private func rows(_ details: [Detail], whenEmpty note: String? = nil) -> some View {
        let known = details.filter { !($0.value ?? "").isEmpty }
        if known.isEmpty, let note {
            Text(note).foregroundStyle(.secondary)
        }
        ForEach(known) { detail in
            LabeledContent(detail.label) {
                Text(detail.value ?? "").textSelection(.enabled)
            }
        }
    }

    // MARK: - Verification

    /// The SDK's answer travelled through the customer's device. The server's did not,
    /// so the two are shown apart and only the server's may release an order.
    @ViewBuilder
    private var verification: some View {
        report("What the SDK reported", record.sdkReport)
        if let answer = record.serverReport {
            report("What the server confirmed with Hesabe", answer)
        } else if isChecking {
            LabeledContent("What the server confirmed with Hesabe") { ProgressView() }
        } else {
            report("What the server confirmed with Hesabe", "Not asked: there is no token to ask by")
        }

        let verdict = record.verdict
        Label(verdict.text, systemImage: verdict.symbol)
            .foregroundStyle(verdict.color)
    }

    private func report(_ title: String, _ answer: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(answer)
        }
    }

    // MARK: - Raw response

    @ViewBuilder
    private var rawResponses: some View {
        let serverAnswer = record.confirmation?.transaction?.rawJSON ?? record.charge?.raw
        let answers = [
            Detail("Hesabe's answer to the SDK", record.transaction?.rawJSON),
            Detail("Hesabe's answer to the server", serverAnswer),
        ].filter { $0.value != nil }
        if answers.isEmpty {
            Text("Hesabe sent nothing about this payment.").foregroundStyle(.secondary)
        }
        ForEach(answers) { answer in
            RawResponse(title: answer.label, json: answer.value ?? "")
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        switch record.outcome {
        case .paid, .cardSaved:
            EmptyView()
        case .failed, .canceled, .notStarted:
            if let onRetry {
                Button("Try again", action: onRetry)
            }
        case .pending, .unconfirmed:
            if let onCheckAgain {
                PayButton(title: "Check status again", isBusy: isChecking, action: onCheckAgain)
                    .disabled(isChecking)
            }
        }
        Button("Done") { dismiss() }
    }
}

/// One of Hesabe's answers as JSON, folded away until a developer asks for it.
@MainActor
private struct RawResponse: View {
    let title: String
    let json: String

    var body: some View {
        DisclosureGroup(title) {
            Button("Copy") { UIPasteboard.general.string = json }
                .buttonStyle(.borderless)
            Text(json)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}

// MARK: - How each result looks

extension PaymentRecord.Verdict {
    var symbol: String {
        switch agrees {
        case true?: "checkmark.seal.fill"
        case false?: "exclamationmark.triangle.fill"
        case nil: "info.circle"
        }
    }

    var color: Color {
        switch agrees {
        case true?: .green
        case false?: .red
        case nil: .secondary
        }
    }
}

extension PaymentRecord.Outcome {
    var title: String {
        switch self {
        case .paid: "Payment successful"
        case .cardSaved: "Card saved"
        case .failed: "Payment failed"
        case .pending: "Pending"
        case .canceled: "Canceled"
        case .unconfirmed: "Could not confirm"
        case .notStarted: "Could not start"
        }
    }

    var symbol: String {
        switch self {
        case .paid: "checkmark.circle.fill"
        case .cardSaved: "creditcard.circle.fill"
        case .failed: "xmark.circle.fill"
        case .pending: "clock.fill"
        case .canceled: "minus.circle.fill"
        case .unconfirmed: "questionmark.circle.fill"
        case .notStarted: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .paid: .green
        case .cardSaved: .blue
        case .failed: .red
        case .pending: .orange
        case .canceled: .gray
        case .unconfirmed: .purple
        case .notStarted: .brown
        }
    }

    /// What the result means for the customer's money.
    var meaning: String {
        switch self {
        case .paid: "Hesabe confirms the payment."
        case .cardSaved: "Hesabe stored the card and charged nothing."
        case .failed: "Hesabe recorded the attempt and it did not go through. Nothing was charged."
        case .pending: "Hesabe has the payment and has not settled it. Do not pay again yet."
        case .canceled: "The payment was closed and Hesabe has no transaction. Nothing was charged."
        case .unconfirmed: "Hesabe could not be asked how it ended. The customer may have been charged."
        case .notStarted: "The payment never started. Nothing was charged."
        }
    }
}
