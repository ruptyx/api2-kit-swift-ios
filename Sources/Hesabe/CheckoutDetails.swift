import Foundation

/// What Hesabe says about a session before anything is paid: the amount and the
/// payment methods enabled for it. Read from `api/checkout-details`, which takes the
/// session's `data` and no merchant key.
public struct CheckoutDetails: Sendable, Hashable, Decodable {
    /// Hesabe's token for the session. The outcome is looked up by it.
    public let token: String
    public let amount: Decimal
    public let currency: String
    /// The payment type the server asked for. `0` leaves the choice to the customer.
    public let requestedMethod: PaymentMethod
    /// Every payment type enabled for this session.
    public let paymentMethods: [PaymentMethod]
    /// The Apple Pay types among them, as Hesabe lists them for its Apple Pay script.
    public let applePayMethods: [PaymentMethod]
    /// The card gateways behind Hesabe's embedded card form on this account, as payment
    /// type ids. `[5]`, CyberSource, on the sandbox and on a production account on
    /// 27 November 2026. `[2]`, MPGS, on the sandbox ten days earlier. Empty when the
    /// account has no Direct Method.
    public let directGateways: [PaymentMethod]
    /// The card schemes the form accepts, as Hesabe names them: `VISA` and `MASTERCARD`
    /// with CyberSource, and also `DINERS_CLUB` and `UNION_PAY` with MPGS (sandbox,
    /// November 2026).
    public let directCardSchemes: [String]
    /// True when your server put a Hesabe customer on the session (`customer_id`).
    public let hasCustomer: Bool
    /// True when the card form offers to save the card: `saveCard` with a customer.
    public let offersCardSaving: Bool

    /// True for a session that saves a card and charges nothing: amount `0.000` with a
    /// customer. The card form then reads "Save Card" in place of "Pay".
    public var isCardVerification: Bool { amount == 0 && hasCustomer }

    /// The methods among `requested` that this session can be paid with, in the order
    /// asked for. Google Pay is left out.
    ///
    /// Hesabe has one payment type per card gateway, and the gateway is Hesabe's
    /// setting for the account, not the app's choice. So a card type the session does
    /// not have stands for the type it has for the same cards: `.card` is offered as
    /// type 5 on an account with 5 and not 2, which is what a production account listed
    /// in November 2026.
    public func offered(from requested: [PaymentMethod]) -> [PaymentMethod] {
        var offered: [PaymentMethod] = []
        for method in requested where !method.isGooglePay {
            let enabled = paymentMethods.contains(method) ? method : method.sameCardsOnOtherGateway
            guard let enabled, paymentMethods.contains(enabled), !offered.contains(enabled) else { continue }
            offered.append(enabled)
        }
        return offered
    }

    /// True when the method is paid in Hesabe's embedded card form: a card type, on an
    /// account with a direct card gateway. The form uses that gateway whichever card type
    /// was asked for: a session created with payment type 2 saved its card as `CYBS` on
    /// the sandbox on 26 November 2026. Every other method opens Hesabe's payment page.
    public func usesCardForm(for method: PaymentMethod) -> Bool {
        guard method.isCard, !directGateways.isEmpty else { return false }
        // Hesabe's name for American Express in this list has not been seen: no account
        // the SDK was run against has it (November 2026). The names seen are capitals
        // with underscores, as in `UNION_PAY`, so `AMEX` and `AMERICAN_EXPRESS` both count.
        return !method.isAmex || directCardSchemes.contains { $0.uppercased().hasPrefix("AM") }
    }

    /// The amount as Hesabe writes it: the currency and three decimals, `KWD 1.000`.
    public var formattedAmount: String {
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 3, .plain)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 3
        formatter.maximumFractionDigits = 3
        formatter.minimumIntegerDigits = 1
        let digits = formatter.string(from: rounded as NSDecimalNumber) ?? "\(rounded)"
        return "\(currency) \(digits)"
    }

    private enum CodingKeys: String, CodingKey {
        case token, amount, currency, paymentTypeId, paymentMethods, applePay
        case hasCustomer, merchantSaveCard, activeDirectGatewayIds, directSupportedCardTypes
    }

    private struct ApplePayEntry: Decodable {
        let id: Int
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decode(String.self, forKey: .token)
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "KWD"

        // Hesabe sends the amount as a number here and as a string elsewhere, and the
        // payment type as "0" (sandbox, November 2026). Both spellings are read.
        if let text = try? container.decode(String.self, forKey: .amount) {
            guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .amount, in: container, debugDescription: "amount is not a number")
            }
            amount = value
        } else {
            amount = try container.decode(Decimal.self, forKey: .amount)
        }

        if let text = try? container.decode(String.self, forKey: .paymentTypeId) {
            requestedMethod = PaymentMethod(rawValue: Int(text) ?? 0)
        } else {
            requestedMethod = PaymentMethod(
                rawValue: try container.decodeIfPresent(Int.self, forKey: .paymentTypeId) ?? 0)
        }

        paymentMethods = try container.decodeIfPresent([Int].self, forKey: .paymentMethods)?
            .map(PaymentMethod.init(rawValue:)) ?? []
        applePayMethods = try container.decodeIfPresent([ApplePayEntry].self, forKey: .applePay)?
            .map { PaymentMethod(rawValue: $0.id) } ?? []
        directGateways = try container.decodeIfPresent([Int].self, forKey: .activeDirectGatewayIds)?
            .map(PaymentMethod.init(rawValue:)) ?? []
        directCardSchemes =
            try container.decodeIfPresent([String].self, forKey: .directSupportedCardTypes) ?? []
        hasCustomer = try container.decodeIfPresent(Bool.self, forKey: .hasCustomer) ?? false
        offersCardSaving = try container.decodeIfPresent(Bool.self, forKey: .merchantSaveCard) ?? false
    }
}
