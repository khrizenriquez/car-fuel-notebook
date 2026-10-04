import Foundation
import SwiftData

enum BackupTransferError: LocalizedError {
    case invalidBackupFormat

    var errorDescription: String? {
        switch self {
        case .invalidBackupFormat:
            return "El archivo seleccionado no tiene un formato de respaldo valido."
        }
    }
}

struct BackupTransferSummary {
    let vehicleCount: Int
    let fillCount: Int
    let snapshotCount: Int
    let adjustmentCount: Int
    let imageCount: Int
}

enum BackupTransferService {
    static func exportBackup(from context: ModelContext) throws -> URL {
        let payload = try makeBackupPayload(from: context)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(payload)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cartrack-Backup-\(timestampString(from: payload.exportedAt)).cartrackbackup.json")

        try data.write(to: url, options: .atomic)
        return url
    }

    static func importBackup(from url: URL, into context: ModelContext) throws -> BackupTransferSummary {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let payload = try? decoder.decode(CartrackBackupPayload.self, from: data) else {
            throw BackupTransferError.invalidBackupFormat
        }

        try replaceLocalData(with: payload, in: context)

        return BackupTransferSummary(
            vehicleCount: payload.vehicles.count,
            fillCount: payload.fillEvents.count,
            snapshotCount: payload.snapshotEvents.count,
            adjustmentCount: payload.adjustments.count,
            imageCount: payload.imageAssets.count
        )
    }

