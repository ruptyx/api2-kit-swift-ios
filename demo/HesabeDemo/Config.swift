import Foundation
import HesabeUI

/// Everything the app itself is told. None of it is secret: the sandbox keys are in
/// `SandboxMerchantServer.swift`, which stands in for your server.
enum Config {
    /// The gateway the sessions are created on. `SandboxMerchantServer` is fixed to the
    /// sandbox, so this changes only when your own server creates the sessions.
    static let environment: HesabeEnvironment = .sandbox

    /// The `responseUrl` and `failureUrl` every session is created with. The SDK ends
    /// the payment when Hesabe navigates to it. Nothing is ever fetched from it.
    static let returnURL = URL(string: "https://example.com/hesabe/return")!

    /// The hosted Apple Pay button page, for example
    /// `URL(string: "https://example.com/apple-pay.html")`. `nil` hides the button.
    static let applePayPage: URL? = nil

    /// The Apple Pay payment type on your account: 11 KNET debit, 13 KNET international.
    static let applePayMethod: PaymentMethod = .applePayKNETDebit

    /// The price shown in the app. The server charges its own copy of it.
    static let unitPrice = Decimal(string: "0.250")!

    static var hesabe: HesabeConfiguration {
        HesabeConfiguration(
            environment: environment,
            returnURLs: ReturnURLs(returnURL),
            merchantDisplayName: "Hesabe Demo",
            applePayPageURL: applePayPage)
    }
}

/// The only place a `Decimal` becomes text: three decimals, as Hesabe writes amounts.
func hesabeAmount(_ amount: Decimal) -> String {
    var value = amount
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, 3, .plain)
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.minimumIntegerDigits = 1
    formatter.minimumFractionDigits = 3
    formatter.maximumFractionDigits = 3
    return formatter.string(from: rounded as NSDecimalNumber) ?? "\(rounded)"
}
