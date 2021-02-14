//
//  File.swift
//  
//
//  Created by Axel Péju on 13/02/2021.
//

import Vapor
import SimlogCore

struct DecorController {
    // MARK:- Time Formatter
    static private var timeFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HHmm"
        return dateFormatter
    }()
    
    // MARK:- Random generation
    static private let pseudoRandomIntegerDateFormatter = DateFormatter()
    
    static private func pseudoRandomInteger(pattern:String, changeInterval:Int) -> Int {
        self.pseudoRandomIntegerDateFormatter.dateFormat = pattern
        
        let pseudoRandomString = self.pseudoRandomIntegerDateFormatter.string(from: Date())
        
        self.pseudoRandomIntegerDateFormatter.dateFormat = "mm"
        let changeIntervalFactor:Int
        if changeInterval > 0 {
            changeIntervalFactor = Int(self.pseudoRandomIntegerDateFormatter.string(from: Date())) ?? 0 / changeInterval
        } else {
            changeIntervalFactor = 0
        }
        
        return changeIntervalFactor + pseudoRandomString.components(separatedBy: ".")
            .map({ (Int($0) ?? 0) })
            .reduce(0) { result, index -> Int in
                result + index
            }
    }
    
    // MARK:- METAR Decoding
    struct Weather {
        var qnh: Int = 0
        var windDirection: Int = 0
        var windSpeed: Int = 0
        var windGust: Int = 0
        var visibility: Int = 0
        var temperature: Int = 0
        var dewPoint: Int = 0
        var northRunway1RVR: Int = 9999
        var northRunway2RVR: Int = 9999
        var southRunway1RVR: Int = 9999
        var southRunway2RVR: Int = 9999
        var ceiling: Int = 10000
        
        init(from metarString:String) {
            let components = metarString.components(separatedBy: " ")
            
            for component in components {
                // Decode QNH
                if component.count == 5 && component.first == "Q" {
                    let qnhString = component.suffix(from: component.index(component.firstIndex(of: "Q")!, offsetBy: 1))
                    qnh = Int(qnhString) ?? 1013
                }
                
                // Decode wind
                if component.count >= 7 && component.count <= 11 && component.hasSuffix("KT") {
                    let numericPrefix = component.prefix(while: { "0"..."9" ~= $0 })
                    windDirection = Int(numericPrefix.prefix(3)) ?? 0
                    let endIndex = component.firstIndex(of: "K")!
                    if let gustIndex = component.firstIndex(of: "G") {
                        windGust = Int(component[component.index(gustIndex,offsetBy:1)..<endIndex]) ?? 0
                        windSpeed = Int(component[component.index(component.startIndex, offsetBy: 3)..<gustIndex]) ?? 0
                    } else {
                        windSpeed = Int(component[component.index(component.startIndex, offsetBy: 3)..<endIndex]) ?? 0
                    }
                }
                
                // Decode visibility
                if component.count == 4 || component == "CAVOK" {
                    if component == "CAVOK" {
                        visibility = 9999
                    } else {
                        visibility = Int(component) ?? 9999
                    }
                }
                
                // Decode temperature
                if let separatorIndex = component.firstIndex(of: "/"), component.first != "R" {
                    let temperatureString = component.prefix(upTo: separatorIndex)
                    if temperatureString.first == "M" {
                        temperature = 0 - (Int(temperatureString.suffix(from: temperatureString.index(after: temperatureString.startIndex))) ?? 0)
                    } else {
                        temperature = Int(temperatureString) ?? 0
                    }
                    let dewPointString = component.suffix(from: component.index(after:separatorIndex))
                    if dewPointString.first == "M" {
                        dewPoint = 0 - (Int(dewPointString.suffix(from: dewPointString.index(after: dewPointString.startIndex))) ?? 0)
                    } else {
                        dewPoint = Int(dewPointString) ?? 0
                    }
                }
                
                // Decode RVRs
                if let separatorIndex = component.firstIndex(of: "/"), component.first == "R" {
                    let runway = component[component.index(after: component.startIndex)..<separatorIndex]
                    let rvr = Int(component.suffix(from: component.index(after: separatorIndex))) ?? 0
                    if runway == "27R" || runway == "09L" {
                        northRunway1RVR = rvr
                    } else if runway == "27L" || runway == "09R" {
                        northRunway2RVR = rvr
                    } else if runway == "26R" || runway == "08L" {
                        southRunway1RVR = rvr
                    } else if runway == "26L" || runway == "08R" {
                        southRunway2RVR = rvr
                    }
                }
                
                // Decode ceiling
                if component.count == 6 && ( component.prefix(3) == "OVC" || component.prefix(3) == "BKN" ) {
                    let value = component.suffix(from: component.firstIndex(where: { "0"..."9" ~= $0 })!)
                    ceiling = (Int(value) ?? 0) * 100
                }
            }
        }
    }
    
    // MARK:- View
    static func view(req:Request, log:Log) -> EventLoopFuture<View> {
        
        // Weather
        let weather = Weather(from: log.properties.weather)
        let qnh: Int = weather.qnh > 0 ? weather.qnh : log.properties.pressure
        
        // Wind
        let windDirection = weather.windDirection
        let windSpeed = weather.windSpeed
        
        let northWindDirection = windDirection + Int.pseudoRandom(in: -1...3, changeEvery: 10)*5
        let southWindDirection = windDirection - Int.pseudoRandom(in: -2...1, changeEvery: 7)*5
        let northWindSpeed = windSpeed - Int.pseudoRandom(in: -1...3, changeEvery: 6)
        let southWindSpeed = windSpeed + Int.pseudoRandom(in: -2...4, changeEvery: 7)
        
        let northWind = DecorContext.Wind(direction: northWindDirection, speed: northWindSpeed)
        let southWind = DecorContext.Wind(direction: southWindDirection, speed: southWindSpeed)
        
        // ATIS Letter
        let pgRandomIndex = Self.pseudoRandomInteger(pattern: "M.d.HH", changeInterval: 40)
        let pbRandomIndex = Self.pseudoRandomInteger(pattern: "M.HH", changeInterval: 50)
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let atispg = String(letters[letters.index(letters.startIndex, offsetBy: pgRandomIndex % 26)])
        let atislb = String(letters[letters.index(letters.startIndex, offsetBy: pbRandomIndex % 26)])
        
        // Transition level
        let transitionAltitude = 5000 + 28 * (1013 - qnh)
        let transitionLevel = Int(ceil(Double(transitionAltitude)/1000))*10 + 10
        
        // Configuration
        let configuration = log.properties.configuration.capitalized
        
        // Start time        
        let startTime = Self.timeFormatter.string(from: log.properties.startDate)
        
        // RVR
        let northRunway1RVR = weather.northRunway1RVR <= 2000 ? String(weather.northRunway1RVR) : ">>>>"
        let northRunway2RVR = weather.northRunway2RVR <= 2000 ? String(weather.northRunway2RVR) : ">>>>"
        let southRunway1RVR = weather.southRunway1RVR <= 2000 ? String(weather.southRunway1RVR) : ">>>>"
        let southRunway2RVR = weather.southRunway2RVR <= 2000 ? String(weather.southRunway2RVR) : ">>>>"
        
        // HBN
        let hbn27 = weather.ceiling < 1000 ? String(weather.ceiling) : ">>>>"
        let hbn26 = weather.ceiling < 1000 ? String(weather.ceiling) : ">>>>"
        let hbn09 = weather.ceiling < 1000 ? String(weather.ceiling) : ">>>>"
        let hbn08 = weather.ceiling < 1000 ? String(weather.ceiling) : ">>>>"
        
        let preLVPNorth = weather.ceiling < 300 || weather.northRunway1RVR < 800 || weather.northRunway2RVR < 800
        let LVPNorth = weather.ceiling <= 200 || weather.northRunway1RVR <= 600 || weather.northRunway2RVR <= 600
        let preLVPSouth = weather.ceiling < 300 || weather.southRunway1RVR < 800 || weather.southRunway2RVR < 800
        let LVPSouth = weather.ceiling <= 200 || weather.southRunway1RVR <= 600 || weather.southRunway2RVR <= 600
        
        struct DecorContext: Encodable {
            struct Wind: Encodable {
                let direction:Int
                let speed:Int
            }
            
            let qnh:String
            let qfe:String
            let transitionLevel:Int
            let temperature:Int
            let dewPoint:Int
            let northWind:Wind
            let southWind:Wind
            let atispg:String
            let atislb:String
            let configuration:String
            let weather:String
            let startTime:String
            let northRunway1RVR:String
            let northRunway2RVR:String
            let southRunway1RVR:String
            let southRunway2RVR:String
            let hbn27:String
            let hbn26:String
            let hbn09:String
            let hbn08:String
            let preLVPNorth: Bool
            let LVPNorth: Bool
            let preLVPSouth: Bool
            let LVPSouth: Bool
        }
        
        let pressureFormatter = NumberFormatter()
        pressureFormatter.minimumIntegerDigits = 4
        
        return req.view.render("decor", DecorContext(qnh: pressureFormatter.string(from: NSNumber(value: qnh)) ?? "",
                                                     qfe: pressureFormatter.string(from: NSNumber(value: qnh - 17)) ?? "",
                                                     transitionLevel: transitionLevel,
                                                     temperature: weather.temperature,
                                                     dewPoint: weather.dewPoint,
                                                     northWind: northWind,
                                                     southWind: southWind,
                                                     atispg: atispg,
                                                     atislb: atislb,
                                                     configuration: configuration,
                                                     weather:log.properties.weather,
                                                     startTime:startTime,
                                                     northRunway1RVR:northRunway1RVR,
                                                     northRunway2RVR:northRunway2RVR,
                                                     southRunway1RVR:southRunway1RVR,
                                                     southRunway2RVR:southRunway2RVR,
                                                     hbn27:hbn27,
                                                     hbn26:hbn26,
                                                     hbn09:hbn09,
                                                     hbn08:hbn08,
                                                     preLVPNorth: preLVPNorth,
                                                     LVPNorth: LVPNorth,
                                                     preLVPSouth: preLVPSouth,
                                                     LVPSouth: LVPSouth
                                                     ))
    }
}

extension Int {
    // Returns a pseudo random integer in range
    // The integer depends on the date
    static func pseudoRandom(in range:ClosedRange<Int>, changeEvery minutes:Int) -> Int {
        let timeString = self.timeFormatter.string(from: Date())
        let hourRandom = Int(timeString.prefix(2)) ?? 0 // an integer between 0 and 23
        let minuteRandom = Int(timeString.suffix(from: timeString.index(timeString.startIndex, offsetBy: 2))) ?? 0 // an integer between 0 and 59
        let random = hourRandom + minuteRandom/minutes // an integer between 0 and 82
        return range.lowerBound + (range.upperBound - range.lowerBound)*random/82
    }
    
    static private var timeFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HHmm"
        return dateFormatter
    }()
}
