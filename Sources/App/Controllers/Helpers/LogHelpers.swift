//
//  File.swift
//  
//
//  Created by Axel Péju on 16/03/2021.
//

import Foundation
import SimlogCore
import Vapor

// MARK: Log file reading

// Possible errors when trying to read a log file
internal enum LogError: Error {
    case notFound, couldNotDecode
}

/// Reads a log file located at path
internal func log(atPath path: String) -> Result<Log, LogError> {
    let logURL = URL(fileURLWithPath: "Public/logs/").appendingPathComponent(path.removingPercentEncoding ?? path)
    let logData: Data
    do {
        logData = try Data(contentsOf: logURL)
    } catch {
        return .failure(.notFound)
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let log = try? decoder.decode(Log.self, from: logData) else {
        return .failure(.couldNotDecode)
    }
    
    
    // Sort events
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "HH:mm:ss"
    let alternateDateFormatter = DateFormatter()
    alternateDateFormatter.dateFormat = "HH:mm"
    
    let sort: (Log.Event, Log.Event) -> Bool = { (lhs, rhs) -> Bool in
        if let lDate = dateFormatter.date(from: lhs.time) {
            if let rDate = dateFormatter.date(from: rhs.time) {
                return lDate < rDate
            } else if let rDate = alternateDateFormatter.date(from: rhs.time) {
                return lDate < rDate
            }
        } else if let lDate = alternateDateFormatter.date(from: lhs.time) {
            if let rDate = dateFormatter.date(from: rhs.time) {
                return lDate < rDate
            } else if let rDate = alternateDateFormatter.date(from: rhs.time) {
                return lDate < rDate
            }
        }
        return true
    }
    
    let instructorSortedEvents = log.instructorLog.events?.sorted(by: sort)
    
    let sortedPilotLogs = log.pilot_logs.map { pilotLog -> Log.PilotLog in
        var sortedLog = pilotLog
        sortedLog.events = pilotLog.events?.sorted(by: sort)
        return sortedLog
    }
    
    let sortedLog = Log(properties: log.properties,
                        instructorLog: .init(setupInfo: log.instructorLog.setupInfo, events: instructorSortedEvents),
                        pilotLogs: sortedPilotLogs)
    
    return .success(sortedLog)
}


// Renders the error view, passing a reason string as the context
internal func renderLogErrorView(from error:LogError, req:Request) -> EventLoopFuture<View> {
    struct ErrorContext: Encodable {
        let reason: String
    }
    
    let reason: String
    switch error {
    case .notFound:
        reason = "Log introuvable"
    case .couldNotDecode:
        reason = "Impossible de lire le log"
    }
    return req.view.render("error",  ["reason":reason])
}
