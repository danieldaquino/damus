//
//  TestRelay.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2025-08-20.
//
import Vapor
import Logging
import NIOCore
import NIOPosix

struct TestRelay {
    static func run() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        
        let app = try await Application.make(env)

        // This attempts to install NIO as the Swift Concurrency global executor.
        // You can enable it if you'd like to reduce the amount of context switching between NIO and Swift Concurrency.
        // Note: this has caused issues with some libraries that use `.wait()` and cleanly shutting down.
        // If enabled, you should be careful about calling async functions before this point as it can cause assertion failures.
        // let executorTakeoverSuccess = NIOSingletons.unsafeTryInstallSingletonPosixEventLoopGroupAsConcurrencyGlobalExecutor()
        // app.logger.debug("Tried to install SwiftNIO's EventLoopGroup as Swift's global concurrency executor", metadata: ["success": .stringConvertible(executorTakeoverSuccess)])
        
        do {
            try await configure(app)
            try await app.execute()
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
    
    // configures your application
    static func configure(_ app: Application) async throws {
        // uncomment to serve files from /Public folder
        // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

        // register routes
        try routes(app)
        
        app.http.server.configuration.port = 63876
    }
    
    static func routes(_ app: Application) throws {
        app.get { req async in
            "It works!"
        }

        app.get("hello") { req async -> String in
            "Hello, world!"
        }
        
//        app.webSocket("/") { req, ws in
//            ws.onText { ws, text in
//                
//            }
//        }
    }
}
