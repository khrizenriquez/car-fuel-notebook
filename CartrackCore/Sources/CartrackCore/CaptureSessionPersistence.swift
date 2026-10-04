import CryptoKit
import Foundation
import SwiftData

@Model
final class CaptureSessionRecord {
    @Attribute(.unique) var id: UUID
    var vehicleID: UUID?
    var kindRawValue: String
    var stateRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var revision: Int64
    var lastErrorCode: String?
    var confirmedEventID: UUID?
    var draftData: Data
    var draftSHA256: String

    init(id: UUID, vehicleID: UUID?, kindRawValue: String, stateRawValue: String,
         createdAt: Date, updatedAt: Date, revision: Int64 = 1,
         lastErrorCode: String? = nil, confirmedEventID: UUID? = nil,
         draftData: Data, draftSHA256: String) {
        self.id = id
        self.vehicleID = vehicleID
        self.kindRawValue = kindRawValue
        self.stateRawValue = stateRawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.lastErrorCode = lastErrorCode
        self.confirmedEventID = confirmedEventID
        self.draftData = draftData
        self.draftSHA256 = draftSHA256
    }
}

@MainActor
final class SwiftDataCaptureSessionRepository: CaptureSessionRepository {
    private let container: ModelContainer
    var beforeSave: (() throws -> Void)?

    init(container: ModelContainer) { self.container = container }

    func create(kind: CaptureSessionKind, vehicleID: UUID?, draft: CaptureDraft) async throws -> CaptureSession {
        try draft.validate(for: kind)
        let context = newContext()
        if let vehicleID, !((try context.fetch(FetchDescriptor<Vehicle>())).contains { $0.id == vehicleID }) {
            throw RepositoryError.notFound
        }
        let encoded = try Self.encode(draft)
        let now = Date.now
        let row = CaptureSessionRecord(id: UUID(), vehicleID: vehicleID,
                                       kindRawValue: kind.rawValue, stateRawValue: CaptureSessionState.draft.rawValue,
                                       createdAt: now, updatedAt: now,
                                       draftData: encoded, draftSHA256: Self.digest(encoded))
        context.insert(row)
        try commit(context)
        return try Self.project(row)
    }

    func find(id: UUID) async throws -> CaptureSession? {
        let context = newContext()
        guard let row = try Self.find(id: id, in: context) else { return nil }
        return try Self.project(row)
    }

    func resumable() async throws -> CaptureSessionRecoveryIndex {
        let context = newContext()
        var sessions: [CaptureSession] = []
        var corrupt: [UUID] = []
        for row in try context.fetch(FetchDescriptor<CaptureSessionRecord>()) {
            guard let state = CaptureSessionState(rawValue: row.stateRawValue) else {
                corrupt.append(row.id)
                continue
            }
            guard state.isResumable else { continue }
            do {
                sessions.append(try Self.project(row))
            } catch CaptureSessionError.corruptDraft {
                corrupt.append(row.id)
            }
        }
        return CaptureSessionRecoveryIndex(
            sessions: sessions.sorted { $0.updatedAt > $1.updatedAt },
            corruptSessionIDs: corrupt.sorted { $0.uuidString < $1.uuidString }
        )
    }

    func updateDraft(id: UUID, expectedRevision: Int64, draft: CaptureDraft) async throws -> CaptureSession {
        let context = newContext()
        guard let row = try Self.find(id: id, in: context) else { throw CaptureSessionError.notFound }
        guard row.revision == expectedRevision else { throw CaptureSessionError.conflict }
        guard let state = CaptureSessionState(rawValue: row.stateRawValue),
              state == .draft || state == .analyzing || state == .review || state == .failedRecoverable,
              let kind = CaptureSessionKind(rawValue: row.kindRawValue) else {
            throw CaptureSessionError.invalidTransition
        }
        try draft.validate(for: kind)
        let encoded = try Self.encode(draft)
        row.draftData = encoded
        row.draftSHA256 = Self.digest(encoded)
        row.revision += 1
        row.updatedAt = .now
        try commit(context)
        return try Self.project(row)
    }

