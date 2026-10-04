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

        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(waitForStaticText(containing: "329.03", in: app))
        XCTAssertTrue(waitForStaticText(containing: "263", in: app))
        XCTAssertTrue(
            waitForStaticText(containing: "6.5", in: app) || waitForStaticText(containing: "6,5", in: app)
        )

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

    func testSnapshotOnlyShowsDashboardActivity() throws {
        let app = launchApp()

        createVehicle(in: app)
        saveSnapshotOnly(in: app)

        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(waitForStaticText(containing: "1", in: app))
        XCTAssertTrue(waitForStaticText(containing: "117", in: app))
        XCTAssertTrue(waitForStaticText(containing: "8", in: app))
    }

    func testMissingSnapshotOdometerReturnsToReviewForManualCorrection() throws {
        let app = launchApp()

        createVehicle(in: app)

        app.tabBars.buttons["Capturar"].tap()
        app.buttons["capture.snapshot"].tap()
        app.buttons["snapshot.next"].tap()
        type("3.4", into: app.textFields["snapshot.trip"])
        app.buttons["snapshot.next"].tap()
        app.buttons["snapshot.save"].tap()

        XCTAssertTrue(app.alerts["No se pudo guardar"].waitForExistence(timeout: 5))
        app.buttons["OK"].tap()
        XCTAssertTrue(app.textFields["snapshot.odometer"].waitForExistence(timeout: 5))

        type("123456", into: app.textFields["snapshot.odometer"])
        app.buttons["snapshot.next"].tap()
        app.buttons["snapshot.save"].tap()
        XCTAssertTrue(app.buttons["capture.snapshot"].waitForExistence(timeout: 5))
    }

	    func testEditFillUpThenResetSelectedVehicleData() throws {
	        let app = launchApp(extraArguments: ["--seed-multivehicle"])
	        let bmw = "Roadster BMW Z4 2003"
	        let toyota = "Commuter Toyota Yaris 2020"

	        app.tabBars.buttons["Historial"].tap()
	        selectVehicle(bmw, in: app, pickerIdentifier: "vehicle.filter.picker")
	        let fillRow = app.buttons.matching(identifier: "history.fillup.row").firstMatch
	        XCTAssertTrue(fillRow.waitForExistence(timeout: 5))
	        fillRow.tap()

	        clearAndType("450", into: app.textFields["fill.total"])
	        clearAndType("13", into: app.textFields["fill.gallons"])
	        app.buttons["fill.next"].tap()
	        app.buttons["fill.save"].tap()

	        let editedFillRow = app.buttons.matching(identifier: "history.fillup.row").firstMatch
	        XCTAssertTrue(editedFillRow.waitForExistence(timeout: 5))
	        XCTAssertTrue(editedFillRow.label.contains("450.00"))

	        app.tabBars.buttons["Ajustes"].tap()
	        let resetButton = app.buttons["settings.reset"]
	        scrollToElement(resetButton, in: app)
	        XCTAssertTrue(resetButton.waitForExistence(timeout: 2))
	        resetButton.tap()
	        app.buttons["settings.reset.confirm"].firstMatch.tap()

	        app.tabBars.buttons["Vehiculos"].tap()
	        XCTAssertTrue(app.staticTexts[bmw].waitForExistence(timeout: 5))
	        XCTAssertTrue(app.staticTexts[toyota].exists)

	        app.tabBars.buttons["Historial"].tap()
	        selectVehicle(bmw, in: app, pickerIdentifier: "vehicle.filter.picker")
	        XCTAssertFalse(app.buttons["history.fillup.row"].waitForExistence(timeout: 2))
	        XCTAssertFalse(app.buttons["history.snapshot.row"].waitForExistence(timeout: 2))
	    }

    func testCreateAndDeleteMonthlyAdjustment() throws {
        let app = launchApp()

        createVehicle(in: app)

        app.tabBars.buttons["Dashboard"].tap()
        app.buttons["dashboard.adjustment.open"].tap()

        type("25", into: app.textFields["adjustment.kilometers"])
        app.buttons["adjustment.save"].tap()

        let distanceTexts = app.staticTexts.matching(identifier: "dashboard.distance")
        XCTAssertTrue(
            distanceTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "15.5 mi"))
                .firstMatch
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            distanceTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "25 km"))
                .firstMatch
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            distanceTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Incluye ajustes manuales del mes"))
                .firstMatch
                .exists
        )

        app.buttons["dashboard.adjustment.open"].tap()
        app.buttons["adjustment.delete"].tap()
        app.buttons["adjustment.delete.confirm"].firstMatch.tap()

        XCTAssertTrue(
            distanceTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Pendiente"))
                .firstMatch
                .waitForExistence(timeout: 5)
        )
    }

    func testMultiVehicleFilteringAcrossDashboardCaptureAndHistory() throws {
        let app = launchApp(extraArguments: ["--seed-multivehicle"])
        let bmw = "Roadster BMW Z4 2003"
        let toyota = "Commuter Toyota Yaris 2020"

        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(waitForStaticText(containing: "720.00", in: app))

        selectVehicle(toyota, in: app, pickerIdentifier: "vehicle.filter.picker")
        XCTAssertTrue(waitForStaticText(containing: "1,240.00", in: app) || waitForStaticText(containing: "1240.00", in: app))

        app.tabBars.buttons["Capturar"].tap()
        app.buttons["capture.fillup"].tap()
        selectVehicle(toyota, in: app, pickerIdentifier: "fill.vehicle.picker")
        XCTAssertTrue(app.buttons["fill.vehicle.picker"].label.contains(toyota))

        app.tabBars.buttons["Historial"].tap()
        selectVehicle(toyota, in: app, pickerIdentifier: "vehicle.filter.picker")
        XCTAssertTrue(app.staticTexts[toyota].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[bmw].exists)
    }

    func testVehicleConfigurationUpdatesCaptureUnits() throws {
        let app = launchApp()

        app.tabBars.buttons["Vehiculos"].tap()
        app.buttons["vehicle.add"].tap()

        type("Roadster", into: app.textFields["vehicle.name"])
        type("BMW", into: app.textFields["vehicle.make"])
        type("Z4", into: app.textFields["vehicle.model"])
        type("2003", into: app.textFields["vehicle.year"])
        type("2.5i", into: app.textFields["vehicle.engine"])
        type("P123ABC", into: app.textFields["vehicle.plate"])
        selectOption("Kilometros", in: app, pickerIdentifier: "vehicle.odometerUnit")
        clearAndType("16", into: app.textFields["vehicle.tankCapacity"])
        clearAndType("30", into: app.textFields["vehicle.referenceKmPerGal"])
        app.buttons["vehicle.save"].tap()

        XCTAssertTrue(app.staticTexts["Roadster BMW Z4 2003"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForStaticText(containing: "Kilometros", in: app))
        XCTAssertTrue(waitForStaticText(containing: "16", in: app))
        XCTAssertTrue(waitForStaticText(containing: "30", in: app))

        tapVehicleRow(named: "Roadster BMW Z4 2003", in: app)
        XCTAssertEqual(stringValue(of: app.textFields["vehicle.engine"]), "2.5i")
        XCTAssertEqual(stringValue(of: app.textFields["vehicle.plate"]), "P123ABC")
        XCTAssertTrue(stringValue(of: app.textFields["vehicle.tankCapacity"]).contains("16"))
        app.swipeUp()
        XCTAssertTrue(stringValue(of: app.textFields["vehicle.referenceKmPerGal"]).contains("30"))
        app.buttons["Cancelar"].tap()

        app.tabBars.buttons["Capturar"].tap()
        app.buttons["capture.fillup"].tap()
        app.buttons["fill.next"].tap()
        XCTAssertTrue(app.textFields["fill.odometer"].waitForExistence(timeout: 5))
        XCTAssertTrue(stringValue(of: app.textFields["fill.odometer"]).localizedCaseInsensitiveContains("kilometros"))
        XCTAssertTrue(stringValue(of: app.textFields["fill.trip"]).localizedCaseInsensitiveContains("kilometros"))

        app.tabBars.buttons["Capturar"].tap()
        app.buttons["capture.snapshot"].tap()
        app.buttons["snapshot.next"].tap()
        XCTAssertTrue(app.textFields["snapshot.odometer"].waitForExistence(timeout: 5))
        XCTAssertTrue(stringValue(of: app.textFields["snapshot.odometer"]).localizedCaseInsensitiveContains("kilometros"))
        XCTAssertTrue(stringValue(of: app.textFields["snapshot.trip"]).localizedCaseInsensitiveContains("kilometros"))
    }

    func testReportsTabSwitchesGranularityAndExportsFiles() throws {
        let app = launchApp(extraArguments: ["--seed-multivehicle"])

        app.tabBars.buttons["Dashboard"].tap()
        app.buttons["dashboard.reports"].tap()
        XCTAssertTrue(app.buttons["reports.export.csv"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForStaticText(containing: "Detalle semanal", in: app))

        selectVehicle("Commuter Toyota Yaris 2020", in: app, pickerIdentifier: "vehicle.filter.picker")
        app.buttons["Mensual"].tap()
        app.buttons["reports.export.csv"].tap()

        let exportStatus = app.staticTexts["reports.export.status"]
        XCTAssertTrue(exportStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(exportStatus.label.contains("CSV listo"))

        app.buttons["reports.export.pdf"].tap()
        XCTAssertTrue(exportStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(exportStatus.label.contains("PDF listo"))
    }

    func testDashboardShowsWeeklyAndMonthlyFuelMetrics() throws {
        let app = launchApp(extraArguments: ["--seed-multivehicle"])

        app.tabBars.buttons["Dashboard"].tap()

        XCTAssertTrue(app.staticTexts["SEMANA COMBUSTIBLE"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["MES COMBUSTIBLE"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["RENDIMIENTO"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForStaticText(containing: "gal", in: app))
        XCTAssertTrue(waitForStaticText(containing: "km/gal", in: app))
    }

    func testBackupActionsAndRefuelMapAreVisible() throws {
        let app = launchApp(extraArguments: ["--seed-multivehicle"])

        app.tabBars.buttons["Ajustes"].tap()
        XCTAssertTrue(app.buttons["settings.backup.export"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.backup.import"].exists)

        app.tabBars.buttons["Historial"].tap()
        XCTAssertTrue(app.buttons["history.refuelMap"].waitForExistence(timeout: 5))
        app.buttons["history.refuelMap"].tap()

        XCTAssertTrue(app.staticTexts["Recargas registradas"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Demo Station West"].waitForExistence(timeout: 5))
    }

    func testReadmeScreensShowKeyFlows() throws {
        let app = launchApp(extraArguments: ["--seed-multivehicle"])

        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(app.staticTexts["SEMANA COMBUSTIBLE"].waitForExistence(timeout: 5))
        saveScreenshot(named: "dashboard-overview")

        app.tabBars.buttons["Capturar"].tap()
        XCTAssertTrue(app.buttons["capture.fillup"].waitForExistence(timeout: 5))
        saveScreenshot(named: "capture-home")

        app.tabBars.buttons["Historial"].tap()
        XCTAssertTrue(app.buttons["history.refuelMap"].waitForExistence(timeout: 5))
        saveScreenshot(named: "history-log")
        app.buttons["history.refuelMap"].tap()
        XCTAssertTrue(app.staticTexts["Recargas registradas"].waitForExistence(timeout: 5))
        saveScreenshot(named: "refuel-map")

        app.tabBars.buttons["Ajustes"].tap()
        XCTAssertTrue(app.buttons["settings.backup.export"].waitForExistence(timeout: 5))
        saveScreenshot(named: "settings-backup")
    }

    func testLatestZ4SnapshotDashboardOutput() throws {
        let app = launchApp(extraArguments: ["--seed-latest-z4-snapshot"])

        app.tabBars.buttons["Dashboard"].tap()

        XCTAssertTrue(waitForStaticText(containing: "Mes actual", in: app))
        saveScreenshot(named: "latest-z4-dashboard-top")

        XCTAssertTrue(waitForStaticText(containing: "150.00", in: app))
        XCTAssertTrue(waitForStaticText(containing: "3.791", in: app))
        XCTAssertTrue(waitForStaticText(containing: "251", in: app))
        XCTAssertTrue(waitForStaticText(containing: "403.9", in: app))
        XCTAssertTrue(waitForStaticText(containing: "1 espacio", in: app) || waitForStaticText(containing: "1 espacios", in: app))
        XCTAssertTrue(waitForStaticText(containing: "39.57", in: app))

        let insight = app.descendants(matching: .any)["dashboard.tankInsight"]
        XCTAssertTrue(scrollToExistingElement(insight, in: app, maxSwipes: 8))
        XCTAssertTrue(insight.waitForExistence(timeout: 5))

        let normalizedInsight = insight.label.replacingOccurrences(of: "\u{00A0}", with: "")
        print("LATEST_Z4_DASHBOARD_INSIGHT\n\(insight.label)")

        XCTAssertTrue(insight.label.contains("251.0"))
        XCTAssertTrue(insight.label.contains("403.9"))
        XCTAssertTrue(insight.label.contains("109,413"))
        XCTAssertTrue(insight.label.contains("232.9"))
        XCTAssertTrue(insight.label.contains("18.1"))
        XCTAssertTrue(insight.label.contains("29.1"))
        XCTAssertTrue(insight.label.contains("45-55 km"))
        XCTAssertTrue(normalizedInsight.contains("Q150.00 / 403.9 km = Q0.37/km"))
        saveScreenshot(named: "latest-z4-dashboard-insight")
    }


    func testPrivatePhotoSnapshotPrefillsAndSavesExpectedReading() throws {
        guard ProcessInfo.processInfo.environment["CARTRACK_RUN_PRIVATE_PHOTOS_UI"] == "1" else {
            throw XCTSkip("The private Photos simulator was not requested.")
        }

        let privateManifest = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("CartrackTests/Fixtures/private-image-scenarios.json")
        guard FileManager.default.fileExists(atPath: privateManifest.path) else {
            throw XCTSkip("Private Photos fixture pack is not enabled.")
        }

        let app = launchApp()
        createVehicle(in: app)
        saveSnapshot(in: app, odometer: "108728", trip: "566.6")
        saveSnapshot(in: app, odometer: "108749", trip: "587.3")

        app.tabBars.buttons["Capturar"].tap()
        app.buttons["capture.snapshot"].tap()

        let photosButton = app.buttons["snapshot.odometerImage.photos"]
        XCTAssertTrue(photosButton.waitForExistence(timeout: 5))
        photosButton.tap()

        let firstPhoto = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(
            firstPhoto.waitForExistence(timeout: 10),
            "The Photos picker must expose the imported odometer fixture."
        )
        let photoFrame = firstPhoto.frame
        XCTAssertFalse(photoFrame.isEmpty)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: photoFrame.midX, dy: photoFrame.midY))
            .tap()

        XCTAssertTrue(
            app.images["snapshot.odometerImage.preview"].waitForExistence(timeout: 10)
        )
        app.buttons["snapshot.next"].tap()

        let odometer = app.textFields["snapshot.odometer"]
        let trip = app.textFields["snapshot.trip"]
        XCTAssertTrue(odometer.waitForExistence(timeout: 90))
        XCTAssertTrue(trip.exists)
        XCTAssertEqual(stringValue(of: odometer), "108,768")
        XCTAssertEqual(stringValue(of: trip), "606.5")

        app.buttons["snapshot.next"].tap()
        app.buttons["snapshot.save"].tap()

        XCTAssertTrue(app.buttons["capture.snapshot"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Historial"].tap()
        XCTAssertTrue(app.staticTexts["Snapshot"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForStaticText(containing: "108,768", in: app, timeout: 10))
    }

    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"] + extraArguments
        app.launch()
        return app
    }

    private func saveScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let outputDirectory = ProcessInfo.processInfo.environment["CARTRACK_SCREENSHOT_DIR"] else {
            return
        }

        let url = URL(fileURLWithPath: outputDirectory, isDirectory: true)
            .appendingPathComponent("\(name).png")
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: outputDirectory, isDirectory: true),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? screenshot.pngRepresentation.write(to: url)
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

    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 4) {
        for _ in 0..<maxSwipes where !element.exists || !element.isHittable {
            app.swipeUp()
        }
    }

    private func scrollToExistingElement(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) -> Bool {
        for _ in 0...maxSwipes {
            if element.waitForExistence(timeout: 1) {
                return true
            }
            app.swipeUp()
        }
        return element.exists
    }

    private func scrollToText(containing text: String, in app: XCUIApplication, maxSwipes: Int = 6) {
        for _ in 0..<maxSwipes where !waitForStaticText(containing: text, in: app, timeout: 1) {
            app.swipeUp()
        }
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

    private func saveSnapshotOnly(in app: XCUIApplication) {
        saveSnapshot(in: app, odometer: "123456", trip: "73.0")
    }

    private func saveSnapshot(
        in app: XCUIApplication,
        odometer: String,
        trip: String
    ) {
        app.tabBars.buttons["Capturar"].tap()
        app.buttons["capture.snapshot"].tap()

        app.buttons["snapshot.next"].tap()
        type(odometer, into: app.textFields["snapshot.odometer"])
        type(trip, into: app.textFields["snapshot.trip"])
        app.buttons["snapshot.next"].tap()
        app.buttons["snapshot.save"].tap()

        XCTAssertTrue(app.buttons["capture.snapshot"].waitForExistence(timeout: 10))
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

    private func selectOption(_ optionName: String, in app: XCUIApplication, pickerIdentifier: String) {
        let picker = app.buttons[pickerIdentifier].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Missing picker: \(pickerIdentifier)")
        picker.tap()

        let buttonOption = app.buttons[optionName].firstMatch
        if buttonOption.waitForExistence(timeout: 2) {
            buttonOption.tap()
            return
        }

        let textOption = app.staticTexts[optionName].firstMatch
        XCTAssertTrue(textOption.waitForExistence(timeout: 5), "Missing option: \(optionName)")
        textOption.tap()
    }

    private func tapVehicleRow(named vehicleName: String, in app: XCUIApplication) {
        let button = app.buttons[vehicleName].firstMatch
        if button.waitForExistence(timeout: 2) {
            button.tap()
            return
        }

        let text = app.staticTexts[vehicleName].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5), "Missing vehicle row: \(vehicleName)")
        text.tap()
    }

    private func stringValue(of element: XCUIElement) -> String {
        (element.value as? String) ?? ""
    }

    private func waitForStaticText(containing text: String, in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return app.staticTexts.containing(predicate).firstMatch.waitForExistence(timeout: timeout)
    }
}
