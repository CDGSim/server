import Vapor
import SimlogCore


/// Registers the routes for the web front end
func registerFrontEndRoutes(_ app: Application) throws {
    
    // GET /
    // Renders a view containing all logs listed in alphabetical order
    app.get { req -> EventLoopFuture<View> in
        
        // Context that will be passed to the view
        struct Context: Encodable {
            struct LogItem: Encodable {
                let name: String
                let group: String
                let path: String
            }
            
            let logs: [LogItem]
        }
        
        // Enumerate files in the logs folder
        let enumerator = FileManager.default.enumerator(atPath: "Public/logs")
        guard let subpaths = enumerator?.allObjects as? [String]  else {
            // If we cannot get the subpaths, render an error
            return req.view.render("error")
        }
            
        // Create an array of LogItem values from the content of the .simlog files
        let logs = subpaths.compactMap { path -> String? in
            // Filter files to only include .simlog files
            guard URL(fileURLWithPath: path).pathExtension == "simlog" else {
                return nil
            }
            return path
        }.map { path -> Context.LogItem in
            let fileNameWithoutExtension = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let group = path.components(separatedBy: "/").first
            return Context.LogItem(name:fileNameWithoutExtension, group:group ?? "", path:path)
        }.sorted { lhs, rhs -> Bool in
            // Sort by name here
            lhs.name < rhs.name
        }
        
        // Render the view index, with the context we've made
        let context:Context = .init(logs: logs)
        return req.view.render("index", context)
    }
}

func routes(_ app: Application) throws {
    
    struct LogsResponse: Content {
        struct Log: Codable {
            let id: String
            let path:String
            let name: String
            let description: String?
        }
        let simulations: [Log]
    }
    
    app.get("api", "logs") { req -> LogsResponse  in
        // Enumerate files in the logs folder
        let enumerator = FileManager.default.enumerator(atPath: "Public/logs")
        guard let subpaths = enumerator?.allObjects as? [String]  else {
            // If we cannot get the subpaths, return an empty array
            return LogsResponse(simulations: [])
        }
        
        // Create an array of SimulationIndex values from the content of the .simlog files
        let simulations = subpaths.compactMap { path -> String? in
            // Filter files to only include .simlog files
            guard URL(fileURLWithPath: path).pathExtension == "simlog" else {
                return nil
            }
            return path
        }.compactMap { path -> LogsResponse.Log? in
            let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            
            switch log(atPath: path) {
                case .success(let log) :
                    return LogsResponse.Log(id: name, path:path, name: name, description: log.properties.description)
                case .failure :
                    return nil
            }
        }.sorted { lhs, rhs -> Bool in
            // Sort by name here
            lhs.name < rhs.name
        }
        
        let response = LogsResponse(simulations: simulations)
        return response
    }
    
    app.get("api", "log", "**") { req -> Log  in
        let path = req.parameters.getCatchall().joined(separator: "/")
        
        switch log(atPath: path) {
        case .failure :
            throw Abort(.notFound)
        case .success(let log):
            return log
        }
    }
    
    app.get("print", "**") { req -> EventLoopFuture<View> in
        let path = req.parameters.getCatchall().joined(separator: "/")
        
        switch log(atPath: path) {
        case .failure(let error) :
            return logErrorView(from: error, req: req)
        case .success(let log):
            let lutinContext = LutinContext(path: path, log: log)
            return req.view.render("print", lutinContext)
        }
    }
    
    app.get("per", ":role", "**") { req -> EventLoopFuture<View> in
        //let role = req.parameters.get("role")
        let path = req.parameters.getCatchall().joined(separator: "/")
        
        switch log(atPath: path) {
        case .failure(let error) :
            return logErrorView(from: error, req: req)
        case .success(let log):
            let lutinContext = LutinContext(path: path, log: log)
            return req.view.render("per", lutinContext)
        }
    }
    
    func logErrorView(from error:LogError, req:Request) -> EventLoopFuture<View> {
            let reason: String
            switch error {
            case .notFound:
                reason = "Log introuvable"
            case .couldNotDecode:
                reason = "Impossible de lire le log"
            }
            return req.view.render("error", ErrorContext(reason: reason))
    }
    
    func log(atPath path: String) -> Result<Log, LogError> {
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
}

enum LogError: Error {
    case notFound, couldNotDecode
}

func log(atPath path: String) -> Result<Log, LogError> {
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

struct ErrorContext: Encodable {
    let reason: String
}

struct LutinContext: Encodable {
    let path:String
    let log: Log
    
    init(path:String, log:Log) {
        self.path = path
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

extension Log: Content {
    
}
