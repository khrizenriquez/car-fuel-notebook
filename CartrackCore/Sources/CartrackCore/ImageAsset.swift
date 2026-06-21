import Foundation
import SwiftData

@Model
final class ImageAsset {
    @Attribute(.unique) var id: UUID
    var eventID: UUID
    var ownerTypeRawValue: String
    var kindRawValue: String
    var localPath: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        eventID: UUID,
        ownerType: ImageOwnerKind,
        kind: CaptureImageKind,
        localPath: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.eventID = eventID
        self.ownerTypeRawValue = ownerType.rawValue
        self.kindRawValue = kind.rawValue
        self.localPath = localPath
        self.createdAt = createdAt
    }
}

extension ImageAsset {
    var kind: CaptureImageKind {
        get { CaptureImageKind(rawValue: kindRawValue) ?? .invoice }
        set { kindRawValue = newValue.rawValue }
    }

    var ownerType: ImageOwnerKind {
        get { ImageOwnerKind(rawValue: ownerTypeRawValue) ?? .fillUp }
        set { ownerTypeRawValue = newValue.rawValue }
    }
}
