//
//  File.swift
//  
//
//  Created by Axel Péju on 16/03/2021.
//

import Foundation
import SimlogCore

// MARK: ELECTRA simulation reading

typealias Flight = SimlogCore.Flight

// Possible errors when trying to read a log file
internal enum SimulationImporterError: Error {
    case notFound, couldNotRead
}

/// Reads a simulation file located at path
/// - Parameter url: The complete url to the simulation file
internal func electraSimulation(at url: URL) throws -> SimlogCore.Simulation {
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        do {
            // Try again, changing the extension to uppercase
            let uppercaseURL = url.deletingPathExtension().appendingPathExtension(url.pathExtension.uppercased())
            data = try Data(contentsOf: uppercaseURL)
        } catch {
            throw SimulationImporterError.notFound
        }
    }
    
    let simulationContent: String
    
    if let content = String(data: data, encoding: .utf8) {
        simulationContent = content
    } else if let content = String(data: data, encoding: .ascii) {
        simulationContent = content
    } else {
        throw SimulationImporterError.notFound
    }
    
    var electraImporter = SimlogCore.ElectraImporter(content: simulationContent)
    
    return electraImporter.simulation()
}

internal func electraSimulation(associatedWithLogAtPath logPath:String) throws -> SimlogCore.Simulation {
    // Get complete electra simulation file URL from log path
    var electraSimulationURL = URL(fileURLWithPath: "Public/logs/\(logPath)")
    electraSimulationURL.deletePathExtension()
    electraSimulationURL.appendPathExtension("exp")
    
    return try electraSimulation(at: electraSimulationURL)
}

/// Reads an ELECTRA simulation file located in the same directory as the log file, finds flights that have been rerouted
/// - Parameter path: The path to the log file
/// - Returns: A tuple containing flights rerouted to runway 27 or 09, and flights rerouted to runway 08 or 26
internal func reroutedFlights(in simulation:SimlogCore.Simulation) -> ([Flight], [Flight]) {
    
    var reroutedFlightsToNorthRunways = [Flight]()
    var reroutedFlightsToSouthRunways = [Flight]()
    
    // Find rerouted flights
    let lfpgArrivals = simulation.flights.filter { $0.destination == "LFPG" }
    let northRunwayArrivals = lfpgArrivals.filter { $0.destinationRunway?.prefix(2) == "27" || $0.destinationRunway?.prefix(2) == "09"}
    reroutedFlightsToNorthRunways = northRunwayArrivals.compactMap { flight -> Flight? in
        guard let iaf = flight.route.last?.fix else {
            return nil
        }
        return ["OKIPA", "BANOX"].contains(iaf) ? flight : nil
    }
    let southRunwayArrivals = lfpgArrivals.filter { $0.destinationRunway?.prefix(2) == "26" || $0.destinationRunway?.prefix(2) == "08"}
    reroutedFlightsToSouthRunways = southRunwayArrivals.compactMap { flight -> Flight? in
        guard let iaf = flight.route.last?.fix else {
            return nil
        }
        return ["MOPAR", "LORNI", "MOBRO"].contains(iaf) ? flight : nil
    }
    
    return (reroutedFlightsToNorthRunways, reroutedFlightsToSouthRunways)
}

protocol Arrival {
    var callsign: String { get }
    var iaf: String { get }
    var destination: String { get }
    var destinationRunway: String { get }
}

internal func reroutedFlights(_ flights:[Arrival]) -> ([Arrival], [Arrival]) {
    
    var reroutedFlightsToNorthRunways = [Arrival]()
    var reroutedFlightsToSouthRunways = [Arrival]()
    
    // Find rerouted flights
    let lfpgArrivals = flights.filter { $0.destination == "LFPG" }
    let northRunwayArrivals = lfpgArrivals.filter { $0.destinationRunway.prefix(2) == "27" || $0.destinationRunway.prefix(2) == "09"}
    reroutedFlightsToNorthRunways = northRunwayArrivals.filter { ["OKIPA", "BANOX"].contains($0.iaf) }
    let southRunwayArrivals = lfpgArrivals.filter { $0.destinationRunway.prefix(2) == "26" || $0.destinationRunway.prefix(2) == "08"}
    reroutedFlightsToSouthRunways = southRunwayArrivals.filter { ["MOPAR", "LORNI", "MOBRO"].contains($0.iaf) }
    
    return (reroutedFlightsToNorthRunways, reroutedFlightsToSouthRunways)
}
