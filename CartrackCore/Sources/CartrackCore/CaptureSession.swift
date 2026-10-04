import Foundation

enum CaptureSessionKind: String, Codable, Sendable {
    case fillUp
    case snapshot
}

enum CaptureSessionState: String, Codable, Sendable {
    case draft
    case analyzing
    case review
    case confirmed
    case failedRecoverable
    case failedTerminal
    case discarded

    var isResumable: Bool {
        switch self {
        case .draft, .review, .failedRecoverable: true
        case .analyzing, .confirmed, .failedTerminal, .discarded: false
        }
    }
}

struct CaptureDraft: Codable, Equatable, Sendable {
    var version: Int = 1
    var occurredAt: Date?
    var odometerKilometers: Decimal?
    var tripKilometers: Decimal?
    var fuelLevelRemaining: Decimal?
    var volumeGallons: Decimal?
    var unitPrice: Decimal?
    var totalCost: Decimal?
    var currencyCode: String = "GTQ"
    var isFullTank: Bool?
    var stationName: String?
    var notes: String?
    var odometerOverrideReason: String?
    var photoIDs: [UUID] = []
    /// Explicit user corrections survive OCR retries for an individual photo.
    var manuallyEditedFields: [CaptureField]? = nil

    func isManuallyEdited(_ field: CaptureField) -> Bool {
        manuallyEditedFields?.contains(field) == true
    }

    mutating func setManualNumber(_ value: Decimal?, for field: CaptureField) {
        let keyPath: WritableKeyPath<CaptureDraft, Decimal?>
        switch field {
        case .odometerKilometers: keyPath = \.odometerKilometers
        case .tripKilometers: keyPath = \.tripKilometers
        case .fuelLevelRemaining: keyPath = \.fuelLevelRemaining
        case .volumeGallons: keyPath = \.volumeGallons
        case .unitPrice: keyPath = \.unitPrice
        case .totalCost: keyPath = \.totalCost
        case .stationName, .occurredAt: return
        }
        let previous = self[keyPath: keyPath]
        let isFormattingEquivalent: Bool
        if let previous, let value,
           field == .odometerKilometers || field == .tripKilometers {
            let difference = previous < value ? value - previous : previous - value
            isFormattingEquivalent = difference <= Decimal(string: "0.02")!
        } else {
            isFormattingEquivalent = previous == value
        }
        if !isFormattingEquivalent {
            var edited = Set(manuallyEditedFields ?? [])
            edited.insert(field)
            manuallyEditedFields = edited.sorted { $0.rawValue < $1.rawValue }
        }
        self[keyPath: keyPath] = value
    }

    func validate(for kind: CaptureSessionKind) throws {
        guard version == 1 else { throw CaptureSessionError.unsupportedDraftVersion }
        guard photoIDs.count == Set(photoIDs).count else { throw CaptureSessionError.invalidDraft }
        if let manuallyEditedFields,
           manuallyEditedFields.count != Set(manuallyEditedFields).count {
            throw CaptureSessionError.invalidDraft
        }
        if kind == .snapshot,
           volumeGallons != nil || unitPrice != nil || totalCost != nil || isFullTank != nil {
            throw CaptureSessionError.invalidDraft
        }
    }
}

struct CaptureSession: Equatable, Sendable {
    let id: UUID
    let vehicleID: UUID?
    let kind: CaptureSessionKind
    let state: CaptureSessionState
    let createdAt: Date
    let updatedAt: Date
    let revision: Int64
    let lastErrorCode: String?
    let confirmedEventID: UUID?
    let draft: CaptureDraft
}

struct CaptureSessionRecoveryIndex: Equatable, Sendable {
    let sessions: [CaptureSession]
    let corruptSessionIDs: [UUID]
}

enum CaptureSessionError: Error, Equatable, Sendable {
    case notFound
    case conflict
    case invalidTransition
    case invalidDraft
    case unsupportedDraftVersion
    case corruptDraft
    case missingConfirmedEventID

    var code: String {
        switch self {
        case .notFound: "session.notFound"
        case .conflict: "repository.conflict"
        case .invalidTransition: "session.invalidTransition"
        case .invalidDraft: "session.invalidDraft"
        case .unsupportedDraftVersion: "session.unsupportedDraftVersion"
        case .corruptDraft: "session.corruptDraft"
        case .missingConfirmedEventID: "session.missingConfirmedEventID"
        }
    }
}

enum CaptureSessionStateMachine {
    static func allows(from: CaptureSessionState, to: CaptureSessionState) -> Bool {
        switch (from, to) {
        case (.draft, .analyzing), (.draft, .discarded),
             (.analyzing, .review), (.analyzing, .failedRecoverable),
             (.analyzing, .failedTerminal), (.analyzing, .discarded),
             (.review, .analyzing), (.review, .confirmed), (.review, .discarded),
             (.failedRecoverable, .analyzing), (.failedRecoverable, .discarded),
             (.failedTerminal, .discarded):
            true
        default:
            false
        }
    }
}

@MainActor
protocol CaptureSessionRepository {
    func create(kind: CaptureSessionKind, vehicleID: UUID?, draft: CaptureDraft) async throws -> CaptureSession
    func find(id: UUID) async throws -> CaptureSession?
    func resumable() async throws -> CaptureSessionRecoveryIndex
    func updateDraft(id: UUID, expectedRevision: Int64, draft: CaptureDraft) async throws -> CaptureSession
    func transition(id: UUID, expectedRevision: Int64, to state: CaptureSessionState,
                    errorCode: String?, confirmedEventID: UUID?) async throws -> CaptureSession
    func discard(id: UUID, expectedRevision: Int64) async throws
    func recoverInterruptedAnalysis() async throws -> Int
}
