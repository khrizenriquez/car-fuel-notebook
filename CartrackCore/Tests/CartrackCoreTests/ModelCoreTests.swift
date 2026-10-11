import XCTest
@testable import CartrackCore

final class ModelCoreTests: XCTestCase {
    func testVehicleDisplayNameOmitsBlankPieces() {
        let vehicle = Vehicle(name: "Roadster", make: "BMW", modelName: "Z4", year: 2003)
        XCTAssertEqual(vehicle.displayName, "Roadster BMW Z4 2003")

        let unnamed = Vehicle(name: "", make: "BMW", modelName: "", year: 0)
        XCTAssertEqual(unnamed.displayName, "BMW")
    }

    func testImageAssetKindAndOwnerRoundTripThroughRawValues() {
        let eventID = UUID()
        let asset = ImageAsset(eventID: eventID, ownerType: .snapshot, kind: .fuelLevel, localPath: "/tmp/fuel.jpg")

        XCTAssertEqual(asset.eventID, eventID)
        XCTAssertEqual(asset.ownerType, .snapshot)
        XCTAssertEqual(asset.kind, .fuelLevel)

        asset.ownerType = .fillUp
        asset.kind = .invoice

        XCTAssertEqual(asset.ownerTypeRawValue, ImageOwnerKind.fillUp.rawValue)
        XCTAssertEqual(asset.kindRawValue, CaptureImageKind.invoice.rawValue)
    }

    func testCaptureImageKindTitlesAreUserFacing() {
        XCTAssertEqual(CaptureImageKind.invoice.title, "Factura")
        XCTAssertEqual(CaptureImageKind.odometer.title, "Odometro")
        XCTAssertEqual(CaptureImageKind.fuelLevel.title, "Nivel de tanque")
    }

    func testMonthlyAllocationModeTitles() {
        XCTAssertEqual(MonthlyAllocationMode.finalFillMonth.title, "Mes cierre")
        XCTAssertEqual(MonthlyAllocationMode.prorated.title, "Prorrateado")
    }

    func testEventLocationPolicyPrefersCurrentCompleteCoordinate() {
        let coordinate = EventLocationPolicy.resolvedCoordinate(
            currentLatitude: 37.3349,
            currentLongitude: -122.0090,
            existingLatitude: 37.2800,
            existingLongitude: -122.1200
        )

        XCTAssertEqual(coordinate, EventCoordinate(latitude: 37.3349, longitude: -122.0090))
    }

    func testEventLocationPolicyPreservesExistingCoordinateWhenCurrentIsMissing() {
        let coordinate = EventLocationPolicy.resolvedCoordinate(
            currentLatitude: nil,
            currentLongitude: nil,
            existingLatitude: 37.2800,
            existingLongitude: -122.1200
        )

        XCTAssertEqual(coordinate, EventCoordinate(latitude: 37.2800, longitude: -122.1200))
    }

    func testEventLocationPolicyRejectsIncompleteCoordinatePairs() {
        let coordinate = EventLocationPolicy.resolvedCoordinate(
            currentLatitude: 37.3349,
            currentLongitude: nil,
            existingLatitude: nil,
            existingLongitude: -122.1200
        )

        XCTAssertNil(coordinate)
    }
}
