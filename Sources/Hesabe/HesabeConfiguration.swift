import Foundation

/// Everything the SDK is told once, at start-up. None of it is secret.
public struct HesabeConfiguration: Sendable, Hashable {
    /// The gateway your server creates sessions on.
    public var environment: HesabeEnvironment

    /// The `responseUrl` and `failureUrl` your server sends to the Checkout API. The
    /// SDK ends the payment when Hesabe navigates to either.
    public var returnURLs: ReturnURLs

    /// Shown in the bar above the payment page.
    public var merchantDisplayName: String?

    /// The hosted page that draws the Apple Pay button, `hosting/apple-pay.html` in this
    /// repository. Apple Pay starts only on a page served over HTTPS from a domain
    /// registered with Apple, so it cannot ship inside the app. Needed by
    /// `HesabeApplePayButton` only.
    public var applePayPageURL: URL?

    public init(
        environment: HesabeEnvironment,
        returnURLs: ReturnURLs,
        merchantDisplayName: String? = nil,
        applePayPageURL: URL? = nil
    ) {
        self.environment = environment
        self.returnURLs = returnURLs
        self.merchantDisplayName = merchantDisplayName
        self.applePayPageURL = applePayPageURL
    }
}
