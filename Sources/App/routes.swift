import Vapor
import SimlogCore

// MARK: Log file reading

// Possible errors when trying to read a log file
fileprivate enum LogError: Error {
    case notFound, couldNotDecode
}

/// Reads a log file located at path
private func log(atPath path: String) -> Result<Log, LogError> {
    guard let logData = FileManager.default.contents(atPath: "Public/logs/\(path)") else {
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

// MARK: -
// MARK: Front End Routes

/// Registers the routes for the web front end
func registerFrontEndRoutes(_ app: Application) throws {
    
    // MARK: GET /
    // Renders a view containing all logs listed in alphabetical order
    app.get { req -> EventLoopFuture<View> in
        
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
                var pathComponents = path.components(separatedBy: "/")
                let name = log.properties.name
                let course = pathComponents.removeFirst()
                let group:String?
                if pathComponents.count > 1 { group = pathComponents.first } else { group = nil }
                return .init(name: name, course: course, group: group, path: path)
            }
        }.sorted { (lhs, rhs) -> Bool in
            lhs.name < rhs.name
        }
        
        var courses = [Context.Course]()
        for log in logs {
            let simulation = Context.Simulation(name: log.name, group: log.group, path: log.path)
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
        return req.view.render("index", context)
    }
    
    // MARK: GET /instructeur
    // Renders a view containing all the courses listed in alphabetical order
    app.get("instructeur") { req -> EventLoopFuture<View> in
        
        // Context type that will be passed to the view
        struct Context: Encodable {
            let courses: [Course]
            
            struct Course: Encodable {
                let name: String
            }
        }
        
        // Enumerate files in the logs folder
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
        .sorted(by: <)
        .map { path -> Context.Course in
            .init(name: path)
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
                return .init(name: name, abstract:log.properties.description, path: courseName + "/" + path)
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
                                    groups: groups)
        return req.view.render("instructor/course", context)
    }
    
    // MARK: GET /instructeur/log_path
    // Renders a view for the instructor
    app.get("instructeur", "**") { req -> EventLoopFuture<View> in
        struct Context: Encodable {
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
                var attachments: [Context.Attachment]? = nil
                var url = URL(fileURLWithPath: "Public/logs")
                url.appendPathComponent(path)
                url.deleteLastPathComponent()
                url.appendPathComponent("Attachments", isDirectory: true)
                let enumerator = FileManager.default.enumerator(atPath: url.path)
                if let subpaths = enumerator?.allObjects as? [String] {
                    let attachmentsFolderPath = path.components(separatedBy: "/").dropLast().joined(separator: "/") + "/Attachments/"
                    attachments = subpaths.map{ path in
                        Context.Attachment(url:attachmentsFolderPath + path, name:path)
                    }
                }
                self.attachments = attachments
                
                // Read notes.md
                var notesURL = URL(fileURLWithPath: "Public/logs")
                notesURL.appendPathComponent(path)
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
            }
        }
        
        let path = req.parameters.getCatchall().joined(separator: "/")
        
        // Read the log file
        switch log(atPath: path) {
        case .failure(let error) :
            return renderLogErrorView(from: error, req: req)
        case .success(let log):
            return req.view.render("instructor/log_instructor", Context(from: log, path: path))
        }
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
                var pathComponents = path.components(separatedBy: "/")
                let name = log.properties.name
                let course = pathComponents.removeFirst()
                let group:String?
                if pathComponents.count > 1 { group = pathComponents.first } else { group = nil }
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
            let path:String
            let pilot_log: Log.PilotLog
            let simulation_properties: SimulationProperties
            let roles: [String]
            let displayEventsLocation: Bool
        }
        
        let path = req.parameters.getCatchall().joined(separator: "/")
        let roleName = req.parameters.get("role")!
        
        // Read the log file
        switch log(atPath: path) {
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
            
            
            let context = Context(path: path, pilot_log: pilotLog, simulation_properties:.init(from: log.properties), roles:log.pilot_logs.map{ pilotLog in
                pilotLog.role
            }, displayEventsLocation: atLeastOneEventContainsALocation)
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
                    }.sorted().joined(separator: "<br />")
                    return .init(controller: .instructor, positionsDescription: positionDescriptions)
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
}

// Make Log conform to Content protocol so that when can return a Log as a response
extension Log: Content { }

private struct DecorData {
    static var metars: [Int:String] = [1:"13014KT CAVOK M01/M11 Q1033"]
    static var configurations: [Int:String] = [1:"WL"]
    static var dates: [Int:Date] = [1:Date()]
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
        if let idString = req.parameters.get("id"), let id = Int(idString), let metar = DecorData.metars[id], let configuration = DecorData.configurations[id], let date = DecorData.dates[id] {
            return DecorController.view(req: req, metar: metar, configuration: configuration, startDate: date)
        } else {
            return req.view.render("decor-error", ["reason":"Cet écran DECOR n'est pas configuré"])
        }
    }
    
    // MARK: GET /decor/setup
    app.get("decor", "setup") { req -> EventLoopFuture<View> in
        return req.view.render("decor-setup", SetupContext(message: "",
                                                           configuration: DecorData.configurations[1]!,
                                                           metar: DecorData.metars[1]!,
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
        let metar: String
        if let metarParameter = req.parameters.get("metar") {
            metar = metarParameter
        } else {
            metar = DecorData.metars[1]!
        }
        return req.view.render("decor-setup", SetupContext(message: "",
                                                           configuration: DecorData.configurations[1]!,
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


// Renders the error view, passing a reason string as the context
fileprivate func renderLogErrorView(from error:LogError, req:Request) -> EventLoopFuture<View> {
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
