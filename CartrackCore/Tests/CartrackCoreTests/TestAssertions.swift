import XCTest

func XCTAssertEqualOptional(
    _ expression: @autoclosure () throws -> Double?,
    _ expected: Double,
    accuracy: Double,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        let value = try expression()
        guard let value else {
            XCTFail("Expected \(expected), got nil", file: file, line: line)
            return
        }
        XCTAssertEqual(value, expected, accuracy: accuracy, file: file, line: line)
    } catch {
        XCTFail("Expression threw error: \(error)", file: file, line: line)
    }
}
