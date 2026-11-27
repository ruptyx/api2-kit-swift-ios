//  SANDBOX DEMO ONLY. Do not ship this file, and do not copy it into an app.
//
//  It does a merchant server's work inside the app, so the demo runs from Xcode with
//  nothing else to start. To do that it holds Hesabe's published sandbox keys and
//  encrypts with them.
//
//  In a live app the merchant keys and this code are on your server, never in the app.
//  Anything compiled into an app can be read out of it, so keys in an app are keys
//  anyone can use: to create sessions for any amount, to read your transactions and to
//  charge your customers' saved cards.
//
//  What to build instead: each method of `SandboxMerchantServer` is one endpoint of
//  your server, which the app calls over HTTPS. The paths are yours to name.
//
//      POST /payments/session   {"quantity": 2, "saveCard": false}
//        answers  {"data": "9e5a960d...", "token": "842217...",
//                  "reference": "DEMO-1795564800000", "amount": "0.500"}
//      POST /payments/confirm   {"token": "842217..."}
//        answers  {"paid": true, "status": "SUCCESSFUL", "transaction": {...}}
//      POST /cards/session      {}
//        answers  as /payments/session, with "amount": "0.000"
//      GET  /cards
//        answers  {"cards": [...]}, Hesabe's list unchanged
//      POST /cards/charge       {"cardId": 2001, "quantity": 2}
//        answers  {"paid": true, "status": "CAPTURED", "amount": "0.500", ...}
//      POST /cards/remove       {"cardId": 2001}
//        answers  {"removed": true}
//
//  Your server takes the customer from its own login, never from a value the app
//  sends, and it owns the price: the app says what was ordered, never what it costs.

import CommonCrypto
import Foundation
import HesabeUI

/// What can go wrong between the demo's server and Hesabe.
enum MerchantServerError: LocalizedError {
    /// No answer arrived. Hesabe may still have acted on the request.
    case unreachable(String)
    /// Hesabe answered, and not with what was asked for.
    case refused(String)

    var errorDescription: String? {
        switch self {
        case .unreachable(let message): "Could not reach Hesabe: \(message)"
        case .refused(let message): "The request was refused: \(message)"
        }
    }
}

/// The demo's stand-in for your server: every Hesabe call that needs the merchant keys.
/// Each method is one endpoint of the server you build, named in its comment.
struct SandboxMerchantServer {
    /// Hesabe's published sandbox account. Yours come from Merchant Panel, Profile,
    /// Merchant Keys, and exist on your server only.
    private enum Keys {
        static let merchantCode = "842217"
        static let accessCode = "c333729b-d060-4b74-a49d-7686a8353481"
        /// The AES-256 key, 32 characters.
        static let secretKey = "PkW64zMe5NVdrlPVNnjo2Jy9nOb7v1Xg"
        /// The AES initialisation vector, 16 characters.
        static let ivKey = "5NVdrlPVNnjo2Jy9"
    }

    /// Fixed to the sandbox. Nothing in this file can reach the live gateway.
    private static let gateway = URL(string: "https://sandbox.hesabe.com")!

    /// The server owns the price. The app sends what was ordered, never what it costs.
    private static let unitPrice = Decimal(string: "0.250")!

    /// A session created with Hesabe's Checkout API.
    struct Order {
        /// `response.data` from the Checkout API, which is all the SDK takes.
        let session: HesabeSession
        /// Hesabe's token for the session. The outcome is looked up by it.
        let token: String
        let reference: String
        /// The amount Hesabe was asked for, with three decimals.
        let amount: String
    }

    /// What the server found when it asked Hesabe about a payment itself.
    struct Confirmation: Codable, Hashable {
        /// The status the server reports when Hesabe has no transaction for the token.
        static let notFound = "NOT_FOUND"

        let paid: Bool
        /// Hesabe's status word, or `NOT_FOUND`.
        let status: String
        /// Hesabe's record as the server read it.
        let transaction: HesabeTransaction?
    }

