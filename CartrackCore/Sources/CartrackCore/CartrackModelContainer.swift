import Foundation
import CryptoKit
import Darwin
import SQLite3
import SwiftData

@Model
final class LocalStoreVersion {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var createdAt: Date
    var sourceFingerprint: String

    init(id: UUID = UUID(), schemaVersion: Int = 2, createdAt: Date = .now, sourceFingerprint: String = "") {
        self.id = id
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.sourceFingerprint = sourceFingerprint
    }
}

enum CartrackV1Schema: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Vehicle.self, FuelFillEvent.self, SnapshotEvent.self, MonthlyManualAdjustment.self, ImageAsset.self]
    }
}

enum CartrackV2Schema: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        CartrackV1Schema.models + [LocalStoreVersion.self]
    }
}

enum StoreMigrationCheckpoint: CaseIterable {
    case afterBackup
    case afterStaging
    case beforeActivation
}

enum StoreMigrationError: Error, LocalizedError {
    case injected(StoreMigrationCheckpoint)
    case invalidActiveStore
    case validationFailed
    case backupFailed(String)
    case insufficientSpace
    case migrationInProgress

    var errorDescription: String? {
        switch self {
        case .injected: "Injected migration failure"
        case .invalidActiveStore: "The active local store is invalid; the previous store was not deleted."
        case .validationFailed: "The staged store did not match the original; the original was not modified."
        case .backupFailed(let detail): "The v1 backup could not be verified: \(detail)"
        case .insufficientSpace: "Not enough free space to back up and migrate the local store."
        case .migrationInProgress: "Another local-store migration is already in progress."
        }
    }
}

