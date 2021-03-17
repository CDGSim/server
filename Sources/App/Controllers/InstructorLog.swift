//
//  File.swift
//  
//
//  Created by Axel Péju on 16/03/2021.
//

import Vapor
import SimlogCore

struct InstructorLogRoute {
    static func register(with app: Application) {
        app.get("instructeur", "**") { req -> EventLoopFuture<View> in
            let path = req.parameters.getCatchall().joined(separator: "/")
            
            // Read the log file
            switch log(atPath: path) {
            case .failure(let error) :
                return renderLogErrorView(from: error, req: req)
            case .success(let log):
                return req.view.render("instructor/log_instructor", Context(from: log, path: path))
            }
        }
    }
}

private struct Context: Encodable {
    struct Attachment: Encodable {
        let url:String
        let name:String
    }
    // Type to replace Log.Properties.ControlPositionAssignment
    // This type has a positionsDescription string instead of a set of positions
    struct ControlPositionAssignment: Encodable {
        let controller: Log.Properties.Controller
        let positionsDescription: String
    }
    let path:String
    let simulation_properties: SimulationProperties
    let log: Log
    let assignments: [ControlPositionAssignment]?
    let attachments: [Attachment]?
    let displayEventsLocation: Bool
    let courseNotes:String
    
    // Rerouted flights
    let reroutedFlightsToNorthRunways:[Flight]?
    let reroutedFlightsToSouthRunways:[Flight]?
    
    // Timelines
    struct Timeline: Encodable {
        struct Flight: Encodable {
            let estimate:String
            let callsign:String
            let IAF:String
            let IAFestimate:String
            let aircraftType:String
            let y: Int
        }
        struct MinuteLabel: Encodable {
            let hours: Int
            let minutes: Int
            let y: Int
        }
        let flights: [Flight]
        let labels: [MinuteLabel]
        let runwayName: String
        let colorClass: String
        let length: Int
    }
    struct TimelineGroup: Encodable {
        let name: String
        let timelines: [Timeline]
    }
    let timelinesGroups: [TimelineGroup]
    
