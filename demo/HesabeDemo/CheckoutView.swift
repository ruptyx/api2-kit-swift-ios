import HesabeUI
import SwiftUI

/// Where the navigation stack goes from the home screen.
enum Route: Hashable {
    case result(PaymentRecord.ID)
    case history
}

/// One product, a quantity, and every way of paying for it the SDK offers. Every
/// payment ends on `ResultView`, and every result stays in the payment history.
@MainActor
struct CheckoutView: View {
    /// What the home screen is waiting for. It puts the spinner on the control that was
    /// tapped and keeps every other control from starting a second payment.
    private enum Busy: Equatable {
        /// From the tap on a pay button until that payment has a result.
        case paying(PaymentRecord.Flow)
        case charging(HesabeSavedCard.ID)
        case removing(HesabeSavedCard.ID)
    }

    /// The payment in the checkout sheet: the order the server created, and how it was
    /// started.
    private struct Attempt {
        let order: SandboxMerchantServer.Order
        let flow: PaymentRecord.Flow
    }

    /// A step that failed before any payment existed, and how to run it again.
    private struct Failure {
        let title: String
        let message: String
        let retry: () -> Void
    }

    /// Stands in for your server. In your app each of these calls goes to your own
    /// server over HTTPS, and the keys stay there.
    private let server = SandboxMerchantServer()

    @State private var path: [Route] = []
    @State private var history = PaymentHistory.load()
    /// The payments Hesabe is being asked about right now.
    @State private var checking: Set<PaymentRecord.ID> = []

    @State private var quantity = 1
    /// Asks the server for a session whose card form offers to save the card.
    @State private var offersCardSaving = false
    @State private var busy: Busy?
    @State private var failure: Failure?

    @State private var attempt: Attempt?
    /// The session the checkout sheet is paying. Non-nil presents the sheet.
    @State private var sheetSession: HesabeSession?

    /// The order behind the Apple Pay button. A session is single use, so the button
    /// gets a new one whenever the quantity changes or a payment ends.
    @State private var applePayOrder: SandboxMerchantServer.Order?
    @State private var applePayRound = 0

    /// The customer's saved cards, as the server lists them. `nil` until it answers.
    @State private var cards: [HesabeSavedCard]?
    @State private var cardsError: String?
    /// The saved card the customer is being asked to confirm a charge on.
    @State private var cardToCharge: HesabeSavedCard?
    /// The saved card the customer is being asked to confirm the removal of.
    @State private var cardToRemove: HesabeSavedCard?

    private var total: Decimal { Config.unitPrice * Decimal(quantity) }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section("Your order") {
                    Stepper("Sticker pack × \(quantity)", value: $quantity, in: 1...20)
                    LabeledContent("Total", value: "KWD \(hesabeAmount(total))")
                }
                .disabled(busy != nil)

                Section {
                    if Config.applePayPage != nil {
                        applePayButton
                    }
                    payButton("Choose a method", methods: [.knet, .card, .amex])
                    payButton("KNET", methods: [.knet])
                    payButton("Card", methods: [.card])
                    payButton(
                        "Indirect Method", methods: [],
                        caption: "Opens Hesabe's hosted payment page, where the customer chooses the method.")
                    Toggle("Offer to save the card", isOn: $offersCardSaving)
                } header: {
                    Text("Pay")
                } footer: {
                    Text("A card is entered in Hesabe's card form, inside the app.")
                }
                .disabled(busy != nil)

                SavedCardsSection(
                    cards: cards, loadError: cardsError, busyCard: busyCard,
                    isAdding: busy == .paying(.addCard),
                    onPay: { cardToCharge = $0 },
                    onRemove: { cardToRemove = $0 },
                    onAdd: { start(.addCard) },
                    onReload: { Task { await loadCards() } }
                )
                .disabled(busy != nil)

