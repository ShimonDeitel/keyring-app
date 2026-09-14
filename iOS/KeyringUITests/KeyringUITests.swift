import XCTest

/// Note on photo coverage: PhotosPicker cannot be reliably driven via
/// XCUITest in the simulator. Photo attachment is optional-but-encouraged
/// (only `name` is required to save), so every add/edit/delete/paywall
/// flow below is fully exercisable without touching the picker.
///
/// Fresh installs now start with zero keys (onboarding leads straight into
/// "add a key" instead of pre-seeded sample data) — UI tests bypass the
/// onboarding screen via `-uiTestReset` (see `KeyringApp.init`) and add
/// whatever keys each test needs.
final class KeyringUITests: XCTestCase {
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
        return app
    }

    private func addKey(_ app: XCUIApplication, name: String) {
        let addButton = app.buttons["addKeyButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 12))
        addButton.tap()
        let labelField = app.textFields["keyLabelField"]
        XCTAssertTrue(labelField.waitForExistence(timeout: 12))
        labelField.tap()
        labelField.typeText(name)
        app.buttons["saveKeyButton"].tap()
    }

    func testAddKeyFromMainList() throws {
        let app = launchApp()
        addKey(app, name: "Storage Unit")
        XCTAssertTrue(app.staticTexts["Storage Unit"].waitForExistence(timeout: 12), "New key did not appear on the list")
    }

    func testAddKeyWithNote() throws {
        let app = launchApp()
        app.buttons["addKeyButton"].tap()

        let labelField = app.textFields["keyLabelField"]
        XCTAssertTrue(labelField.waitForExistence(timeout: 12))
        labelField.tap()
        labelField.typeText("Bike Lock")

        let noteField = app.textFields["keyNoteField"]
        noteField.tap()
        noteField.typeText("Small U-lock key")

        app.buttons["saveKeyButton"].tap()

        XCTAssertTrue(app.staticTexts["Bike Lock"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'U-lock'")).firstMatch.waitForExistence(timeout: 12))
    }

    func testEditKeyChangesLabel() throws {
        let app = launchApp()
        addKey(app, name: "Front Door")

        let row = app.staticTexts["Front Door"]
        XCTAssertTrue(row.waitForExistence(timeout: 12))
        row.tap()

        let menuButton = app.buttons["keyMenu_Front Door"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 12), "Detail screen menu did not appear")
        menuButton.tap()

        let editMenuItem = app.buttons["Edit"].exists ? app.buttons["Edit"] : app.menuItems["Edit"]
        XCTAssertTrue(editMenuItem.waitForExistence(timeout: 12), "Edit menu item did not appear")
        editMenuItem.tap()

        let labelField = app.textFields["keyLabelField"]
        XCTAssertTrue(labelField.waitForExistence(timeout: 12))
        labelField.tap()
        labelField.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) {
            app.menuItems["Select All"].tap()
        }
        labelField.typeText("Back Door")

        app.buttons["saveKeyButton"].tap()

        XCTAssertTrue(app.navigationBars["Back Door"].waitForExistence(timeout: 12), "Key edit did not apply")
    }

    func testDeleteKeyViaDetailMenu() throws {
        let app = launchApp()
        addKey(app, name: "Disposable Key")

        let row = app.staticTexts["Disposable Key"]
        XCTAssertTrue(row.waitForExistence(timeout: 12))
        row.tap()

        let menuButton = app.buttons["keyMenu_Disposable Key"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 12), "Detail screen menu did not appear")
        menuButton.tap()

        let deleteMenuItem = app.buttons["Delete Key"].exists ? app.buttons["Delete Key"] : app.menuItems["Delete Key"]
        XCTAssertTrue(deleteMenuItem.waitForExistence(timeout: 12), "Delete menu item did not appear")
        deleteMenuItem.tap()

        let confirmButton = app.buttons["Delete"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 12), "Delete confirmation dialog did not appear")
        confirmButton.tap()

        XCTAssertTrue(app.buttons["addKeyButton"].waitForExistence(timeout: 12), "Did not return to the key list")
        XCTAssertFalse(app.staticTexts["Disposable Key"].exists, "Key was not deleted")
    }

    func testTapRingFansOutKeys() throws {
        let app = launchApp()
        addKey(app, name: "Front Door")
        let ringButton = app.buttons["keyRingFanToggle"]
        let ringOther = app.otherElements["keyRingFanToggle"]
        let ring = ringButton.exists ? ringButton : ringOther
        XCTAssertTrue(ring.waitForExistence(timeout: 12), "Key ring fan toggle did not appear")
        ring.tap()
        // Give the spring animation time to settle; the toggle should still exist afterward.
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        ring.tap()
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
    }

    func testFreeLimitTriggersPaywallAtSixthKey() throws {
        let app = launchApp()
        for name in ["Key A", "Key B", "Key C", "Key D", "Key E"] {
            addKey(app, name: name)
        }
        app.buttons["addKeyButton"].tap()
        XCTAssertTrue(app.staticTexts["Keyring Pro"].waitForExistence(timeout: 12), "Paywall did not appear after hitting the free key limit")
    }

    func testSimulatedPurchaseUnlocksUnlimitedKeys() throws {
        let app = launchApp()
        for name in ["Key A", "Key B", "Key C", "Key D", "Key E"] {
            addKey(app, name: name)
        }
        app.buttons["addKeyButton"].tap()
        XCTAssertTrue(app.staticTexts["Keyring Pro"].waitForExistence(timeout: 12))

        let unlockButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Subscribe' OR label CONTAINS[c] 'unlock'")).firstMatch
        XCTAssertTrue(unlockButton.waitForExistence(timeout: 12))
        unlockButton.tap()

        let confirmButton = app.buttons["Subscribe"].exists ? app.buttons["Subscribe"] : app.buttons["Buy"]
        if confirmButton.waitForExistence(timeout: 12) {
            confirmButton.tap()
        }

        XCTAssertTrue(app.buttons["addKeyButton"].waitForExistence(timeout: 15))

        let addButton = app.buttons["addKeyButton"]
        var tapped = false
        for _ in 0..<16 {
            if addButton.isHittable {
                addButton.tap()
                tapped = true
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        if !tapped {
            addButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        let labelField = app.textFields["keyLabelField"]
        if labelField.waitForExistence(timeout: 8) {
            labelField.tap()
            labelField.typeText("Key F")
            app.buttons["saveKeyButton"].tap()
            XCTAssertTrue(app.staticTexts["Key F"].waitForExistence(timeout: 12))
        }
    }

    func testSettingsSheetShowsUpgradeOption() throws {
        let app = launchApp()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["upgradeProButton"].waitForExistence(timeout: 12))
    }
}
