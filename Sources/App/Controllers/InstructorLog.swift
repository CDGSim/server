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
            switch logWithSortedEvents(atPath: path) {
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
    let displayInitialConditionsTable:Bool
    let courseNotes:String
    let showDECORButton: Bool
    
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
        showDECORButton = ProcessInfo.processInfo.environment["simulator"] == "electra"
        self.path = path
        self.simulation_properties = .init(from: log.properties)
        
        self.log = log
        
        // Build up assignments
        // We need to make the positionDescriptions string from the set of positions
        self.assignments = log.properties.assignments?.map { assignment -> Context.ControlPositionAssignment in
            let positionDescriptions = Array(assignment.positions).map { controlPosition in
                controlPosition.rawValue
            }.sorted().joined(separator: " - ")
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
        
        // Determine if we should display the initial conditions table
        self.displayInitialConditionsTable = log.pilot_logs
            .filter { pilotLog in
                pilotLog.role.prefix(8) != "Adjacent"
            }.compactMap { pilotLog -> Log.PilotLog? in
                guard let setup = pilotLog.setup else { return nil }
                return setup.count > 0 ? pilotLog : nil
            }.count > 0
        
        // Find attachments for the simulation
        // Attachments can be located in two directories :
        //      - /path_to_course/Attachments               --> those are the attachments global to the course
        //      - /path_to_course/path_to_log/Attachments   --> those will be attachments specific to the simulation
        
        func appendAttachments(atURL url: URL, to attachments:inout [Context.Attachment], attachmentsPath:String) {
            if let logAttachmentsURLs = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                let logAttachments = logAttachmentsURLs.map { url -> Context.Attachment in
                    return Context.Attachment(url:attachmentsPath + url.lastPathComponent, name:url.lastPathComponent)
                }
                attachments.append(contentsOf:logAttachments)
            }
        }
        var attachments = [Context.Attachment]()
        
        var url = URL(fileURLWithPath: "Public/logs")
        url.appendPathComponent(path)
        url.deleteLastPathComponent()
        
        // Attachments specific to the simulation
        let logAttachmentsContainerURL = url.appendingPathComponent("Attachments", isDirectory: true)
        let logAttachmentsFolderPath = path.components(separatedBy: "/").dropLast().joined(separator: "/") + "/Attachments/"
        appendAttachments(atURL: logAttachmentsContainerURL, to: &attachments, attachmentsPath: logAttachmentsFolderPath)
        
        // Attachments globally available the course
        url = URL(fileURLWithPath: "Public/logs")
        if let courseRelativePath = path.components(separatedBy: "/").first {
            let courseAttachmentsContainerURL = URL(fileURLWithPath: "Public/logs").appendingPathComponent(courseRelativePath, isDirectory: true)
                .appendingPathComponent("Attachments", isDirectory: true)
            let courseAttachmentsFolderPath = courseRelativePath + "/Attachments/"
            appendAttachments(atURL: courseAttachmentsContainerURL, to: &attachments, attachmentsPath: courseAttachmentsFolderPath)
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
        
        let flightList: [TimelineableFlight]
        let startDate: Date
        let duration: Int
        
        do {
            // ELECTRA
            let simulation =  try electraSimulation(associatedWithLogAtPath: path)
            
            // Length of the timeline according to simulation's duration
            guard let simulationDuration = simulation.duration, let simulationStartDate = simulation.date else {
                self.timelinesGroups = []
                self.reroutedFlightsToNorthRunways = []
                self.reroutedFlightsToSouthRunways = []
                return
            }
            flightList = simulation.flights
            startDate = simulationStartDate
            duration = simulationDuration
            
            // Get rerouted flights
            let flights = reroutedFlights(in:simulation)
            self.reroutedFlightsToNorthRunways = flights.0
            self.reroutedFlightsToSouthRunways = flights.1
            
        } catch SimulationImporterError.notFound {
            // ATTower
            self.reroutedFlightsToNorthRunways = []
            self.reroutedFlightsToSouthRunways = []
            
            guard let exercise = try? atTowerExercise(associatedWithLogAtPath: path) else {
                self.timelinesGroups = []
                return
            }
            flightList = exercise.flights
            startDate = exercise.startDate
            duration = exercise.duration
        } catch {
            self.timelinesGroups = []
            self.reroutedFlightsToNorthRunways = []
            self.reroutedFlightsToSouthRunways = []
            return
        }
        
        let length: Int
        length = duration * 20
        
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
        
        // Date formatters
        let movementDateFormatter = DateFormatter()
        movementDateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        movementDateFormatter.dateFormat = "HH:mm"
        let IAFDateFormatter = DateFormatter()
        IAFDateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        IAFDateFormatter.dateFormat = "mm"
        
        // Filter arrivals
        let lfpgArrivals = flightList
            .filter { flight -> Bool in
                flight.destination == "LFPG"
            }
        
        let timelineArrival: (TimelineableFlight) -> Timeline.Flight? = { flight in
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
            return .init(estimate: estimate, callsign: flight.callsign, IAF: abreviatedIAF(from:flight.initialApproachFix), IAFestimate: estimatedIAFTime, aircraftType: flight.aircraftType, y: coordinate)
        }
        
        // LFPG arrivals
        let northRunwaysArrivals = lfpgArrivals
            .filter { ["27", "09"].contains($0.destinationRunway?.prefix(2)) }
            .compactMap(timelineArrival)
        let southRunwaysArrivals = lfpgArrivals
            .filter { ["26", "08"].contains($0.destinationRunway?.prefix(2)) }
            .compactMap(timelineArrival)
        let leBourgetArrivals = flightList
            .filter { $0.destination == "LFPB" }
            .compactMap(timelineArrival)
        let facingWest = log.properties.configuration.prefix(1) == "W"
        let lfpgArrivalsTimelines:[Timeline] = [.init(flights: northRunwaysArrivals, labels: minuteLabels, runwayName: facingWest ? "27R":"09L", colorClass: "salmon", length: length),
                                                .init(flights: southRunwaysArrivals, labels: minuteLabels, runwayName: facingWest ? "26L":"08R", colorClass: "pink", length: length),
                                                .init(flights: leBourgetArrivals, labels: minuteLabels, runwayName: facingWest ? "27":"07", colorClass: "purple", length: length)]
        
        
        
        let timelineDeparture: (TimelineableFlight) -> Timeline.Flight? = { flight in
            guard let estimatedMovementTime = flight.estimatedMovementTime() else {
                return nil
            }
            let coordinate: Int = Int(estimatedMovementTime.timeIntervalSince(startDate) / 60 * 20)
            if coordinate > length {
                return nil
            }
            let estimate = movementDateFormatter.string(from: estimatedMovementTime)
            return .init(estimate: estimate, callsign: flight.callsign, IAF: abreviatedDeparture(from: flight.departureFix), IAFestimate: "", aircraftType: flight.aircraftType, y: coordinate)
        }
        
        // LFPG departures
        let lfpgDepartures = flightList
            .filter { flight -> Bool in
                flight.origin == "LFPG"
            }
        let northRunwaysDepartures = lfpgDepartures
            .filter { ["27", "09"].contains($0.departureRunway?.prefix(2)) }
            .compactMap(timelineDeparture)
        let southRunwaysDepartures = lfpgDepartures
            .filter { ["26", "08"].contains($0.departureRunway?.prefix(2)) }
            .compactMap(timelineDeparture)
        let leBourgetDepartures = flightList
            .filter { $0.origin == "LFPB" }
            .compactMap(timelineDeparture)
        
        let lfpgDeparturesTimelines: [Timeline] = [.init(flights: northRunwaysDepartures, labels: minuteLabels, runwayName: facingWest ? "27L":"09R", colorClass: "cyan", length: length),
                                                   .init(flights: southRunwaysDepartures, labels: minuteLabels, runwayName: facingWest ? "26R":"08L", colorClass: "cyan", length: length),
                                                   .init(flights: leBourgetDepartures, labels: minuteLabels, runwayName: facingWest ? "25":"09", colorClass: "cyan", length: length)]
        // LFOB
        let lfobDepartures = flightList
            .filter { flight -> Bool in
                flight.origin == "LFOB"
            }
            .compactMap(timelineDeparture)
        let lfobArrivals = flightList
            .filter { flight -> Bool in
                flight.destination == "LFOB"
            }
            .compactMap(timelineArrival)
        let lfobTimelines: [Timeline] = [.init(flights: lfobDepartures, labels: minuteLabels, runwayName: "Départs", colorClass: "blue", length: length),
                                         .init(flights: lfobArrivals, labels: minuteLabels, runwayName: "Arrivées", colorClass: "orange", length: length)]
        
        // LFPO
        let lfpoDepartures = flightList
            .filter { flight -> Bool in
                flight.origin == "LFPO"
            }
            .compactMap(timelineDeparture)
        let lfpoArrivals = flightList
            .filter { flight -> Bool in
                flight.destination == "LFPO"
            }
            .compactMap(timelineArrival)
        let lfpoTimelines: [Timeline] = [.init(flights: lfpoDepartures, labels: minuteLabels, runwayName: "Départs", colorClass: "blue", length: length),
                                         .init(flights: lfpoArrivals, labels: minuteLabels, runwayName: "Arrivées", colorClass: "orange", length: length)]
        
        self.timelinesGroups = [.init(name: "Arrivées LFPG", timelines: lfpgArrivalsTimelines),
                                .init(name: "Départs LFPG", timelines: lfpgDeparturesTimelines),
                                .init(name: "Beauvais", timelines: lfobTimelines),
                                .init(name: "Orly", timelines: lfpoTimelines)]
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

protocol TimelineableFlight {
    func estimatedMovementTime() -> Date?
    
    func estimatedIAFTime() -> Date?
    
    var callsign:String { get }
    var aircraftType:String { get }
    var initialApproachFix:String { get }
    var departureFix:String { get }
    var origin:String { get }
    var departureRunway:String? { get }
    var destination:String { get }
    var destinationRunway:String? { get }
}

extension ATTowerFlight: TimelineableFlight {
    func estimatedMovementTime() -> Date? {
        self.estimatedMovementDate
    }
    
    func estimatedIAFTime() -> Date? {
        self.estimatedIAFDate
    }
    
    var initialApproachFix: String {
        self.iaf ?? ""
    }
    
    var departureFix: String {
        self.departure ?? ""
    }
    
}

extension Flight: TimelineableFlight {
    var initialApproachFix: String {
        self.route.last?.fix ?? ""
    }
    
    var departureFix: String {
        self.route.first?.fix ?? ""
    }
}
