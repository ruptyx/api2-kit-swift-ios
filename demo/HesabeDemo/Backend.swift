import Foundation
import HesabeUI

/// What can go wrong talking to your own server.
enum BackendError: LocalizedError {
    case unreachable(String)
    case refused(String)

    var errorDescription: String? {
        switch self {
        case .unreachable(let message): "Could not reach the server: \(message)"
        case .refused(let message): "The server said: \(message)"
        }
    }
}

/// The calls the app makes to your server. Any server that answers them works:
/// `demo/server/server.mjs` is one in about two hundred lines.
struct Backend {
    /// A session your server created with Hesabe's Checkout API.
    struct Order: Decodable {
        /// `response.data` from the Checkout API, which is all the SDK takes.
        let session: HesabeSession
        /// Hesabe's token for the session. The outcome is looked up by it.
        let token: String
        let reference: String
        /// The amount your server asked Hesabe for, with three decimals.
        let amount: String

        private enum CodingKeys: String, CodingKey {
            case data, token, reference, amount
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            session = try HesabeSession(data: try container.decode(String.self, forKey: .data))
            token = try container.decode(String.self, forKey: .token)
            reference = try container.decode(String.self, forKey: .reference)
            amount = try container.decode(String.self, forKey: .amount)
        }
    }

    /// What your server found when it asked Hesabe about a payment itself.
    struct Confirmation: Codable, Hashable {
        /// The status your server reports when Hesabe has no transaction for the token.
        static let notFound = "NOT_FOUND"

        let paid: Bool
        /// Hesabe's status word, or `NOT_FOUND`.
        let status: String
        /// Hesabe's record as your server read it.
        let transaction: HesabeTransaction?
    }

    /// Hesabe's answer to your server charging a saved card.
    struct Charge: Codable, Hashable {
        let paid: Bool
        /// Hesabe's result code, `CAPTURED` when paid. `DECLINED` when the issuer said no.
        let status: String
        let amount: String?
        let reference: String?
        let token: String?
        let paymentId: String?
        let transactionId: String?
        let trackId: String?
        /// The issuer's authorisation code.
        let auth: String?
        /// Kuwait time (UTC+3) with no zone, as Hesabe writes it.
        let paidOn: String?
        /// Why the charge did not go through.
        let message: String?
        /// Hesabe's whole answer as indented JSON.
        let raw: String?
    }

    private struct CardList: Decodable {
        let cards: [HesabeSavedCard]
    }

    private struct Removal: Decodable {
        let removed: Bool
    }

    private struct Failure: Decodable {
        let error: String
    }

    let baseURL: URL

    // MARK: - Payments

    /// - Parameter saveCard: asks your server to put the customer on the session, so
    ///   Hesabe's card form offers to save the card.
    func createSession(quantity: Int, saveCard: Bool = false) async throws -> Order {
        try await send("POST", "session", ["quantity": quantity, "saveCard": saveCard])
    }

    func confirm(token: String) async throws -> Confirmation {
        try await send("POST", "confirm", ["token": token])
    }

    // MARK: - Saved cards

    /// A session that saves a card and charges nothing.
    func createCardSession() async throws -> Order {
        try await send("POST", "cards/session", [:])
    }

    func savedCards() async throws -> [HesabeSavedCard] {
        let list: CardList = try await send("GET", "cards", nil)
        return list.cards
    }

    /// Your server charges the card. There is no page and no 3-D Secure.
    func charge(_ card: HesabeSavedCard, quantity: Int) async throws -> Charge {
        try await send("POST", "cards/charge", ["cardId": card.id, "quantity": quantity])
    }

    func remove(_ card: HesabeSavedCard) async throws {
        let _: Removal = try await send("POST", "cards/remove", ["cardId": card.id])
    }

    // MARK: - Transport

    private func send<Answer: Decodable>(
        _ method: String, _ path: String, _ body: [String: Any]?
    ) async throws -> Answer {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 60
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw BackendError.unreachable(error.localizedDescription)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error
            throw BackendError.refused(message ?? "an unexpected answer")
        }
        do {
            return try JSONDecoder().decode(Answer.self, from: data)
        } catch let error as HesabeError {
            // The SDK refused the session's `data`, and says why.
            throw BackendError.refused(error.localizedDescription)
        } catch {
            throw BackendError.refused("an answer the app could not read")
        }
    }
}
