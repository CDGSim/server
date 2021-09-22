import Leaf
import Vapor
import LeafMarkdown

// configures your application
public func configure(_ app: Application) throws {
    // uncomment to serve files from /Public folder
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    app.views.use(.leaf)
    app.leaf.tags["markdown"] = Markdown()
    app.leaf.tags["gmtTime"] = GMTTimeTag()
    app.leaf.tags["DECORLink"] = DECORLink()

    //app.http.server.configuration.hostname = "172.16.151.113"

    // Register routes
    try registerFrontEndRoutes(app)
    try registerAPIRoutes(app)
    try registerDecorRoutes(app)
}

struct DECORLink: LeafTag, UnsafeUnescapedLeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
        guard ProcessInfo.processInfo.environment["simulator"] == "electra" else {
            return .string("")
        }
        return .string("<li><a href=\"/decor/setup\">DECOR</a></li>")
    }
}


private struct GMTTimeTag: LeafTag {

    func render(_ ctx: LeafContext) throws -> LeafData {
        struct GMTTimeTagError: Error {}

        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        switch ctx.parameters.count {
        case 1: formatter.dateFormat = "HH:mm"
        case 2:
            guard let string = ctx.parameters[1].string else {
                throw GMTTimeTagError()
            }
            formatter.dateFormat = string
        default:
            throw GMTTimeTagError()
        }
        
        guard let dateAsDouble = ctx.parameters.first?.double else {
            throw "Unable to convert parameter to double for date"
        }
        let date = Date(timeIntervalSince1970: dateAsDouble)

        let dateAsString = formatter.string(from: date)
        return LeafData.string(dateAsString)
    }
}
