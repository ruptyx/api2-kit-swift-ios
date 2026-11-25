#if canImport(UIKit)
import Hesabe
import UIKit

/// The ready-made checkout: a sheet that takes one session, lets the customer pay, asks
/// Hesabe how it ended, and returns that.
///
///     let sheet = HesabeCheckoutSheet(configuration: configuration)
///     let result = await sheet.present(session, methods: [.knet, .card], from: self)
///
/// Cards are entered in Hesabe's embedded card form inside the sheet. A session with
/// amount `0.000` and a customer shows the same form to save a card without a charge.
///
/// The sheet is on screen as soon as `present` is called, with a loader for every step
/// that waits on Hesabe: reading the session, opening the payment page, and confirming
/// the payment.
@MainActor
public final class HesabeCheckoutSheet {
    private let configuration: HesabeConfiguration
    private let strings: HesabeStrings
    private let client: HesabeClient

    public init(configuration: HesabeConfiguration, strings: HesabeStrings = .automatic) {
        self.configuration = configuration
        self.strings = strings
        self.client = HesabeClient(environment: configuration.environment)
    }

    /// Presents the payment and returns once Hesabe has been asked how it ended.
    ///
    /// - Parameters:
    ///   - session: a session your server created. It is single use: after any result
    ///     except `.notStarted`, pay again with a new one.
    ///   - methods: the payment methods to offer. One opens that method directly.
    ///     Several show a native list of those enabled for the session, each with
    ///     Hesabe's logo. None opens Hesabe's own page with every enabled method.
    ///     Ignored by a session that only saves a card.
    ///   - presenter: the view controller on screen.
    @discardableResult
    public func present(
        _ session: HesabeSession,
        methods: [PaymentMethod] = [],
        from presenter: UIViewController
    ) async -> PaymentResult {
        guard presenter.presentedViewController == nil else {
            return .notStarted(.configuration("the presenting view controller is already presenting"))
        }

        let navigation = UINavigationController()
        navigation.modalPresentationStyle = .formSheet
        // The customer leaves through Cancel, so the end of the payment is always seen.
        navigation.isModalInPresentation = true

        // Fetched while the session is read, so the method list opens with its logos.
        if methods.count > 1 { HesabeLogos.prefetch(methods) }

        let details: CheckoutDetails
        switch await start(session, in: navigation, from: presenter) {
        case .ready(let read):
            details = read
        case .ended(let result):
            await dismiss(navigation)
            return result
        }

        // A session that only saves a card has one way through: the card form.
        let offered = details.isCardVerification
            ? []
            : methods.filter { details.paymentMethods.contains($0) && !$0.isGooglePay }
        if !details.isCardVerification, !methods.isEmpty, offered.isEmpty {
            await dismiss(navigation)
            return .notStarted(.configuration("none of the requested payment methods is enabled for this session"))
        }

        var method: PaymentMethod? = offered.count == 1 ? offered[0] : nil
        if offered.count > 1 {
            let picker = MethodPickerViewController(
                methods: offered, amount: details.formattedAmount,
                title: configuration.merchantDisplayName ?? strings.chooseMethod,
                cancelTitle: strings.cancel)
            navigation.setViewControllers([picker], animated: false)
            method = await withCheckedContinuation { continuation in
                picker.onChoice = { continuation.resume(returning: $0) }
            }
            guard method != nil else {
                await dismiss(navigation)
                return .canceled
            }
        }

        // Written down before the page opens: from here on money can move without
        // the app seeing the end of it.
        HesabePendingPayments.track(
            PendingPayment(token: details.token, environment: configuration.environment))

        // Cards go to Hesabe's embedded form. Every other method, and a card type the
        // form does not take for this session, goes to Hesabe's payment page.
        let usesCardForm = details.isCardVerification
            || (method.map(details.embeddedCardMethods.contains) ?? false)
        let page = PaymentWebViewController(
            pageURL: usesCardForm
                ? client.cardFormURL(for: session, language: strings.languageCode)
                : client.paymentURL(for: session, method: method),
            returnURLs: configuration.returnURLs,
            title: details.isCardVerification
                ? strings.addCard
                : configuration.merchantDisplayName ?? method?.displayName,
            cancelTitle: strings.cancel,
            loadingMessage: strings.opening(method, inCardForm: usesCardForm))
        let outcome: PaymentWebViewController.Outcome = await withCheckedContinuation { continuation in
            page.onOutcome = { continuation.resume(returning: $0) }
            // The page slides in after the method list, and takes the loader's place.
            navigation.setViewControllers([page], animated: offered.count > 1)
        }

        page.showConfirming(strings.confirming)
        var result: PaymentResult
        switch outcome {
        case .returned:
            result = await client.settle(token: details.token, afterReturn: true)
        case .canceled:
            result = await client.settle(token: details.token, afterReturn: false)
        case .failed(let error):
            result = await client.settle(token: details.token, afterReturn: false)
            // No transaction at Hesabe means the page failed before anything was paid.
            if result == .canceled { result = .notStarted(error) }
        }

        switch result {
        case .paid, .cardSaved, .failed, .canceled, .notStarted:
            HesabePendingPayments.resolve(details.token)
        case .pending, .unconfirmed:
            break // left for recoverPayments() at the next launch
        }

        if let summary = strings.summary(of: result) {
            await page.showSettled(succeeded: summary.succeeded, message: summary.message)
        }
        await dismiss(navigation)
        return result
    }

    /// How the first step ended: with the session read, or with the checkout over.
    private enum Start {
        case ready(CheckoutDetails)
        case ended(PaymentResult)
    }

    /// Puts the sheet on screen with a loader and reads the session from Hesabe. The
    /// request runs while the sheet rises, so the loader costs the customer no time.
    private func start(
        _ session: HesabeSession, in navigation: UINavigationController, from presenter: UIViewController
    ) async -> Start {
        let loading = LoadingViewController(
            title: configuration.merchantDisplayName, message: strings.preparing,
            cancelTitle: strings.cancel, retryTitle: strings.tryAgain)
        navigation.setViewControllers([loading], animated: false)

        var attempt = Task { [client] in try await client.details(for: session) }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            presenter.present(navigation, animated: true) { continuation.resume() }
        }

        while true {
            loading.onCancel = { [attempt] in attempt.cancel() }
            do {
                return .ready(try await attempt.value)
            } catch {
                if attempt.isCancelled { return .ended(.canceled) }
                let error = (error as? HesabeError) ?? .connection(error.localizedDescription)
                // Reading a session changes nothing at Hesabe, so a lost connection is
                // tried again in place. A session Hesabe refused stays refused.
                guard case .connection = error,
                      await loading.offerRetry(after: error.localizedDescription)
                else { return .ended(.notStarted(error)) }
                attempt = Task { [client] in try await client.details(for: session) }
            }
        }
    }

    private func dismiss(_ navigation: UINavigationController) async {
        guard let presenting = navigation.presentingViewController else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            presenting.dismiss(animated: true) { continuation.resume() }
        }
    }
}
#endif