    private static func makeBackupPayload(from context: ModelContext) throws -> CartrackBackupPayload {
        let vehicles = try context.fetch(FetchDescriptor<Vehicle>(sortBy: [SortDescriptor(\.createdAt)]))
        let fillEvents = try context.fetch(FetchDescriptor<FuelFillEvent>(sortBy: [SortDescriptor(\.date)]))
        let snapshotEvents = try context.fetch(FetchDescriptor<SnapshotEvent>(sortBy: [SortDescriptor(\.date)]))
        let adjustments = try context.fetch(FetchDescriptor<MonthlyManualAdjustment>(sortBy: [SortDescriptor(\.monthStart)]))
        let imageAssets = try context.fetch(FetchDescriptor<ImageAsset>(sortBy: [SortDescriptor(\.createdAt)]))

        return CartrackBackupPayload(
            formatVersion: 1,
            exportedAt: .now,
            vehicles: vehicles.map {
                VehicleBackupRecord(
                    id: $0.id,
                    name: $0.name,
                    make: $0.make,
                    modelName: $0.modelName,
                    year: $0.year,
                    engine: $0.engine,
                    plate: $0.plate,
                    odometerUnitRawValue: $0.odometerUnitRawValue,
                    tankCapacityGallons: $0.tankCapacityGallons,
                    fuelScaleMax: $0.fuelScaleMax,
                    fuelScaleStep: $0.fuelScaleStep,
                    fuelEconomyReferenceKilometersPerGallon: $0.fuelEconomyReferenceKilometersPerGallon,
                    notes: $0.notes,
                    createdAt: $0.createdAt
                )
            },
            fillEvents: fillEvents.map {
                FuelFillBackupRecord(
                    id: $0.id,
                    vehicleID: $0.vehicle?.id,
                    date: $0.date,
                    odometerMilesOriginal: $0.odometerMilesOriginal,
                    odometerKilometers: $0.odometerKilometers,
                    tripMilesOriginal: $0.tripMilesOriginal,
                    tripKilometers: $0.tripKilometers,
                    gallons: $0.gallons,
                    pricePerGallon: $0.pricePerGallon,
                    totalCost: $0.totalCost,
                    isFullTank: $0.isFullTank,
                    stationName: $0.stationName,
                    fuelLevelRemaining: $0.fuelLevelRemaining,
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    notes: $0.notes,
                    invoiceOCRText: $0.invoiceOCRText,
                    odometerOCRText: $0.odometerOCRText,
                    fuelLevelOCRText: $0.fuelLevelOCRText,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            snapshotEvents: snapshotEvents.map {
                SnapshotBackupRecord(
                    id: $0.id,
                    vehicleID: $0.vehicle?.id,
                    date: $0.date,
                    odometerMilesOriginal: $0.odometerMilesOriginal,
                    odometerKilometers: $0.odometerKilometers,
                    tripMilesOriginal: $0.tripMilesOriginal,
                    tripKilometers: $0.tripKilometers,
                    fuelLevelRemaining: $0.fuelLevelRemaining,
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    notes: $0.notes,
                    odometerOCRText: $0.odometerOCRText,
                    fuelLevelOCRText: $0.fuelLevelOCRText,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            adjustments: adjustments.map {
                MonthlyAdjustmentBackupRecord(
                    id: $0.id,
                    vehicleID: $0.vehicle?.id,
                    monthStart: $0.monthStart,
                    manualDistanceMiles: $0.manualDistanceMiles,
                    manualDistanceKilometers: $0.manualDistanceKilometers,
                    note: $0.note,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            imageAssets: imageAssets.map {
                ImageAssetBackupRecord(
                    id: $0.id,
                    eventID: $0.eventID,
                    ownerTypeRawValue: $0.ownerTypeRawValue,
                    kindRawValue: $0.kindRawValue,
                    createdAt: $0.createdAt,
                    originalFilename: URL(fileURLWithPath: $0.localPath).lastPathComponent,
                    imageData: ImageStorageService.shared.loadImageData(at: $0.localPath)
                )
            }
        )
    }

    private static func replaceLocalData(with payload: CartrackBackupPayload, in context: ModelContext) throws {
        try clearExistingLocalData(in: context)

        let vehicles = payload.vehicles.map {
            Vehicle(
                id: $0.id,
                name: $0.name,
                make: $0.make,
                modelName: $0.modelName,
                year: $0.year,
                engine: $0.engine,
                plate: $0.plate,
                odometerUnit: OdometerUnit(rawValue: $0.odometerUnitRawValue) ?? .miles,
                tankCapacityGallons: $0.tankCapacityGallons,
                fuelScaleMax: $0.fuelScaleMax,
                fuelScaleStep: $0.fuelScaleStep,
                fuelEconomyReferenceKilometersPerGallon: $0.fuelEconomyReferenceKilometersPerGallon,
                notes: $0.notes,
                createdAt: $0.createdAt
            )
        }

        let vehicleMap = Dictionary(uniqueKeysWithValues: vehicles.map { ($0.id, $0) })
        vehicles.forEach(context.insert)
        for vehicle in vehicles {
            try SyncMetadataMaintainer.recordChange(ownerID: vehicle.id, kind: "vehicle",
                                                    createdAt: vehicle.createdAt,
                                                    updatedAt: vehicle.createdAt, in: context)
        }

        for record in payload.fillEvents {
            let fill = FuelFillEvent(
                id: record.id,
                date: record.date,
                vehicle: record.vehicleID.flatMap { vehicleMap[$0] },
                odometerMilesOriginal: record.odometerMilesOriginal,
                odometerKilometers: record.odometerKilometers,
                tripMilesOriginal: record.tripMilesOriginal,
                tripKilometers: record.tripKilometers,
                gallons: record.gallons,
                pricePerGallon: record.pricePerGallon,
                totalCost: record.totalCost,
                isFullTank: record.isFullTank,
                stationName: record.stationName,
                fuelLevelRemaining: record.fuelLevelRemaining,
                latitude: record.latitude,
                longitude: record.longitude,
                notes: record.notes,
                invoiceOCRText: record.invoiceOCRText,
                odometerOCRText: record.odometerOCRText,
                fuelLevelOCRText: record.fuelLevelOCRText,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            )
            context.insert(fill)
            try SyncMetadataMaintainer.recordChange(ownerID: fill.id, kind: "fuelEntry",
                                                    createdAt: fill.createdAt,
                                                    updatedAt: fill.updatedAt, in: context)
        }

        for record in payload.snapshotEvents {
            let snapshot = SnapshotEvent(
                id: record.id,
                date: record.date,
                vehicle: record.vehicleID.flatMap { vehicleMap[$0] },
                odometerMilesOriginal: record.odometerMilesOriginal,
                odometerKilometers: record.odometerKilometers,
                tripMilesOriginal: record.tripMilesOriginal,
                tripKilometers: record.tripKilometers,
                fuelLevelRemaining: record.fuelLevelRemaining,
                latitude: record.latitude,
                longitude: record.longitude,
                notes: record.notes,
                odometerOCRText: record.odometerOCRText,
                fuelLevelOCRText: record.fuelLevelOCRText,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            )
            context.insert(snapshot)
            try SyncMetadataMaintainer.recordChange(ownerID: snapshot.id, kind: "usageSnapshot",
                                                    createdAt: snapshot.createdAt,
                                                    updatedAt: snapshot.updatedAt, in: context)
        }

        for record in payload.adjustments {
            let adjustment = MonthlyManualAdjustment(
                id: record.id,
                monthStart: record.monthStart,
                vehicle: record.vehicleID.flatMap { vehicleMap[$0] },
                manualDistanceMiles: record.manualDistanceMiles,
                manualDistanceKilometers: record.manualDistanceKilometers,
                note: record.note,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            )
            context.insert(adjustment)
        }

        for record in payload.imageAssets {
            guard let imageData = record.imageData else { continue }

            let preferredName = URL(fileURLWithPath: record.originalFilename ?? "\(record.kindRawValue)-\(record.id.uuidString).jpg")
                .deletingPathExtension()
                .lastPathComponent
            let localPath = try ImageStorageService.shared.saveImageData(imageData, preferredName: preferredName)
            let asset = ImageAsset(
                id: record.id,
                eventID: record.eventID,
                ownerType: ImageOwnerKind(rawValue: record.ownerTypeRawValue) ?? .fillUp,
                kind: CaptureImageKind(rawValue: record.kindRawValue) ?? .invoice,
                localPath: localPath,
                createdAt: record.createdAt
            )
            context.insert(asset)
        }

        try context.save()
    }

    private static func clearExistingLocalData(in context: ModelContext) throws {
        let existingAssets = try context.fetch(FetchDescriptor<ImageAsset>())
        for asset in existingAssets {
            try ImageStorageService.shared.deleteImage(at: asset.localPath)
            context.delete(asset)
        }

        try context.fetch(FetchDescriptor<FuelFillEvent>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<SnapshotEvent>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<MonthlyManualAdjustment>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Vehicle>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<SyncMetadataRecord>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<V2RecordExtras>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<LocalPhotoAsset>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<OCRFieldEvidence>()).forEach(context.delete)
        try context.save()
    }

    private static func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

private struct CartrackBackupPayload: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let vehicles: [VehicleBackupRecord]
    let fillEvents: [FuelFillBackupRecord]
    let snapshotEvents: [SnapshotBackupRecord]
    let adjustments: [MonthlyAdjustmentBackupRecord]
    let imageAssets: [ImageAssetBackupRecord]
}

private struct VehicleBackupRecord: Codable {
    let id: UUID
    let name: String
    let make: String
    let modelName: String
    let year: Int
    let engine: String
    let plate: String
    let odometerUnitRawValue: String
    let tankCapacityGallons: Double
    let fuelScaleMax: Double
    let fuelScaleStep: Double
    let fuelEconomyReferenceKilometersPerGallon: Double
    let notes: String
    let createdAt: Date
}

private struct FuelFillBackupRecord: Codable {
    let id: UUID
    let vehicleID: UUID?
    let date: Date
    let odometerMilesOriginal: Double?
    let odometerKilometers: Double
    let tripMilesOriginal: Double?
    let tripKilometers: Double?
    let gallons: Double
    let pricePerGallon: Double
    let totalCost: Double
    let isFullTank: Bool
    let stationName: String
    let fuelLevelRemaining: Double
    let latitude: Double?
    let longitude: Double?
    let notes: String
    let invoiceOCRText: String
    let odometerOCRText: String
    let fuelLevelOCRText: String
    let createdAt: Date
    let updatedAt: Date
}

private struct SnapshotBackupRecord: Codable {
    let id: UUID
    let vehicleID: UUID?
    let date: Date
    let odometerMilesOriginal: Double?
    let odometerKilometers: Double
    let tripMilesOriginal: Double?
    let tripKilometers: Double?
    let fuelLevelRemaining: Double
    let latitude: Double?
    let longitude: Double?
    let notes: String
    let odometerOCRText: String
    let fuelLevelOCRText: String
    let createdAt: Date
    let updatedAt: Date
}

private struct MonthlyAdjustmentBackupRecord: Codable {
    let id: UUID
    let vehicleID: UUID?
    let monthStart: Date
    let manualDistanceMiles: Double?
    let manualDistanceKilometers: Double?
    let note: String
    let createdAt: Date
    let updatedAt: Date
}

private struct ImageAssetBackupRecord: Codable {
    let id: UUID
    let eventID: UUID
    let ownerTypeRawValue: String
    let kindRawValue: String
    let createdAt: Date
    let originalFilename: String?
    let imageData: Data?
}
