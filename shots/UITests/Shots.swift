import XCTest

/// Drives the demo on a simulator and saves what each screen shows.
final class Shots: XCTestCase {
    /// Where the pictures go: a folder on the Mac, which a simulator can write to.
    static let folder: URL = {
        let environment = ProcessInfo.processInfo.environment
        let path = environment["SHOTS_DIR"]
            ?? (environment["SIMULATOR_HOST_HOME"] ?? NSTemporaryDirectory()) + "/hesabe-shots"
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        print("SHOT folder \(url.path)")
        return url
    }()

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func test1Home() {
        let demo = Demo("1-home")
        demo.shot("home")
        demo.dump("home")
        demo.app.swipeUp()
        demo.pause(1)
        demo.shot("home-lower")
        if demo.tap("Payment history") {
            demo.pause(2)
            demo.shot("history-empty")
        }
    }

    @MainActor
    func test2MethodList() {
        let demo = Demo("2-methods")
        guard demo.tap("Choose a method") else { return }
        demo.shot("opening")
        let knet = demo.app.staticTexts["KNET"]
        XCTAssertTrue(knet.waitForExistence(timeout: 60), "the method list")
        demo.pause(5)
        demo.shot("method-list")
        demo.dump("method-list")
    }

    @MainActor
    func test3KNET() {
        let demo = Demo("3-knet")
        guard demo.tap("KNET") else { return }
        demo.shot("opening")
        let web = demo.app.webViews.firstMatch
        let fields = web.textFields
        guard fields.firstMatch.waitForExistence(timeout: 90) else {
            XCTFail("the KNET page did not open")
            demo.shot("no-page")
            demo.dump("no-page")
            return
        }
        demo.pause(2)
        demo.shot("page")
        demo.dump("page")
        let ordered = fields.allElementsBoundByIndex.sorted { $0.frame.minY < $1.frame.minY }
        guard ordered.count == 3 else {
            XCTFail("the KNET page has \(ordered.count) fields")
            return
        }
        demo.type("8888880000000001", into: ordered[0], "card number")
        demo.type("0930", into: ordered[1], "expiry")
        demo.type("1234", into: ordered[2], "PIN")
        demo.dismissKeyboard()
        demo.shot("filled")
        demo.dump("filled")
        web.buttons["Submit"].tap()
        let confirm = web.buttons["Confirm"]
        if confirm.waitForExistence(timeout: 40) {
            demo.pause(1)
            demo.shot("confirm")
            confirm.tap()
        } else {
            demo.shot("after-submit")
            demo.dump("after-submit")
        }
        guard demo.result("paid") else { return }
        demo.backHome()
        if demo.tap("Payment history") {
            demo.pause(2)
            demo.shot("history")
        }
    }

    @MainActor
    func test4Card() {
        let demo = Demo("4-card")
        guard demo.tap("Card") else { return }
        demo.shot("opening")
        demo.waitForPage()
        demo.shot("page")
        demo.dump("page")
    }

    @MainActor
    func test5SavedCard() {
        let demo = Demo("5-saved-card")
        guard demo.tap("Add a card") else { return }
        let web = demo.app.webViews.firstMatch
        guard web.textFields.firstMatch.waitForExistence(timeout: 90) else {
            XCTFail("the card form did not open")
            demo.shot("no-form")
            demo.dump("no-form")
            return
        }
        demo.pause(2)
        demo.shot("form")
        demo.dump("form")
        demo.type("Demo Customer", into: demo.field(in: web, "Cardholder name"), "name on card")
        demo.type("5123450000000008", into: demo.field(in: web, "Card number"), "card number")
        demo.type("01/39", into: demo.field(in: web, "Expiry"), "expiry")
        demo.type("100", into: web.secureTextFields.firstMatch, "security code")
        demo.dismissKeyboard()
        let consent = web.switches.firstMatch
        if consent.exists {
            consent.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap()
            demo.pause(1)
            if (consent.value as? String) != "1" { consent.tap() }
            demo.pause(1)
        }
        demo.shot("filled")
        demo.dump("filled")
        let save = web.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Save")).firstMatch
        guard save.waitForExistence(timeout: 10) else {
            XCTFail("no Save Card button")
            demo.dump("no-save-button")
            return
        }
        save.tap()
        guard demo.result("saved") else { return }

        // The card is now in the list on the home screen. Paying with it asks first.
        demo.backHome()
        let card = demo.app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "0008")).firstMatch
        for _ in 0..<5 where !(card.exists && card.isHittable) {
            demo.app.swipeUp()
            demo.pause(1)
        }
        demo.shot("home-with-card")
        demo.dump("home-with-card")
        guard card.exists else {
            XCTFail("the saved card is not listed")
            return
        }
        card.tap()
        let pay = demo.app.buttons["Pay"]
        guard pay.waitForExistence(timeout: 10) else {
            XCTFail("no confirmation before the charge")
            demo.dump("no-confirmation")
            return
        }
        demo.shot("confirm-charge")
        pay.tap()
        _ = demo.result("charged")
    }

    @MainActor
    func test6Indirect() {
        let demo = Demo("6-indirect")
        guard demo.tap("Indirect Method") else { return }
        demo.shot("opening")
        demo.waitForPage()
        demo.shot("page")
        demo.dump("page")
    }

    @MainActor
    func test7Cancel() {
        let demo = Demo("7-cancel")
        guard demo.tap("KNET") else { return }
        guard demo.app.webViews.firstMatch.textFields.firstMatch.waitForExistence(timeout: 90) else {
            XCTFail("the KNET page did not open")
            return
        }
        demo.app.navigationBars.buttons["Cancel"].tap()
        demo.pause(2)
        demo.shot("after-cancel")
        demo.dump("after-cancel")
        _ = demo.result("canceled")
    }
}

