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
    /// Visa and Mastercard through MPGS.
    public static let card: PaymentMethod = 2
    /// Visa and Mastercard through CyberSource.
    public static let cardCyberSource: PaymentMethod = 5
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
