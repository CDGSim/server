//
//  ResponsePerformanceTests.swift
//  
//
//  Created by Axel Péju on 14/04/2021.
//

@testable import App
import XCTVapor

final class ResponsePerformanceTests: XCTestCase {
    func testIndexResponse() throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configure(app)
        
        measureMetrics([.wallClockTime], automaticallyStartMeasuring: true) {
            _ = try? app.test(.GET, "/") { res in
                stopMeasuring()
            }
        }
    }
    
    func testInstructorResponse() throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configure(app)
        
        measureMetrics([.wallClockTime], automaticallyStartMeasuring: true) {
            _ = try? app.test(.GET, "/instructeur") { res in
                stopMeasuring()
            }
        }
    }
    
    func testPilotResponse() throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configure(app)
        
        measureMetrics([.wallClockTime], automaticallyStartMeasuring: true) {
            _ = try? app.test(.GET, "/pilote") { res in
                stopMeasuring()
            }
        }
    }
}
