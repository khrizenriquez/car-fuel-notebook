import Foundation
import SwiftData
import CryptoKit

enum BackupTransferError: LocalizedError {
    case invalidBackupFormat
    case unsupportedFormatVersion(Int)
    case integrityFailed(String)
    case duplicateRecord(String)
    case invalidReference(String)
    case invalidValue(String)
    case restoreInterrupted
    case rollbackFailed

    var errorDescription: String? {
        switch self {
        case .invalidBackupFormat:
            return "El archivo seleccionado no tiene un formato de respaldo valido."
        case .unsupportedFormatVersion(let version):
            return "El respaldo usa el formato \(version), que esta version de Cartrack no admite."
        case .integrityFailed:
            return "El respaldo no paso la verificacion de integridad. No se modificaron tus datos locales."
        case .duplicateRecord:
            return "El respaldo contiene registros o evidencia duplicados. No se modificaron tus datos locales."
        case .invalidReference, .invalidValue:
            return "El respaldo contiene una referencia o valor invalido. No se modificaron tus datos locales."
        case .restoreInterrupted:
            return "La restauracion se interrumpio y los datos locales originales fueron conservados."
        case .rollbackFailed:
            return "No se pudo completar la restauracion ni recuperar automaticamente el estado anterior."
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

/// A read-only result of inspecting a backup. Import always creates this plan before deleting
/// any local record, which makes the destructive part of restoration explicit and testable.
struct BackupImportPlan {
    let formatVersion: Int
    let schemaVersion: Int
    let vehicleCount: Int
    let fillCount: Int
    let snapshotCount: Int
    let adjustmentCount: Int
    let imageCount: Int
    let includesImageBytes: Bool
    let existingRecordConflictCount: Int
}

enum BackupRestoreCheckpoint: Sendable {
    case afterSafetyBackup
    case afterStaging
    case beforeConfirmation
}

enum BackupTransferService {
    /// Exports a package directory. Evidence is opt-in because it can be considerably larger
    /// than the structured records and is never needed by cloud synchronization.
    static func exportBackup(from context: ModelContext, includeImages: Bool = true) throws -> URL {
        let payload = try makeBackupPayload(from: context)
        return try writeVersion2Package(payload: payload, includeImages: includeImages)
    }

    static func inspectBackup(from url: URL) throws -> BackupImportPlan {
        try loadPreparedBackup(from: url).plan
    }

    static func importBackup(from url: URL, into context: ModelContext,
                             failureAt: BackupRestoreCheckpoint? = nil) throws -> BackupTransferSummary {
        let incoming = try loadPreparedBackup(from: url)
        let currentIDs = try allPersistentIDs(in: context)
        let plan = BackupImportPlan(
            formatVersion: incoming.plan.formatVersion,
            schemaVersion: incoming.plan.schemaVersion,
            vehicleCount: incoming.plan.vehicleCount,
            fillCount: incoming.plan.fillCount,
            snapshotCount: incoming.plan.snapshotCount,
            adjustmentCount: incoming.plan.adjustmentCount,
            imageCount: incoming.plan.imageCount,
            includesImageBytes: incoming.plan.includesImageBytes,
            existingRecordConflictCount: currentIDs.intersection(incoming.recordIDs).count
        )

        // Keep a separately validated safety package until the replacement has committed.
        let safetyPayload = try makeBackupPayload(from: context)
        let safetyURL = try writeVersion2Package(payload: safetyPayload, includeImages: true,
                                                  prefix: "Cartrack-Rollback")
        _ = try loadPreparedBackup(from: safetyURL)
        try inject(failureAt, checkpoint: .afterSafetyBackup)

        do {
            // `incoming` is our staged representation: all JSON, hashes, UUIDs, references and
            // numeric invariants are already checked before this point.
            try inject(failureAt, checkpoint: .afterStaging)
            try replaceLocalData(with: incoming.payload, in: context)
            try inject(failureAt, checkpoint: .beforeConfirmation)
            try? FileManager.default.removeItem(at: safetyURL)
            return BackupTransferSummary(
                vehicleCount: plan.vehicleCount,
                fillCount: plan.fillCount,
                snapshotCount: plan.snapshotCount,
                adjustmentCount: plan.adjustmentCount,
                imageCount: plan.imageCount
            )
        } catch {
            do {
                let safety = try loadPreparedBackup(from: safetyURL)
                try replaceLocalData(with: safety.payload, in: context)
            } catch {
                throw BackupTransferError.rollbackFailed
            }
            throw error
        }
    }

    private static func makeBackupPayload(from context: ModelContext) throws -> CartrackBackupPayload {
        let vehicles = try context.fetch(FetchDescriptor<Vehicle>(sortBy: [SortDescriptor(\.createdAt)]))
        let fillEvents = try context.fetch(FetchDescriptor<FuelFillEvent>(sortBy: [SortDescriptor(\.date)]))
        let snapshotEvents = try context.fetch(FetchDescriptor<SnapshotEvent>(sortBy: [SortDescriptor(\.date)]))
        let adjustments = try context.fetch(FetchDescriptor<MonthlyManualAdjustment>(sortBy: [SortDescriptor(\.monthStart)]))
        let imageAssets = try context.fetch(FetchDescriptor<ImageAsset>(sortBy: [SortDescriptor(\.createdAt)]))
        let localPhotos = try context.fetch(FetchDescriptor<LocalPhotoAsset>(sortBy: [SortDescriptor(\.createdAt)]))

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
            },
            localPhotoAssets: localPhotos.compactMap { photo in
                guard photo.sessionID != nil else { return nil }
                let record = LocalPhotoRecord(
                    id: photo.id, sessionID: photo.sessionID, eventID: photo.eventID,
                    kind: photo.kindRawValue, localRelativePath: photo.localRelativePath,
                    sha256: photo.sha256, pixelWidth: photo.pixelWidth, pixelHeight: photo.pixelHeight,
                    byteCount: photo.byteCount, mimeType: photo.mimeType, capturedAt: photo.capturedAt,
                    optimizationState: photo.optimizationStateRawValue, createdAt: photo.createdAt
                )
                guard let path = try? CapturePhotoStore().absolutePath(for: record) else { return nil }
                return LocalPhotoBackupRecord(record: record,
                                              imageData: FileManager.default.contents(atPath: path))
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

        var restoredLocalPaths: [String: String] = [:]
        let photoStore = CapturePhotoStore()
        for record in payload.localPhotoAssets ?? [] {
            guard let imageData = record.imageData else { continue }
            let localRecord = record.localPhotoRecord
            try photoStore.restore(imageData, for: localRecord)
            let path = try photoStore.absolutePath(for: localRecord)
            restoredLocalPaths[evidenceKey(eventID: localRecord.eventID,
                                           kind: localRecord.kind, sha256: localRecord.sha256)] = path
            context.insert(LocalPhotoAsset(
                id: localRecord.id, sessionID: localRecord.sessionID, eventID: localRecord.eventID,
                kindRawValue: localRecord.kind, localRelativePath: localRecord.localRelativePath,
                sha256: localRecord.sha256, pixelWidth: localRecord.pixelWidth,
                pixelHeight: localRecord.pixelHeight, byteCount: localRecord.byteCount,
                mimeType: localRecord.mimeType, capturedAt: localRecord.capturedAt,
                optimizationStateRawValue: localRecord.optimizationState,
                createdAt: localRecord.createdAt
            ))
        }

        for record in payload.imageAssets {
            guard let imageData = record.imageData else { continue }

            let preferredName = URL(fileURLWithPath: record.originalFilename ?? "\(record.kindRawValue)-\(record.id.uuidString).jpg")
                .deletingPathExtension()
                .lastPathComponent
            let digest = sha256(imageData)
            let evidencePath = restoredLocalPaths[evidenceKey(eventID: record.eventID,
                                                               kind: record.kindRawValue, sha256: digest)]
            let localPath: String
            if let evidencePath {
                localPath = evidencePath
            } else {
                localPath = try ImageStorageService.shared.saveImageData(imageData, preferredName: preferredName)
            }
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

        let localPhotos = try context.fetch(FetchDescriptor<LocalPhotoAsset>())
        for photo in localPhotos {
            let record = LocalPhotoRecord(
                id: photo.id, sessionID: photo.sessionID, eventID: photo.eventID,
                kind: photo.kindRawValue, localRelativePath: photo.localRelativePath,
                sha256: photo.sha256, pixelWidth: photo.pixelWidth, pixelHeight: photo.pixelHeight,
                byteCount: photo.byteCount, mimeType: photo.mimeType, capturedAt: photo.capturedAt,
                optimizationState: photo.optimizationStateRawValue, createdAt: photo.createdAt
            )
            try? CapturePhotoStore().remove(record)
        }

        try context.fetch(FetchDescriptor<FuelFillEvent>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<SnapshotEvent>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<MonthlyManualAdjustment>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Vehicle>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<SyncMetadataRecord>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<V2RecordExtras>()).forEach(context.delete)
        localPhotos.forEach(context.delete)
        try context.fetch(FetchDescriptor<OCRFieldEvidence>()).forEach(context.delete)
        try context.save()
    }

    private static func writeVersion2Package(payload: CartrackBackupPayload, includeImages: Bool,
                                             prefix: String = "Cartrack-Backup") throws -> URL {
        let fileManager = FileManager.default
        let exportDate = payload.exportedAt
        let root = fileManager.temporaryDirectory
        let finalURL = root.appendingPathComponent(
            "\(prefix)-\(timestampString(from: exportDate))-\(UUID().uuidString).cartrackbackup",
            isDirectory: true
        )
        let stagingURL = root.appendingPathComponent(".\(UUID().uuidString).cartrackbackup-staging",
                                                     isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        do {
            let imageDirectory = stagingURL.appendingPathComponent("images", isDirectory: true)
            if includeImages { try fileManager.createDirectory(at: imageDirectory, withIntermediateDirectories: true) }

            var records = payload
            records = CartrackBackupPayload(
                formatVersion: 2,
                exportedAt: payload.exportedAt,
                vehicles: payload.vehicles,
                fillEvents: payload.fillEvents,
                snapshotEvents: payload.snapshotEvents,
                adjustments: payload.adjustments,
                imageAssets: payload.imageAssets.map {
                    ImageAssetBackupRecord(
                        id: $0.id, eventID: $0.eventID, ownerTypeRawValue: $0.ownerTypeRawValue,
                        kindRawValue: $0.kindRawValue, createdAt: $0.createdAt,
                        originalFilename: $0.originalFilename, hasLocalEvidence: $0.imageData != nil,
                        imageData: nil
                    )
                },
                localPhotoAssets: (payload.localPhotoAssets ?? []).map {
                    LocalPhotoBackupRecord(record: $0.localPhotoRecord,
                                           hasLocalEvidence: $0.imageData != nil, imageData: nil)
                }
            )

            var files: [BackupPackageFile] = []
            if includeImages {
                for asset in payload.imageAssets {
                    guard let bytes = asset.imageData else { continue }
                    let path = "images/\(asset.id.uuidString.lowercased()).jpg"
                    let destination = stagingURL.appendingPathComponent(path)
                    try bytes.write(to: destination, options: .atomic)
                    files.append(try BackupPackageFile(path: path, url: destination))
                }
                for photo in payload.localPhotoAssets ?? [] {
                    guard let bytes = photo.imageData else { continue }
                    let path = "images/local-\(photo.id.uuidString.lowercased()).jpg"
                    let destination = stagingURL.appendingPathComponent(path)
                    try bytes.write(to: destination, options: .atomic)
                    files.append(try BackupPackageFile(path: path, url: destination))
                }
            }

            let recordsURL = stagingURL.appendingPathComponent("records.json")
            let recordsData = try backupEncoder.encode(records)
            try recordsData.write(to: recordsURL, options: .atomic)
            files.insert(try BackupPackageFile(path: "records.json", url: recordsURL), at: 0)

            let manifest = BackupPackageManifest(
                formatVersion: 2,
                schemaVersion: 2,
                exportedAt: exportDate,
                appVersion: appVersion,
                entityCounts: BackupEntityCounts(payload: payload),
                includesImages: files.contains { $0.path.hasPrefix("images/") },
                files: files,
                expectedTotalByteCount: files.reduce(0) { $0 + $1.byteCount }
            )
            let manifestURL = stagingURL.appendingPathComponent("manifest.json")
            try backupEncoder.encode(manifest).write(to: manifestURL, options: .atomic)

            // Validate staging exactly as an importer would before publishing it.
            _ = try loadPreparedBackup(from: stagingURL)
            try fileManager.moveItem(at: stagingURL, to: finalURL)
            return finalURL
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    private static func loadPreparedBackup(from url: URL) throws -> PreparedBackup {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            return try loadVersion2Package(from: url)
        }
        return try loadVersion1JSON(from: url)
    }

    private static func loadVersion1JSON(from url: URL) throws -> PreparedBackup {
        let data = try Data(contentsOf: url)
        guard let payload = try? backupDecoder.decode(CartrackBackupPayload.self, from: data) else {
            throw BackupTransferError.invalidBackupFormat
        }
        guard payload.formatVersion == 1 else {
            throw BackupTransferError.unsupportedFormatVersion(payload.formatVersion)
        }
        return try preparedBackup(payload: payload, schemaVersion: 1)
    }

    private static func loadVersion2Package(from root: URL) throws -> PreparedBackup {
        let manifestURL = root.appendingPathComponent("manifest.json")
        let recordsURL = root.appendingPathComponent("records.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path),
              FileManager.default.fileExists(atPath: recordsURL.path),
              let manifest = try? backupDecoder.decode(BackupPackageManifest.self,
                                                       from: Data(contentsOf: manifestURL)) else {
            throw BackupTransferError.invalidBackupFormat
        }
        guard manifest.formatVersion == 2, manifest.schemaVersion == 2 else {
            throw BackupTransferError.unsupportedFormatVersion(manifest.formatVersion)
        }
        guard !manifest.files.isEmpty, manifest.files.map(\.path).contains("records.json") else {
            throw BackupTransferError.integrityFailed("missing-records")
        }

        var byteCount = 0
        var fileData: [String: Data] = [:]
        for entry in manifest.files {
            guard isSafeArchivePath(entry.path) else { throw BackupTransferError.integrityFailed("unsafe-path") }
            let fileURL = root.appendingPathComponent(entry.path)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw BackupTransferError.integrityFailed("missing-file")
            }
            let data = try Data(contentsOf: fileURL)
            guard data.count == entry.byteCount, sha256(data) == entry.sha256 else {
                throw BackupTransferError.integrityFailed("hash-mismatch")
            }
            byteCount += data.count
            fileData[entry.path] = data
        }
        guard byteCount == manifest.expectedTotalByteCount,
              let recordsData = fileData["records.json"],
              var payload = try? backupDecoder.decode(CartrackBackupPayload.self, from: recordsData),
              payload.formatVersion == 2 else {
            throw BackupTransferError.integrityFailed("records")
        }

        payload = CartrackBackupPayload(
            formatVersion: payload.formatVersion,
            exportedAt: payload.exportedAt,
            vehicles: payload.vehicles,
            fillEvents: payload.fillEvents,
            snapshotEvents: payload.snapshotEvents,
            adjustments: payload.adjustments,
            imageAssets: payload.imageAssets.map { asset in
                let bytes = fileData["images/\(asset.id.uuidString.lowercased()).jpg"]
                return ImageAssetBackupRecord(
                    id: asset.id, eventID: asset.eventID, ownerTypeRawValue: asset.ownerTypeRawValue,
                    kindRawValue: asset.kindRawValue, createdAt: asset.createdAt,
                    originalFilename: asset.originalFilename, hasLocalEvidence: asset.hasLocalEvidence,
                    imageData: bytes
                )
            },
            localPhotoAssets: (payload.localPhotoAssets ?? []).map { photo in
                LocalPhotoBackupRecord(
                    record: photo.localPhotoRecord,
                    hasLocalEvidence: photo.hasLocalEvidence,
                    imageData: fileData["images/local-\(photo.id.uuidString.lowercased()).jpg"]
                )
            }
        )
        let prepared = try preparedBackup(payload: payload, schemaVersion: manifest.schemaVersion)
        guard manifest.entityCounts == BackupEntityCounts(payload: payload),
              manifest.includesImages == (payload.imageAssets.contains(where: { $0.imageData != nil }) ||
                (payload.localPhotoAssets ?? []).contains(where: { $0.imageData != nil })) else {
            throw BackupTransferError.integrityFailed("counts")
        }
        return prepared
    }

    private static func preparedBackup(payload: CartrackBackupPayload, schemaVersion: Int) throws -> PreparedBackup {
        try validate(payload)
        let imageBytes = payload.imageAssets.compactMap(\.imageData) +
            (payload.localPhotoAssets ?? []).compactMap(\.imageData)
        return PreparedBackup(
            payload: payload,
            plan: BackupImportPlan(
                formatVersion: payload.formatVersion,
                schemaVersion: schemaVersion,
                vehicleCount: payload.vehicles.count,
                fillCount: payload.fillEvents.count,
                snapshotCount: payload.snapshotEvents.count,
                adjustmentCount: payload.adjustments.count,
                imageCount: payload.imageAssets.count + (payload.localPhotoAssets ?? []).count,
                includesImageBytes: !imageBytes.isEmpty,
                existingRecordConflictCount: 0
            ),
            recordIDs: Set(payload.vehicles.map(\.id) + payload.fillEvents.map(\.id) +
                           payload.snapshotEvents.map(\.id) + payload.adjustments.map(\.id) +
                           payload.imageAssets.map(\.id) + (payload.localPhotoAssets ?? []).map(\.id))
        )
    }

    private static func validate(_ payload: CartrackBackupPayload) throws {
        var identifiers = Set<UUID>()
        func insertUnique(_ ids: [UUID], label: String) throws {
            for id in ids where !identifiers.insert(id).inserted {
                throw BackupTransferError.duplicateRecord(label)
            }
        }
        try insertUnique(payload.vehicles.map(\.id), label: "uuid")
        try insertUnique(payload.fillEvents.map(\.id), label: "uuid")
        try insertUnique(payload.snapshotEvents.map(\.id), label: "uuid")
        try insertUnique(payload.adjustments.map(\.id), label: "uuid")
        try insertUnique(payload.imageAssets.map(\.id), label: "uuid")
        try insertUnique((payload.localPhotoAssets ?? []).map(\.id), label: "uuid")

        let vehicleIDs = Set(payload.vehicles.map(\.id))
        for vehicleID in payload.fillEvents.compactMap(\.vehicleID) +
            payload.snapshotEvents.compactMap(\.vehicleID) + payload.adjustments.compactMap(\.vehicleID) {
            guard vehicleIDs.contains(vehicleID) else { throw BackupTransferError.invalidReference("vehicle") }
        }
        for fill in payload.fillEvents {
            guard fill.odometerKilometers.isFinite, fill.odometerKilometers >= 0,
                  fill.gallons.isFinite, fill.gallons > 0,
                  fill.pricePerGallon.isFinite, fill.pricePerGallon >= 0,
                  fill.totalCost.isFinite, fill.totalCost >= 0,
                  fill.fuelLevelRemaining.isFinite, fill.fuelLevelRemaining >= 0 else {
                throw BackupTransferError.invalidValue("fill")
            }
        }
        for snapshot in payload.snapshotEvents {
            guard snapshot.odometerKilometers.isFinite, snapshot.odometerKilometers >= 0,
                  snapshot.fuelLevelRemaining.isFinite, snapshot.fuelLevelRemaining >= 0 else {
                throw BackupTransferError.invalidValue("snapshot")
            }
        }
        let eventIDs = Set(payload.fillEvents.map(\.id) + payload.snapshotEvents.map(\.id))
        for photo in payload.localPhotoAssets ?? [] {
            guard photo.sessionID != nil, photo.eventID.map(eventIDs.contains) ?? true else {
                throw BackupTransferError.invalidReference("local-photo-event")
            }
            if let data = photo.imageData, sha256(data) != photo.sha256 {
                throw BackupTransferError.integrityFailed("local-photo-hash")
            }
        }
        var imageHashes = Set<String>()
        for asset in payload.imageAssets {
            if let data = asset.imageData {
                let hash = sha256(data)
                guard imageHashes.insert(hash).inserted else {
                    throw BackupTransferError.duplicateRecord("image-hash")
                }
            }
        }
    }

    private static func allPersistentIDs(in context: ModelContext) throws -> Set<UUID> {
        let vehicles = try context.fetch(FetchDescriptor<Vehicle>()).map(\.id)
        let fills = try context.fetch(FetchDescriptor<FuelFillEvent>()).map(\.id)
        let snapshots = try context.fetch(FetchDescriptor<SnapshotEvent>()).map(\.id)
        let adjustments = try context.fetch(FetchDescriptor<MonthlyManualAdjustment>()).map(\.id)
        let images = try context.fetch(FetchDescriptor<ImageAsset>()).map(\.id)
        return Set(vehicles + fills + snapshots + adjustments + images)
    }

    private static func inject(_ expected: BackupRestoreCheckpoint?, checkpoint: BackupRestoreCheckpoint) throws {
        guard expected == checkpoint else { return }
        throw BackupTransferError.restoreInterrupted
    }

    private static var backupEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var backupDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private static func isSafeArchivePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("..") &&
            (path == "records.json" || path.hasPrefix("images/"))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func evidenceKey(eventID: UUID?, kind: String, sha256: String) -> String {
        "\(eventID?.uuidString ?? "none")|\(kind)|\(sha256)"
    }

    private static func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

private struct PreparedBackup {
    let payload: CartrackBackupPayload
    let plan: BackupImportPlan
    let recordIDs: Set<UUID>
}

private struct BackupEntityCounts: Codable, Equatable {
    let vehicles: Int
    let fillEvents: Int
    let snapshotEvents: Int
    let adjustments: Int
    let imageAssets: Int
    let localPhotoAssets: Int

    init(payload: CartrackBackupPayload) {
        vehicles = payload.vehicles.count
        fillEvents = payload.fillEvents.count
        snapshotEvents = payload.snapshotEvents.count
        adjustments = payload.adjustments.count
        imageAssets = payload.imageAssets.count
        localPhotoAssets = (payload.localPhotoAssets ?? []).count
    }
}

private struct BackupPackageFile: Codable, Equatable {
    let path: String
    let sha256: String
    let byteCount: Int

    init(path: String, url: URL) throws {
        let data = try Data(contentsOf: url)
        self.path = path
        self.sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        self.byteCount = data.count
    }
}

private struct BackupPackageManifest: Codable {
    let formatVersion: Int
    let schemaVersion: Int
    let exportedAt: Date
    let appVersion: String
    let entityCounts: BackupEntityCounts
    let includesImages: Bool
    let files: [BackupPackageFile]
    let expectedTotalByteCount: Int
}

private struct CartrackBackupPayload: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let vehicles: [VehicleBackupRecord]
    let fillEvents: [FuelFillBackupRecord]
    let snapshotEvents: [SnapshotBackupRecord]
    let adjustments: [MonthlyAdjustmentBackupRecord]
    let imageAssets: [ImageAssetBackupRecord]
    /// Optional so a v1 JSON document keeps decoding without a migration write.
    let localPhotoAssets: [LocalPhotoBackupRecord]?
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
    /// `true` means the source device had local evidence even when bytes were intentionally omitted.
    let hasLocalEvidence: Bool?
    let imageData: Data?

    init(id: UUID, eventID: UUID, ownerTypeRawValue: String, kindRawValue: String,
         createdAt: Date, originalFilename: String?, hasLocalEvidence: Bool? = nil,
         imageData: Data?) {
        self.id = id
        self.eventID = eventID
        self.ownerTypeRawValue = ownerTypeRawValue
        self.kindRawValue = kindRawValue
        self.createdAt = createdAt
        self.originalFilename = originalFilename
        self.hasLocalEvidence = hasLocalEvidence
        self.imageData = imageData
    }
}

private struct LocalPhotoBackupRecord: Codable {
    let id: UUID
    let sessionID: UUID?
    let eventID: UUID?
    let kind: String
    let sha256: String
    let pixelWidth: Int
    let pixelHeight: Int
    let byteCount: Int
    let mimeType: String
    let capturedAt: Date?
    let optimizationState: String
    let createdAt: Date
    let hasLocalEvidence: Bool?
    let imageData: Data?

    init(record: LocalPhotoRecord, hasLocalEvidence: Bool? = nil, imageData: Data?) {
        id = record.id
        sessionID = record.sessionID
        eventID = record.eventID
        kind = record.kind
        sha256 = record.sha256
        pixelWidth = record.pixelWidth
        pixelHeight = record.pixelHeight
        byteCount = record.byteCount
        mimeType = record.mimeType
        capturedAt = record.capturedAt
        optimizationState = record.optimizationState
        createdAt = record.createdAt
        self.hasLocalEvidence = hasLocalEvidence
        self.imageData = imageData
    }

    var localPhotoRecord: LocalPhotoRecord {
        // A deterministic local path is regenerated from the identifiers during restoration;
        // neither backup records nor manifests expose the device's original file path.
        LocalPhotoRecord(
            id: id, sessionID: sessionID, eventID: eventID, kind: kind,
            localRelativePath: "CaptureSessions/\(sessionID!.uuidString)/\(id.uuidString).jpg",
            sha256: sha256, pixelWidth: pixelWidth, pixelHeight: pixelHeight,
            byteCount: byteCount, mimeType: mimeType, capturedAt: capturedAt,
            optimizationState: optimizationState, createdAt: createdAt
        )
    }
}