/// The demo app, launched fresh, and the handful of things every flow does to it.
@MainActor
final class Demo {
    let app = XCUIApplication(bundleIdentifier: "com.example.HesabeDemo")
    private let name: String
    private var count = 0

    init(_ name: String) {
        self.name = name
        app.launch()
        XCTAssertTrue(app.navigationBars["Hesabe Demo"].waitForExistence(timeout: 120), "the home screen")
        // The logos are fetched after the screen appears.
        pause(6)
    }

    func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    func shot(_ label: String) {
        count += 1
        save(XCUIScreen.main.screenshot().pngRepresentation, "\(name)-\(count)-\(label).png")
    }

    /// The accessibility tree, to see what a screen is made of when a tap misses.
    func dump(_ label: String) {
        save(Data(app.debugDescription.utf8), "\(name)-\(label).txt")
    }

    private func save(_ data: Data, _ file: String) {
        do {
            try data.write(to: Shots.folder.appendingPathComponent(file))
            print("SHOT saved \(file)")
        } catch {
            print("SHOT failed \(file): \(error)")
        }
    }

    func button(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    /// Scrolls until the button can be tapped, then taps it.
    @discardableResult
    func tap(_ title: String) -> Bool {
        let target = button(title)
        for _ in 0..<5 where !(target.exists && target.isHittable) {
            app.swipeUp()
            pause(1)
        }
        guard target.waitForExistence(timeout: 10) else {
            XCTFail("no button: \(title)")
            dump("missing-button")
            return false
        }
        target.tap()
        return true
    }

    func type(_ text: String, into field: XCUIElement, _ what: String) {
        guard field.waitForExistence(timeout: 60) else {
            XCTFail("no field: \(what)")
            return
        }
        field.tap()
        pause(1)
        field.typeText(text)
    }

    func field(in web: XCUIElement, _ label: String) -> XCUIElement {
        web.textFields.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
    }

    /// Waits until a page on another host has drawn something to read or tap.
    func waitForPage() {
        let web = app.webViews.firstMatch
        let content = web.descendants(matching: .any).matching(
            NSPredicate(format: "elementType IN %@", [
                XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.button.rawValue,
                XCUIElement.ElementType.staticText.rawValue,
            ])).firstMatch
        if !content.waitForExistence(timeout: 120) { XCTFail("the page did not draw") }
        pause(4)
    }

    /// A web view's keyboard has a Done button above it, and the keyboard covers the
    /// page's own button until it is gone.
    func dismissKeyboard() {
        let done = app.toolbars.buttons["Done"]
        if done.exists {
            done.tap()
            pause(1)
        }
    }

    /// Waits for the result screen, then saves it from top to bottom.
    func result(_ label: String) -> Bool {
        guard app.navigationBars["Result"].waitForExistence(timeout: 150) else {
            XCTFail("no result screen: \(label)")
            shot("\(label)-no-result")
            dump("\(label)-no-result")
            return false
        }
        // The server's own lookup arrives a moment after the screen.
        pause(8)
        shot("\(label)-result")
        dump("\(label)-result")
        for _ in 0..<4 {
            app.swipeUp()
            pause(1)
            shot("\(label)-result-more")
        }
        return true
    }

    func backHome() {
        app.navigationBars["Result"].buttons.firstMatch.tap()
        _ = app.navigationBars["Hesabe Demo"].waitForExistence(timeout: 20)
        pause(3)
    }
}
