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
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dateFormatter
    }()
    
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
        
        // Sunrise and sunset
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd"
        let dayString = dateFormatter.string(from: startDate)
        dateFormatter.dateFormat = "MM"
        let monthString = dateFormatter.string(from: startDate)
        let sunriseAndSunset: (String, String)
        if let day = Int(dayString), let month = Int(monthString) {
            sunriseAndSunset = Self.sunriseAndSunsetHours(month: month, day: day)
        } else {
            sunriseAndSunset = ("XXXX", "XXXX")
        }
        
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
            let sunrise: String
            let sunset: String
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
                                                     LVPSouth: LVPSouth,
                                                     sunrise: sunriseAndSunset.0,
                                                     sunset: sunriseAndSunset.1
                                                     ))
    }
    
    private struct SunTime: Equatable {
        let month: Int
        let day: Int
        let sunrise: String
        let sunset: String
    }
    
    private static var sunsetSunriseTimes: [[SunTime]] {
        let separator = "    "
        
        let january = "07:55/16:11    07:55/16:14    07:54/16:18    07:53/16:22    07:51/16:26    07:49/16:30    07:46/16:35    07:44/16:39    07:40/16:44    07:37/16:49    07:33/16:54"
        let february = "07:31/16:55    07:27/17:00    07:22/17:05    07:18/17:10    07:13/17:15    07:07/17:20    07:02/17:25    06:56/17:30    06:51/17:35    06:45/17:40"
        let march = "06:43/17:42    06:37/17:46    06:31/17:51    06:24/17:56    06:18/18:00    06:12/18:05    06:06/18:10    05:59/18:14    05:53/18:19    05:47/18:23    05:40/18:28"
        let april = "05:38/18:29    05:32/18:34    05:26/18:38    05:20/18:43    05:14/18:47    05:08/18:52    05:02/18:56    04:56/19:01    04:51/19:05    04:45/19:10"
        let may = "04:40/19:14    04:35/19:18    04:30/19:23    04:26/19:27    04:21/19:31    04:17/19:35    04:14/19:39    04:10/19:43    04:07/19:46    04:05/19:50    04:02/19:53"
        let june = "04:02/19:54    04:00/19:56    03:58/19:59    03:57/20:01    03:57/20:03    03:56/20:04    03:57/20:05    03:57/20:06    03:58/20:06    04:00/20:06"
        let july = "04:01/20:05    04:03/20:04    04:06/20:03    04:08/20:01    04:11/19:59    04:14/19:56    04:18/19:53    04:21/19:50    04:25/19:46    04:29/19:42    04:33/19:38"
        let august = "04:34/19:37    04:38/19:32    04:42/19:27    04:46/19:22    04:51/19:17    04:55/19:12    04:59/19:06    05:03/19:00    05:08/18:54    05:12/18:48    05:16/18:42"
        let september = "05:18/18:40    05:22/18:34    05:26/18:28    05:30/18:21    05:35/18:15    05:39/18:09    05:43/18:02    05:48/17:56    05:52/17:49    05:56/17:43"
        let october = "06:01/17:37    06:05/17:30    06:09/17:24    06:14/17:18    06:19/17:12    06:23/17:06    06:28/17:00    06:32/16:55    06:37/16:49    06:42/16:44    06:47/16:39"
        let november = "06:48/16:37    06:53/16:32    06:58/16:28    07:03/16:23    07:08/16:19    07:12/16:16    07:17/16:12    07:21/16:09    07:26/16:07    07:30/16:05"
        let december = "07:34/16:03    07:38/16:02    07:41/16:01    07:44/16:00    07:47/16:00    07:49/16:01    07:51/16:02    07:53/16:03    07:54/16:05    07:55/16:07    07:55/16:10"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        
        return [january, february, march, april, may, june, july, august, september, october, november, december]
            .map { timesText -> [SunTime] in
                return timesText
                    .components(separatedBy:separator)
                    .map { timesText -> (String, String) in
                        let times = timesText.components(separatedBy:"/").map { timeString -> String in
                            let date = dateFormatter.date(from: timeString)!
                            return dateFormatter.string(from: date.addingTimeInterval(-8*60))
                        }
                        return (times.first!, times.last!)
                    }
                    .enumerated()
                    .map { (index, times) -> SunTime in
                        return .init(month: 1, day: 1 + index*3, sunrise: times.0, sunset: times.1)
                    }
            }
    }
    
    static func sunriseAndSunsetHours(month: Int, day: Int) -> (String, String) {
        guard month > 0 && month <= self.sunsetSunriseTimes.count else {
            return ("", "")
        }
        let timesForTheMonth = self.sunsetSunriseTimes[month - 1]
        guard day > 0 && day < 32 else {
            return ("", "")
        }
        var sunsetAndSunrise = ("", "")
        for time in timesForTheMonth {
            if time.day > day {
                return sunsetAndSunrise
            } else {
                sunsetAndSunrise = (time.sunrise, time.sunset)
            }
        }
        return sunsetAndSunrise
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
