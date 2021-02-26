@testable import App
import XCTVapor

final class DecorTests: XCTestCase {
    
    func testJanuarySunset() throws {
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 1, day: 1).1, "16:11")
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 1, day: 2).1, "16:11")
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 1, day: 3).1, "16:11")
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 1, day: 4).1, "16:14")
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 1, day: 16).1, "16:30")
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 1, day: 31).1, "16:54")
    }
    
    func testRandomHours() throws {
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 13, day: 13).1, "")
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 2, day: 40).1, "")
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 2, day: 13).1, "17:15")
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 6, day: 4).0, "04:00")
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 12, day: 21).1, "16:02")
    }
}
