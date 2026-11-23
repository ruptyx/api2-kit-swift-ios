import Foundation
import HesabeUI

/// One result as the demo shows and keeps it: what the SDK reported, what the server
/// found when it asked Hesabe itself, and everything Hesabe said about the payment.
struct PaymentRecord: Codable, Identifiable, Hashable {
    /// The SDK's seven results, as a value that can be stored.
    enum Outcome: String, Codable {
        case paid, cardSaved, failed, pending, canceled, unconfirmed, notStarted
    }

    /// How the payment was started.
    enum Flow: Codable, Hashable {
        /// The checkout sheet. No methods is the Indirect Method: Hesabe's own page.
        case checkout(methods: [PaymentMethod])
        case applePay
        /// A session with amount `0.000`, which saves a card and charges nothing.
        case addCard
        /// The server charged a saved card: no page, and no SDK.
        case savedCard(name: String)
        /// Settled by `recoverPayments()` at launch.
        case recovered

        /// The methods the checkout sheet is asked for.
        var methods: [PaymentMethod] {
            if case .checkout(let methods) = self { return methods }
            return []
        }

        var title: String {
            switch self {
            case .checkout(let methods) where methods.isEmpty: return "Indirect Method"
            case .checkout(let methods) where methods == [.knet]: return "KNET"
            case .checkout(let methods) where methods == [.card]: return "Card"
            case .checkout: return "Choose a method"
            case .applePay: return "Apple Pay"
            case .addCard: return "Add a card"
            case .savedCard: return "Saved card"
            case .recovered: return "Recovered at launch"
            }
        }
    }

    let id: UUID
    /// When the demo learned the result.
    let date: Date
    let flow: Flow
    var outcome: Outcome
    /// Why, in the SDK's or the server's words, when there is something to explain.
    var message: String?
    /// Hesabe's token for the session. A later check asks Hesabe by it.
    var token: String?
    var reference: String?
    /// With three decimals, as Hesabe or the server wrote it.
    var amount: String?
    /// Hesabe's record as the SDK read it. `nil` when Hesabe has none, and for a
    /// saved-card charge, which the SDK takes no part in.
    var transaction: HesabeTransaction?
    /// What the server found when it asked Hesabe itself.
    var confirmation: Backend.Confirmation?
    /// Why the server could not be asked.
    var confirmationError: String?
    /// Hesabe's answer to the server's saved-card charge.
    var charge: Backend.Charge?
}

// MARK: - From a result

extension PaymentRecord {
    /// A result of the checkout sheet, the Apple Pay button or `recoverPayments()`.
    ///
    /// - Parameter order: the session the payment ran on. It names the payment when
    ///   Hesabe has no transaction to name it by.
    init(_ result: PaymentResult, flow: Flow, order: Backend.Order? = nil) {
        self.init(
            id: UUID(), date: Date(), flow: flow, outcome: .canceled,
            token: order?.token, reference: order?.reference, amount: order?.amount)
        apply(result)
    }

    /// The server's answer to charging a saved card. It is Hesabe's own answer to the
    /// server, so there is nothing further to confirm.
    init(_ charge: Backend.Charge, card: HesabeSavedCard) {
        self.init(
            id: UUID(), date: Date(), flow: .savedCard(name: card.displayName),
            outcome: charge.paid ? .paid : .failed, message: charge.message,
            token: charge.token, reference: charge.reference, amount: charge.amount, charge: charge)
    }

    /// A saved-card charge whose answer never arrived. The request may have reached
    /// Hesabe before the answer was lost, so it is never reported as not paid.
    init(unansweredChargeOn card: HesabeSavedCard, error: Error) {
        self.init(
            id: UUID(), date: Date(), flow: .savedCard(name: card.displayName), outcome: .unconfirmed,
            message: "\(error.localizedDescription) The card may have been charged. Check before paying again.")
    }

