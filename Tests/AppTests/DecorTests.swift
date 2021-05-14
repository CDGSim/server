@testable import App
import XCTVapor

final class DecorTests: XCTestCase {
    
    func testJanuarySunset() throws {
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 1, day: 1).1, "16:03")
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 1, day: 2).1, "16:03")
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 1, day: 3).1, "16:03")
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 1, day: 4).1, "16:06")
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 1, day: 16).1, "16:22")
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 1, day: 31).1, "16:46")
    }
    
    func testRandomHours() throws {
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 13, day: 13).1, "")
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 2, day: 40).1, "")
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 2, day: 13).1, "17:07")
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 6, day: 4).0, "03:52")
        XCTAssertEqual(DecorController.sunriseAndSunsetHours(month: 12, day: 21).1, "15:54")
    }
    
    func testTransitionLevels() throws {
        XCTAssertEqual(DecorController.transitionLevel(for:1048), 60)
        XCTAssertEqual(DecorController.transitionLevel(for:1013), 60)
        XCTAssertEqual(DecorController.transitionLevel(for:1012), 70)
        XCTAssertEqual(DecorController.transitionLevel(for:977), 70)
        XCTAssertEqual(DecorController.transitionLevel(for:976), 80)
        XCTAssertEqual(DecorController.transitionLevel(for:970), 80)
    }
}
