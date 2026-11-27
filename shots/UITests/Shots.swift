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
        demo.watchLoader()
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
        demo.watchLoader()
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
        demo.shot("filled")
        demo.dump("filled")
        let pay = web.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "pay")).firstMatch
        guard pay.waitForExistence(timeout: 10) else {
            XCTFail("no Pay button")
            demo.dump("no-pay-button")
            return
        }
        pay.tap()
        demo.pause(5)
        demo.shot("after-pay")
        demo.dump("after-pay")
        _ = demo.result("paid")
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
        guard demo.result("charged") else { return }
        demo.backHome()
        demo.removeSavedCard()
    }

    @MainActor
    func test6Indirect() {
        let demo = Demo("6-indirect")
        guard demo.tap("Indirect Method") else { return }
        demo.watchLoader()
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

    @MainActor
    func test8SaveWhilePaying() {
        let demo = Demo("8-save-while-paying")
        let offer = demo.app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Offer to save")).firstMatch
        guard offer.waitForExistence(timeout: 10) else {
            XCTFail("no \"Offer to save the card\" switch")
            demo.dump("no-offer-switch")
            return
        }
        // The row's label takes no taps: the switch itself is at its trailing edge.
        offer.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        demo.pause(1)
        if (offer.value as? String) != "1" { offer.tap() }
        demo.pause(1)
        demo.shot("offer-on")
        guard (offer.value as? String) == "1" else {
            XCTFail("the switch did not turn on")
            demo.dump("offer-not-on")
            return
        }

        guard let web = demo.openCardForm() else { return }
        demo.shot("form")
        demo.dump("form")
        demo.fillCard(in: web, expiry: "01/39")
        let consent = web.switches.firstMatch
        guard consent.exists else {
            XCTFail("the card form does not offer to save the card")
            demo.dump("no-consent")
            return
        }
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap()
        demo.pause(1)
        if (consent.value as? String) != "1" { consent.tap() }
        demo.pause(1)
        demo.shot("filled")
        demo.dump("filled")
        guard demo.tapPay(in: web), demo.result("paid") else { return }

        demo.backHome()
        let card = demo.app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "0008")).firstMatch
        for _ in 0..<5 where !(card.exists && card.isHittable) {
            demo.app.swipeUp()
            demo.pause(1)
        }
        demo.shot("home-with-card")
        guard card.exists else {
            XCTFail("the card paid with is not in the saved cards")
            demo.dump("card-not-saved")
            return
        }
        demo.removeSavedCard()
    }

    @MainActor
    func test9Declined() {
        let demo = Demo("9-declined")
        guard let web = demo.openCardForm() else { return }
        // On the MPGS test gateway expiry 05/39 is a declined card.
        demo.fillCard(in: web, expiry: "05/39")
        demo.shot("filled")
        guard demo.tapPay(in: web) else { return }
        demo.pause(8)
        demo.shot("after-pay")
        demo.dump("after-pay")
        _ = demo.result("declined")
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

    /// Times the loader over the first page: when the page's own content could first be
    /// found under it, and when it left. Takes a screenshot the moment it leaves.
    func watchLoader() {
        let loader = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Opening", "Connecting")).firstMatch
        let content = app.webViews.firstMatch.descendants(matching: .any).matching(
            NSPredicate(format: "elementType IN %@", [
                XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.button.rawValue,
                XCUIElement.ElementType.staticText.rawValue,
            ])).firstMatch
        func seconds(_ value: TimeInterval) -> String { String(format: "%.1f", value) }
        let start = Date()
        guard loader.waitForExistence(timeout: 20) else {
            print("SHOT timing \(name): no loader seen")
            return
        }
        let seen = Date().timeIntervalSince(start)
        shot("loader")
        var drawn: TimeInterval?
        while loader.exists, Date().timeIntervalSince(start) < 90 {
            if drawn == nil, content.exists { drawn = Date().timeIntervalSince(start) }
        }
        let left = Date().timeIntervalSince(start)
        shot("loader-left")
        print("SHOT timing \(name): loader seen at \(seconds(seen)) s, left at \(seconds(left)) s, "
            + "page content first found at \(drawn.map(seconds) ?? "no time before that")")
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

    /// Opens the card form from the "Card" button and waits for its fields.
    func openCardForm() -> XCUIElement? {
        guard tap("Card") else { return nil }
        let web = app.webViews.firstMatch
        guard web.textFields.firstMatch.waitForExistence(timeout: 90) else {
            XCTFail("the card form did not open")
            shot("no-form")
            dump("no-form")
            return nil
        }
        pause(2)
        return web
    }

    /// Types the sandbox test card into Hesabe's card form.
    func fillCard(in web: XCUIElement, expiry: String) {
        type("Demo Customer", into: field(in: web, "Cardholder name"), "name on card")
        type("5123450000000008", into: field(in: web, "Card number"), "card number")
        type(expiry, into: field(in: web, "Expiry"), "expiry")
        type("100", into: web.secureTextFields.firstMatch, "security code")
        dismissKeyboard()
    }

    /// Taps the card form's own pay button.
    func tapPay(in web: XCUIElement) -> Bool {
        let pay = web.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "pay")).firstMatch
        guard pay.waitForExistence(timeout: 10) else {
            XCTFail("no Pay button")
            dump("no-pay-button")
            return false
        }
        pay.tap()
        return true
    }

    /// Removes the saved card through Edit, Remove and the confirmation, and waits for
    /// its row to go.
    func removeSavedCard() {
        let edit = app.buttons["Edit"]
        for _ in 0..<5 where !(edit.exists && edit.isHittable) {
            app.swipeUp()
            pause(1)
        }
        guard edit.exists else {
            XCTFail("no Edit button over the saved cards")
            dump("no-edit")
            return
        }
        edit.tap()
        let remove = app.buttons["Remove"]
        guard remove.waitForExistence(timeout: 10) else {
            XCTFail("no Remove button on the card")
            dump("no-remove")
            return
        }
        pause(1)
        shot("editing-cards")
        remove.tap()
        let confirm = app.buttons["Remove card"]
        guard confirm.waitForExistence(timeout: 10) else {
            XCTFail("no confirmation before the removal")
            dump("no-removal-confirmation")
            return
        }
        pause(1)
        shot("confirm-removal")
        confirm.tap()
        let empty = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "No saved cards yet")).firstMatch
        if !empty.waitForExistence(timeout: 60) {
            XCTFail("the card is still listed")
            dump("card-not-removed")
        }
        pause(2)
        shot("card-removed")
    }
}
