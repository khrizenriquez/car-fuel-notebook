import XCTest

@MainActor
final class CartrackSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCreateVehicleAndOpenCaptureFlow() throws {
        let app = launchApp()

        createVehicle(in: app)

        app.tabBars.buttons["Capturar"].tap()
        XCTAssertTrue(app.buttons["capture.fillup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["capture.snapshot"].exists)
    }

    func testSaveFillUpAndSnapshotThenShowInHistory() throws {
        let app = launchApp()

        createVehicle(in: app)
        saveFillUpAndSnapshot(in: app)

        app.tabBars.buttons["Historial"].tap()
        XCTAssertTrue(app.staticTexts["Llenado"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Snapshot"].waitForExistence(timeout: 5))

        app.buttons["history.snapshot.row"].tap()
        let fuelLevelValue = app.staticTexts["snapshot.fuelLevel.value"]
        XCTAssertTrue(fuelLevelValue.waitForExistence(timeout: 5))
        XCTAssertTrue(
            fuelLevelValue.label.contains("6.5") || fuelLevelValue.label.contains("6,5"),
            "Expected saved fuel level to include 6.5, got: \(fuelLevelValue.label)"
        )
    }

    func testEditFillUpThenResetAllData() throws {
        let app = launchApp()

        createVehicle(in: app)
        saveFillUpAndSnapshot(in: app)

        app.tabBars.buttons["Historial"].tap()
        app.buttons["history.fillup.row"].tap()

        clearAndType("420", into: app.textFields["fill.total"])
        clearAndType("12", into: app.textFields["fill.gallons"])
        app.buttons["fill.next"].tap()
        app.buttons["fill.save"].tap()

        let editedFillRow = app.buttons["history.fillup.row"]
        XCTAssertTrue(editedFillRow.waitForExistence(timeout: 5))
        XCTAssertTrue(editedFillRow.label.contains("420.00"))

        app.tabBars.buttons["Ajustes"].tap()
        app.buttons["settings.reset"].tap()
        app.buttons["settings.reset.confirm"].firstMatch.tap()

        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(app.staticTexts["Agrega tu primer vehiculo"].waitForExistence(timeout: 5))
    }

    func testCreateAndDeleteMonthlyAdjustment() throws {
        let app = launchApp()

        createVehicle(in: app)

        app.tabBars.buttons["Dashboard"].tap()
        app.buttons["dashboard.adjustment.open"].tap()

        type("25", into: app.textFields["adjustment.kilometers"])
        app.buttons["adjustment.save"].tap()

        XCTAssertTrue(app.staticTexts["25 km"].waitForExistence(timeout: 5))

        app.buttons["dashboard.adjustment.open"].tap()
        app.buttons["adjustment.delete"].tap()
        app.buttons["adjustment.delete.confirm"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["0 km"].waitForExistence(timeout: 5))
    }

    func testMultiVehicleFilteringAcrossDashboardCaptureAndHistory() throws {
        let app = launchApp(extraArguments: ["--seed-multivehicle"])
        let bmw = "Roadster BMW Z4 2003"
        let toyota = "Commuter Toyota Yaris 2020"

        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(waitForStaticText(containing: "420.00", in: app))

        selectVehicle(toyota, in: app, pickerIdentifier: "vehicle.filter.picker")
        XCTAssertTrue(waitForStaticText(containing: "700.00", in: app))

        app.tabBars.buttons["Capturar"].tap()
        app.buttons["capture.fillup"].tap()
        selectVehicle(toyota, in: app, pickerIdentifier: "fill.vehicle.picker")
        XCTAssertTrue(app.buttons["fill.vehicle.picker"].label.contains(toyota))

        app.tabBars.buttons["Historial"].tap()
        selectVehicle(toyota, in: app, pickerIdentifier: "vehicle.filter.picker")
        XCTAssertTrue(app.staticTexts[toyota].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[bmw].exists)
    }

    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"] + extraArguments
        app.launch()
        return app
    }

    private func createVehicle(in app: XCUIApplication) {
        app.tabBars.buttons["Vehiculos"].tap()
        app.buttons["vehicle.add"].tap()

        let name = app.textFields["vehicle.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        type("Roadster", into: name)

        let make = app.textFields["vehicle.make"]
        type("BMW", into: make)

        let model = app.textFields["vehicle.model"]
        type("Z4", into: model)

        let year = app.textFields["vehicle.year"]
        type("2003", into: year)

        app.buttons["vehicle.save"].tap()

        XCTAssertTrue(app.staticTexts["Roadster BMW Z4 2003"].waitForExistence(timeout: 5))
    }

    private func saveFillUpAndSnapshot(in app: XCUIApplication) {
        app.tabBars.buttons["Capturar"].tap()
        app.buttons["capture.fillup"].tap()

        app.buttons["fill.next"].tap()
        type("123456", into: app.textFields["fill.odometer"])
        type("0.0", into: app.textFields["fill.trip"])
        type("10.2500", into: app.textFields["fill.gallons"])
        type("32.10", into: app.textFields["fill.price"])
        type("329.03", into: app.textFields["fill.total"])
        app.buttons["fill.next"].tap()
        app.buttons["fill.save"].tap()

        XCTAssertTrue(app.buttons["capture.snapshot"].waitForExistence(timeout: 5))
        app.buttons["capture.snapshot"].tap()

        app.buttons["snapshot.next"].tap()
        type("123620", into: app.textFields["snapshot.odometer"])
        type("164.0", into: app.textFields["snapshot.trip"])
        let decrementFuelLevel = app.buttons["snapshot.fuelLevel.decrement"]
        XCTAssertTrue(decrementFuelLevel.waitForExistence(timeout: 5))
        for _ in 0..<6 {
            decrementFuelLevel.tap()
        }
        app.buttons["snapshot.next"].tap()
        app.buttons["snapshot.save"].tap()
    }

    private func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }

    private func clearAndType(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if let value = field.value as? String {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        field.typeText(text)
    }

    private func selectVehicle(_ vehicleName: String, in app: XCUIApplication, pickerIdentifier: String) {
        let picker = app.buttons[pickerIdentifier].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Missing picker: \(pickerIdentifier)")
        picker.tap()

        let buttonOption = app.buttons[vehicleName].firstMatch
        if buttonOption.waitForExistence(timeout: 2) {
            buttonOption.tap()
            return
        }

        let textOption = app.staticTexts[vehicleName].firstMatch
        XCTAssertTrue(textOption.waitForExistence(timeout: 5), "Missing vehicle option: \(vehicleName)")
        textOption.tap()
    }

    private func waitForStaticText(containing text: String, in app: XCUIApplication) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return app.staticTexts.containing(predicate).firstMatch.waitForExistence(timeout: 5)
    }
}
