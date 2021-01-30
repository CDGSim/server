import Leaf
import Vapor
import LeafMarkdown

// configures your application
public func configure(_ app: Application) throws {
    // uncomment to serve files from /Public folder
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    app.views.use(.leaf)
    app.leaf.tags["markdown"] = Markdown()

    //app.http.server.configuration.hostname = "172.16.151.113"

    // register routes
    try routes(app)
    try registerFrontEndRoutes(app)
}
