#if canImport(UIKit)
import UIKit

/// The first screen of the sheet: a loader while the session is read from Hesabe. It is
/// on screen the moment the app asks for the checkout, so a tap is always answered.
@MainActor
final class LoadingViewController: UIViewController {
    private let message: String
    private let cancelTitle: String
    private let retryTitle: String
    private let status = StatusView()

    /// Called when the customer cancels while the loader is showing.
    var onCancel: (() -> Void)?

    /// Set while the customer is choosing between trying again and cancelling.
    private var onChoice: ((Bool) -> Void)?

    init(title: String?, message: String, cancelTitle: String, retryTitle: String) {
        self.message = message
        self.cancelTitle = cancelTitle
        self.retryTitle = retryTitle
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        view = status
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: cancelTitle, style: .plain, target: self, action: #selector(cancelTapped))
        status.showLoading(message)
    }

    /// Replaces the loader with what went wrong and a button to try again.
    ///
    /// - Returns: `true` when the customer asks to try again, and the loader is back on
    ///   screen. `false` when the customer cancels.
    func offerRetry(after failure: String) async -> Bool {
        await withCheckedContinuation { continuation in
            onChoice = { continuation.resume(returning: $0) }
            status.showFailure(failure, retryTitle: retryTitle) { [weak self] in self?.choose(true) }
        }
    }

    @objc private func cancelTapped() {
        if onChoice == nil {
            onCancel?()
        } else {
            choose(false)
        }
    }

    private func choose(_ tryAgain: Bool) {
        guard let report = onChoice else { return }
        onChoice = nil
        if tryAgain { status.showLoading(message) }
        report(tryAgain)
    }
}
#endif
