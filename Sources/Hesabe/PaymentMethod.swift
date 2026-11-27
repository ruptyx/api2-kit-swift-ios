import Foundation

/// A Hesabe payment type id. Hesabe calls it `paymentType`.
///
/// It is a struct, not an enum, so a type Hesabe adds later still works: pass its id.
public struct PaymentMethod: RawRepresentable, Sendable, Hashable, Codable,
    ExpressibleByIntegerLiteral
{
    public let rawValue: Int

    public init(rawValue: Int) { self.rawValue = rawValue }
    public init(integerLiteral value: Int) { self.rawValue = value }

    public static let knet: PaymentMethod = 1
    /// Visa and Mastercard. The id is the MPGS one. On an account whose cards go through
    /// CyberSource the checkout sheet offers type 5 for it: see
    /// `CheckoutDetails.offered(from:)`.
    public static let card: PaymentMethod = 2
    /// Visa and Mastercard through CyberSource.
    public static let cardCyberSource: PaymentMethod = 5
    /// American Express. On an account that has type 8 and not 7, the checkout sheet
    /// offers 8 for it.
    public static let amex: PaymentMethod = 7
    /// American Express through MPGS.
    public static let amexMPGS: PaymentMethod = 8
    public static let applePayMPGS: PaymentMethod = 9
    public static let applePayCyberSource: PaymentMethod = 10
    public static let applePayKNETDebit: PaymentMethod = 11
    public static let applePayKNETCredit: PaymentMethod = 12
    public static let applePayKNETInternational: PaymentMethod = 13
    public static let applePayAmex: PaymentMethod = 14
    public static let deema: PaymentMethod = 18
    public static let samsungPay: PaymentMethod = 20

    /// True for the four card types, which Hesabe's Direct Method takes: 2 and 5 are
    /// Visa and Mastercard, 7 and 8 are American Express.
    public var isCard: Bool { [2, 5, 7, 8].contains(rawValue) }

    /// True for the two American Express types, 7 and 8.
    public var isAmex: Bool { rawValue == 7 || rawValue == 8 }

    /// The payment type for the same cards on Hesabe's other card gateway: 2 and 5 are
    /// one pair, 7 and 8 the other. `nil` for every method that is not a card.
    var sameCardsOnOtherGateway: PaymentMethod? {
        switch rawValue {
        case 2: return .cardCyberSource
        case 5: return .card
        case 7: return .amexMPGS
        case 8: return .amex
        default: return nil
        }
    }

    /// True for the six Apple Pay types, 9 to 14.
    public var isApplePay: Bool { (9...14).contains(rawValue) }

    /// True for Google Pay, type 16. It is not part of the iOS SDK, so the method list
    /// never offers it, even when the account has it enabled.
    public var isGooglePay: Bool { rawValue == 16 }

    /// Hesabe's logo for the method: a PNG in Hesabe's assets bucket, named by the
    /// payment type id. Hesabe has none for some ids, and the address then answers 404.
    public var logoURL: URL { Self.logos.appendingPathComponent("\(rawValue).png") }

    private static let logos = URL(
        string: "https://hesabe-assets-ir.s3.eu-west-1.amazonaws.com/landingpage/assets")!

    /// The name shown in the method list.
    public var displayName: String {
        switch rawValue {
        case 1: "KNET"
        case 2, 5: "Visa / Mastercard"
        case 7, 8: "American Express"
        case 9, 10: "Apple Pay"
        case 11, 12: "Apple Pay (KNET)"
        case 13: "Apple Pay (international cards)"
        case 14: "Apple Pay (American Express)"
        case 18: "Deema"
        case 20: "Samsung Pay"
        default: "Payment method \(rawValue)"
        }
    }
}