    /// Hesabe's answer to the server charging a saved card.
    struct Charge: Codable, Hashable {
        let paid: Bool
        /// Hesabe's result code, `CAPTURED` when paid. `DECLINED` when the card was
        /// refused.
        let status: String
        var amount: String?
        var reference: String?
        var token: String?
        var paymentId: String?
        var transactionId: String?
        var trackId: String?
        /// The issuer's authorisation code.
        var auth: String?
        /// Kuwait time (UTC+3) with no zone, as Hesabe writes it.
        var paidOn: String?
        /// Why the charge did not go through.
        var message: String?
        /// Hesabe's whole answer as indented JSON.
        var raw: String?
    }

    // MARK: - Payments

    /// `POST /payments/session`. Creates the session the SDK pays.
    ///
    /// - Parameter saveCard: puts the customer on the session, so Hesabe's card form
    ///   offers to save the card.
    func createSession(quantity: Int, saveCard: Bool = false) async throws -> Order {
        let amount = try price(of: quantity)
        var customer: Int?
        if saveCard { customer = try await customerID() }
        return try await checkout(amount: amount, reference: "DEMO-\(Self.stamp())", customer: customer)
    }

    /// `POST /payments/confirm`. Asks Hesabe about a payment with the merchant keys.
    /// What the app reports travelled through the customer's device, so this answer,
    /// not the SDK's, is the one that releases an order.
    func confirm(token: String) async throws -> Confirmation {
        // The token goes into the path, so it must not be able to change the path.
        guard !token.isEmpty, token.utf8.allSatisfy({ byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
        }) else {
            throw MerchantServerError.refused("the token is not alphanumeric")
        }

        let answer = try await send("GET", "api/transaction/\(token)")
        // A session nobody has paid has no transaction, and Hesabe says "not found".
        if answer.isNotFound {
            return Confirmation(paid: false, status: Confirmation.notFound, transaction: nil)
        }
        let record = try answer.record()
        return Confirmation(
            paid: Self.isPaid(record),
            status: Self.text(record["status"]) ?? "UNKNOWN",
            transaction: Self.decode(HesabeTransaction.self, from: record))
    }

    // MARK: - Saved cards

    /// `POST /cards/session`. A session that saves a card and charges nothing: amount
    /// `0.000` with the customer. The SDK shows Hesabe's card form for it and reports
    /// `.cardSaved`.
    func createCardSession() async throws -> Order {
        let customer = try await customerID()
        return try await checkout(amount: 0, reference: "DEMO-CARD-\(Self.stamp())", customer: customer)
    }

    /// `GET /cards`. The customer's saved cards, as Hesabe lists them. The SDK's
    /// `HesabeSavedCard` decodes each entry unchanged.
    func savedCards() async throws -> [HesabeSavedCard] {
        guard let customer = Self.storedCustomerID else { return [] }
        let answer = try await send("GET", "api/direct-payment/cards", ["customer_id": customer])
        guard let list = try answer.payload()["cards"] as? [Any] else { return [] }
        guard let cards = Self.decode([HesabeSavedCard].self, from: list) else {
            throw MerchantServerError.refused("Hesabe's list of cards could not be read")
        }
        return cards
    }

    /// `POST /cards/charge`. Charges a saved card. There is no page and no 3-D Secure:
    /// Hesabe authenticated the card when it was saved. The answer is Hesabe's own, so
    /// the payment is already confirmed.
    func charge(_ card: HesabeSavedCard, quantity: Int) async throws -> Charge {
        let amount = try hesabeAmount(price(of: quantity))
        guard let customer = Self.storedCustomerID else {
            throw MerchantServerError.refused("this card is not saved")
        }
        let reference = "DEMO-\(Self.stamp())"
        // With the customer on the charge, Hesabe refuses a card saved by anyone else.
        // Sent once and never again: Hesabe has no idempotency keys, so a retry is a
        // second charge.
        let answer = try await send("POST", "api/direct-payment/charge-card", [
            "card_id": card.id,
            "amount": amount,
            "customer_id": customer,
            "order_reference": reference,
        ])
        // The card was refused. That is an answer, not a request that went wrong.
        if answer.isDecline {
            return Charge(
                paid: false, status: "DECLINED", amount: amount, reference: reference,
                message: answer.message)
        }
        let payment = try answer.payload()
        return Charge(
            paid: Self.isPaid(payment),
            status: Self.text(payment["resultCode"]) ?? "UNKNOWN",
            amount: Self.text(payment["amount"]) ?? amount,
            reference: reference,
            token: Self.text(payment["paymentToken"]),
            paymentId: Self.text(payment["paymentId"]),
            transactionId: Self.text(payment["transactionId"]),
            trackId: Self.text(payment["trackID"]),
            auth: Self.text(payment["auth"]),
            paidOn: Self.text(payment["paidOn"]),
            raw: Self.prettyJSON(payment))
    }

