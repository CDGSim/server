//
//  File.swift
//  
//
//  Created by Axel Péju on 07/01/2022.
//

import Foundation
import XMLCoder

struct ATTowerExercise {
    let startDate: Date
    let duration: Int
    let flights: [ATTowerFlight]
}

struct ATTowerFlight {
    let callsign: String
    let aircraftType: String
    let origin: String
    let departureRunway: String?
    let destination: String
    let destinationRunway: String?
    let estimatedMovementDate: Date?
    let estimatedIAFDate: Date? = nil
    let iaf: String?
    let departure: String?
}

internal func atTowerExercise(associatedWithLogAtPath logPath:String) throws -> ATTowerExercise {
    // Get complete ATTower simulation file URL from log path
    var atTowerSimulationURL = URL(fileURLWithPath: "Public/logs/\(logPath)")
    atTowerSimulationURL.deletePathExtension()
    atTowerSimulationURL.appendPathExtension("exercise")
    
    return try atTowerExercise(fromFileAt: atTowerSimulationURL)
}

enum ATTowerExerciseReaderError: Error {
    case notFound
}

internal func atTowerExercise(fromFileAt url: URL) throws -> ATTowerExercise {
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        do {
            // Try again, changing the extension to uppercase
            let uppercaseURL = url.deletingPathExtension().appendingPathExtension(url.pathExtension.uppercased())
            data = try Data(contentsOf: uppercaseURL)
        } catch {
            throw ATTowerExerciseReaderError.notFound
        }
    }
    
    let exerciseData = try XMLDecoder().decode(ExerciseData.self, from: data)
    let startDate = Date(timeIntervalSince1970: TimeInterval(exerciseData.exercise.header.basicData.start))
    
    let flights = exerciseData.exercise.flightPlans.flightPlans.map { flightPlan -> ATTowerFlight in
        // Movement date
        let estimatedMovementDate: Date?
        if let eta = flightPlan.arrivalAirport.plannedEta {
            let date = startDate.addingTimeInterval(TimeInterval(eta))
            estimatedMovementDate = date
        } else if let etd = flightPlan.departureAirport.plannedEtd {
            let date = startDate.addingTimeInterval(TimeInterval(etd))
            estimatedMovementDate = date
        } else {
            estimatedMovementDate = nil
        }
        
        // IAF
        let iaf: String
        let firstApproachName = flightPlan.actionLines.actionLines
            .filter { actionLine in
                actionLine.name?.components(separatedBy: "_").first?.count == 7 && actionLine.name?.prefix(5).trimmingCharacters(in: .letters).count == 0
            }
            .reversed()
            .first { actionLine in
            actionLine.command == "APP"
            }.map { actionLine in
                actionLine.name?.prefix(5) ?? ""
            }
        iaf = String(firstApproachName ?? "X")
        
        // Departure name according to SID
        let departureName: String
        let firstSIDName = flightPlan.actionLines.actionLines
            .first { actionLine in
            actionLine.command == "SID"
            }.map { actionLine in
                actionLine.name?.dropLast(2) ?? ""
            }
        departureName = String(firstSIDName ?? "D")
        
        return ATTowerFlight(callsign: flightPlan.basicData.callsign,
                             aircraftType: flightPlan.basicData.aircraftType,
                             origin: flightPlan.departureAirport.code,
                             departureRunway: flightPlan.misc.assignedRunway,
                             destination: flightPlan.arrivalAirport.code,
                             destinationRunway: flightPlan.misc.assignedRunway,
                             estimatedMovementDate: estimatedMovementDate,
                             iaf:iaf,
                             departure: departureName)
    }
    return ATTowerExercise(startDate: startDate,
                           duration: exerciseData.exercise.header.basicData.duration/60,
                           flights: flights)
}

// MARK: - Exercise XML Data

struct ExerciseData: Codable {
    let exercise: Exercise
    
    enum CodingKeys: String, CodingKey {
        case exercise = "Exercise"
    }
}

struct Exercise: Codable {
    let flightPlans: FlightPlans
    let header: Header
    
    enum CodingKeys: String, CodingKey {
        case header = "Header"
        case flightPlans = "FlightPlans"
    }
}

struct Header: Codable {
    let basicData: HeaderData
    
    enum CodingKeys: String, CodingKey {
        case basicData = "BasicData"
    }
}

struct HeaderData: Codable {
    let duration: Int
    let start: Int
    
    enum CodingKeys: String, CodingKey {
        case duration = "Duration"
        case start = "Start"
    }
}

struct FlightPlans: Codable {
    let flightPlans: [FlightPlan]
    
    enum CodingKeys: String, CodingKey {
        case flightPlans = "FlightPlan"
    }
}

struct FlightPlan: Codable {
    let basicData: BasicData
    let departureAirport: FlightAirport
    let arrivalAirport: FlightAirport
    let misc: Misc
    let actionLines: ActionLines
    
    enum CodingKeys: String, CodingKey {
        case basicData = "BasicData"
        case departureAirport = "DepartureAirport"
        case arrivalAirport = "ArrivalAirport"
        case misc = "Misc"
        case actionLines = "ActionLines"
    }
}

struct BasicData: Codable {
    let aircraftType: String
    let callsign: String
    
    enum CodingKeys: String, CodingKey {
        case aircraftType = "AircraftType"
        case callsign = "Callsign"
    }
}

struct FlightAirport: Codable {
    let code: String
    let eta: Int?
    let plannedEta: Int?
    let etd: Int?
    let plannedEtd: Int?
    
    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case eta = "ETA"
        case plannedEta = "PlannedETA"
        case etd = "ETD"
        case plannedEtd = "PlannedETD"
    }
}

struct Misc: Codable {
    let assignedRunway: String?
    
    enum CodingKeys: String, CodingKey {
        case assignedRunway = "AssignedRunway"
    }
}

struct ActionLines: Codable {
    let actionLines: [ActionLine]
    
    enum CodingKeys: String, CodingKey {
        case actionLines = "ActionLine"
    }
}

struct ActionLine: Codable {
    let command: String
    let name: String?
    
    enum CodingKeys: String, CodingKey {
        case command = "Command"
        case name = "Name"
    }
}
