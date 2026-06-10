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
        endpointField.tap()
        endpointField.typeText("https://issuer.example/api/emrtd/sessions/uitest-1")
        let sessionField = app.textFields["qr.sessionIdField"]
        sessionField.tap()
        sessionField.typeText("uitest-1")
        let secretField = app.textFields["qr.secretField"]
        secretField.tap()
        secretField.typeText("uitest-secret")
        app.buttons["qr.continueButton"].tap()

        // Step 2: MRZ key (manual entry path; ICAO specimen values)
        let docField = app.textFields["mrz.docNumberField"]
        XCTAssertTrue(docField.waitForExistence(timeout: 5))
        docField.tap()
        docField.typeText("L898902C3")
        let dobField = app.textFields["mrz.dobField"]
        dobField.tap()
        dobField.typeText("740812")
        let expiryField = app.textFields["mrz.expiryField"]
        expiryField.tap()
        expiryField.typeText("120415")
        app.buttons["mrz.continueButton"].tap()

        // Step 3: chip read (mock reads the bundled sample passport)
        let readButton = app.buttons["nfc.startButton"]
        XCTAssertTrue(readButton.waitForExistence(timeout: 5))
        readButton.tap()

        // Step 4: review shows the sample passport's parsed MRZ
        let sendButton = app.buttons["review.sendButton"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["review.fullName"].label.contains("ERIKSSON"))
        XCTAssertTrue(app.staticTexts["review.documentNumber"].label.contains("L898902C3"))
        sendButton.tap()

        // Step 5/6: upload (mock succeeds) then done
        let doneTitle = app.staticTexts["done.title"]
        XCTAssertTrue(doneTitle.waitForExistence(timeout: 10))

        // Reset returns to Home
        app.buttons["done.resetButton"].tap()
        XCTAssertTrue(app.buttons["home.start"].waitForExistence(timeout: 5))
    }
}