    /// `POST /cards/remove`. Hesabe's call takes any card id of the merchant, so the
    /// server checks that the card belongs to this customer first.
    func remove(_ card: HesabeSavedCard) async throws {
        guard try await savedCards().contains(where: { $0.id == card.id }) else {
            throw MerchantServerError.refused("this card is not saved")
        }
        _ = try await send("DELETE", "api/direct-payment/cards/\(card.id)", [:]).payload()
    }

    // MARK: - The customer

    private static let customerKey = "com.hesabe.demo.customer.\(Keys.merchantCode)"

    private static var storedCustomerID: Int? {
        UserDefaults.standard.object(forKey: customerKey) as? Int
    }

    /// The Hesabe customer the saved cards belong to. The demo has one, created on
    /// first use and remembered on the device. Your server keeps one per user account,
    /// in the user's row.
    private func customerID() async throws -> Int {
        if let existing = Self.storedCustomerID { return existing }
        // Hesabe refuses a second customer with the same email or mobile number.
        let stamp = String(Self.stamp().suffix(8))
        let customer = try await send("POST", "api/direct-payment/customer", [
            "name": "Demo Customer",
            "email": "demo-\(stamp)@example.com",
            "mobile_number": stamp,
        ]).payload()
        guard let id = Self.text(customer["customer_id"]).flatMap({ Int($0) }) else {
            throw MerchantServerError.refused("Hesabe did not return a customer")
        }
        UserDefaults.standard.set(id, forKey: Self.customerKey)
        return id
    }

    // MARK: - Hesabe's Checkout API

    /// `POST https://sandbox.hesabe.com/checkout`, the call that creates a session.
    ///
    /// - Parameter customer: the Hesabe customer a card may be saved for.
    private func checkout(amount: Decimal, reference: String, customer: Int?) async throws -> Order {
        let total = hesabeAmount(amount)
        var payload: [String: Any] = [
            "amount": total,
            "currency": "KWD",
            // 0 leaves the method to the app and the card gateway to Hesabe, so one
            // session serves KNET, cards and Apple Pay on any account.
            "paymentType": 0,
            "orderReferenceNumber": reference,
            // The address the SDK watches for. Nothing is ever fetched from it.
            "responseUrl": Config.returnURL.absoluteString,
            "failureUrl": Config.returnURL.absoluteString,
            "version": "2.0",
        ]
        if let customer {
            // With these, Hesabe's card form offers to save the card. A session with a
            // customer is a version 3.0 request.
            payload["saveCard"] = true
            payload["customer_id"] = customer
            payload["version"] = "3.0"
        }

        let answer = try await send("POST", "checkout", payload)
        // `data` is what the SDK takes. It opens this one payment and nothing else.
        guard let data = try answer.payload()["data"] as? String,
              let token = Self.text(answer.envelope["token"])
        else { throw MerchantServerError.refused("Hesabe returned no session") }
        do {
            return Order(
                session: try HesabeSession(data: data), token: token, reference: reference, amount: total)
        } catch {
            throw MerchantServerError.refused(error.localizedDescription)
        }
    }

    private func price(of quantity: Int) throws -> Decimal {
        guard (1...20).contains(quantity) else {
            throw MerchantServerError.refused("the quantity must be from 1 to 20")
        }
        return Self.unitPrice * Decimal(quantity)
    }

    // MARK: - Hesabe's wire format

    private static let cipher = HesabeCipher(secretKey: Keys.secretKey, ivKey: Keys.ivKey)

