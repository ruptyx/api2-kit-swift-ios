#if canImport(UIKit)
import UIKit

/// The SDK's one full-screen status: a loader with a line of text, a settled result, or
/// a failure with a way to try again. The sheet shows it while it reads the session,
/// while a payment page opens, and while Hesabe is asked how the payment ended, so the
/// customer never looks at a screen that does not answer a tap.
@MainActor
final class StatusView: UIView {
    private let spinner = UIActivityIndicatorView(style: .large)
    private let icon = UIImageView()
    private let label = UILabel()
    private let retryButton = UIButton(configuration: .borderedProminent())
    private var onRetry: (() -> Void)?

    init() {
        super.init(frame: .zero)
        backgroundColor = .systemBackground

        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 52, weight: .regular)
        icon.isHidden = true
        retryButton.isHidden = true
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 0
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        // A stack view closes the gap of a hidden view, so each state shows only its own.
        let stack = UIStackView(arrangedSubviews: [icon, spinner, label, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// A spinner over one line saying what the customer is waiting for.
    func showLoading(_ message: String) {
        icon.isHidden = true
        retryButton.isHidden = true
        spinner.startAnimating()
        label.text = message
    }

    /// The settled outcome, the way a card terminal shows its result before printing.
    func showResult(succeeded: Bool, message: String) {
        spinner.stopAnimating()
        retryButton.isHidden = true
        icon.image = UIImage(systemName: succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
        icon.tintColor = succeeded ? .systemGreen : .systemOrange
        icon.isHidden = false
        label.text = message
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    /// What went wrong, with a button that runs `onRetry`.
    func showFailure(_ message: String, retryTitle: String, onRetry: @escaping () -> Void) {
        spinner.stopAnimating()
        icon.isHidden = true
        label.text = message
        retryButton.configuration?.title = retryTitle
        retryButton.isHidden = false
        self.onRetry = onRetry
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    @objc private func retryTapped() {
        onRetry?()
    }
}
#endif
