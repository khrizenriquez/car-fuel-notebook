import Foundation
import UIKit

enum ImageStorageError: Error {
    case encodingFailed
}

final class ImageStorageService: @unchecked Sendable {
    static let shared = ImageStorageService()

    private let fileManager = FileManager.default

    private init() {}

    func saveImage(_ image: UIImage, preferredName: String = UUID().uuidString) throws -> String {
        let directory = try imagesDirectory()
        let url = directory.appendingPathComponent("\(preferredName).jpg")
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw ImageStorageError.encodingFailed
        }
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        return url.path
    }

    func loadImage(at path: String) -> UIImage? {
        UIImage(contentsOfFile: path)
    }

    func deleteImage(at path: String) {
        guard fileManager.fileExists(atPath: path) else { return }
        try? fileManager.removeItem(atPath: path)
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
