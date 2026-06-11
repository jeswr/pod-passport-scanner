import XCTest

/// Drives the entire flow in the Simulator with the mock chip reader and
/// mock uploader (`--uitest` enables both and forces the manual-entry paths,
/// so no camera/NFC hardware or permission prompts are needed).
final class FlowUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testFullIssuanceFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()

        // Home
        let start = app.buttons["home.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        // Step 1: issuer session (manual entry path)
        let endpointField = app.textFields["qr.endpointField"]
        XCTAssertTrue(endpointField.waitForExistence(timeout: 5))
        type("https://issuer.example/api/emrtd/sessions/uitest-1", into: endpointField, in: app)
        type("uitest-1", into: app.textFields["qr.sessionIdField"], in: app)
        type("uitest-secret", into: app.textFields["qr.secretField"], in: app)
        app.buttons["qr.continueButton"].tap()

        // Step 2: MRZ key (manual entry path; ICAO specimen values)
        let docField = app.textFields["mrz.docNumberField"]
        XCTAssertTrue(docField.waitForExistence(timeout: 5))
        type("L898902C3", into: docField, in: app)
        type("740812", into: app.textFields["mrz.dobField"], in: app)
        type("120415", into: app.textFields["mrz.expiryField"], in: app)
        app.buttons["mrz.continueButton"].tap()

        // Step 3: chip read (mock reads the bundled sample passport)
        let readButton = app.buttons["nfc.startButton"]
        XCTAssertTrue(readButton.waitForExistence(timeout: 5))
        readButton.tap()

        // Step 4: review shows the sample passport's parsed MRZ
        let sendButton = app.buttons["review.sendButton"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["review.fullName"].label.contains("DOE"))
        XCTAssertTrue(app.staticTexts["review.documentNumber"].label.contains("L898902C3"))
        sendButton.tap()

        // Step 5/6: upload (mock succeeds) then done
        let doneTitle = app.staticTexts["done.title"]
        XCTAssertTrue(doneTitle.waitForExistence(timeout: 10))

        // Reset returns to Home
        app.buttons["done.resetButton"].tap()
        XCTAssertTrue(app.buttons["home.start"].waitForExistence(timeout: 5))
    }

    /// Taps a text field, waits for keyboard focus, then types — robust against
    /// the simulator's well-known first-field focus race where `typeText`
    /// arrives before the keyboard is up and the characters are dropped.
    private func type(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), "missing field for \(text)")
        // Retry tap-until-focused: hasKeyboardFocus flips true once the field
        // is the first responder and ready to receive synthesized key events.
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        for _ in 0..<3 {
            field.tap()
            let exp = XCTNSPredicateExpectation(predicate: focused, object: field)
            if XCTWaiter().wait(for: [exp], timeout: 2) == .completed { break }
        }
        field.typeText(text)
    }
}
