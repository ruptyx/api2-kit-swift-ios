import XCTest
@testable import Hesabe

/// Answers Hesabe gave on the sandbox in November 2026, replayed without a network.
final class HesabeTests: XCTestCase {
    private let hex = "9e5a960de9a5c9abb43fad522fab51d1567a51fae68b520666a373cf417c7591"

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// A client whose every request is answered from `answers`, in order. The last
    /// answer repeats. Requests are recorded in `log`.
    private func client(_ answers: [(Int, Data)], log: RequestLog = RequestLog()) -> HesabeClient {
        HesabeClient(
            environment: .sandbox,
            transport: { request in
                let index = await log.record(request)
                let (status, body) = answers[min(index, answers.count - 1)]
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                return (body, response)
            },
            pause: { _ in })
    }

    // MARK: - Session

    func testSessionTakesTheHexData() throws {
        XCTAssertEqual(try HesabeSession(data: " \(hex)\n").data, hex)
    }

    func testSessionUnwrapsAnEmbeddedSession() throws {
        let wrapper = try JSONSerialization.data(withJSONObject: [
            "data": hex, "token": "84221700000000000000000000004", "payment_types": ["1", "2"],
        ])
        XCTAssertEqual(try HesabeSession(data: wrapper.base64EncodedString()).data, hex)
    }

    func testSessionRefusesAnythingElse() {
        XCTAssertThrowsError(try HesabeSession(data: ""))
        XCTAssertThrowsError(try HesabeSession(data: "https://sandbox.hesabe.com/payment?data=\(hex)"))
    }

    // MARK: - Details

    func testDetailsReadTheSandboxAnswer() async throws {
        let log = RequestLog()
        let answer = try fixture("checkout-details")
        let session = try HesabeSession(data: hex)
        let details = try await client([(200, answer)], log: log).details(for: session)

        XCTAssertEqual(details.token, "84221700000000000000000000002")
        XCTAssertEqual(details.formattedAmount, "KWD 1.000")
        XCTAssertEqual(details.requestedMethod, 0)
        XCTAssertTrue(details.paymentMethods.contains(.knet))
        XCTAssertTrue(details.paymentMethods.contains(.amex))
        XCTAssertTrue(details.paymentMethods.contains { $0.isGooglePay })
        XCTAssertEqual(details.applePayMethods, [9, 10, 11, 13])
        XCTAssertEqual(details.embeddedCardMethods, [.card])
        XCTAssertFalse(details.hasCustomer)
        XCTAssertFalse(details.offersCardSaving)
        XCTAssertFalse(details.isCardVerification)

        let url = await log.urls.first
        XCTAssertEqual(url?.absoluteString, "https://sandbox.hesabe.com/api/checkout-details?data=\(hex)")
    }

    func testDetailsRejectASessionHesabeRefuses() async throws {
        let answer = try fixture("checkout-details-rejected")
        let session = try HesabeSession(data: hex)
        do {
            _ = try await client([(400, answer)]).details(for: session)
            XCTFail("expected a rejection")
        } catch {
            XCTAssertEqual(error as? HesabeError, .rejected("Failed to decrypt data parameter"))
        }
    }

    func testDetailsRecogniseASessionThatOnlySavesACard() async throws {
        let answer = try fixture("checkout-details-verify")
        let session = try HesabeSession(data: hex)
        let details = try await client([(200, answer)]).details(for: session)

        XCTAssertEqual(details.formattedAmount, "KWD 0.000")
        XCTAssertTrue(details.hasCustomer)
        XCTAssertTrue(details.offersCardSaving)
        XCTAssertTrue(details.isCardVerification)
        XCTAssertEqual(details.embeddedCardMethods, [.card])
    }

    // MARK: - Payment page

    func testPaymentURLOpensHesabesPageOrOneMethod() throws {
        let client = HesabeClient(environment: .production)
        let session = try HesabeSession(data: hex)
        XCTAssertEqual(
            client.paymentURL(for: session).absoluteString,
            "https://api.hesabe.com/payment?data=\(hex)")
        XCTAssertEqual(
            client.paymentURL(for: session, method: .knet).absoluteString,
            "https://api.hesabe.com/payment?data=\(hex)&paymentType=1")
    }

