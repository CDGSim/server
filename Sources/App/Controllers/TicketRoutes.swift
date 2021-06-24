//
//  File.swift
//  
//
//  Created by Axel Péju on 16/06/2021.
//

import Vapor
import CSV

struct TicketRoutes {
    static func register(with app: Application) {
        struct TicketContext: Encodable {
            let message:String
        }
        
        // MARK: GET /ticket/form
        app.get("ticket", "form") { req -> EventLoopFuture<View> in
            // Optional query
            let simulationName: String? = req.query["simulation-name"]
            
            // View context
            struct FormContext: Encodable {
                struct FeedbackEntry: Encodable {
                    let date: Date
                    let authorName: String
                    let feedback: String
                    let simulationRequiresAnUpdate: Bool
                    let commentsFromTrainingDept: String?
                }
                
                let simulationName: String?
                let pastEntries:[FeedbackEntry]
                let pendingEntries:[FeedbackEntry]
            }

            // Fetch entries for the simulation
            var existingEntries = [FormContext.FeedbackEntry]()
            if let simulationName = simulationName {
                if let ticketsContent = try? String(contentsOf: URL(fileURLWithPath: "Public/tickets/tickets.csv")) {
                    let csv = try! CSVReader(string: ticketsContent)
                    
                    let dateFormatter = ISO8601DateFormatter()
                    existingEntries = csv
                        .filter { columns in
                            if columns.count == 5 || columns.count == 6 {
                                return columns[1].trimmingCharacters(in: .whitespaces) == simulationName
                            }
                            return false
                        }.compactMap { columns -> FormContext.FeedbackEntry? in
                            guard columns.count == 5 || columns.count == 6 else {
                                return nil
                            }
                            guard let date = dateFormatter.date(from: columns[0]) else {
                                return nil
                            }
                            let authorName = columns[2]
                            let feedback = columns[3].trimmingCharacters(in: CharacterSet(charactersIn:"\""))
                            let simulationRequiresAnUpdate = columns[4] == "1"
                            let comments: String? = columns.count == 6 ? columns[5].trimmingCharacters(in: CharacterSet(charactersIn:"\"")) : nil
                            return .init(date: date,
                                         authorName: authorName,
                                         feedback: feedback,
                                         simulationRequiresAnUpdate: simulationRequiresAnUpdate,
                                         commentsFromTrainingDept: comments)
                        }
                        .sorted { $0.date > $1.date }
                }
            }
            
            let context = FormContext(simulationName: simulationName, pastEntries: existingEntries.filter({ $0.commentsFromTrainingDept?.count ?? 0 > 0 }), pendingEntries: existingEntries.filter({ $0.commentsFromTrainingDept?.count ?? 0 == 0 }))
            
            return req.view.render("ticket-form", context)
        }
        
        // MARK: POST /ticket/form
        app.post("ticket", "form") { req -> EventLoopFuture<View> in
            struct Post: Content {
                let user_name: String
                let user_simu: String
                let user_rem: String
                let user_requires_update: Bool
            }
            let content = try req.content.decode(Post.self)
            let ticketsFileContent:String
            do {
                ticketsFileContent = try String(contentsOfFile: "Public/tickets/tickets.csv")
            } catch {
                return req.view.render("ticket-form", TicketContext(message :"Impossible de lire le fichier de tickets existant"))
            }
            let input = ticketsFileContent
                + "\(ISO8601DateFormatter().string(from:Date()))"
                + ","
                + content.user_simu
                + ","
                + content.user_name
                + ","
                + "\"\(content.user_rem)\""
                + ","
                + "\(content.user_requires_update ? 1 : 0)"
                + ","
                + "\n"
            do {
                try input.write(toFile: "Public/tickets/tickets.csv", atomically: false, encoding: String.Encoding.utf8)
            } catch {
                return req.view.render("ticket-form", TicketContext(message :"Erreur: \(error)"))
            }
            return req.view.render("ticket-form", TicketContext(message :"Remarque enregistrée"))
        }
    }
}
