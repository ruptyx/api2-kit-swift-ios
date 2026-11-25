#if canImport(UIKit)
import Hesabe
import UIKit

/// The native list of payment methods, shown when the app offers more than one. Each
/// row is the method's name beside Hesabe's logo for it.
@MainActor
final class MethodPickerViewController: UITableViewController {
    private let methods: [PaymentMethod]
    private let amount: String
    private let cancelTitle: String
    private var hasChosen = false

    /// Called once, with the method tapped, or `nil` when the customer cancels.
    var onChoice: ((PaymentMethod?) -> Void)?

    init(methods: [PaymentMethod], amount: String, title: String, cancelTitle: String) {
        self.methods = methods
        self.amount = amount
        self.cancelTitle = cancelTitle
        super.init(style: .insetGrouped)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "method")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: cancelTitle, style: .plain, target: self, action: #selector(cancelTapped))
        loadLogos()
    }

    /// Each logo joins its row when it arrives. A method Hesabe has no logo for keeps
    /// its name alone.
    private func loadLogos() {
        for (row, method) in methods.enumerated() {
            Task {
                guard await HesabeLogos.badge(for: method) != nil else { return }
                let indexPath = IndexPath(row: row, section: 0)
                if let cell = tableView.cellForRow(at: indexPath) { configure(cell, at: indexPath) }
            }
        }
    }

    @objc private func cancelTapped() {
        choose(nil)
    }

    private func choose(_ method: PaymentMethod?) {
        guard !hasChosen else { return }
        hasChosen = true
        let report = onChoice
        onChoice = nil
        report?(method)
    }

    // MARK: - Table

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        methods.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        amount
    }

    override func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "method", for: indexPath)
        configure(cell, at: indexPath)
        return cell
    }

    private func configure(_ cell: UITableViewCell, at indexPath: IndexPath) {
        let method = methods[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = method.displayName
        content.image = HesabeLogos.fetched(method) ?? HesabeLogos.placeholder
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !hasChosen else { return }
        // The row answers the tap at once, and no second row can be tapped while the
        // payment page slides in.
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        tableView.cellForRow(at: indexPath)?.accessoryView = spinner
        tableView.allowsSelection = false
        choose(methods[indexPath.row])
    }
}
#endif
