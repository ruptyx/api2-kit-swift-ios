#if canImport(UIKit)
import Hesabe
import UIKit
@preconcurrency import WebKit

/// Shows Hesabe's payment page and reports when the payment flow has ended. It never
/// says how it ended: `HesabeCheckoutSheet` asks Hesabe for that.
@MainActor
final class PaymentWebViewController: UIViewController {
    enum Outcome {
        /// Hesabe navigated to a return URL.
        case returned
        /// The customer tapped Cancel.
        case canceled
        /// The page could not be loaded, or the connection dropped.
        case failed(HesabeError)
    }

    private let pageURL: URL
    private let returnURLs: ReturnURLs
    private let cancelTitle: String
    private let loadingMessage: String
    private var hasFinished = false
    /// False until the first page is shown: it has finished loading, or it has been
    /// drawing for three seconds. An HTTP error before that is Hesabe refusing the
    /// session, not a step of the payment.
    private var hasShownPage = false

    /// Called once, with how the flow ended.
    var onOutcome: ((Outcome) -> Void)?

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        // Card entry and gateway cookies must not outlive the payment inside the app.
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        // An iPad web view asks for desktop pages by default, and Hesabe's card form
        // answers those with HTTP 403: it is served to phone web views only.
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile

        // No user scripts and no evaluateJavaScript anywhere in this class: WebKit
        // switches Apple Pay off in a web view the app has injected script into.
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = false
        // Hesabe's card form has a transparent page around the fields, so the app's
        // background shows through in light and dark mode.
        view.isOpaque = false
        view.backgroundColor = .systemBackground
        view.scrollView.backgroundColor = .systemBackground
        return view
    }()

    /// Covers the page while it opens, and again once the flow ends, so the customer
    /// sees what is happening and not a blank page or a sheet that vanishes
    /// mid-transaction.
    private let status = StatusView()

    /// Spins in the bar while a later page of the flow loads: the bank's page after
    /// KNET's, or the way back to Hesabe. It never covers the page the customer is on.
    private lazy var progress = UIActivityIndicatorView(style: .medium)

    /// - Parameter loadingMessage: the line under the loader until the first page has
    ///   rendered, for example "Connecting to KNET…".
    init(pageURL: URL, returnURLs: ReturnURLs, title: String?, cancelTitle: String, loadingMessage: String) {
        self.pageURL = pageURL
        self.returnURLs = returnURLs
        self.cancelTitle = cancelTitle
        self.loadingMessage = loadingMessage
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: cancelTitle, style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: progress)

        webView.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        view.addSubview(status)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            status.topAnchor.constraint(equalTo: view.topAnchor),
            status.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            status.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        status.showLoading(loadingMessage)
        webView.load(URLRequest(url: pageURL))
    }

    @objc private func cancelTapped() {
        // Not "payment failed": a charge may be in flight, or already taken in a
        // banking app. The sheet asks Hesabe before it says anything.
        finish(.canceled)
    }

    // MARK: - Status

    /// Takes the loader off the first page. Once the flow has ended the cover stays: it
    /// is showing the confirmation by then.
    private func revealPage() {
        guard !hasShownPage else { return }
        hasShownPage = true
        guard !hasFinished else { return }
        status.isHidden = true
        // A page shown before it has finished keeps the spinner in the bar until it has.
        if webView.isLoading { progress.startAnimating() }
    }

    /// Hides the page behind a loader while Hesabe is asked what happened.
    func showConfirming(_ message: String) {
        navigationItem.leftBarButtonItem?.isEnabled = false
        webView.stopLoading()
        progress.stopAnimating()
        status.showLoading(message)
        status.isHidden = false
    }

    /// Shows the settled outcome for a moment before the sheet closes.
    func showSettled(succeeded: Bool, message: String) async {
        status.showResult(succeeded: succeeded, message: message)
        status.isHidden = false
        try? await Task.sleep(nanoseconds: 1_200_000_000)
    }

    private func finish(_ outcome: Outcome) {
        guard !hasFinished else { return }
        hasFinished = true
        let report = onOutcome
        onOutcome = nil
        report?(outcome)
    }

    /// Every delegate callback funnels through here, so they cannot disagree.
    private func endIfReturn(_ url: URL?) -> Bool {
        guard let url, returnURLs.matches(url) else { return false }
        finish(.returned)
        return true
    }
}

// MARK: - WKNavigationDelegate

extension PaymentWebViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true

        // KNET and several issuers hand 3-D Secure to a banking app over a custom
        // scheme. WKWebView drops those silently and the customer is left on a dead
        // page. Frames keep their about:, blob: and data: documents.
        if let scheme = url.scheme?.lowercased(), !["http", "https"].contains(scheme) {
            guard isMainFrame, !["about", "blob", "data", "javascript"].contains(scheme) else {
                return .allow
            }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return .cancel
        }

        // The return URL is never loaded: a slow or missing page on the merchant's
        // site must not strand a customer who has paid.
        if isMainFrame, endIfReturn(url) { return .cancel }
        return .allow
    }

    /// Server redirects stay inside one navigation and are reported here, not to the
    /// policy callback above. Hesabe returns to `responseUrl` with exactly such a
    /// redirect, so a delegate with only the policy callback renders the merchant's
    /// page and misses the end of the payment.
    func webView(
        _ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
    ) {
        if endIfReturn(webView.url) { webView.stopLoading() }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        guard navigationResponse.isForMainFrame else { return .allow }
        if endIfReturn(navigationResponse.response.url) { return .cancel }
        if !hasShownPage, let http = navigationResponse.response as? HTTPURLResponse, http.statusCode >= 400 {
            finish(.failed(.rejected("the payment page answered HTTP \(http.statusCode)")))
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if hasShownPage, !hasFinished { progress.startAnimating() }
    }

    /// The first page has begun to draw. `didFinish` waits for every file on it, and
    /// Hesabe's payment page for a card type went on loading for more than four seconds
    /// after its text could be read (sandbox, iOS simulator, November 2026). The loader
    /// gives a page three seconds to finish, then shows it as it is.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard !hasShownPage else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self?.revealPage()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        revealPage()
        progress.stopAnimating()
        // A page that reached a return URL without either callback, by script.
        _ = endIfReturn(webView.url)
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) {
        fail(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failed(.connection("the payment page stopped")))
    }

    private func fail(_ error: Error) {
        progress.stopAnimating()
        let error = error as NSError
        // Both are the echo of a navigation this delegate cancelled itself.
        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled { return }
        if error.domain == "WebKitErrorDomain", error.code == 102 { return }
        finish(.failed(.connection(error.localizedDescription)))
    }
}

// MARK: - WKUIDelegate

extension PaymentWebViewController: WKUIDelegate {
    /// Some 3-D Secure pages open with `target="_blank"`. WKWebView opens nothing by
    /// default, so the button appears dead; loading the page in place fixes that.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
#endif
