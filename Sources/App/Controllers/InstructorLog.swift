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
    }
}
