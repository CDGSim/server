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
        var cloudLayers: [String] = []
        var weatherEvents: [String] = []
        
        init(from metarString:String) {
            let components = metarString.components(separatedBy: " ")
            
            for component in components {
                // Decode QNH
                if component.first == "Q" {
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
                        visibility = 10000
                        cloudLayers = ["CAVOK"]
                    } else if let value = Int(component) {
                        visibility = value
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
                if component.count == 6 && ["OVC", "BKN", "FEW", "SCT"].contains(component.prefix(3)) {
                    cloudLayers.append(component)
                    if ["OVC", "BKN"].contains(component.prefix(3)){
                        let value = component.suffix(from: component.firstIndex(where: { "0"..."9" ~= $0 })!)
                        ceiling = min(ceiling, (Int(value) ?? 0) * 100)
                    }
                }
                
                // Weather events
                let weatherEventComponents = ["VC", "MI", "PR", "DR", "BL", "FZ", "RE", "BC", "SH", "XX",
                                              "RA", "SN", "GR", "DZ", "PL", "GS", "SG", "IC", "UP",
                                              "BR", "FG", "HZ", "FU", "SA", "DU", "VA",
                                              "PO", "SS", "DS", "SQ", "FC", "TS",
                                              "+", "-", ""]
                let possibleWeatherEvents = weatherEventComponents.map { firstComponent -> [String] in
                    return weatherEventComponents.map { secondComponent -> String in
                        firstComponent+secondComponent
                    }
                }.flatMap { $0 }
                if possibleWeatherEvents.contains(component) {
                    weatherEvents.append(component)
                }
            }
        }
        
        var readable: String {
            let visibilityString: String
            if visibility >= 9999 && cloudLayers.contains("CAVOK") {
                visibilityString = ""
            } else if visibility >= 9999 {
                visibilityString = "10km"
            } else if visibility >= 1000 {
                visibilityString = "\(visibility/1000)km"
            } else if visibility > 0 {
                visibilityString = "\(visibility)m"
            } else {
                visibilityString = ""
            }
            let cloudStrings = cloudLayers.compactMap { layer -> String? in
                guard let valueIndex = layer.firstIndex(where: { "0"..."9" ~= $0 }) else {
                    return layer
                }
                let value = layer.suffix(from: valueIndex)
                guard let height = Int(value) else {
                    return nil
                }
                return "\(layer.prefix(3)) \(height*100)ft"
            }.joined(separator: " ")
            return "\(visibilityString) \(weatherEvents.joined(separator: " ")) \(cloudStrings)"
        }
    }
    
    // MARK:- View
    static func view(req:Request, log:Log) -> EventLoopFuture<View> {
        return self.view(req: req, metar: log.properties.weather, configuration: log.properties.configuration, startDate: log.properties.startDate)
    }
    
    static func view(req:Request, metar:String, configuration:String, startDate:Date) -> EventLoopFuture<View> {
        // Weather
        let weather = Weather(from: metar)
        let qnh: Int = weather.qnh
        
        // Wind
        let windDirection = weather.windDirection
        let windSpeed = weather.windSpeed
        
        var northWindDirection = windDirection + Int.pseudoRandom(in: -1...2, changeEvery: 5)*10
        while northWindDirection <= 0 {
            northWindDirection += 360
        }
        while northWindDirection > 360 {
            northWindDirection -= 360
        }
        var southWindDirection = windDirection - Int.pseudoRandom(in: -2...1, changeEvery: 4)*10
        while southWindDirection <= 0 {
            southWindDirection += 360
        }
        while southWindDirection > 360 {
            southWindDirection -= 360
        }
        let northWindSpeed = max(windSpeed + Int.pseudoRandom(in: -1...8, changeEvery: 2), 0)
        let southWindSpeed = max(windSpeed + Int.pseudoRandom(in: -2...7, changeEvery: 3), 0)
        
        let northWind = DecorContext.Wind(direction: northWindDirection, speed: northWindSpeed, gust: weather.windGust)
        let southWind = DecorContext.Wind(direction: southWindDirection, speed: southWindSpeed, gust: weather.windGust)
        
        // ATIS Letter
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let atispg = String(letters[letters.index(letters.startIndex, offsetBy: Int.pseudoRandom(in: 0...25, changeEvery: 40) % 26)])
        let atisol = String(letters[letters.index(letters.startIndex, offsetBy: 7 + Int.pseudoRandom(in: 0...20, changeEvery: 50) % 26)])
        let atislb = String(letters[letters.index(letters.startIndex, offsetBy: 5 + Int.pseudoRandom(in: 0...20, changeEvery: 50) % 26)])
        
        // Transition level
        let transitionAltitude = 5000 + 28 * (1013 - qnh)
        let transitionLevel = Int(ceil(Double(transitionAltitude)/1000))*10 + 10
        
        // Configuration
        let configuration = configuration.uppercased()
        
        // Start time        
        let startTime = Self.timeFormatter.string(from: startDate)
        
        // RVR
        let northRunway1RVR = weather.northRunway1RVR
        let northRunway2RVR = weather.northRunway2RVR
        let southRunway1RVR = weather.southRunway1RVR
        let southRunway2RVR = weather.southRunway2RVR
        
        let preLVPNorth = weather.ceiling < 300 || weather.northRunway1RVR < 800 || weather.northRunway2RVR < 800
        let LVPNorth = weather.ceiling <= 200 || weather.northRunway1RVR <= 600 || weather.northRunway2RVR <= 600
        let preLVPSouth = weather.ceiling < 300 || weather.southRunway1RVR < 800 || weather.southRunway2RVR < 800
        let LVPSouth = weather.ceiling <= 200 || weather.southRunway1RVR <= 600 || weather.southRunway2RVR <= 600
        
        struct DecorContext: Encodable {
            struct Wind: Encodable {
                let direction:Int
                let speed:Int
                let gust:Int?
            }
            
            struct RunwayRVR: Encodable {
                let start:Int
                let mid:Int
                let end:Int
            }
            
            let qnh:String
            let transitionLevel:Int
            let temperature:Int
            let dewPoint:Int
            let northWind:Wind
            let southWind:Wind
            let atispg:String
            let atisol:String
            let atislb:String
            let configuration:String
            let weather:String
            let startTime:String
            let northRunway1RVR:RunwayRVR
            let northRunway2RVR:RunwayRVR
            let southRunway1RVR:RunwayRVR
            let southRunway2RVR:RunwayRVR
            let hbn27:Int
            let hbn26:Int
            let hbn09:Int
            let hbn08:Int
            let preLVPNorth: Bool
            let LVPNorth: Bool
            let preLVPSouth: Bool
            let LVPSouth: Bool
        }
        
        let pressureFormatter = NumberFormatter()
        pressureFormatter.minimumIntegerDigits = 4
        
        return req.view.render("decor", DecorContext(qnh: pressureFormatter.string(from: NSNumber(value: qnh)) ?? "",
                                                     transitionLevel: transitionLevel,
                                                     temperature: weather.temperature,
                                                     dewPoint: weather.dewPoint,
                                                     northWind: northWind,
                                                     southWind: southWind,
                                                     atispg: atispg,
                                                     atisol: atisol,
                                                     atislb: atislb,
                                                     configuration: configuration,
                                                     weather:weather.readable,
                                                     startTime:startTime,
                                                     northRunway1RVR:.init(start: northRunway1RVR + (1 + Int.pseudoRandom(in: -2...1, changeEvery: 2))*Int.pseudoRandom(in: 0...2, changeEvery: 2)*25,
                                                                           mid: northRunway1RVR + Int.pseudoRandom(in: -1...2, changeEvery: 2)*Int.pseudoRandom(in: 0...2, changeEvery: 2)*25,
                                                                           end: northRunway1RVR + (2 - Int.pseudoRandom(in: -1...2, changeEvery: 3))*Int.pseudoRandom(in: 0...2, changeEvery: 2)*25),
                                                     northRunway2RVR:.init(start: northRunway2RVR + Int.pseudoRandom(in: -2...1, changeEvery: 3)*Int.pseudoRandom(in: 0...2, changeEvery: 2)*25,
                                                                           mid: northRunway2RVR + (1 - Int.pseudoRandom(in: -1...1, changeEvery: 4))*Int.pseudoRandom(in: 0...2, changeEvery: 2)*25,
                                                                           end: northRunway2RVR + Int.pseudoRandom(in: -1...2, changeEvery: 2)*Int.pseudoRandom(in: 0...2, changeEvery: 2)*25),
                                                     southRunway1RVR:.init(start: southRunway1RVR + Int.pseudoRandom(in: -2...1, changeEvery: 3)*Int.pseudoRandom(in: 0...2, changeEvery: 2)*25,
                                                                           mid: southRunway1RVR + (1 - Int.pseudoRandom(in: -1...1, changeEvery: 2))*Int.pseudoRandom(in: 0...2, changeEvery: 2)*25,
                                                                           end: southRunway1RVR + Int.pseudoRandom(in: -1...2, changeEvery: 3)*Int.pseudoRandom(in: 0...2, changeEvery: 2)*25),
                                                     southRunway2RVR:.init(start: southRunway2RVR + Int.pseudoRandom(in: -2...1, changeEvery: 3)*Int.pseudoRandom(in: 0...2, changeEvery: 2)*25,
                                                                           mid: southRunway2RVR + (1 - Int.pseudoRandom(in: -1...1, changeEvery: 4))*Int.pseudoRandom(in: 0...2, changeEvery: 2)*25,
                                                                           end: southRunway2RVR + Int.pseudoRandom(in: -1...2, changeEvery: 2)*Int.pseudoRandom(in: 0...2, changeEvery: 2)*25),
                                                     hbn27:weather.ceiling + Int.pseudoRandom(in: -1...2, changeEvery: 2)*50,
                                                     hbn26:weather.ceiling + Int.pseudoRandom(in: -3...1, changeEvery: 3)*50,
                                                     hbn09:weather.ceiling + Int.pseudoRandom(in: -3...2, changeEvery: 2)*50,
                                                     hbn08:weather.ceiling + Int.pseudoRandom(in: -2...1, changeEvery: 4)*50,
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
    fileprivate static func pseudoRandom(in range:ClosedRange<Int>, changeEvery minutes:Int) -> Int {
        guard minutes != 0 else {
            return range.lowerBound
        }
        // An integer between 0 and 60
        let pseudoRandom = Int( (Date().timeIntervalSinceReferenceDate / 60).truncatingRemainder(dividingBy: 60) / Double(minutes % 60) )
        let random = self.randomNumbers[pseudoRandom]
        return Int(Double(range.lowerBound) + Double(range.upperBound - range.lowerBound)*Double(random)/10)
    }
    
    fileprivate static let randomNumbers:[Int] = [3, 8, 0, 4, 8, 5, 3, 5, 7, 4, 2, 3, 1, 9, 6, 3, 2, 8, 1, 2, 2, 1, 1, 8, 4, 2, 4, 8, 2, 9, 8, 3, 0, 7, 5, 7, 9, 9, 5, 7, 1, 3, 5, 0, 4, 0, 5, 8, 1, 5, 0, 2, 7, 2, 2, 2, 5, 2, 1, 8, 0]
}
