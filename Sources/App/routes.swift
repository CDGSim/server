import Vapor
import SimlogCore
import CSV

// MARK: -
// MARK: Front End Routes

/// Registers the routes for the web front end
func registerFrontEndRoutes(_ app: Application) throws {
    
    // MARK: GET /
    // Renders the home page
    app.get { req -> EventLoopFuture<View> in
        return req.view.render("index")
    }
    
    // Register instructor routes
    // MARK: GET /instructeur/log_path
    InstructorLogRoute.register(with: app)
    
    // MARK: GET /instructeur
    // Renders a view containing all the courses listed in alphabetical order
    app.get("instructeur") { req -> EventLoopFuture<View> in
        
        // Context type that will be passed to the view
        struct Context: Encodable {
            let courses: [Course]
            
            struct Course: Encodable {
                let name: String
                let abstract: String
                let groupNames: [String]
            }
        }
        
        // Enumerate files in the logs folder
        let compareFunction: (String, String) -> Bool = {$0.localizedStandardCompare($1) == .orderedAscending }
        let enumerator = FileManager.default.enumerator(atPath: "Public/logs")
        guard let subpaths = enumerator?.allObjects as? [String]  else {
            // If we cannot get the subpaths, render the error view
            return req.view.render("error")
        }
        
        let courses = subpaths.compactMap { path -> String? in
            // Only include the subfolders
            guard path.components(separatedBy: "/").count == 1 else { return nil }
         
            // Exclude hidden folders
            guard path.first != "." else { return nil }
            
            return path
        }
        .sorted(by: compareFunction)
        .map { path -> Context.Course in
            let url = URL(fileURLWithPath: "Public/logs/" + path)
            let groupNames: [String]
            do {
                groupNames = try FileManager.default
                    .contentsOfDirectory(at: url, includingPropertiesForKeys: [URLResourceKey.isDirectoryKey], options: [.skipsHiddenFiles])
                    .filter { url in
                        url.hasDirectoryPath
                    }
                    .filter{ url in
                        url.lastPathComponent != "Attachments"
                    }
                    .map { url -> String in
                        return url.lastPathComponent
                    }
                    .sorted(by: compareFunction)
            } catch {
                groupNames = []
            }
            
            let notesPath = "Public/logs/" + path + "/Abstract.md"
            let notesContent:String
            do {
                notesContent = try String(contentsOf:URL(fileURLWithPath: notesPath), encoding:.utf8)
            }
            catch {
                notesContent = ""
            }
            
            return .init(name: path, abstract: notesContent, groupNames: groupNames)
        }
        
        // Render the view index, with the context we've made
        let context:Context = .init(courses: courses)
        return req.view.render("instructor/index", context)
    }
    
    // MARK: GET /stage/NOM_DU_STAGE
    // Renders a view containing all the simulations of the specified course
    app.get("stage", ":courseName") { req -> EventLoopFuture<View> in
        guard let courseName = req.parameters.get("courseName") else {
            return req.view.render("error")
        }
        
        // Context type that will be passed to the view
        struct Context: Encodable {
            let name: String
            let notes: String
            
            var rootSimulations: [Simulation]
            let groups: [SimulationGroup]
            
            struct Simulation: Encodable {
                let name: String
                let abstract: String
                let path: String
                let trafficDensity: [Bool]
                let weatherIcon: String
                let minimumNumberOfAttendees: Int?
                let minimumNumberOfPilots: Int?
                let requiresUpdate: Bool
            }
            
            struct SimulationGroup: Encodable {
                let name: String
                var simulations: [Simulation]
            }
        }
        
        // Enumerate files in the logs folder
        let enumerator = FileManager.default.enumerator(atPath: "Public/logs/" + courseName)
        guard let subpaths = enumerator?.allObjects as? [String]  else {
            // If we cannot get the subpaths, render the error view
            return req.view.render("error")
        }
        
        // Fetch tickets and check which simulations require an update
        var simulationsRequiringAnUpdate = [String]()
        if let ticketsContent = try? String(contentsOf: URL(fileURLWithPath: "Public/tickets/tickets.csv")) {
            let csv = try! CSVReader(string: ticketsContent)
            csv.forEach { columns in
                if columns.count >= 5 {
                    let simulationName = columns[1].trimmingCharacters(in: .whitespaces)
                    if columns[4].trimmingCharacters(in: .whitespaces) == "1" {
                        simulationsRequiringAnUpdate.append(simulationName)
                    }
                }
            }
        }
        
        let simulations = subpaths.compactMap { path -> String? in
            // Filter files to only include .simlog files
            guard URL(fileURLWithPath: path).pathExtension == "simlog" else { return nil }
            
            return path
        }.compactMap { path -> Context.Simulation? in
            // Read the simulation name from the log file
            switch log(atPath: courseName + "/" + path) {
            case .failure : return nil // If the log file cannot be read, just ignore it
            case .success(let log):
                let name = log.properties.name
                var trafficDensity = [Bool]()
                for index in 1...4 {
                    trafficDensity.append(index <= log.properties.trafficDensity)
                }
                
                // Determine weather icon
                let iconName:String
                if log.properties.startDate.isDuringDaytime() {
                    if log.properties.weather.contains("SN") {
                        iconName = "cloud-snow"
                    } else if log.properties.weather.contains("TS") || log.properties.weather.contains("CB") {
                        if log.properties.weather.contains("RA") {
                            iconName = "cloud-bolt-rain"
                        } else {
                            iconName = "cloud-bolt"
                        }
                    } else if log.properties.weather.contains("FG") {
                        iconName = "cloud-fog"
                    } else if log.properties.weather.contains("RA") {
                        if log.properties.weather.contains("BKN") || log.properties.weather.contains("OVC") {
                            iconName = "cloud-rain"
                        } else {
                            iconName = "cloud-sun-rain"
                        }
                    } else if log.properties.weather.contains("BKN") || log.properties.weather.contains("OVC") {
                        iconName = "cloud"
                    } else if log.properties.weather.contains("SCT") || log.properties.weather.contains("FEW") {
                        iconName = "cloud-sun"
                    } else {
                        iconName = "sun"
                    }
                } else {
                    if log.properties.weather.contains("SN") {
                        iconName = "cloud-snow"
                    } else if log.properties.weather.contains("TS") || log.properties.weather.contains("CB") {
                        if log.properties.weather.contains("RA") {
                            iconName = "cloud-bolt-rain"
                        } else {
                            iconName = "cloud-moon-bolt"
                        }
                    } else if log.properties.weather.contains("FG") {
                        iconName = "cloud-fog"
                    } else if log.properties.weather.contains("RA") {
                        if log.properties.weather.contains("BKN") || log.properties.weather.contains("OVC") {
                            iconName = "cloud-rain"
                        } else {
                            iconName = "cloud-moon-rain"
                        }
                    } else if log.properties.weather.contains("BKN") || log.properties.weather.contains("OVC") {
                        iconName = "cloud"
                    } else if log.properties.weather.contains("SCT") || log.properties.weather.contains("FEW") {
                        iconName = "cloud-moon"
                    } else {
                        iconName = "moon"
                    }
                }
                
                return .init(name: name, abstract:log.properties.description, path: courseName + "/" + path, trafficDensity: trafficDensity, weatherIcon: iconName, minimumNumberOfAttendees: log.properties.minimumNumberOfAttendees, minimumNumberOfPilots: log.properties.minimumNumberOfPilots, requiresUpdate: simulationsRequiringAnUpdate.contains(name))
            }
        }.sorted { (lhs, rhs) -> Bool in
            lhs.name < rhs.name
        }
        
        var rootSimulations: [Context.Simulation] = []
        var groups: [Context.SimulationGroup] = []
        
        for simulation in simulations {
            let groupName:String?
            let pathComponents = simulation.path.components(separatedBy: "/")
            if pathComponents.count > 3 { groupName = pathComponents[1] } else { groupName = nil }
            if let groupName = groupName {
                let filter: (Context.SimulationGroup) -> Bool = { $0.name == groupName }
                if var group = groups.first(where: filter) {
                    groups.removeAll(where: filter)
                    group.simulations.append(simulation)
                    groups.append(group)
                } else {
                    groups.append(.init(name: groupName, simulations: [simulation]))
                }
            } else {
                rootSimulations.append(simulation)
            }
        }
        
        let notesPath = "Public/logs/" + courseName + "/Notes.md"
        let notesContent:String
        do {
            notesContent = try String(contentsOf:URL(fileURLWithPath: notesPath), encoding:.utf8)
        }
        catch {
            notesContent = ""
        }
        
        // Render the view index, with the context we've made
        let context:Context = .init(name: courseName,
                                    notes: notesContent,
                                    rootSimulations: rootSimulations,
                                    groups: groups.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }))
        return req.view.render("instructor/course", context)
    }
    
    
    
    // MARK: GET /attachment/attachment_path
    // Returns the file at the specified path
    app.get("attachment", "**") { req -> Response in
        
        let path = "Public/logs/" + req.parameters.getCatchall().joined(separator: "/")
        
        return req.fileio.streamFile(at: path)
    }
    
    // MARK: GET /pilote
    // Renders a view containing all logs listed in alphabetical order
    app.get("pilote") { req -> EventLoopFuture<View> in
        // Context type that will be passed to the view
        struct Context: Encodable {
            let courses: [Course]
            
            struct Course: Encodable {
                let name: String
                var simulations: [Simulation]
            }
            
            struct Simulation: Encodable {
                let name: String // Simulation name
                let group: String? // Simulation's group within the course, this is optional
                let path: String // Path to the log file
                let defaultRole: String?
            }
        }
        
        // Enumerate files in the logs folder
        let enumerator = FileManager.default.enumerator(atPath: "Public/logs")
        guard let subpaths = enumerator?.allObjects as? [String]  else {
            // If we cannot get the subpaths, render the error view
            return req.view.render("error")
        }
        
        struct Log {
            let name:String
            let course:String
            let group:String?
            let path:String
            let role:String?
        }
        
        // Create an array of logs from the content of the .simlog files
        let logs = subpaths.compactMap { path -> String? in
            // Filter files to only include .simlog files
            guard URL(fileURLWithPath: path).pathExtension == "simlog" else { return nil }
            
            // Only include files in a subfolder
            guard path.components(separatedBy: "/").count > 1 else { return nil }
            
            return path
        }.compactMap { path -> Log? in
            // Read the simulation name from the log file
            switch log(atPath: path) {
            case .failure : return nil // If the log file cannot be read, just ignore it
            case .success(let log):
                let name = log.properties.name
                var pathComponents = path.components(separatedBy: "/")
                let course = pathComponents.removeFirst()
                let group = pathComponents.count > 1 ? pathComponents.first : nil
                let role = log.pilot_logs.first?.role
                return .init(name: name, course: course, group: group, path: path, role:role)
            }
        }.sorted { (lhs, rhs) -> Bool in
            lhs.name < rhs.name
        }
        
        var courses = [Context.Course]()
        for log in logs {
            let simulation = Context.Simulation(name: log.name, group: log.group, path: log.path, defaultRole: log.role)
            if let courseIndex = courses.firstIndex(where: { $0.name == log.course }) {
                courses[courseIndex].simulations.append(simulation)
            } else {
                courses.append(.init(name: log.course, simulations: [simulation]))
            }
        }
        courses.sort { (lhs, rhs) -> Bool in
            lhs.name < rhs.name
        }
        
        // Render the view index, with the context we've made
        let context:Context = .init(courses: courses)
        return req.view.render("pilot/index", context)
    }
    
    // MARK: GET /pilote/role/log_path
    // Renders a view for a pilot with the specified role
    app.get("pilote", ":role", "**") { req -> EventLoopFuture<View> in
        struct Context: Encodable {
            struct Attachment: Encodable {
                let url:String
                let name:String
            }
            let path:String
            let pilot_log: Log.PilotLog
            let simulation_properties: SimulationProperties
            let roles: [String]
            let displayEventsLocation: Bool
            let displayEventsCommand: Bool
            let attachments: [Attachment]?
        }
        
        let path = req.parameters.getCatchall().joined(separator: "/")
        let roleName = req.parameters.get("role")!
        
        // Read the log file
        switch logWithSortedEvents(atPath: path) {
        case .failure(let error) :
            return renderLogErrorView(from: error, req: req)
        case .success(let log):
            guard let pilotLog = log.pilot_logs.first(where: { pilotLog -> Bool in
                pilotLog.role == roleName
            }) else {
                return req.view.render("error", ["reason":"Role non trouvé pour ce log"])
            }
            
            // Check if we should display the events locations
            // Location is optional, if at least one event has a location, we should display the corresponding column
            let atLeastOneEventContainsALocation: Bool
            if let eventsWithLocation = pilotLog.events?.filter({ event in
                if let location = event.location {
                    return location != "-" && location.count > 0
                } else { return false }
            }) {
                atLeastOneEventContainsALocation = eventsWithLocation.count > 0
            } else {
                atLeastOneEventContainsALocation = false
            }
            
            // Check if we should display the events commands
            // Command is optional, if at least one event has a command, we should display the corresponding column
            let atLeastOneEventContainsACommand: Bool
            if let eventsWithCommand = pilotLog.events?.filter({ event in
                if let command = event.command {
                    return command != "-" && command.count > 0
                } else { return false }
            }) {
                atLeastOneEventContainsACommand = eventsWithCommand.count > 0
            } else {
                atLeastOneEventContainsACommand = false
            }
            
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
            if let courseRelativePath = req.parameters.getCatchall().first {
                let courseAttachmentsContainerURL = URL(fileURLWithPath: "Public/logs").appendingPathComponent(courseRelativePath, isDirectory: true)
                    .appendingPathComponent("Attachments", isDirectory: true)
                let courseAttachmentsFolderPath = courseRelativePath + "/Attachments/"
                appendAttachments(atURL: courseAttachmentsContainerURL, to: &attachments, attachmentsPath: courseAttachmentsFolderPath)
            }
            
            let context = Context(path: path, pilot_log: pilotLog, simulation_properties:.init(from: log.properties), roles:log.pilot_logs.map{ pilotLog in
                pilotLog.role
            }, displayEventsLocation: atLeastOneEventContainsALocation, displayEventsCommand: atLeastOneEventContainsACommand, attachments: attachments)
            return req.view.render("pilot/log_pilot", context)
        }
    }
    
    // MARK: GET /print2/log_path
    // Renders a view to print the complete log all at once
    // Can be used to generate PDF via a web browser
    app.get("print2", "**") { req -> EventLoopFuture<View> in
        struct Context: Encodable {
            // Type to replace Log.Properties.ControlPositionAssignment
            // This type has a positionsDescription string instead of a set of positions
            struct ControlPositionAssignment: Encodable {
                let controller: Log.Properties.Controller
                let positionsDescription: String
            }
            let path:String
            let log: Log
            let properties: SimulationProperties
            let assignments: [ControlPositionAssignment]?
            
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
            
            init(path:String, log:Log) {
                self.path = path
                
                // Edit the log to sort events for the pilots by date
                var editedLog = log
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "HH:mm"
                editedLog.pilot_logs = editedLog.pilot_logs.map({ pilotLog in
                    var log = pilotLog
                    log.events = pilotLog.events?.sorted(by: { (eventA, eventB) -> Bool in
                        guard let dateA = dateFormatter.date(from: eventA.time), let dateB = dateFormatter.date(from: eventB.time) else {
                            return true
                        }
                        return dateA < dateB
                    })
                    return log
                })
                self.log = editedLog
                
                self.properties = .init(from: log.properties)
                
                // Build up assignments
                // We need to make the positionDescriptions string from the set of positions
                self.assignments = editedLog.properties.assignments?.map { assignment -> Context.ControlPositionAssignment in
                    let positionDescriptions = Array(assignment.positions).map { controlPosition in
                        controlPosition.rawValue
                    }.sorted().joined(separator: " - ")
                    return .init(controller: .instructor, positionsDescription: positionDescriptions)
                }
                
                do {
                    let simulation =  try electraSimulation(associatedWithLogAtPath: path)
                    
                    // Get rerouted flights
                    let flights = reroutedFlights(in:simulation)
                    self.reroutedFlightsToNorthRunways = flights.0
                    self.reroutedFlightsToSouthRunways = flights.1
                    
                    // Length of the timeline according to simulation's duration
                    let duration = simulation.duration
                    let startDate = simulation.date
                        let length = duration * 13
                        
                        // Build minute labels
                        var calendar = Calendar(identifier: .gregorian)
                        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                        
                        var minuteLabels = [Timeline.MinuteLabel]()
                        var currentDate = startDate
                        while currentDate.timeIntervalSince(startDate) < TimeInterval(duration * 60) {
                            let components = calendar.dateComponents([.hour, .minute], from: currentDate)
                            if let hours = components.hour, let minutes = components.minute {
                                minuteLabels.append(.init(hours: hours, minutes: minutes, y: Int(currentDate.timeIntervalSince(startDate) / 60 * 13)))
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
                            let coordinate: Int = Int(estimatedMovementTime.timeIntervalSince(startDate) / 60 * 13)
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
                            let coordinate: Int = Int(estimatedMovementTime.timeIntervalSince(startDate) / 60 * 13)
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
                        
                        // LFOB
                        let lfobDepartures = simulation.flights
                            .filter { flight -> Bool in
                                flight.origin == "LFOB"
                            }
                            .compactMap(timelineDeparture)
                        let lfobArrivals = simulation.flights
                            .filter { flight -> Bool in
                                flight.destination == "LFOB"
                            }
                            .compactMap(timelineArrival)
                        let lfobTimelines: [Timeline] = [.init(flights: lfobDepartures, labels: minuteLabels, runwayName: "Départs", colorClass: "blue", length: length),
                                                                   .init(flights: lfobArrivals, labels: minuteLabels, runwayName: "Arrivées", colorClass: "orange", length: length)]
                        
                        // LFPO
                        let lfpoDepartures = simulation.flights
                            .filter { flight -> Bool in
                                flight.origin == "LFPO"
                            }
                            .compactMap(timelineDeparture)
                        let lfpoArrivals = simulation.flights
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
                } catch {
                    self.timelinesGroups = []
                    self.reroutedFlightsToNorthRunways = []
                    self.reroutedFlightsToSouthRunways = []
                }
            }
        }
        
        let path = req.parameters.getCatchall().joined(separator: "/")
        
        // Read the log file
        switch log(atPath: path) {
        case .failure(let error) :
            return renderLogErrorView(from: error, req: req)
        case .success(let log):
            let context = Context(path: path, log: log)
            return req.view.render("print2", context)
        }
    }
    
    // MARK: GET /print/log_path
    // Renders a view to print the complete log all at once
    // Can be used to generate PDF via a web browser
    app.get("print", "**") { req -> EventLoopFuture<View> in
        struct Context: Encodable {
            let path:String
            let log: Log
            let properties:SimulationProperties
            
            init(path:String, log:Log) {
                self.path = path
                
                // Edit the log to sort events for the pilots by date
                var editedLog = log
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "HH:mm"
                editedLog.pilot_logs = editedLog.pilot_logs.map({ pilotLog in
                    var log = pilotLog
                    log.events = pilotLog.events?.sorted(by: { (eventA, eventB) -> Bool in
                        guard let dateA = dateFormatter.date(from: eventA.time), let dateB = dateFormatter.date(from: eventB.time) else {
                            return true
                        }
                        return dateA < dateB
                    })
                    return log
                })
                self.log = editedLog
                
                self.properties = .init(from: log.properties)
            }
        }
        
        let path = req.parameters.getCatchall().joined(separator: "/")
        
        // Read the log file
        switch log(atPath: path) {
        case .failure(let error) :
            return renderLogErrorView(from: error, req: req)
        case .success(let log):
            let context = Context(path: path, log: log)
            return req.view.render("print", context)
        }
    }
    
    // Register tickets routes
    TicketRoutes.register(with: app)
    
    // MARK: GET /apple-touch-icon.png
    // Returns the icon for web app clip
    app.get("apple-touch-icon.png") { req -> Response in
        
        let path = "Resources/apple-touch-icon.png"
        
        return req.fileio.streamFile(at: path)
    }
    
    // MARK: GET /inventaire
    // Renders a view containing all logs listed in alphabetical order
    app.get("inventaire") { req -> EventLoopFuture<View> in
        // Context type that will be passed to the view
        struct Context: Encodable {
            let courses: [Course]
            
            struct Course: Encodable {
                let name: String
                var simulations: [Simulation]
            }
            
            struct Simulation: Encodable {
                let name: String // Simulation name
                let group: String? // Simulation's group within the course, this is optional
                let description: String
                let trafficDensity: [Bool]
                let minimumNumberOfAttendees: Int?
                let minimumNumberOfPilots: Int?
            }
        }
        
        // Enumerate files in the logs folder
        let enumerator = FileManager.default.enumerator(atPath: "Public/logs")
        guard let subpaths = enumerator?.allObjects as? [String]  else {
            // If we cannot get the subpaths, render the error view
            return req.view.render("error")
        }
        
        // Create an array of logs from the content of the .simlog files
        let logs = subpaths.compactMap { path -> String? in
            // Filter files to only include .simlog files
            guard URL(fileURLWithPath: path).pathExtension == "simlog" else { return nil }
            
            // Only include files in a subfolder
            guard path.components(separatedBy: "/").count > 1 else { return nil }
            
            return path
        }.compactMap { path -> (Log, String, String?)? in
            // Read the simulation name from the log file
            switch log(atPath: path) {
            case .failure : return nil // If the log file cannot be read, just ignore it
            case .success(let log):
                var pathComponents = path.components(separatedBy: "/")
                let course = pathComponents.removeFirst()
                let group = pathComponents.count > 1 ? pathComponents.first : nil
                return (log, course, group)
            }
        }.sorted { (lhs, rhs) -> Bool in
            lhs.0.properties.name < rhs.0.properties.name
        }
        
        var courses = [Context.Course]()
        for (log, course, group) in logs {
            
            var trafficDensity = [Bool]()
            for index in 1...4 {
                trafficDensity.append(index <= log.properties.trafficDensity)
            }
            
            let simulation = Context.Simulation(name: log.properties.name,
                                                group: group,
                                                description: log.properties.description,
                                                trafficDensity: trafficDensity,
                                                minimumNumberOfAttendees: log.properties.minimumNumberOfAttendees,
                                                minimumNumberOfPilots: log.properties.minimumNumberOfPilots
            )
            if let courseIndex = courses.firstIndex(where: { $0.name == course }) {
                courses[courseIndex].simulations.append(simulation)
            } else {
                courses.append(.init(name: course, simulations: [simulation]))
            }
        }
        courses.sort { (lhs, rhs) -> Bool in
            lhs.name < rhs.name
        }
        
        // Render the view index, with the context we've made
        let context:Context = .init(courses: courses)
        return req.view.render("inventaire/index", context)
    }
}


// MARK: -
// MARK: API Routes

/// Registers routes for the API
/// The API only delivers raw JSON files when receiving GET requests
func registerAPIRoutes(_ app: Application) throws {
    
    
    let api = app.grouped("api")
    
    // MARK: GET /api/logs/
    api.get("logs") { req -> LogsResponse  in
        
        // Enumerate files in the logs folder
        let enumerator = FileManager.default.enumerator(atPath: "Public/logs")
        guard let subpaths = enumerator?.allObjects as? [String]  else {
            // If we cannot get the subpaths, return an empty array
            return LogsResponse(simulations: [])
        }
        
        // Create an array of LogsResponse.Log values from the content of the .simlog files
        let simulations = subpaths.compactMap { path -> String? in
            // Filter files to only include .simlog files
            guard URL(fileURLWithPath: path).pathExtension == "simlog" else {
                return nil
            }
            return path
        }.compactMap { path -> LogsResponse.Log? in
            // Read the simulation name from the log file
            switch log(atPath: path) {
            case .failure : return nil // If the log file cannot be read, just ignore it
            case .success(let log):
                let name = log.properties.name
                return LogsResponse.Log(id: UUID().uuidString,
                                        path:path,
                                        name: name,
                                        configuration:log.properties.configuration,
                                        duration:log.properties.duration,
                                        description: log.properties.description)
            }
        }.sorted { lhs, rhs -> Bool in
            // Sort by name here
            lhs.name < rhs.name
        }
        
        let response = LogsResponse(simulations: simulations)
        return response
    }
    
    // Response type sent when calling GET /api/logs
    struct LogsResponse: Content {
        struct Log: Codable {
            let id: String
            let path:String
            let name: String
            let configuration: String
            let duration: Int
            let description: String?
        }
        let simulations: [Log]
    }
    
    // MARK: GET /api/logs/log_path
    // Returns the log as a response
    api.get("log", "**") { req -> Log  in
        let path = req.parameters.getCatchall().joined(separator: "/")
        
        switch log(atPath: path) {
        case .failure :
            throw Abort(.notFound)
        case .success(let log):
            return log
        }
    }
    
    // MARK: POST /api/setup-decor
    // Configures DECOR screen with provided parameters
    api.post("setup-decor") { req -> EventLoopFuture<Response>  in
        struct DecorSetupParameters: Content {
            let metar:String
            let configuration: String
            let date: Date
        }
        let parameters = try req.content.decode(DecorSetupParameters.self)
        for index in 1...10 {
            DecorData.metars[index] = parameters.metar
            DecorData.configurations[index] = parameters.configuration
            DecorData.dates[index] = parameters.date
        }
        return req.eventLoop.makeSucceededFuture(.init())
    }
    
    // MARK: GET /api/tickets/
    api.get("tickets") { req -> TicketsResponse  in
        guard let ticketsContent = try? String(contentsOf: URL(fileURLWithPath: "Public/tickets/tickets.csv")) else {
            return TicketsResponse(tickets: [])
        }
        let csv = try! CSVReader(string: ticketsContent)
        
        let dateFormatter = ISO8601DateFormatter()
        
        let tickets = csv.filter { columns in
            return (columns.count == 5 || columns.count == 6) && dateFormatter.date(from: columns[0]) != nil
        }
        
        let responses = tickets.indices
        .map { index -> TicketsResponse.Ticket in
            let columns = tickets[index]
            let date = dateFormatter.date(from: columns[0])!
            let simulation = columns[1]
            let authorName = columns[2]
            let feedback = columns[3].trimmingCharacters(in: CharacterSet(charactersIn:"\""))
            let simulationRequiresAnUpdate = columns[4] == "1"
            let comments: String? = columns.count == 6 ? columns[5].trimmingCharacters(in: CharacterSet(charactersIn:"\"")) : nil
            return TicketsResponse.Ticket(id: index, simulation: simulation, date: date, authorName: authorName, feedback: feedback, simulationRequiresAnUpdate: simulationRequiresAnUpdate, commentsFromTrainingDept: comments)
        }
        return TicketsResponse(tickets: responses)
    }
    
    // Response type sent when calling GET /api/tickets
    struct TicketsResponse: Content {
        struct Ticket: Codable {
            let id: Int
            let simulation: String
            let date: Date
            let authorName: String
            let feedback: String
            let simulationRequiresAnUpdate: Bool
            let commentsFromTrainingDept: String?
        }
        let tickets: [Ticket]
    }
    
    // MARK: POST /api/ticket/X
    // Configures DECOR screen with provided parameters
    api.post("ticket", ":id") { req -> EventLoopFuture<Response>  in
        
        enum UpdateTicketError: Error {
            case noCSVFileFound, couldNotUpdateCSVFile, couldNotDecodePayload
        }
        
        let ticketID = req.parameters.get("id")!
        guard let id = Int(ticketID) else {
            return req.eventLoop.makeSucceededFuture(.init())
        }
        
        struct TicketContent:Codable {
            let id: Int
            let simulation: String
            let date: Date
            let authorName: String
            let feedback: String
            let simulationRequiresAnUpdate: Bool
            let commentsFromTrainingDept: String?
        }
        let content:TicketContent
        do {
            content = try req.content.decode(TicketContent.self)
        } catch {
            return req.eventLoop.makeFailedFuture(UpdateTicketError.couldNotDecodePayload)
        }
        
        guard let ticketsContent = try? String(contentsOf: URL(fileURLWithPath: "Public/tickets/tickets.csv")) else {
            return req.eventLoop.makeFailedFuture(UpdateTicketError.noCSVFileFound)
        }
        let csv = try! CSVReader(string: ticketsContent)
        
        // Writer
        guard let outpoutStream = OutputStream(toFileAtPath: "Public/tickets/tickets.csv", append: false) else {
            return req.eventLoop.makeFailedFuture(UpdateTicketError.noCSVFileFound)
        }
        do {
            let writer = try CSVWriter(stream: outpoutStream)
            
            for (index, row) in csv.enumerated() {
                writer.beginNewRow()
                if index == id + 1 {
                    // Update row
                    try writer.write(field: row[0])
                    try writer.write(field: row[1])
                    try writer.write(field: row[2])
                    try writer.write(field: row[3])
                    try writer.write(field: content.simulationRequiresAnUpdate ? "1": "0")
                    try writer.write(field: content.commentsFromTrainingDept ?? "")
                } else {
                    // Copy row
                    try writer.write(row: row)
                }
            }
            
            writer.stream.close()
        } catch {
            return req.eventLoop.makeFailedFuture(UpdateTicketError.couldNotUpdateCSVFile)
        }
        return req.eventLoop.makeSucceededFuture(.init())
    }
}

// Make Log conform to Content protocol so that when can return a Log as a response
extension Log: Content { }

private struct DecorData {
    static var metars: [Int:String] = [:]
    static var configurations: [Int:String] = [:]
    static var dates: [Int:Date] = [:]
}

func registerDecorRoutes(_ app: Application) throws {
    struct SetupContext: Encodable {
        let message:String
        let configuration:String
        let metar: String
        let decor1: Bool
        let decor2: Bool
        let decor3: Bool
        let decor4: Bool
        let decor5: Bool
        let decor6: Bool
        let decor7: Bool
        let decor8: Bool
        let decor9: Bool
        let decor10: Bool
    }
	
    // MARK: GET /decor/ID/
    app.get("decor", ":id") { req -> EventLoopFuture<View> in
        let idString = req.parameters.get("id")!
        if let id = Int(idString), let metar = DecorData.metars[id], let configuration = DecorData.configurations[id], let date = DecorData.dates[id] {
            return DecorController.view(req: req, metar: metar, configuration: configuration, startDate: date)
        }
        // Return a page containing the id in big letters
        // and a background color depending on the id
        let colors = ["3D4766", "2E354C", "1F2433", "0F1219", "000"]
        let color:String
        if let id = Int(idString) {
            var index = 5 - id
            if index < 0 { index = abs(index + 1) }
            color = "#" + colors[index]
        } else {
            // Id is not and integer
            color = "red"
        }
        let params = ["reason":"Cet écran DECOR n'est pas configuré",
                      "id":idString,
                      "color":color]
        return req.view.render("decor-error", params)
    }
    
    // MARK: GET /decor/setup
    app.get("decor", "setup") { req -> EventLoopFuture<View> in
        let configuration:String = DecorData.configurations[1] ?? "WL"
        let metar = DecorData.metars[1] ?? "CAVOK"
        return req.view.render("decor-setup", SetupContext(message: "",
                                                           configuration: configuration,
                                                           metar: metar,
                                                           decor1: true,
                                                           decor2: true,
                                                           decor3: true,
                                                           decor4: true,
                                                           decor5: true,
                                                           decor6: true,
                                                           decor7: true,
                                                           decor8: true,
                                                           decor9: true,
                                                           decor10: true))
    }
    
    // MARK: GET /decor/setup/METAR
    app.get("decor", "setup", ":metar") { req -> EventLoopFuture<View> in
        let metar:String
        if let metarParameter = req.parameters.get("metar") {
            metar = metarParameter
        } else {
            metar = DecorData.metars[1] ?? "CAVOK"
        }
        let configuration:String = DecorData.configurations[1] ?? "WL"
        return req.view.render("decor-setup", SetupContext(message: "",
                                                           configuration: configuration,
                                                           metar: metar,
                                                           decor1: true,
                                                           decor2: true,
                                                           decor3: true,
                                                           decor4: true,
                                                           decor5: true,
                                                           decor6: true,
                                                           decor7: true,
                                                           decor8: true,
                                                           decor9: true,
                                                           decor10: true))
    }
    
    // MARK: POST /decor1/setup
    app.post("decor", "setup") { req -> EventLoopFuture<View> in
        struct Post: Content {
            var metar: String
            var configuration: String
            var decor1: Bool
            var decor2: Bool
            var decor3: Bool
            var decor4: Bool
            var decor5: Bool
            var decor6: Bool
            var decor7: Bool
            var decor8: Bool
            var decor9: Bool
            var decor10: Bool
        }
        let content = try req.content.decode(Post.self)
        
        let decorSettings = [content.decor1, content.decor2, content.decor3, content.decor4, content.decor5, content.decor6, content.decor7, content.decor8, content.decor9, content.decor10]
        for index in 1...10 {
            let setting = decorSettings[index - 1]
            if setting == true {
                DecorData.metars[index] = content.metar
                DecorData.configurations[index] = content.configuration
                DecorData.dates[index] = Date()
            }
        }
        
        return req.view.render("decor-setup", SetupContext(message: "Données transmises : \(content.metar) - Configuration \(content.configuration.uppercased())",
                                                           configuration: content.configuration,
                                                           metar: content.metar,
                                                           decor1: content.decor1,
                                                           decor2: content.decor2,
                                                           decor3: content.decor3,
                                                           decor4: content.decor4,
                                                           decor5: content.decor5,
                                                           decor6: content.decor6,
                                                           decor7: content.decor7,
                                                           decor8: content.decor8,
                                                           decor9: content.decor9,
                                                           decor10: content.decor10))
    }
    
    // MARK: GET /decor/log_path
    // Renders a view representing a DECOR screen
    // Generates values from the simulation file
    app.get("decor", "**") { req -> EventLoopFuture<View> in
        let path = req.parameters.getCatchall().joined(separator: "/")
        
        // Read the log file
        switch log(atPath: path) {
        case .failure(let error) :
            return renderLogErrorView(from: error, req: req)
        case .success(let log):
            return DecorController.view(req: req, log: log)
        }
        
    }
    
    // MARK: GET /decorgenerator/
    app.get("decorgenerator") { req -> EventLoopFuture<View> in
        return req.view.render("decorgenerator")
    }
    
    // MARK: POST /decorgenerator/
    app.post("decorgenerator") { req -> EventLoopFuture<View> in
        struct FormContent: Content {
            var weather: String
            var configuration: String
            var date: String
        }
        let content = try req.content.decode(FormContent.self)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        let date = dateFormatter.date(from: content.date) ?? Date()
        return DecorController.view(req: req, metar: content.weather, configuration: content.configuration, startDate: date)
    }
}

struct SimulationProperties: Encodable {
    let name: String
    let update_date: Date
    let description: String
    let configuration: String
    let start_date:Date
    let duration:Int
    let traffic_density_description: String
    let weather:String
    let metar:String
    let qnh: Int
    let objectives:String
    
    init(from properties:Log.Properties) {
        name = properties.name
        update_date = properties.updateDate
        description = properties.description
        configuration = properties.configuration
        start_date = properties.startDate
        duration = properties.duration
        
        switch properties.trafficDensity {
            case 1: traffic_density_description = "Faible"
            case 2: traffic_density_description = "Modérée"
            case 3: traffic_density_description = "Modérée à forte"
            case 4: traffic_density_description = "Forte"
            default: traffic_density_description = ""
        }
        
        let weather = Weather(from: properties.weather)
        qnh = weather.qnh
        let windDirection:String
        if weather.windDirection >= 100 {
            windDirection = "\(weather.windDirection)"
        } else {
            windDirection = "0\(weather.windDirection)"
        }
        self.weather = "\(weather.readable) - \(windDirection)° \(weather.windSpeed) KT"
        
        self.metar = properties.weather
        
        self.objectives = properties.objectives
    }
}