    func testCardFormURLCarriesTheSessionAndTheLanguage() throws {
        let client = HesabeClient(environment: .sandbox)
        let session = try HesabeSession(data: hex)
        XCTAssertEqual(
            client.cardFormURL(for: session).absoluteString,
            "https://sandbox.hesabe.com/pay/webview?data=\(hex)")
        XCTAssertEqual(
            client.cardFormURL(for: session, language: "ar-KW").absoluteString,
            "https://sandbox.hesabe.com/pay/webview?data=\(hex)&locale=ar")
        XCTAssertEqual(
            client.cardFormURL(for: session, language: "fr").absoluteString,
            "https://sandbox.hesabe.com/pay/webview?data=\(hex)&locale=en")
    }

    // MARK: - Outcome

    func testSettleReportsAPaidPayment() async throws {
        let log = RequestLog()
        let paid = try fixture("enquiry-paid")
        let result = await client([(200, paid)], log: log)
            .settle(token: "84221700000000000000000000001", afterReturn: true)

        guard case .paid(let transaction) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(transaction.amount, "25.000")
        XCTAssertEqual(transaction.orderReference, "ORDER-1001")
        XCTAssertEqual(transaction.paymentType, "KNET")
        let urls = await log.urls
        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://sandbox.hesabe.com/api/transaction/enquire/84221700000000000000000000001",
        ])
    }

    func testATransactionKeepsHesabesWholeRecord() async throws {
        let attempts = try await client([(200, try fixture("enquiry-paid"))])
            .transactions(token: "84221700000000000000000000001")
        let transaction = try XCTUnwrap(attempts.first)

        XCTAssertEqual(transaction.trackID, "300001")
        XCTAssertEqual(transaction.terminal, "000001")
        // The sandbox fills the card fields of a KNET payment with "-NA-".
        XCTAssertNil(transaction.cardType)
        XCTAssertNil(transaction.maskedCard)
        // Fields the SDK has no name for are still in the record.
        XCTAssertTrue(transaction.rawJSON.contains("service_type"))
        XCTAssertTrue(transaction.rawJSON.contains("Payment Gateway"))

        // Stored and read again, it is the same transaction.
        let stored = try JSONEncoder().encode(transaction)
        XCTAssertEqual(try JSONDecoder().decode(HesabeTransaction.self, from: stored), transaction)
    }

    func testSettleWaitsForHesabeToRecordThePayment() async throws {
        let log = RequestLog()
        let notFound = (404, try fixture("enquiry-not-found"))
        let paid = (200, try fixture("enquiry-paid"))
        let result = await client([notFound, notFound, paid], log: log)
            .settle(token: "84221700000000000000000000001", afterReturn: true)

        guard case .paid = result else { return XCTFail("\(result)") }
        let count = await log.urls.count
        XCTAssertEqual(count, 3)
    }

    func testClosingAnUnpaidSessionIsACancellation() async throws {
        let log = RequestLog()
        let notFound = try fixture("enquiry-not-found")
        let result = await client([(404, notFound)], log: log)
            .settle(token: "84221700000000000000000000003", afterReturn: false)

        XCTAssertEqual(result, .canceled)
        let count = await log.urls.count
        XCTAssertEqual(count, 1)
    }

    func testAReturnWithNoTransactionIsUnconfirmedNotFailed() async throws {
        let log = RequestLog()
        let notFound = try fixture("enquiry-not-found")
        let result = await client([(404, notFound)], log: log)
            .settle(token: "84221700000000000000000000003", afterReturn: true)

        XCTAssertEqual(result, .unconfirmed(.noTransaction))
        let count = await log.urls.count
        XCTAssertEqual(count, 5)
    }

    func testAnUnreachableHesabeIsUnconfirmedEvenAfterCancel() async {
        let result = await client([(503, Data("<html>".utf8))])
            .settle(token: "84221700000000000000000000003", afterReturn: false)
        XCTAssertEqual(result, .unconfirmed(.connection("Hesabe answered HTTP 503")))
    }

    func testAFailedAttemptIsReportedAsFailed() async throws {
        let failed = Data(#"{"status":true,"data":{"data":[{"status":"FAILED","amount":"1.000","Id":7}]}}"#.utf8)
        let result = await client([(200, failed)]).settle(token: "8422171", afterReturn: true)
        guard case .failed(let transaction) = result else { return XCTFail("\(result)") }
        XCTAssertFalse(transaction.isPaid)
    }

    func testASavedCardIsNotReportedAsAPayment() async throws {
        let saved = try fixture("enquiry-card-saved")
        let result = await client([(200, saved)])
            .settle(token: "84221700000000000000000000005", afterReturn: true)

        guard case .cardSaved(let transaction) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(transaction.amount, "0.000")
        XCTAssertEqual(transaction.status, "AUTHORIZED")
        XCTAssertFalse(transaction.isPaid)
    }

    func testAnAuthorisationWithAnAmountIsNotASavedCard() async throws {
        let held = Data(#"{"status":true,"data":{"data":[{"status":"AUTHORIZED","amount":"1.000","Id":8}]}}"#.utf8)
        let result = await client([(200, held)]).settle(token: "8422172", afterReturn: true)
        guard case .pending = result else { return XCTFail("\(result)") }
    }

    // MARK: - Saved cards

    func testSavedCardsDecodeHesabesList() throws {
        let list = try JSONDecoder().decode([String: [HesabeSavedCard]].self, from: try fixture("saved-cards"))
        let cards = try XCTUnwrap(list["cards"])

        XCTAssertEqual(cards.map(\.id), [2001, 2002])
        XCTAssertEqual(cards[0].displayName, "Mastercard •••• 0008")
        XCTAssertEqual(cards[0].expiry, "01/39")
        XCTAssertEqual(cards[1].displayName, "Visa •••• 1019")
        XCTAssertEqual(cards[1].nameOnCard, "Test Customer")
    }

    func testTheTokenCannotChangeThePath() async {
        do {
            _ = try await client([(200, Data())]).transactions(token: "../checkout")
            XCTFail("expected a configuration error")
        } catch {
            guard case .configuration? = error as? HesabeError else { return XCTFail("\(error)") }
        }
    }

    // MARK: - Return URLs

    func testReturnURLsMatchWhateverQueryHesabeAdds() throws {
        let urls = ReturnURLs(
            success: try XCTUnwrap(URL(string: "https://example.com/hesabe/return")),
            failure: try XCTUnwrap(URL(string: "https://example.com/hesabe/failed/")))
        XCTAssertTrue(urls.matches(try XCTUnwrap(URL(string: "https://example.com/hesabe/return?data=9e5a"))))
        XCTAssertTrue(urls.matches(try XCTUnwrap(URL(string: "https://EXAMPLE.com/hesabe/failed?data=9e5a"))))
        XCTAssertFalse(urls.matches(try XCTUnwrap(URL(string: "https://example.com/hesabe/returning"))))
        XCTAssertFalse(urls.matches(try XCTUnwrap(URL(string: "https://sandbox.hesabe.com/payment?data=9e5a"))))
    }

    // MARK: - Pending payments

    func testPendingPaymentsSurviveUntilResolved() throws {
        let suite = "HesabeTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }

        HesabePendingPayments.track(PendingPayment(token: "a1", environment: .sandbox), in: store)
        HesabePendingPayments.track(PendingPayment(token: "a1", environment: .sandbox), in: store)
        HesabePendingPayments.track(
            PendingPayment(token: "old", environment: .sandbox, startedAt: Date(timeIntervalSinceNow: -30 * 86_400)),
            in: store)
        XCTAssertEqual(HesabePendingPayments.all(in: store).map(\.token), ["old", "a1"])

        HesabePendingPayments.prune(in: store)
        XCTAssertEqual(HesabePendingPayments.all(in: store).map(\.token), ["a1"])

        HesabePendingPayments.resolve("a1", in: store)
        XCTAssertTrue(HesabePendingPayments.all(in: store).isEmpty)
    }
}

/// The requests a test client was asked to send.
actor RequestLog {
    private(set) var urls: [URL] = []

    /// Records the request and returns its position, starting at zero.
    func record(_ request: URLRequest) -> Int {
        urls.append(request.url!)
        return urls.count - 1
    }
}
