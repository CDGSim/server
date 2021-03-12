//
//  File.swift
//  
//
//  Created by Axel Péju on 23/02/2021.
//

import Foundation

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
    var northRunway1Closed: Bool = false
    var northRunway2Closed: Bool = false
    var southRunway1Closed: Bool = false
    var southRunway2Closed: Bool = false
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
            if component.count == 4 || component.count == 3 || component == "CAVOK" {
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
            
            // Decode RVRs & runway closure
            if let separatorIndex = component.firstIndex(of: "/"), component.first == "R" {
                let runway = component[component.index(after: component.startIndex)..<separatorIndex]
                if let rvr = Int(component.suffix(from: component.index(after: separatorIndex))) {
                    if runway == "27R" || runway == "09L" {
                        northRunway1RVR = rvr
                    } else if runway == "27L" || runway == "09R" {
                        northRunway2RVR = rvr
                    } else if runway == "26R" || runway == "08L" {
                        southRunway1RVR = rvr
                    } else if runway == "26L" || runway == "08R" {
                        southRunway2RVR = rvr
                    }
                } else {
                    let closure = String(component.suffix(from: component.index(after: separatorIndex)))
                    if closure == "CLOSED" {
                        if runway == "27R" || runway == "09L" {
                            northRunway1Closed = true
                        } else if runway == "27L" || runway == "09R" {
                            northRunway2Closed = true
                        } else if runway == "26R" || runway == "08L" {
                            southRunway1Closed = true
                        } else if runway == "26L" || runway == "08R" {
                            southRunway2Closed = true
                        }
                    }
                }
            }
            
            // Decode ceiling
            if ["OVC", "BKN", "FEW", "SCT"].contains(component.prefix(3)) {
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
        } else if visibility >= 2000 {
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
            let value = layer[valueIndex..<layer.index(valueIndex, offsetBy: 3)]
            guard let height = Int(value) else {
                return nil
            }
            if layer.count > 6 {
                return "\(layer.prefix(3)) \(height*100)ft \(layer.suffix(from: layer.index(valueIndex, offsetBy: 3)))"
            }
            return "\(layer.prefix(3)) \(height*100)ft"
        }.joined(separator: " ")
        return "\(visibilityString) \(weatherEvents.joined(separator: " ")) \(cloudStrings)"
    }
}
