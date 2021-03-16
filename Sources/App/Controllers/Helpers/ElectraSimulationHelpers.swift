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
internal func electraSimulation(at url: URL) -> Result<SimlogCore.Simulation, SimulationImporterError> {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return .failure(.notFound)
    }
    
    let fileContent: String?
    do {
        fileContent = try String(contentsOf: url, encoding: .utf8)
    } catch {
        fileContent = try? String(contentsOf: url, encoding: .ascii)
    }
    
    guard let simulationContent = fileContent else {
        return .failure(.couldNotRead)
    }
    
    var electraImporter = SimlogCore.ElectraImporter(content: simulationContent)
    
    return .success(electraImporter.simulation())
}

/// Reads an ELECTRA simulation file located in the same directory as the log file, finds flights that have been rerouted
/// - Parameter path: The path to the log file
/// - Returns: A tuple containing flights rerouted to runway 27 or 09, and flights rerouted to runway 08 or 26
internal func reroutedFlights(logPath path:String) -> ([Flight], [Flight]) {
    // Read electra simulation file if it exists
    var electraSimulationURL = URL(fileURLWithPath: "Public/logs")
    electraSimulationURL.appendPathComponent(path)
    electraSimulationURL.deletePathExtension()
    electraSimulationURL.appendPathExtension("EXP")
    
    var reroutedFlightsToNorthRunways = [Flight]()
    var reroutedFlightsToSouthRunways = [Flight]()
    
    // Find rerouted flights
    if let simulation = try? electraSimulation(at:electraSimulationURL).get() {
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
    }
    
    return (reroutedFlightsToNorthRunways, reroutedFlightsToSouthRunways)
}