    /// Hesabe never redirects an API call, and following one would send the access code
    /// to wherever it points.
    private static let session = URLSession(
        configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    /// Sends one request to Hesabe. The access code is a header. A payload gains the
    /// merchant code and goes out encrypted as `data`: in the query of a GET, in the
    /// body of anything else.
    private func send(
        _ method: String, _ path: String, _ payload: [String: Any]? = nil
    ) async throws -> Answer {
        var components = URLComponents(
            url: Self.gateway.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var body: Data?
        if var payload {
            payload["merchantCode"] = Keys.merchantCode
            let data = try Self.cipher.encrypt(Self.json(payload))
            if method == "GET" {
                components.queryItems = [URLQueryItem(name: "data", value: data)]
            } else {
                body = try Self.json(["data": data])
            }
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.httpBody = body
        request.setValue(Keys.accessCode, forHTTPHeaderField: "accessCode")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let answer: Data
        let response: URLResponse
        do {
            (answer, response) = try await Self.session.data(for: request)
        } catch {
            throw MerchantServerError.unreachable(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return Answer(status: status, envelope: try Self.envelope(from: answer, status: status))
    }

    /// One answer from Hesabe: the HTTP status and the envelope, decrypted.
    private struct Answer {
        /// What Hesabe's message says when a card is refused.
        private static let declineWords = [
            "insufficient funds", "do not honour", "do not honor", "declined",
            "not eligible for merchant-initiated charge", "expired card", "stolen", "lost card",
            "invalid card",
        ]

        let status: Int
        let envelope: [String: Any]

        /// Hesabe sets `status` to false when it refuses, and does not always change
        /// the HTTP status to match.
        var isRefusal: Bool { envelope["status"] as? Bool == false || status >= 300 }

        /// Hesabe's words for a refusal, or the field errors when it lists those.
        var message: String {
            if let message = envelope["message"] as? String, !message.isEmpty { return message }
            if let fields = envelope["data"] as? [String: Any] {
                let lines = fields.compactMap { key, value -> String? in
                    guard let messages = value as? [String] else { return nil }
                    return "\(key): \(messages.joined(separator: " "))"
                }
                if !lines.isEmpty { return lines.sorted().joined(separator: "\n") }
            }
            return "Hesabe answered HTTP \(status)"
        }

        /// True when Hesabe has nothing under the key that was looked up. It says so
        /// with HTTP 404 or in the message, and not always with both.
        var isNotFound: Bool {
            status == 404 || (isRefusal && message.range(of: "not found", options: .caseInsensitive) != nil)
        }

        /// True when the card was refused, by its issuer or by Hesabe: "Invalid card or
        /// customer" for a card the customer never saved (sandbox, November 2026).
        /// Hesabe reports both as a refused request whose message says why.
        var isDecline: Bool {
            guard isRefusal, ![401, 403, 429].contains(status) else { return false }
            let words = message.lowercased()
            return Self.declineWords.contains { words.contains($0) }
        }

        /// What was asked for: `response`, or `data` in the answers that name it so.
        func payload() throws -> [String: Any] {
            guard !isRefusal else { throw MerchantServerError.refused(message) }
            return envelope["response"] as? [String: Any] ?? envelope["data"] as? [String: Any] ?? [:]
        }

        /// A transaction's fields. Hesabe's lookups do not agree on where the record
        /// sits: it is the answer itself, or one level down in `data`.
        func record() throws -> [String: Any] {
            let payload = try payload()
            if let inner = payload["data"] as? [String: Any], inner["status"] != nil { return inner }
            return payload
        }
    }

    /// Hesabe answers in hex ciphertext when it accepts a request and in plain JSON
    /// for most refusals, so the body is read for what it is, not for what the status
    /// code suggests.
    private static func envelope(from body: Data, status: Int) throws -> [String: Any] {
        let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if isHex(text) { return try decrypted(text) }

        let json = try? JSONSerialization.jsonObject(with: body, options: .fragmentsAllowed)
        if let hex = json as? String, isHex(hex) { return try decrypted(hex) }
        if let object = json as? [String: Any] {
            if let hex = object["response"] as? String, isHex(hex) { return try decrypted(hex) }
            return object
        }
        throw MerchantServerError.refused("Hesabe answered HTTP \(status) with nothing readable")
    }

    private static func decrypted(_ hex: String) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: cipher.decrypt(hex)) as? [String: Any]
        else { throw MerchantServerError.refused("Hesabe's answer could not be decrypted") }
        return object
    }

    private static func json(_ object: [String: Any]) throws -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: .withoutEscapingSlashes)
        else { throw MerchantServerError.refused("the request could not be written as JSON") }
        return data
    }

    // MARK: - Reading Hesabe's answers

    /// True only when Hesabe says the money moved. The numeric status decides when
    /// there is one: it does not change with casing or wording.
    private static func isPaid(_ record: [String: Any]) -> Bool {
        if let code = text(record["payment_status"]).flatMap({ Int($0) }) {
            // 1 is paid. 6 is paid through a multivendor split.
            return code == 1 || code == 6
        }
        return ["status", "result_code", "resultCode"].contains { key in
            guard let word = record[key] as? String else { return false }
            return ["SUCCESSFUL", "SUCCESS", "CAPTURED", "PAID"]
                .contains(word.trimmingCharacters(in: .whitespaces).uppercased())
        }
    }

    /// Hesabe sends ids as strings in some answers and as numbers in others.
    private static func text(_ value: Any?) -> String? {
        switch value {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    /// Reads a part of Hesabe's answer as one of the SDK's types.
    private static func decode<Value: Decodable>(_ type: Value.Type, from json: Any) -> Value? {
        guard JSONSerialization.isValidJSONObject(json),
              let data = try? JSONSerialization.data(withJSONObject: json)
        else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func prettyJSON(_ object: [String: Any]) -> String? {
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: options) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Milliseconds since 1970, for a reference no other order of the demo has.
    private static func stamp() -> String {
        String(Int(Date().timeIntervalSince1970 * 1000))
    }
}

/// AES-256-CBC as Hesabe uses it: the payload is padded to a 32-byte block, not AES's
/// 16, every pad byte holds the pad length, and the result is written as lowercase hex.
private struct HesabeCipher {
    let secretKey: String
    let ivKey: String

    func encrypt(_ plaintext: Data) throws -> String {
        let padLength = 32 - plaintext.count % 32
        let padded = plaintext + Data(repeating: UInt8(padLength), count: padLength)
        return try crypt(padded, CCOperation(kCCEncrypt)).map { String(format: "%02x", $0) }.joined()
    }

    func decrypt(_ hex: String) throws -> Data {
        var ciphertext = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            guard let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex),
                  let byte = UInt8(hex[index..<next], radix: 16)
            else { throw Self.unreadable }
            ciphertext.append(byte)
            index = next
        }
        let padded = try crypt(ciphertext, CCOperation(kCCDecrypt))

        // Every pad byte holds the pad length. Some of Hesabe's answers are padded
        // with zeros instead.
        if let last = padded.last, (1...32).contains(last), Int(last) <= padded.count,
           padded.suffix(Int(last)).allSatisfy({ $0 == last }) {
            return padded.dropLast(Int(last))
        }
        var end = padded.endIndex
        while end > padded.startIndex, padded[end - 1] == 0 { end -= 1 }
        return padded[padded.startIndex..<end]
    }

    private static let unreadable = MerchantServerError.refused("Hesabe's answer could not be decrypted")

    private func crypt(_ input: Data, _ operation: CCOperation) throws -> Data {
        let key = Data(secretKey.utf8)
        let iv = Data(ivKey.utf8)
        guard key.count == kCCKeySizeAES256, iv.count == kCCBlockSizeAES128 else {
            throw MerchantServerError.refused("the secret key must be 32 bytes and the IV key 16 bytes")
        }
        guard input.count.isMultiple(of: kCCBlockSizeAES128) else { throw Self.unreadable }

        let capacity = input.count + kCCBlockSizeAES128
        var output = Data(count: capacity)
        var written = 0
        let status = output.withUnsafeMutableBytes { out in
            input.withUnsafeBytes { inBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        // No padding option: Hesabe's padding is added and removed
                        // above, not by CommonCrypto.
                        CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), 0,
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                inBytes.baseAddress, input.count,
                                out.baseAddress, capacity, &written)
                    }
                }
            }
        }
        guard status == CCCryptorStatus(kCCSuccess) else { throw Self.unreadable }
        return output.prefix(written)
    }
}

private func isHex(_ text: String) -> Bool {
    !text.isEmpty && text.count.isMultiple(of: 2) && text.allSatisfy(\.isHexDigit)
}
