import Foundation
import UIKit

enum ImageStorageError: Error {
    case encodingFailed
    case unreadableSavedImage
}

final class ImageStorageService: @unchecked Sendable {
    static let shared = ImageStorageService()

    private let fileManager = FileManager.default

    private init() {}

    func saveImage(_ image: UIImage, preferredName: String = UUID().uuidString) throws -> String {
        let optimized = try CapturePhotoStore.encodeOptimizedJPEG(image)
        return try saveImageData(optimized.data, preferredName: preferredName)
    }

    func loadImage(at path: String) -> UIImage? {
        UIImage(contentsOfFile: path)
    }

    func loadImageData(at path: String) -> Data? {
        fileManager.contents(atPath: path)
    }

    func saveImageData(_ data: Data, preferredName: String = UUID().uuidString) throws -> String {
        let directory = try imagesDirectory()
        let url = directory.appendingPathComponent("\(preferredName).jpg")
        do {
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
            guard UIImage(contentsOfFile: url.path) != nil else {
                throw ImageStorageError.unreadableSavedImage
            }
            return url.path
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
    }

    func deleteImage(at path: String) throws {
        guard fileManager.fileExists(atPath: path) else { return }
        try fileManager.removeItem(atPath: path)
    }

    func clearAllImages() throws {
        let directory = try imagesDirectory()
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    private func imagesDirectory() throws -> URL {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("CartrackImages", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableDirectory = directory
            try mutableDirectory.setResourceValues(resourceValues)
        }
        return directory
    }
}

enum LocalDiagnosticCode: String, Codable, CaseIterable {
    case insufficientStorage = "storage.insufficientSpace"
    case evidenceUnavailable = "evidence.unavailable"
    case evidenceIntegrity = "evidence.integrity"
    case backupRejected = "backup.rejected"
    case backupRecoveryFailed = "backup.recoveryFailed"
    case persistenceUnavailable = "persistence.unavailable"
    case captureRecoverable = "capture.recoverable"
    case localOperationFailed = "local.operationFailed"
}

struct LocalDiagnosticIncident: Codable, Equatable {
    let code: LocalDiagnosticCode
    let operation: String
    let occurredAt: Date
    let recommendedAction: String
}

struct LocalDiagnosticReport: Codable, Equatable {
    let formatVersion: Int
    let generatedAt: Date
    let incidents: [LocalDiagnosticIncident]
}

struct LocalErrorRecovery: Equatable {
    let code: LocalDiagnosticCode
    let message: String
    let recommendedAction: String
}

/// Stores only stable error categories, timestamps and non-sensitive operation names. It never
/// serializes an Error description because those descriptions may contain filenames or user input.
enum LocalDiagnosticsService {
    private static let incidentsKey = "diagnostics.local.incidents.v1"
    private static let maxIncidents = 30
    private static let allowedOperations: Set<String> = [
        "app.start",
        "backup.export", "backup.import", "backup.select", "vehicle.reset",
        "capture.fillup.analyze", "capture.fillup.save", "capture.fillup.draft",
        "capture.snapshot.analyze", "capture.snapshot.save", "capture.snapshot.draft",
        "vehicle.save", "vehicle.delete", "history.delete", "dashboard.adjustment",
        "report.export", "diagnostics.export"
    ]

    static func recovery(for error: Error, operation: String,
                         userDefaults: UserDefaults = .standard,
                         now: Date = .now) -> LocalErrorRecovery {
        let recovery = classify(error)
        record(code: recovery.code, operation: operation,
               recommendedAction: recovery.recommendedAction, userDefaults: userDefaults, now: now)
        return recovery
    }

    static func report(userDefaults: UserDefaults = .standard, now: Date = .now) -> LocalDiagnosticReport {
        LocalDiagnosticReport(formatVersion: 1, generatedAt: now, incidents: incidents(userDefaults: userDefaults))
    }

    static func export(userDefaults: UserDefaults = .standard, now: Date = .now,
                       directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report(userDefaults: userDefaults, now: now))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: now)
            .replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("Cartrack-Diagnostic-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func clear(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: incidentsKey)
    }

    private static func incidents(userDefaults: UserDefaults) -> [LocalDiagnosticIncident] {
        guard let data = userDefaults.data(forKey: incidentsKey),
              let decoded = try? JSONDecoder().decode([LocalDiagnosticIncident].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func record(code: LocalDiagnosticCode, operation: String,
                               recommendedAction: String, userDefaults: UserDefaults, now: Date) {
        let incident = LocalDiagnosticIncident(code: code,
                                                operation: allowedOperations.contains(operation) ? operation : "local.operation",
                                                occurredAt: now, recommendedAction: recommendedAction)
        let retained = Array((incidents(userDefaults: userDefaults) + [incident]).suffix(maxIncidents))
        if let data = try? JSONEncoder().encode(retained) {
            userDefaults.set(data, forKey: incidentsKey)
        }
    }

    private static func classify(_ error: Error) -> LocalErrorRecovery {
        let code: LocalDiagnosticCode
        switch error {
        case StoreMigrationError.insufficientSpace:
            code = .insufficientStorage
        case StoreMigrationError.invalidActiveStore, StoreMigrationError.validationFailed,
             StoreMigrationError.backupFailed(_), StoreMigrationError.migrationInProgress:
            code = .persistenceUnavailable
        case BackupTransferError.rollbackFailed:
            code = .backupRecoveryFailed
        case is BackupTransferError:
            code = .backupRejected
        case CapturePhotoStoreError.integrityMismatch, CapturePhotoStoreError.invalidRelativePath,
             CapturePhotoStoreError.optimizedImageDegraded:
            code = .evidenceIntegrity
        case is CapturePhotoStoreError, is ImageStorageError, is CaptureImagePipelineError:
            code = .evidenceUnavailable
        case is CaptureSessionError, is CaptureConfirmationError:
            code = .captureRecoverable
        default:
            let nsError = error as NSError
            code = nsError.domain == NSCocoaErrorDomain &&
                nsError.code == CocoaError.Code.fileWriteOutOfSpace.rawValue
                ? .insufficientStorage : .localOperationFailed
        }
        return recovery(for: code)
    }

    private static func recovery(for code: LocalDiagnosticCode) -> LocalErrorRecovery {
        switch code {
        case .insufficientStorage:
            .init(code: code, message: AppCopy.text("No hay espacio suficiente para terminar la operación.", "There is not enough storage space to finish this operation."),
                  recommendedAction: AppCopy.text("Libera espacio y vuelve a intentar; el borrador y los datos confirmados se conservan.", "Free up space and try again; drafts and confirmed data are preserved."))
        case .evidenceUnavailable:
            .init(code: code, message: AppCopy.text("No se pudo guardar o leer la evidencia local.", "The local evidence could not be saved or read."),
                  recommendedAction: AppCopy.text("Reintenta con la foto; no se guardó un registro incompleto.", "Try the photo again; no incomplete record was saved."))
        case .evidenceIntegrity:
            .init(code: code, message: AppCopy.text("La evidencia local no pasó la verificación de integridad.", "The local evidence did not pass its integrity check."),
                  recommendedAction: AppCopy.text("Conserva el borrador y toma nuevamente sólo la foto afectada.", "Keep the draft and retake only the affected photo."))
        case .backupRejected:
            .init(code: code, message: AppCopy.text("El respaldo no se pudo validar y no se modificaron tus datos locales.", "The backup could not be validated and your local data was not changed."),
                  recommendedAction: AppCopy.text("Elige otro respaldo o vuelve a exportarlo desde el dispositivo de origen.", "Choose a different backup or export it again from the source device."))
        case .backupRecoveryFailed:
            .init(code: code, message: AppCopy.text("La restauración no pudo confirmar una recuperación automática.", "The restore could not confirm an automatic recovery."),
                  recommendedAction: AppCopy.text("No borres la app; exporta el diagnóstico y conserva el respaldo seleccionado.", "Do not delete the app; export the diagnostic and keep the selected backup."))
        case .persistenceUnavailable:
            .init(code: code, message: AppCopy.text("La base local no está disponible para esta operación.", "The local database is unavailable for this operation."),
                  recommendedAction: AppCopy.text("Cierra y abre la app; revisa el espacio disponible antes de borrar datos.", "Close and reopen the app; check available storage before deleting any data."))
        case .captureRecoverable:
            .init(code: code, message: AppCopy.text("No se pudo completar la captura, pero el borrador se puede reanudar.", "The capture could not be completed, but the draft can be resumed."),
                  recommendedAction: AppCopy.text("Vuelve a Capturar y continúa el borrador o corrige los campos marcados.", "Return to Capture and continue the draft or correct the marked fields."))
        case .localOperationFailed:
            .init(code: code, message: AppCopy.text("La operación local no se pudo completar.", "The local operation could not be completed."),
                  recommendedAction: AppCopy.text("Vuelve a intentarlo. Si persiste, exporta el diagnóstico redactado.", "Try again. If it persists, export the redacted diagnostic."))
        }
    }
}