    /// Takes what the SDK now says about the same payment.
    mutating func apply(_ result: PaymentResult) {
        switch result {
        case .paid(let transaction): settle(.paid, transaction)
        case .cardSaved(let transaction): settle(.cardSaved, transaction)
        case .failed(let transaction): settle(.failed, transaction)
        case .pending(let transaction): settle(.pending, transaction)
        case .canceled:
            outcome = .canceled
            message = nil
        case .unconfirmed(let error):
            outcome = .unconfirmed
            message = error.localizedDescription
        case .notStarted(let error):
            outcome = .notStarted
            message = error.localizedDescription
        }
    }

    private mutating func settle(_ outcome: Outcome, _ transaction: HesabeTransaction) {
        self.outcome = outcome
        self.transaction = transaction
        message = nil
        token = transaction.token ?? token
        reference = transaction.orderReference ?? reference
        amount = transaction.amount ?? amount
    }
}

// MARK: - Verification

extension PaymentRecord {
    /// What the SDK learned from Hesabe on the device, in one line.
    var sdkReport: String {
        if case .savedCard = flow { return "Not involved. Your server charged the card." }
        switch outcome {
        case .paid, .cardSaved, .failed, .pending: return transaction?.status ?? "No status"
        case .canceled: return "No transaction at Hesabe"
        case .unconfirmed: return "Could not ask Hesabe"
        case .notStarted: return "The payment never started"
        }
    }

    /// What the server learned by asking Hesabe itself. `nil` until it has answered.
    var serverReport: String? {
        charge?.status ?? confirmation?.status ?? confirmationError
    }

    /// Whether the SDK and the server say the same thing, and what that means for the
    /// order.
    struct Verdict {
        /// `nil` when there are not two answers to compare.
        let agrees: Bool?
        let text: String
    }

    var verdict: Verdict {
        if let charge {
            let consequence = charge.paid ? "The order can be released." : "Nothing was charged."
            return Verdict(agrees: nil, text: "Hesabe answered your server directly. \(consequence)")
        }
        guard let confirmation else {
            return Verdict(
                agrees: nil, text: "Your server has not confirmed this payment. Do not release the order.")
        }
        let consequence = confirmation.paid ? "The order can be released." : "There is nothing to release."
        guard let sdkStatus else {
            return Verdict(agrees: nil, text: "Only your server's answer counts here. \(consequence)")
        }
        return sdkStatus.caseInsensitiveCompare(confirmation.status) == .orderedSame
            ? Verdict(agrees: true, text: "They agree. \(consequence)")
            : Verdict(agrees: false, text: "They disagree. Act on your server's answer. \(consequence)")
    }

    /// Hesabe's status word as the SDK read it, in the server's terms. `nil` when the
    /// SDK has nothing to compare.
    private var sdkStatus: String? {
        switch outcome {
        case .paid, .cardSaved, .failed, .pending: return transaction?.status
        case .canceled: return Backend.Confirmation.notFound
        case .unconfirmed, .notStarted: return nil
        }
    }
}

// MARK: - History

/// Every result the demo has shown, newest first, kept on the device so an earlier one
/// can be reopened.
struct PaymentHistory {
    private static let storageKey = "com.hesabe.demo.paymentHistory"
    /// Enough for a demo. Each record holds Hesabe's answers in full.
    private static let limit = 50

    private(set) var records: [PaymentRecord]

    static func load() -> PaymentHistory {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let records = try? JSONDecoder().decode([PaymentRecord].self, from: data)
        else { return PaymentHistory(records: []) }
        return PaymentHistory(records: records)
    }

    subscript(id: PaymentRecord.ID) -> PaymentRecord? {
        records.first { $0.id == id }
    }

    mutating func add(_ record: PaymentRecord) {
        records.insert(record, at: 0)
        records = Array(records.prefix(Self.limit))
        save()
    }

    /// Changes one record in place. Nothing happens when it is no longer kept.
    mutating func update(_ id: PaymentRecord.ID, _ change: (inout PaymentRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        change(&records[index])
        save()
    }

    mutating func clear() {
        records = []
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
