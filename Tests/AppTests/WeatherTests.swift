@testable import App
import XCTVapor

final class WeatherTests: XCTestCase {
    func testQNH() throws {
        let weather = Weather(from:"Q1033")
        XCTAssertEqual(weather.qnh, 1033)
    }
    
    func testLowQNH() throws {
        let weather = Weather(from:"Q687")
        XCTAssertEqual(weather.qnh, 687)
    }
    
    func testWind() throws {
        let weather = Weather(from:"12017KT")
        XCTAssertEqual(weather.windDirection, 120)
        XCTAssertEqual(weather.windSpeed, 17)
    }
    
    func testWindWithStrongWind() throws {
        let weather = Weather(from:"120170KT")
        XCTAssertEqual(weather.windDirection, 120)
        XCTAssertEqual(weather.windSpeed, 170)
    }
    
    func testWindWithGust() throws {
        let weather = Weather(from:"12017G35KT")
        XCTAssertEqual(weather.windDirection, 120)
        XCTAssertEqual(weather.windSpeed, 17)
        XCTAssertEqual(weather.windGust, 35)
    }
    
    func testVisibilityCAVOK() throws {
        let weather = Weather(from:"CAVOK")
        XCTAssertEqual(weather.visibility, 9999)
    }
    
    func testVisibility2000() throws {
        let weather = Weather(from:"2000")
        XCTAssertEqual(weather.visibility, 2000)
    }
    
    func testTemperature() throws {
        let weather = Weather(from:"15/12")
        XCTAssertEqual(weather.temperature, 15)
        XCTAssertEqual(weather.dewPoint, 12)
    }
    
    func testNegativeTemperature() throws {
        let weather = Weather(from:"M15/M17")
        XCTAssertEqual(weather.temperature, -15)
        XCTAssertEqual(weather.dewPoint, -17)
    }
    
    func testSampleMETAR() throws {
        let weather = Weather(from:"10022G34KT 9999 -RA FEW025 BKN032 BKN150 06/M01 Q1002")
        XCTAssertEqual(weather.temperature, 6)
        XCTAssertEqual(weather.dewPoint, -1)
        XCTAssertEqual(weather.windDirection, 100)
        XCTAssertEqual(weather.windSpeed, 22)
        XCTAssertEqual(weather.windGust, 34)
        XCTAssertEqual(weather.visibility, 9999)
        XCTAssertEqual(weather.qnh, 1002)
    }
    
    func testSampleMETAR2() throws {
        let weather = Weather(from:"Q1015 24005KT BKN040 M01/M05 R27L/1500")
        XCTAssertEqual(weather.temperature, -1)
        XCTAssertEqual(weather.dewPoint, -5)
        XCTAssertEqual(weather.windDirection, 240)
        XCTAssertEqual(weather.windSpeed, 05)
        XCTAssertEqual(weather.windGust, 0)
        XCTAssertEqual(weather.qnh, 1015)
        XCTAssertEqual(weather.northRunway2RVR, 1500)
        XCTAssertEqual(weather.ceiling, 4000)
    }
    
    func testRVR() throws {
        let weather = Weather(from:"R27R/1500 R08L/1000 R09R/900 R26L/750")
        XCTAssertEqual(weather.northRunway1RVR, 1500)
        XCTAssertEqual(weather.northRunway2RVR, 900)
        XCTAssertEqual(weather.southRunway1RVR, 1000)
        XCTAssertEqual(weather.southRunway2RVR, 750)
    }
}
