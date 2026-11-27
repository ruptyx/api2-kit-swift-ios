import HesabeUI
import SwiftUI
import SwiftyJSON

/// An app that uses one pod and the Hesabe Swift package together, to prove that a
/// CocoaPods project builds with the package added to it.
@main
struct PodsCheckApp: App {
    @State private var session: HesabeSession?

    private let configuration = HesabeConfiguration(
        environment: .sandbox,
        returnURLs: ReturnURLs(URL(string: "https://example.com/hesabe/return")!),
        merchantDisplayName: "Example Store")

    var body: some Scene {
        WindowGroup {
            Text(JSON(["pod": "SwiftyJSON"])["pod"].stringValue)
                .hesabeCheckout(session: $session, configuration: configuration, methods: [.knet, .card]) { _ in }
        }
    }
}
