import Foundation

struct PrivateImageScenarioManifest: Decodable, Equatable {
    let version: Int
    let scenarios: [PrivateImageScenario]

    static func decode(data: Data) throws -> Self {
        let manifest = try JSONDecoder().decode(Self.self, from: data)
        try manifest.validate()
        return manifest
    }

    static func load(from url: URL) throws -> Self {
        try decode(data: Data(contentsOf: url))
    }

    private func validate() throws {
        guard version == 1 else {
            throw PrivateImageScenarioManifestError.unsupportedVersion(version)
        }

        var ids = Set<String>()

        for scenario in scenarios {
            let id = scenario.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                throw PrivateImageScenarioManifestError.emptyID
            }
            guard ids.insert(id).inserted else {
                throw PrivateImageScenarioManifestError.duplicateID(id)
            }

            if scenario.excluded {
                let reason = scenario.exclusionReason?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !reason.isEmpty else {
                    throw PrivateImageScenarioManifestError.missingExclusionReason(id)
                }
            } else if scenario.imagePaths.isEmpty {
                throw PrivateImageScenarioManifestError.missingImages(id)
            }

            if scenario.tolerance.hasNegativeValue {
                throw PrivateImageScenarioManifestError.negativeTolerance(id)
            }

            if let manualFuelSpaces = scenario.ui?.manualFuelSpaces,
               !(0...8).contains(manualFuelSpaces) {
                throw PrivateImageScenarioManifestError.invalidManualFuelSpaces(id)
            }
        }
    }
}

enum PrivateImageScenarioKind: String, Decodable, Equatable {
    case snapshot
    case fillUp
}

struct PrivateImageScenario: Decodable, Equatable {
    let id: String
    let kind: PrivateImageScenarioKind
    let invoiceImage: String?
    let odometerImage: String?
    let fuelImage: String?
    let expected: PrivateImageScenarioExpected?
    let tolerance: PrivateImageScenarioTolerance
    let ui: PrivateImageScenarioUI?
    let excluded: Bool
    let exclusionReason: String?

    var imagePaths: [String] {
        [invoiceImage, odometerImage, fuelImage]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case invoiceImage
        case odometerImage
        case fuelImage
        case expected
        case tolerance
        case ui
        case excluded
        case exclusionReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(PrivateImageScenarioKind.self, forKey: .kind)
        invoiceImage = try container.decodeIfPresent(String.self, forKey: .invoiceImage)
        odometerImage = try container.decodeIfPresent(String.self, forKey: .odometerImage)
        fuelImage = try container.decodeIfPresent(String.self, forKey: .fuelImage)
        expected = try container.decodeIfPresent(PrivateImageScenarioExpected.self, forKey: .expected)
        tolerance = try container.decodeIfPresent(
            PrivateImageScenarioTolerance.self,
            forKey: .tolerance
        ) ?? PrivateImageScenarioTolerance()
        ui = try container.decodeIfPresent(PrivateImageScenarioUI.self, forKey: .ui)
        excluded = try container.decodeIfPresent(Bool.self, forKey: .excluded) ?? false
        exclusionReason = try container.decodeIfPresent(String.self, forKey: .exclusionReason)
    }
}

struct PrivateImageScenarioExpected: Decodable, Equatable {
    let odometerMiles: Double?
    let tripMiles: Double?
    let fuelLevelOCR: Double?
    let expectsFuelLevelOCR: Bool
    let gallons: Double?
    let pricePerGallon: Double?
    let totalCost: Double?
    let invoiceTextContains: String?