    func transition(id: UUID, expectedRevision: Int64, to state: CaptureSessionState,
                    errorCode: String? = nil, confirmedEventID: UUID? = nil) async throws -> CaptureSession {
        let context = newContext()
        guard let row = try Self.find(id: id, in: context) else { throw CaptureSessionError.notFound }
        guard row.revision == expectedRevision else { throw CaptureSessionError.conflict }
        guard let current = CaptureSessionState(rawValue: row.stateRawValue),
              state != .discarded, CaptureSessionStateMachine.allows(from: current, to: state) else {
            throw CaptureSessionError.invalidTransition
        }
        _ = try Self.project(row)
        if state == .confirmed {
            guard let confirmedEventID else { throw CaptureSessionError.missingConfirmedEventID }
            row.confirmedEventID = confirmedEventID
        } else if confirmedEventID != nil {
            throw CaptureSessionError.invalidTransition
        }
        if state == .failedRecoverable || state == .failedTerminal {
            guard let errorCode, !errorCode.isEmpty else { throw CaptureSessionError.invalidTransition }
            row.lastErrorCode = errorCode
        } else {
            row.lastErrorCode = nil
        }
        row.stateRawValue = state.rawValue
        row.revision += 1
        row.updatedAt = .now
        try commit(context)
        return try Self.project(row)
    }

    func discard(id: UUID, expectedRevision: Int64) async throws {
        let context = newContext()
        guard let row = try Self.find(id: id, in: context) else { throw CaptureSessionError.notFound }
        guard row.revision == expectedRevision else { throw CaptureSessionError.conflict }
        guard let state = CaptureSessionState(rawValue: row.stateRawValue),
              CaptureSessionStateMachine.allows(from: state, to: .discarded) else {
            throw CaptureSessionError.invalidTransition
        }
        let emptyDraft = try Self.encode(CaptureDraft())
        row.draftData = emptyDraft
        row.draftSHA256 = Self.digest(emptyDraft)
        row.stateRawValue = CaptureSessionState.discarded.rawValue
        row.lastErrorCode = nil
        row.revision += 1
        row.updatedAt = .now
        for evidence in try context.fetch(FetchDescriptor<OCRFieldEvidence>()) where evidence.sessionID == id {
            context.delete(evidence)
        }
        try commit(context)
    }

    func recoverInterruptedAnalysis() async throws -> Int {
        let context = newContext()
        let count = try Self.recoverInterruptedAnalysis(in: context)
        if count > 0 { try commit(context) }
        return count
    }

    // Called before the app shows capture UI, so an interrupted Vision task is retryable.
    static func recoverOnLaunch(in container: ModelContainer) throws -> Int {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let count = try recoverInterruptedAnalysis(in: context)
        if count > 0 { try context.save() }
        return count
    }

    private static func recoverInterruptedAnalysis(in context: ModelContext) throws -> Int {
        let rows = try context.fetch(FetchDescriptor<CaptureSessionRecord>())
        var count = 0
        for row in rows where row.stateRawValue == CaptureSessionState.analyzing.rawValue {
            row.stateRawValue = CaptureSessionState.failedRecoverable.rawValue
            row.lastErrorCode = "session.interruptedAnalysis"
            row.revision += 1
            row.updatedAt = .now
            count += 1
        }
        return count
    }

    private func newContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func commit(_ context: ModelContext) throws {
        try beforeSave?()
        try context.save()
    }

    private static func find(id: UUID, in context: ModelContext) throws -> CaptureSessionRecord? {
        try context.fetch(FetchDescriptor<CaptureSessionRecord>()).first { $0.id == id }
    }

    private static func project(_ row: CaptureSessionRecord) throws -> CaptureSession {
        guard let kind = CaptureSessionKind(rawValue: row.kindRawValue),
              let state = CaptureSessionState(rawValue: row.stateRawValue),
              Self.digest(row.draftData) == row.draftSHA256,
              let draft = try? JSONDecoder().decode(CaptureDraft.self, from: row.draftData),
              (try? draft.validate(for: kind)) != nil else {
            throw CaptureSessionError.corruptDraft
        }
        return CaptureSession(id: row.id, vehicleID: row.vehicleID, kind: kind, state: state,
                              createdAt: row.createdAt, updatedAt: row.updatedAt,
                              revision: row.revision, lastErrorCode: row.lastErrorCode,
                              confirmedEventID: row.confirmedEventID, draft: draft)
    }

    private static func encode(_ draft: CaptureDraft) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(draft)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
