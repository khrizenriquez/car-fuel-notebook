import CryptoKit
import Foundation
import UIKit

enum CapturePhotoStoreError: Error {
    case encodingFailed
    case invalidRelativePath
    case unreadableSavedImage
    case integrityMismatch
    case optimizedImageDegraded
    case storageBudgetExceeded
}

/// Original capture evidence lives locally until T14 verifies its optimized replacement.
struct CapturePhotoStore {
    static let optimizedJPEGQuality: CGFloat = 0.72
    /// Five capture records weekly with two retained photos each stays below 250 MB/year.
    static let maxOptimizedByteCount = 450_000
    private let rootURL: URL?
    private let fileManager = FileManager.default

    init(rootURL: URL? = nil) {
        self.rootURL = rootURL
    }

    func save(_ image: UIImage, sessionID: UUID, kind: CaptureImageKind) throws -> LocalPhotoRecord {
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            throw CapturePhotoStoreError.encodingFailed
        }
        let id = UUID()
        let relativePath = "CaptureSessions/\(sessionID.uuidString)/\(id.uuidString).jpg"
        let url = try resolvedURL(for: relativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        do {
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
            guard let savedImage = UIImage(contentsOfFile: url.path),
                  let cgImage = savedImage.cgImage else {
                throw CapturePhotoStoreError.unreadableSavedImage
            }
            let sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return LocalPhotoRecord(id: id, sessionID: sessionID, eventID: nil,
                                    kind: kind.rawValue, localRelativePath: relativePath,
                                    sha256: sha256, pixelWidth: cgImage.width,
                                    pixelHeight: cgImage.height, byteCount: data.count,
                                    mimeType: "image/jpeg", capturedAt: .now,
                                    optimizationState: "original", createdAt: .now)
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
    }

    func load(_ record: LocalPhotoRecord) throws -> UIImage {
        let url = try resolvedURL(for: record)
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == record.sha256 else { throw CapturePhotoStoreError.integrityMismatch }
        guard let image = UIImage(data: data) else {
            throw CapturePhotoStoreError.unreadableSavedImage
        }
        return image
    }

    func remove(_ record: LocalPhotoRecord) throws {
        let url = try resolvedURL(for: record)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    func absolutePath(for record: LocalPhotoRecord) throws -> String {
        try resolvedURL(for: record).path
    }

    func evidenceRootURL() throws -> URL { try rootDirectory() }

    /// Stages a verified replacement under a new name. The caller updates database references
    /// before deleting the original, so a failed save never destroys the source evidence.
    func optimizedCopy(of record: LocalPhotoRecord,
                       beforeReturn: (() throws -> Void)? = nil) throws -> LocalPhotoRecord {
        guard let sessionID = record.sessionID else { throw CapturePhotoStoreError.invalidRelativePath }
        let source = try load(record)
        let optimizedJPEG = try Self.encodeOptimizedJPEG(source)
        let bytes = optimizedJPEG.data
        let width = optimizedJPEG.width
        let height = optimizedJPEG.height
        let relativePath = "CaptureSessions/\(sessionID.uuidString)/\(UUID().uuidString).jpg"
        let url = try resolvedURL(for: relativePath)
        do {
            try bytes.write(to: url, options: .atomic)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
            let persisted = try Data(contentsOf: url)
            guard persisted == bytes, let verifiedImage = UIImage(data: persisted),
                  let verified = verifiedImage.cgImage,
                  verified.width == width, verified.height == height,
                  max(verified.width, verified.height) <= 2_000 else {
                throw CapturePhotoStoreError.optimizedImageDegraded
            }
            let declaredKind = CaptureImageKind(rawValue: record.kind)
            let pipeline = CaptureImagePipeline()
            let originalQuality = try pipeline.prepare(source, declaredKind: declaredKind).quality
            let optimizedQuality = try pipeline.prepare(verifiedImage, declaredKind: declaredKind).quality
            for issue in [CaptureImageIssue.lowResolution, .tooBlurred, .overexposed, .underexposed] {
                if optimizedQuality.issues.contains(issue) && !originalQuality.issues.contains(issue) {
                    throw CapturePhotoStoreError.optimizedImageDegraded
                }
            }
            try beforeReturn?()
            return LocalPhotoRecord(
                id: record.id, sessionID: record.sessionID, eventID: record.eventID,
                kind: record.kind, localRelativePath: relativePath,
                sha256: SHA256.hash(data: persisted).map { String(format: "%02x", $0) }.joined(),
                pixelWidth: width, pixelHeight: height, byteCount: persisted.count,
                mimeType: "image/jpeg", capturedAt: record.capturedAt,
                optimizationState: "optimized", createdAt: record.createdAt
            )
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
    }

    static func encodeOptimizedJPEG(_ image: UIImage) throws -> (data: Data, width: Int, height: Int) {
        guard let sourceCG = image.cgImage else { throw CapturePhotoStoreError.unreadableSavedImage }
        let scale = min(1.0, 2_000.0 / Double(max(sourceCG.width, sourceCG.height)))
        var width = max(1, Int((Double(sourceCG.width) * scale).rounded()))
        var height = max(1, Int((Double(sourceCG.height) * scale).rounded()))
        while true {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let resized = UIGraphicsImageRenderer(size: CGSize(width: width, height: height),
                                                  format: format).image { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            guard let data = resized.jpegData(compressionQuality: optimizedJPEGQuality) else {
                throw CapturePhotoStoreError.encodingFailed
            }
            if data.count <= maxOptimizedByteCount { return (data, width, height) }
            guard max(width, height) > 300 else { throw CapturePhotoStoreError.storageBudgetExceeded }
            let reduction = min(0.9, max(0.5,
                sqrt(Double(maxOptimizedByteCount) / Double(data.count)) * 0.97))
            let nextWidth = max(300, Int((Double(width) * reduction).rounded(.down)))
            let nextHeight = max(300, Int((Double(height) * reduction).rounded(.down)))
            guard nextWidth < width || nextHeight < height else {
                throw CapturePhotoStoreError.storageBudgetExceeded
            }
            width = nextWidth
            height = nextHeight
        }
    }

    private func resolvedURL(for record: LocalPhotoRecord) throws -> URL {
        guard let sessionID = record.sessionID,
              record.localRelativePath.hasPrefix("CaptureSessions/\(sessionID.uuidString)/") else {
            throw CapturePhotoStoreError.invalidRelativePath
        }
        return try resolvedURL(for: record.localRelativePath)
    }

    private func resolvedURL(for relativePath: String) throws -> URL {
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "CaptureSessions",
              UUID(uuidString: String(parts[1])) != nil,
              String(parts[2]).hasSuffix(".jpg"),
              UUID(uuidString: String(parts[2].dropLast(4))) != nil else {
            throw CapturePhotoStoreError.invalidRelativePath
        }
        let root = try rootDirectory()
        return root.appendingPathComponent(relativePath)
    }

    private func rootDirectory() throws -> URL {
        let root: URL
        if let rootURL {
            root = rootURL
        } else {
            root = try fileManager.url(for: .applicationSupportDirectory,
                                       in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("CartrackImages", isDirectory: true)
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = root
        try mutableRoot.setResourceValues(values)
        return root
    }
}
