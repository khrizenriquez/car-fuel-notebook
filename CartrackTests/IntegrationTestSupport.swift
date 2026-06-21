import SwiftData
import XCTest
@testable import Cartrack

enum IntegrationTestSupport {
    static func makeInMemoryContext(file: StaticString = #filePath, line: UInt = #line) throws -> ModelContext {
        let container = try CartrackModelContainer.make(isStoredInMemoryOnly: true)
        return ModelContext(container)
    }

    static func count<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }
}