    private enum CodingKeys: String, CodingKey {
        case odometerMiles
        case tripMiles
        case fuelLevelOCR
        case gallons
        case pricePerGallon
        case totalCost
        case invoiceTextContains
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        odometerMiles = try container.decodeIfPresent(Double.self, forKey: .odometerMiles)
        tripMiles = try container.decodeIfPresent(Double.self, forKey: .tripMiles)
        expectsFuelLevelOCR = container.contains(.fuelLevelOCR)
        fuelLevelOCR = try container.decodeIfPresent(Double.self, forKey: .fuelLevelOCR)
        gallons = try container.decodeIfPresent(Double.self, forKey: .gallons)
        pricePerGallon = try container.decodeIfPresent(Double.self, forKey: .pricePerGallon)
        totalCost = try container.decodeIfPresent(Double.self, forKey: .totalCost)
        invoiceTextContains = try container.decodeIfPresent(String.self, forKey: .invoiceTextContains)
    }
}

struct PrivateImageScenarioTolerance: Decodable, Equatable {
    let odometerMiles: Double
    let tripMiles: Double
    let fuelLevelOCR: Double
    let gallons: Double
    let pricePerGallon: Double
    let totalCost: Double

    init(
        odometerMiles: Double = 1,
        tripMiles: Double = 0.2,
        fuelLevelOCR: Double = 0.01,
        gallons: Double = 0.0001,
        pricePerGallon: Double = 0.001,
        totalCost: Double = 0.001
    ) {
        self.odometerMiles = odometerMiles
        self.tripMiles = tripMiles
        self.fuelLevelOCR = fuelLevelOCR
        self.gallons = gallons
        self.pricePerGallon = pricePerGallon
        self.totalCost = totalCost
    }

    private enum CodingKeys: String, CodingKey {
        case odometerMiles
        case tripMiles
        case fuelLevelOCR
        case gallons
        case pricePerGallon
        case totalCost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            odometerMiles: try container.decodeIfPresent(Double.self, forKey: .odometerMiles) ?? 1,
            tripMiles: try container.decodeIfPresent(Double.self, forKey: .tripMiles) ?? 0.2,
            fuelLevelOCR: try container.decodeIfPresent(Double.self, forKey: .fuelLevelOCR) ?? 0.01,
            gallons: try container.decodeIfPresent(Double.self, forKey: .gallons) ?? 0.0001,
            pricePerGallon: try container.decodeIfPresent(Double.self, forKey: .pricePerGallon) ?? 0.001,
            totalCost: try container.decodeIfPresent(Double.self, forKey: .totalCost) ?? 0.001
        )
    }

    var hasNegativeValue: Bool {
        [
            odometerMiles,
            tripMiles,
            fuelLevelOCR,
            gallons,
            pricePerGallon,
            totalCost,
        ].contains(where: { $0 < 0 })
    }
}

struct PrivateImageScenarioUI: Decodable, Equatable {
    let manualFuelSpaces: Double?
    let runInSimulator: Bool

    private enum CodingKeys: String, CodingKey {
        case manualFuelSpaces
        case runInSimulator
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manualFuelSpaces = try container.decodeIfPresent(Double.self, forKey: .manualFuelSpaces)
        runInSimulator = try container.decodeIfPresent(Bool.self, forKey: .runInSimulator) ?? false
    }
}

enum PrivateImageScenarioManifestError: Error, Equatable, LocalizedError {
    case unsupportedVersion(Int)
    case emptyID
    case duplicateID(String)
    case missingImages(String)
    case negativeTolerance(String)
    case missingExclusionReason(String)
    case invalidManualFuelSpaces(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            "Unsupported private image manifest version: \(version)."
        case .emptyID:
            "Every private image scenario must have a non-empty ID."
        case let .duplicateID(id):
            "Duplicate private image scenario ID: \(id)."
        case let .missingImages(id):
            "Active private image scenario \(id) has no image paths."
        case let .negativeTolerance(id):
            "Private image scenario \(id) has a negative tolerance."
        case let .missingExclusionReason(id):
            "Excluded private image scenario \(id) requires a reason."
        case let .invalidManualFuelSpaces(id):
            "Private image scenario \(id) has manual fuel spaces outside 0...8."
        }
    }
}
