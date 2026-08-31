import XCTest

/// Run on demand (xcodebuild test -only-testing:KeyringUITests/KeyringScreenshotTests)
/// to produce App Store screenshot material -- not part of the app's regular
/// full-suite CI run. Each method drives the real UI (same accessibility
/// identifiers as KeyringUITests) and attaches a full-screen capture so it
/// can be pulled out of the .xcresult bundle afterward.
final class KeyringScreenshotTests: XCTestCase {
    private var interruptionMonitorToken: NSObjectProtocol?

    override func setUpWithError() throws {
        continueAfterFailure = false
        interruptionMonitorToken = addUIInterruptionMonitor(withDescription: "System alert dismissal") { alert in
            for label in ["Allow", "OK", "Don't Allow", "Cancel"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
    }

    override func tearDownWithError() throws {
        if let token = interruptionMonitorToken {
            removeUIInterruptionMonitor(token)
        }
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()
        app.tap() // wake the interruption monitor
        return app
    }

    private func addKey(_ app: XCUIApplication, name: String, note: String? = nil) {
        let addButton = app.buttons["addKeyButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 12))
        addButton.tap()
        let labelField = app.textFields["keyLabelField"]
        XCTAssertTrue(labelField.waitForExistence(timeout: 12))
        labelField.tap()
        labelField.typeText(name)
        if let note {
            let noteField = app.textFields["keyNoteField"]
            noteField.tap()
            noteField.typeText(note)
        }
        app.buttons["saveKeyButton"].tap()
        _ = app.staticTexts[name].waitForExistence(timeout: 12)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func purchasePro(_ app: XCUIApplication) {
        let unlockButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Unlock'")).firstMatch
        guard unlockButton.waitForExistence(timeout: 12) else { return }
        unlockButton.tap()
        let confirmButton = app.buttons["Subscribe"].exists ? app.buttons["Subscribe"] : app.buttons["Buy"]
        if confirmButton.waitForExistence(timeout: 12) {
            confirmButton.tap()
        }
        _ = app.buttons["addKeyButton"].waitForExistence(timeout: 15)
    }

    func testCaptureMainList() {
        let app = launchApp()
        addKey(app, name: "Front Door", note: "Deadbolt, brass key")
        addKey(app, name: "Garage", note: "Side entrance")
        addKey(app, name: "Storage Unit 12", note: "Rented locker, unit B")
        addKey(app, name: "Mom's House", note: "Spare, top of ring")
        attach(app, name: "01-main-list")

        let ring = app.buttons["keyRingFanToggle"].exists ? app.buttons["keyRingFanToggle"] : app.otherElements["keyRingFanToggle"]
        if ring.waitForExistence(timeout: 5) {
            ring.tap()
            Thread.sleep(forTimeInterval: 0.6)
            attach(app, name: "02-main-list-fanned")
        }
    }

    func testCaptureAddKeyForm() {
        let app = launchApp()
        let addButton = app.buttons["addKeyButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 12))
        addButton.tap()
        _ = app.textFields["keyLabelField"].waitForExistence(timeout: 12)
        Thread.sleep(forTimeInterval: 0.5)
        attach(app, name: "00-add-key-form")
    }

    func testCaptureKeyDetail() {
        let app = launchApp()
        addKey(app, name: "Garage", note: "Side entrance, silver key")
        app.staticTexts["Garage"].tap()
        _ = app.buttons["keyMenu_Garage"].waitForExistence(timeout: 12)
        attach(app, name: "03-key-detail")
    }

    func testCapturePaywall() {
        let app = launchApp()
        for name in ["Key A", "Key B", "Key C", "Key D", "Key E"] {
            addKey(app, name: name)
        }
        app.buttons["addKeyButton"].tap()
        _ = app.staticTexts["Keyring Pro"].waitForExistence(timeout: 12)
        Thread.sleep(forTimeInterval: 1.0)
        attach(app, name: "04-paywall")
    }

    func testCaptureLoanedKey() {
        let app = launchApp()
        for name in ["Key A", "Key B", "Key C", "Key D", "Key E"] {
            addKey(app, name: name)
        }
        app.buttons["addKeyButton"].tap()
        _ = app.staticTexts["Keyring Pro"].waitForExistence(timeout: 12)
        purchasePro(app)

        app.staticTexts["Key A"].tap()
        _ = app.buttons["keyMenu_Key A"].waitForExistence(timeout: 12)
        app.buttons["keyMenu_Key A"].tap()
        let loanItem = app.buttons["Loan Key"].exists ? app.buttons["Loan Key"] : app.menuItems["Loan Key"]
        guard loanItem.waitForExistence(timeout: 8) else { return }
        loanItem.tap()

        let personField = app.textFields["loanPersonField"]
        guard personField.waitForExistence(timeout: 8) else { return }
        personField.tap()
        personField.typeText("Dad")
        app.buttons["saveLoanButton"].tap()
        _ = app.staticTexts["Dad"].waitForExistence(timeout: 8)
        attach(app, name: "05-loaned-key-detail")
    }
}