                Section {
                    NavigationLink(value: Route.history) {
                        LabeledContent("Payment history", value: "\(history.records.count)")
                    }
                }
            }
            .navigationTitle("Hesabe Demo")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .history:
                    HistoryView(records: history.records) { history.clear() }
                case .result(let id):
                    if let record = history[id] {
                        ResultView(
                            record: record, isChecking: checking.contains(id),
                            onRetry: retry(record),
                            onCheckAgain: record.token == nil ? nil : { checkAgain(id) })
                    }
                }
            }
        }
        .hesabeCheckout(
            session: $sheetSession, configuration: Config.hesabe, methods: attempt?.flow.methods ?? []
        ) { result in
            finish(result)
        }
        .confirmationDialog(
            chargeQuestion, isPresented: isPresenting($cardToCharge), titleVisibility: .visible,
            presenting: cardToCharge
        ) { card in
            Button("Pay") { charge(card) }
        }
        .confirmationDialog(
            removalQuestion, isPresented: isPresenting($cardToRemove), titleVisibility: .visible,
            presenting: cardToRemove
        ) { card in
            Button("Remove card", role: .destructive) { remove(card) }
        }
        .alert(failure?.title ?? "", isPresented: isPresenting($failure), presenting: failure) { failure in
            Button("Try again") { failure.retry() }
            Button("Cancel", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
        .task { await recover() }
        .task { await loadCards() }
        .task(id: ApplePayKey(quantity: quantity, round: applePayRound)) {
            await prepareApplePay()
        }
    }

    /// True while `item` holds a value. Dismissing clears the value.
    private func isPresenting<Item>(_ item: Binding<Item?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }

    // MARK: - Checkout sheet

    private func payButton(_ title: String, methods: [PaymentMethod], caption: String? = nil) -> some View {
        let flow = PaymentRecord.Flow.checkout(methods: methods)
        return PayButton(title: title, caption: caption, logos: methods, isBusy: busy == .paying(flow)) {
            start(flow)
        }
    }

    /// Asks the server for a session and hands it to the checkout sheet. The spinner is
    /// on the button from the tap until the payment has a result, so no payment can be
    /// started twice.
    private func start(_ flow: PaymentRecord.Flow) {
        busy = .paying(flow)
        Task {
            do {
                // "Add a card" is a session with amount 0.000: the sheet shows the card
                // form and saves the card.
                let order = try await (flow == .addCard
                    ? server.createCardSession()
                    : server.createSession(quantity: quantity, saveCard: offersCardSaving))
                attempt = Attempt(order: order, flow: flow)
                sheetSession = order.session
            } catch {
                busy = nil
                failure = Failure(title: "Could not start the payment", message: error.localizedDescription) {
                    start(flow)
                }
            }
        }
    }

    private func finish(_ result: PaymentResult) {
        busy = nil
        guard let attempt else { return }
        self.attempt = nil
        show(PaymentRecord(result, flow: attempt.flow, order: attempt.order))
    }

    /// A payment that did not go through starts again with a new session: a session is
    /// single use. Apple Pay and a saved card start again from the home screen.
    private func retry(_ record: PaymentRecord) -> (() -> Void)? {
        switch record.flow {
        case .checkout, .addCard:
            return {
                path = []
                start(record.flow)
            }
        case .applePay, .savedCard, .recovered:
            return nil
        }
    }

    // MARK: - Apple Pay

    @ViewBuilder
    private var applePayButton: some View {
        if let applePayOrder {
            HesabeApplePayButton(
                session: applePayOrder.session, configuration: Config.hesabe, method: Config.applePayMethod
            ) { result in
                show(PaymentRecord(result, flow: .applePay, order: applePayOrder))
                applePayRound += 1
            }
            .id(applePayOrder.token)
            .listRowInsets(EdgeInsets())
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }

    private struct ApplePayKey: Equatable {
        let quantity: Int
        let round: Int
    }

    private func prepareApplePay() async {
        guard Config.applePayPage != nil else { return }
        applePayOrder = nil
        do {
            let order = try await server.createSession(quantity: quantity)
            if !Task.isCancelled { applePayOrder = order }
        } catch {
            guard !Task.isCancelled else { return }
            failure = Failure(title: "Could not prepare Apple Pay", message: error.localizedDescription) {
                applePayRound += 1
            }
        }
    }

    // MARK: - Saved cards

    /// "Pay KWD 0.250 with Mastercard •••• 0008?"
    private var chargeQuestion: String {
        guard let card = cardToCharge else { return "" }
        return "Pay KWD \(hesabeAmount(total)) with \(card.displayName)?"
    }

    private var removalQuestion: String {
        guard let card = cardToRemove else { return "" }
        return "Remove \(card.displayName)?"
    }

    private var busyCard: HesabeSavedCard.ID? {
        switch busy {
        case .charging(let id)?, .removing(let id)?: return id
        case .paying?, nil: return nil
        }
    }

    private func loadCards() async {
        do {
            cards = try await server.savedCards()
            cardsError = nil
        } catch {
            // A list that was read once stays on screen: paying with a card still works.
            cardsError = cards == nil ? error.localizedDescription : nil
        }
    }

    private func charge(_ card: HesabeSavedCard) {
        busy = .charging(card.id)
        Task {
            defer { busy = nil }
            do {
                show(PaymentRecord(try await server.charge(card, quantity: quantity), card: card))
            } catch {
                show(PaymentRecord(unansweredChargeOn: card, error: error))
            }
        }
    }

    private func remove(_ card: HesabeSavedCard) {
        busy = .removing(card.id)
        Task {
            defer { busy = nil }
            do {
                try await server.remove(card)
            } catch {
                failure = Failure(title: "Could not remove the card", message: error.localizedDescription) {
                    remove(card)
                }
            }
            await loadCards()
        }
    }

    // MARK: - Results

    /// Opens the result screen for a payment that has just ended, then has the server
    /// ask Hesabe about it.
    private func show(_ record: PaymentRecord) {
        history.add(record)
        path = [.result(record.id)]
        Task {
            await verify(record.id)
            // A payment can save a card, and a charge can be a card's last.
            await loadCards()
        }
    }

    /// Has the server ask Hesabe about a payment. What the SDK reported travelled
    /// through the customer's device, so only this answer may release an order.
    private func verify(_ id: PaymentRecord.ID) async {
        // A saved-card charge is already the server's own answer from Hesabe.
        guard let record = history[id], record.charge == nil, let token = record.token else { return }
        checking.insert(id)
        defer { checking.remove(id) }
        do {
            let confirmation = try await server.confirm(token: token)
            history.update(id) {
                $0.confirmation = confirmation
                $0.confirmationError = nil
            }
        } catch {
            history.update(id) {
                $0.confirmation = nil
                $0.confirmationError = error.localizedDescription
            }
        }
    }

    /// "Check status again": asks Hesabe from the device, then from the server.
    private func checkAgain(_ id: PaymentRecord.ID) {
        guard let token = history[id]?.token else { return }
        checking.insert(id)
        Task {
            defer { checking.remove(id) }
            let result = await HesabeClient(environment: Config.environment)
                .settle(token: token, afterReturn: false)
            switch result {
            case .pending, .unconfirmed:
                break // still open: `recoverPayments()` asks again at the next launch
            case .paid, .cardSaved, .failed, .canceled, .notStarted:
                HesabePendingPayments.resolve(token)
            }
            history.update(id) { $0.apply(result) }
            await verify(id)
            await loadCards()
        }
    }

    /// A customer can pay in a banking app and never come back, and iOS can close the
    /// app during 3-D Secure. Hesabe is asked at every launch, and a payment it has
    /// settled since opens as a result.
    private func recover() async {
        let settled = await HesabeClient(environment: Config.environment).recoverPayments()
        let records = settled.map { PaymentRecord($0, flow: .recovered) }
        guard let latest = records.last else { return }
        for record in records { history.add(record) }
        if path.isEmpty, busy == nil { path = [.result(latest.id)] }
        for record in records { await verify(record.id) }
        await loadCards()
    }
}