    init(from log: Log, path:String) {
        self.path = path
        self.simulation_properties = .init(from: log.properties)
        
        self.log = log
        
        // Build up assignments
        // We need to make the positionDescriptions string from the set of positions
        self.assignments = log.properties.assignments?.map { assignment -> Context.ControlPositionAssignment in
            let positionDescriptions = Array(assignment.positions).map { controlPosition in
                controlPosition.rawValue
            }.sorted().joined(separator: "<br />")
            return .init(controller: .instructor, positionsDescription: positionDescriptions)
        }
            
        // Check if we should display the events locations
        // Location is optional, if at least one event has a location, we should display the corresponding column
        let atLeastOneEventContainsALocation: Bool
        if let eventsWithLocation = log.instructorLog.events?.filter({ event in
            if let location = event.location {
                return location != "-" && location.count > 0
            } else { return false }
        }) {
            atLeastOneEventContainsALocation = eventsWithLocation.count > 0
        } else {
            atLeastOneEventContainsALocation = false
        }
        self.displayEventsLocation = atLeastOneEventContainsALocation
        
        // Check if there is an Attachments subfolder
        var url = URL(fileURLWithPath: "Public/logs")
        url.appendPathComponent(path)
        url.deleteLastPathComponent()
        url.appendPathComponent("Attachments", isDirectory: true)
        let urls = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        let attachments = urls?.map { url -> Context.Attachment in
            let attachmentsFolderPath = path.components(separatedBy: "/").dropLast().joined(separator: "/") + "/Attachments/"
            return Context.Attachment(url:attachmentsFolderPath + url.lastPathComponent, name:url.lastPathComponent)
        }
        self.attachments = attachments
        
        // Read notes.md
        var notesURL = URL(fileURLWithPath: "Public/logs")
        notesURL.appendPathComponent(path)
        notesURL.deleteLastPathComponent()
        notesURL.deleteLastPathComponent()
        notesURL.deleteLastPathComponent()
        notesURL.appendPathComponent("Notes.md", isDirectory: false)
        let notes:String
        do {
            notes = try String(contentsOf:notesURL, encoding:.utf8)
        }
        catch {
            notes = ""
        }
        self.courseNotes = notes
        
        let flights = reroutedFlights(logPath: path)
        self.reroutedFlightsToNorthRunways = flights.0
        self.reroutedFlightsToSouthRunways = flights.1
        
        do {
            let simulation =  try electraSimulation(atPath: path)
            
            // Length of the timeline according to simulation's duration
            if let duration = simulation.duration, let startDate = simulation.date {
                let length = duration * 20
                
                // Build minute labels
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                
                var minuteLabels = [Timeline.MinuteLabel]()
                var currentDate = startDate
                while currentDate.timeIntervalSince(startDate) < TimeInterval(duration * 60) {
                    let components = calendar.dateComponents([.hour, .minute], from: currentDate)
                    if let hours = components.hour, let minutes = components.minute {
                        minuteLabels.append(.init(hours: hours, minutes: minutes, y: Int(currentDate.timeIntervalSince(startDate) / 60 * 20)))
                    }
                    currentDate.addTimeInterval(60)
                }
                
                let movementDateFormatter = DateFormatter()
                movementDateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                movementDateFormatter.dateFormat = "HH:mm"
                let IAFDateFormatter = DateFormatter()
                IAFDateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                IAFDateFormatter.dateFormat = "mm"
                
                // Filter arrivals
                let lfpgArrivals = simulation.flights
                    .filter { flight -> Bool in
                        flight.destination == "LFPG"
                    }
                
                let timelineArrival: (Flight) -> Timeline.Flight? = { flight in
                    guard let estimatedMovementTime = flight.estimatedMovementTime() else {
                        return nil
                    }
                    let coordinate: Int = Int(estimatedMovementTime.timeIntervalSince(startDate) / 60 * 20)
                    if coordinate > length {
                        return nil
                    }
                    let estimate = movementDateFormatter.string(from: estimatedMovementTime)
                    let estimatedIAFTime: String
                    if let IAFtime = flight.estimatedIAFTime() {
                        estimatedIAFTime = IAFDateFormatter.string(from: IAFtime)
                    } else {
                        estimatedIAFTime = ""
                    }
                    return .init(estimate: estimate, callsign: flight.callsign, IAF: abreviatedIAF(from:flight.route.last?.fix ?? ""), IAFestimate: estimatedIAFTime, aircraftType: flight.aircraftType, y: coordinate)
                }
                
                // LFPG arrivals
                let northRunwaysArrivals = lfpgArrivals
                    .filter { ["27", "09"].contains($0.destinationRunway?.prefix(2)) }
                    .compactMap(timelineArrival)
                let southRunwaysArrivals = lfpgArrivals
                    .filter { ["26", "08"].contains($0.destinationRunway?.prefix(2)) }
                    .compactMap(timelineArrival)
                let leBourgetArrivals = simulation.flights
                    .filter { $0.destination == "LFPB" }
                    .compactMap(timelineArrival)
                let facingWest = log.properties.configuration.prefix(1) == "W"
                let lfpgArrivalsTimelines:[Timeline] = [.init(flights: northRunwaysArrivals, labels: minuteLabels, runwayName: facingWest ? "27R":"09L", colorClass: "salmon", length: length),
                                  .init(flights: southRunwaysArrivals, labels: minuteLabels, runwayName: facingWest ? "26L":"08R", colorClass: "pink", length: length),
                                  .init(flights: leBourgetArrivals, labels: minuteLabels, runwayName: facingWest ? "27":"07", colorClass: "purple", length: length)]
                
                
            
                let timelineDeparture: (Flight) -> Timeline.Flight? = { flight in
                    guard let estimatedMovementTime = flight.estimatedMovementTime() else {
                        return nil
                    }
                    let coordinate: Int = Int(estimatedMovementTime.timeIntervalSince(startDate) / 60 * 20)
                    if coordinate > length {
                        return nil
                    }
                    let estimate = movementDateFormatter.string(from: estimatedMovementTime)
                    return .init(estimate: estimate, callsign: flight.callsign, IAF: abreviatedDeparture(from: flight.route.first?.fix ?? ""), IAFestimate: "", aircraftType: flight.aircraftType, y: coordinate)
                }
                    
                // LFPG departures
                let lfpgDepartures = simulation.flights
                    .filter { flight -> Bool in
                        flight.origin == "LFPG"
                    }
                let northRunwaysDepartures = lfpgDepartures
                    .filter { ["27", "09"].contains($0.departureRunway?.prefix(2)) }
                    .compactMap(timelineDeparture)
                let southRunwaysDepartures = lfpgDepartures
                    .filter { ["26", "08"].contains($0.departureRunway?.prefix(2)) }
                    .compactMap(timelineDeparture)
                let leBourgetDepartures = simulation.flights
                    .filter { $0.origin == "LFPB" }
                    .compactMap(timelineDeparture)
                
                let lfpgDeparturesTimelines: [Timeline] = [.init(flights: northRunwaysDepartures, labels: minuteLabels, runwayName: facingWest ? "27L":"09R", colorClass: "cyan", length: length),
                                                           .init(flights: southRunwaysDepartures, labels: minuteLabels, runwayName: facingWest ? "26R":"08L", colorClass: "cyan", length: length),
                                                           .init(flights: leBourgetDepartures, labels: minuteLabels, runwayName: facingWest ? "25":"09", colorClass: "cyan", length: length)]
                
                self.timelinesGroups = [.init(name: "Arrivées LFPG", timelines: lfpgArrivalsTimelines),
                                        .init(name: "Départs LFPG", timelines: lfpgDeparturesTimelines)]
            } else {
                self.timelinesGroups = []
            }
        } catch {
            self.timelinesGroups = []
        }
    }
}

func abreviatedIAF(from IAFName:String) -> String {
    if(IAFName == "MOPAR") { return "M" }
    if(IAFName == "LORNI") { return "L" }
    if(IAFName == "VEBEK") { return "V" }
    if(IAFName == "OKIPA") { return "O" }
    if(IAFName == "BANOX") { return "B" }
    if(IAFName == "OKABO") { return "o" }
    if(IAFName == "KOLIV") { return "K" }
    if(IAFName == "MOBRO") { return "m" }
    if(IAFName == "IPNOB") { return "L" }
    if(IAFName == "ODILO") { return "O" }
    if(IAFName == "MOLBA") { return "M" }
    return IAFName
}

func abreviatedDeparture(from departureName:String) -> String {
    if(departureName == "OPALE") { return "NO" }
    if(departureName == "ATREX") { return "NA" }
    if(departureName == "NURMO") { return "NN" }
    if(departureName == "RANUX") { return "ER" }
    if(departureName == "DIKOL") { return "ED" }
    if(departureName == "LANVI") { return "EL" }
    if(departureName == "BUBLI") { return "EB" }
    if(departureName == "AGOPA") { return "SA" }
    if(departureName == "ERIXU") { return "SE" }
    if(departureName == "LATRA") { return "SL" }
    if(departureName == "OKASI") { return "SO" }
    if(departureName == "PILUL") { return "SP" }
    if(departureName == "EVX") { return "WE" }
    if(departureName == "LGL") { return "WL" }
    return departureName
}