enum CartrackModelContainer {
    static func make(
        isStoredInMemoryOnly: Bool = false,
        applicationSupportURL: URL? = nil,
        legacyStoreURL: URL? = nil,
        failureAt: StoreMigrationCheckpoint? = nil
    ) throws -> ModelContainer {
        if isStoredInMemoryOnly {
            let schema = Schema(versionedSchema: CartrackV2Schema.self)
            let configuration = ModelConfiguration("CartrackDataV2", schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        let supportURL = applicationSupportURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        return try LocalStoreMigrator(applicationSupportURL: supportURL,
                                      legacyStoreURL: legacyStoreURL,
                                      failureAt: failureAt).open()
    }
}

private struct ActiveStorePointer: Codable {
    let schemaVersion: Int
    let storeName: String
    let backupName: String?
    let sourceFingerprint: String
}

private struct StoreInventory: Equatable {
    let fingerprint: String
    let vehicleCount: Int
    let fillCount: Int
    let snapshotCount: Int
    let adjustmentCount: Int
    let imageCount: Int

    init(context: ModelContext) throws {
        let vehicles = try context.fetch(FetchDescriptor<Vehicle>())
        let fills = try context.fetch(FetchDescriptor<FuelFillEvent>())
        let snapshots = try context.fetch(FetchDescriptor<SnapshotEvent>())
        let adjustments = try context.fetch(FetchDescriptor<MonthlyManualAdjustment>())
        let images = try context.fetch(FetchDescriptor<ImageAsset>())
        vehicleCount = vehicles.count
        fillCount = fills.count
        snapshotCount = snapshots.count
        adjustmentCount = adjustments.count
        imageCount = images.count

        func double(_ value: Double?) -> String { value.map { String($0.bitPattern) } ?? "nil" }
        func date(_ value: Date) -> String { String(value.timeIntervalSinceReferenceDate.bitPattern) }
        func uuid(_ value: UUID?) -> String { value?.uuidString ?? "nil" }

        var rows: [String] = []
        rows += vehicles.map {
            ["vehicle", $0.id.uuidString, $0.name, $0.make, $0.modelName, String($0.year),
             $0.engine, $0.plate, $0.odometerUnitRawValue, double($0.tankCapacityGallons),
             double($0.fuelScaleMax), double($0.fuelScaleStep),
             double($0.fuelEconomyReferenceKilometersPerGallon), $0.notes, date($0.createdAt)]
                .joined(separator: "\u{1F}")
        }
        rows += fills.map {
            ["fill", $0.id.uuidString, uuid($0.vehicle?.id), date($0.date),
             double($0.odometerMilesOriginal), double($0.odometerKilometers),
             double($0.tripMilesOriginal), double($0.tripKilometers), double($0.gallons),
             double($0.pricePerGallon), double($0.totalCost), String($0.isFullTank),
             $0.stationName, double($0.fuelLevelRemaining), double($0.latitude),
             double($0.longitude), $0.notes, $0.invoiceOCRText, $0.odometerOCRText,
             $0.fuelLevelOCRText, date($0.createdAt), date($0.updatedAt)]
                .joined(separator: "\u{1F}")
        }
        rows += snapshots.map {
            ["snapshot", $0.id.uuidString, uuid($0.vehicle?.id), date($0.date),
             double($0.odometerMilesOriginal), double($0.odometerKilometers),
             double($0.tripMilesOriginal), double($0.tripKilometers), double($0.fuelLevelRemaining),
             double($0.latitude), double($0.longitude), $0.notes, $0.odometerOCRText,
             $0.fuelLevelOCRText, date($0.createdAt), date($0.updatedAt)]
                .joined(separator: "\u{1F}")
        }
        rows += adjustments.map {
            ["adjustment", $0.id.uuidString, uuid($0.vehicle?.id), date($0.monthStart),
             double($0.manualDistanceMiles), double($0.manualDistanceKilometers), $0.note,
             date($0.createdAt), date($0.updatedAt)]
                .joined(separator: "\u{1F}")
        }
        rows += try images.map { image in
            let fileURL = URL(fileURLWithPath: image.localPath)
            let hash = FileManager.default.fileExists(atPath: image.localPath)
                ? try FileDigest.sha256(of: fileURL)
                : "missing"
            return ["image", image.id.uuidString, image.eventID.uuidString, image.ownerTypeRawValue,
                    image.kindRawValue, image.localPath, date(image.createdAt), hash]
                .joined(separator: "\u{1F}")
        }
        let canonical = rows.sorted().joined(separator: "\u{1E}")
        fingerprint = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private struct LocalStoreMigrator {
    let applicationSupportURL: URL
    let legacyStoreURL: URL?
    let failureAt: StoreMigrationCheckpoint?
    private let fileManager = FileManager.default

    private var migrationDirectory: URL { applicationSupportURL.appendingPathComponent("CartrackV2", isDirectory: true) }
    private var storesDirectory: URL { migrationDirectory.appendingPathComponent("Stores", isDirectory: true) }
    private var backupsDirectory: URL { migrationDirectory.appendingPathComponent("Backups", isDirectory: true) }
    private var pointerURL: URL { migrationDirectory.appendingPathComponent("active-store.json") }

    func open() throws -> ModelContainer {
        try fileManager.createDirectory(at: storesDirectory, withIntermediateDirectories: true)
        return try withMigrationLock { try openLocked() }
    }

    private func openLocked() throws -> ModelContainer {
        if fileManager.fileExists(atPath: pointerURL.path) {
            let pointer = try JSONDecoder().decode(ActiveStorePointer.self, from: Data(contentsOf: pointerURL))
            let storeID = String(pointer.storeName.dropLast(".store".count))
            guard pointer.schemaVersion == 2, pointer.storeName == "\(storeID).store",
                  UUID(uuidString: storeID) != nil else {
                throw StoreMigrationError.invalidActiveStore
            }
            let storeURL = storesDirectory.appendingPathComponent(pointer.storeName)
            guard fileManager.fileExists(atPath: storeURL.path) else { throw StoreMigrationError.invalidActiveStore }
            let container = try makeV2Container(at: storeURL)
            guard let version = try ModelContext(container).fetch(FetchDescriptor<LocalStoreVersion>()).first,
                  version.schemaVersion == 2, version.sourceFingerprint == pointer.sourceFingerprint else {
                throw StoreMigrationError.invalidActiveStore
            }
            return container
        }

        // The v1 URL is taken from its exact old configuration, rather than guessed.
        let legacySchema = Schema(CartrackV1Schema.models)
        let legacyConfiguration: ModelConfiguration
        if let legacyStoreURL {
            legacyConfiguration = ModelConfiguration("CartrackData", schema: legacySchema,
                                                     url: legacyStoreURL, allowsSave: true)
        } else {
            legacyConfiguration = ModelConfiguration("CartrackData", schema: legacySchema,
                                                     isStoredInMemoryOnly: false)
        }
        let legacyURL = legacyConfiguration.url
        let hasLegacyStore = fileManager.fileExists(atPath: legacyURL.path)
        if hasLegacyStore { try ensureFreeSpace(for: legacyURL) }
        let legacyContainer = hasLegacyStore
            ? try ModelContainer(for: legacySchema, configurations: [legacyConfiguration])
            : nil
        let sourceInventory = try legacyContainer.map { try StoreInventory(context: ModelContext($0)) }

        var backupName: String?
        if hasLegacyStore, let sourceInventory {
            try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            let name = "v1-\(UUID().uuidString).sqlite"
            let backupURL = backupsDirectory.appendingPathComponent(name)
            try SQLiteStoreBackup.createAndValidate(source: legacyURL, destination: backupURL)
            // Keep a small manifest next to the recoverable v1 database; photos remain untouched.
            let manifest = BackupManifest(sourceFingerprint: sourceInventory.fingerprint,
                                          backupSHA256: try FileDigest.sha256(of: backupURL))
            try JSONEncoder().encode(manifest)
                .write(to: backupURL.appendingPathExtension("manifest.json"), options: .atomic)
            backupName = name
            try inject(.afterBackup)
        }

        let storeName = "\(UUID().uuidString).store"
        let candidateURL = storesDirectory.appendingPathComponent(storeName)
        let container = try makeV2Container(at: candidateURL)
        let context = ModelContext(container)
        if let legacyContainer {
            try copyLegacyData(from: ModelContext(legacyContainer), to: context)
        }
        try context.save()
        try inject(.afterStaging)

        let candidateInventory = try StoreInventory(context: ModelContext(container))
        if let sourceInventory, candidateInventory != sourceInventory {
            throw StoreMigrationError.validationFailed
        }
        let version = LocalStoreVersion(sourceFingerprint: candidateInventory.fingerprint)
        context.insert(version)
        try context.save()
        try inject(.beforeActivation)

        let pointer = ActiveStorePointer(schemaVersion: 2, storeName: storeName,
                                         backupName: backupName, sourceFingerprint: candidateInventory.fingerprint)
        try JSONEncoder().encode(pointer).write(to: pointerURL, options: .atomic)
        return container
    }

    private func withMigrationLock<T>(_ body: () throws -> T) throws -> T {
        let lockURL = migrationDirectory.appendingPathComponent("migration.lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw StoreMigrationError.migrationInProgress }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw StoreMigrationError.migrationInProgress
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    private func ensureFreeSpace(for storeURL: URL) throws {
        let related = [storeURL, URL(fileURLWithPath: storeURL.path + "-wal"),
                       URL(fileURLWithPath: storeURL.path + "-shm")]
        let sourceBytes = related.reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
        let requiredBytes = max(1_048_576, sourceBytes * 3)
        let attributes = try fileManager.attributesOfFileSystem(forPath: applicationSupportURL.path)
        let freeBytes = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        guard freeBytes >= requiredBytes else { throw StoreMigrationError.insufficientSpace }
    }

    private func makeV2Container(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CartrackV2Schema.self)
        let configuration = ModelConfiguration("CartrackDataV2", schema: schema, url: url,
                                               allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func inject(_ checkpoint: StoreMigrationCheckpoint) throws {
        if failureAt == checkpoint { throw StoreMigrationError.injected(checkpoint) }
    }

    private func copyLegacyData(from source: ModelContext, to destination: ModelContext) throws {
        var vehiclesByID: [UUID: Vehicle] = [:]
        for old in try source.fetch(FetchDescriptor<Vehicle>()) {
            let copy = Vehicle(id: old.id, name: old.name, make: old.make, modelName: old.modelName,
                               year: old.year, engine: old.engine, plate: old.plate,
                               odometerUnit: old.odometerUnit, tankCapacityGallons: old.tankCapacityGallons,
                               fuelScaleMax: old.fuelScaleMax, fuelScaleStep: old.fuelScaleStep,
                               fuelEconomyReferenceKilometersPerGallon: old.fuelEconomyReferenceKilometersPerGallon,
                               notes: old.notes, createdAt: old.createdAt)
            destination.insert(copy)
            vehiclesByID[old.id] = copy
        }
        for old in try source.fetch(FetchDescriptor<FuelFillEvent>()) {
            destination.insert(FuelFillEvent(
                id: old.id, date: old.date, vehicle: old.vehicle.flatMap { vehiclesByID[$0.id] },
                odometerMilesOriginal: old.odometerMilesOriginal, odometerKilometers: old.odometerKilometers,
                tripMilesOriginal: old.tripMilesOriginal, tripKilometers: old.tripKilometers,
                gallons: old.gallons, pricePerGallon: old.pricePerGallon, totalCost: old.totalCost,
                isFullTank: old.isFullTank, stationName: old.stationName,
                fuelLevelRemaining: old.fuelLevelRemaining, latitude: old.latitude, longitude: old.longitude,
                notes: old.notes, invoiceOCRText: old.invoiceOCRText,
                odometerOCRText: old.odometerOCRText, fuelLevelOCRText: old.fuelLevelOCRText,
                createdAt: old.createdAt, updatedAt: old.updatedAt
            ))
        }
        for old in try source.fetch(FetchDescriptor<SnapshotEvent>()) {
            destination.insert(SnapshotEvent(
                id: old.id, date: old.date, vehicle: old.vehicle.flatMap { vehiclesByID[$0.id] },
                odometerMilesOriginal: old.odometerMilesOriginal, odometerKilometers: old.odometerKilometers,
                tripMilesOriginal: old.tripMilesOriginal, tripKilometers: old.tripKilometers,
                fuelLevelRemaining: old.fuelLevelRemaining, latitude: old.latitude, longitude: old.longitude,
                notes: old.notes, odometerOCRText: old.odometerOCRText,
                fuelLevelOCRText: old.fuelLevelOCRText, createdAt: old.createdAt, updatedAt: old.updatedAt
            ))
        }
        for old in try source.fetch(FetchDescriptor<MonthlyManualAdjustment>()) {
            destination.insert(MonthlyManualAdjustment(
                id: old.id, monthStart: old.monthStart, vehicle: old.vehicle.flatMap { vehiclesByID[$0.id] },
                manualDistanceMiles: old.manualDistanceMiles,
                manualDistanceKilometers: old.manualDistanceKilometers, note: old.note,
                createdAt: old.createdAt, updatedAt: old.updatedAt
            ))
        }
        for old in try source.fetch(FetchDescriptor<ImageAsset>()) {
            destination.insert(ImageAsset(id: old.id, eventID: old.eventID,
                                          ownerType: old.ownerType, kind: old.kind,
                                          localPath: old.localPath, createdAt: old.createdAt))
        }
    }
}

private enum SQLiteStoreBackup {
    static func createAndValidate(source: URL, destination: URL) throws {
        var sourceDB: OpaquePointer?
        var destinationDB: OpaquePointer?
        guard sqlite3_open_v2(source.path, &sourceDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_open_v2(destination.path, &destinationDB, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            if let sourceDB { sqlite3_close(sourceDB) }
            if let destinationDB { sqlite3_close(destinationDB) }
            throw StoreMigrationError.backupFailed("open")
        }
        defer { sqlite3_close(sourceDB); sqlite3_close(destinationDB) }
        guard let backup = sqlite3_backup_init(destinationDB, "main", sourceDB, "main") else {
            throw StoreMigrationError.backupFailed("initialize")
        }
        let stepResult = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw StoreMigrationError.backupFailed("copy")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(destinationDB, "PRAGMA integrity_check", -1, &statement, nil) == SQLITE_OK else {
            throw StoreMigrationError.backupFailed("integrity prepare")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let result = sqlite3_column_text(statement, 0),
              String(cString: result) == "ok" else {
            throw StoreMigrationError.backupFailed("integrity check")
        }
    }
}

private struct BackupManifest: Codable {
    let sourceFingerprint: String
    let backupSHA256: String
}

private enum FileDigest {
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            digest.update(data: chunk)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
