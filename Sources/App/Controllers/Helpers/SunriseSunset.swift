//
//  File.swift
//  
//
//  Created by Axel Péju on 03/05/2021.
//

import Foundation

struct SunriseSunset {

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

    public static func sunriseAndSunsetHours(month: Int, day: Int) -> (String, String) {
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
    
    static private let dayFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)!
        return dateFormatter
    }()
    
    static private let monthFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)!
        return dateFormatter
    }()
    
    static private let timeFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)!
        return dateFormatter
    }()
    
    static func sunriseAndSunset(for date:Date) throws -> (Date, Date) {
        struct UnableToParseDateError: Error {}
        
        let dayString = Self.dayFormatter.string(from: date)
        let monthString = Self.monthFormatter.string(from: date)
        guard let month = Int(monthString), let day = Int(dayString) else {
            throw UnableToParseDateError()
        }
        let components = self.sunriseAndSunsetHours(month: month, day: day)
        guard let sunRiseTime = self.timeFormatter.date(from:components.0), let sunSetTime = self.timeFormatter.date(from:components.1) else {
            throw UnableToParseDateError()
        }
        
        var gmtCalendar = Calendar(identifier: .gregorian)
        gmtCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dateComponents = gmtCalendar.dateComponents([.year, .month, .day, .hour, .minute], from:date)
        
        var sunriseComponents = gmtCalendar.dateComponents([.hour, .minute], from:sunRiseTime)
        sunriseComponents.year = dateComponents.year
        sunriseComponents.month = dateComponents.month
        sunriseComponents.day = dateComponents.day
        let sunrise = gmtCalendar.date(from:sunriseComponents)!
        
        var sunsetComponents = gmtCalendar.dateComponents([.hour, .minute], from:sunSetTime)
        sunsetComponents.year = dateComponents.year
        sunsetComponents.month = dateComponents.month
        sunsetComponents.day = dateComponents.day
        let sunset = gmtCalendar.date(from:sunsetComponents)!
        
        return (sunrise, sunset)
    }
    
    static func isDateDuringDaytime(date:Date) -> Bool {
        do {
            let sunriseAndSunset = try self.sunriseAndSunset(for: date)
            return date < sunriseAndSunset.1 && date > sunriseAndSunset.0
        }
        catch {
            return true
        }
    }
}

extension Date {
    func isDuringDaytime() -> Bool {
        return SunriseSunset.isDateDuringDaytime(date: self)
    }
}
