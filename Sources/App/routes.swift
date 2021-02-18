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
    return .success(log)
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
    
    // MARK: GET /instructor/log_path
    // Renders a view for the instructor
    app.get("instructor", "**") { req -> EventLoopFuture<View> in
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
            let simulation_properties: Log.Properties
            let log: Log
            let assignments: [ControlPositionAssignment]?
            let attachments: [Attachment]?
            let displayEventsLocation: Bool
        }
        
        let path = req.parameters.getCatchall().joined(separator: "/")
        
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
        
        // Read the log file
        switch log(atPath: path) {
        case .failure(let error) :
            return renderLogErrorView(from: error, req: req)
        case .success(let log):
            // Build up assignments
            // We need to make the positionDescriptions string from the set of positions
            let assignments = log.properties.assignments?.map { assignment -> Context.ControlPositionAssignment in
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
            
            let context = Context(path: path, simulation_properties:log.properties, log: log, assignments: assignments, attachments:attachments, displayEventsLocation: atLeastOneEventContainsALocation)
            return req.view.render("log_instructor", context)
        }
    }
    
    // MARK: GET /attachment/attachment_path
    // Returns the file at the specified path
    app.get("attachment", "**") { req -> Response in
        
        let path = "Public/logs/" + req.parameters.getCatchall().joined(separator: "/")
        
        return req.fileio.streamFile(at: path)
    }
    
    // MARK: GET /pilot/role/log_path
    // Renders a view for a pilot with the specified role
    app.get("pilot", ":role", "**") { req -> EventLoopFuture<View> in
        struct Context: Encodable {
            let path:String
            let pilot_log: Log.PilotLog
            let simulation_properties: Log.Properties
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
            
            // Sort events
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm:ss"
            let alternateDateFormatter = DateFormatter()
            alternateDateFormatter.dateFormat = "HH:mm"
            let sortedEvents = pilotLog.events?.sorted(by: { (lhs, rhs) -> Bool in
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
            })
            var pilotLogWithSortedEvents = pilotLog
            pilotLogWithSortedEvents.events = sortedEvents
            
            let context = Context(path: path, pilot_log: pilotLogWithSortedEvents, simulation_properties:log.properties, roles:log.pilot_logs.map{ pilotLog in
                pilotLog.role
            }, displayEventsLocation: atLeastOneEventContainsALocation)
            return req.view.render("log_pilot", context)
        }
    }
    
    // MARK: GET /print/log_path
    // Renders a view to print the complete log all at once
    // Can be used to generate PDF via a web browser
    app.get("print", "**") { req -> EventLoopFuture<View> in
        struct Context: Encodable {
            let path:String
            let log: Log
            
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
}

// Make Log conform to Content protocol so that when can return a Log as a response
extension Log: Content { }

private struct DecorData {
    static var decor1: String = "??"
    static var configuration1: String = "??"
}

func registerDecorRoutes(_ app: Application) throws {
    // MARK: GET /decor1/
    app.get("decor1") { req -> EventLoopFuture<View> in
        return DecorController.view(req: req, metar: DecorData.decor1, configuration: DecorData.configuration1, startDate: Date())
    }
    
    // MARK: GET /decor1/setup
    app.get("decor1", "setup") { req -> EventLoopFuture<View> in
        return req.view.render("decor1")
    }
    
    // MARK: POST /decor1/
    app.post("decor1") { req -> EventLoopFuture<View> in
        struct Post: Content {
            var metar: String
            var configuration: String
        }
        let content = try req.content.decode(Post.self)
        DecorData.decor1 = content.metar
        DecorData.configuration1 = content.configuration
        return DecorController.view(req: req, metar: DecorData.decor1, configuration: DecorData.configuration1, startDate: Date())
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
    return req.view.render("error", reason)
}
