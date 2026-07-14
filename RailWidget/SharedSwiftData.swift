import Foundation
import SwiftData
import os

enum SharedSwiftData {
    static let appGroupID = "group.com.francescoparadis.Rail"
    static let databaseFileName = "default.store"
    static let logger = Logger(subsystem: "com.francescoparadis.Rail", category: "SharedSwiftData")

    static var schema: Schema {
        Schema([
            Train.self,
            Stop.self,
            Seat.self,
            Favorite.self,
            Pass.self,
            UserProfile.self
        ])
    }

    static var databaseURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(databaseFileName)
    }

    static func appConfiguration() -> ModelConfiguration? {
        guard let databaseURL else { return nil }

        return ModelConfiguration(
            appGroupID,
            schema: schema,
            url: databaseURL,
            allowsSave: true,
            cloudKitDatabase: .automatic
        )
    }

    static func readOnlyConfiguration() -> ModelConfiguration? {
        guard let databaseURL else { return nil }

        return ModelConfiguration(
            appGroupID,
            schema: schema,
            url: databaseURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
    }

    static func makeAppContainer() throws -> ModelContainer {
        if let configuration = appConfiguration() {
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)]
        )
    }

    static func makeReadOnlyContainer() throws -> ModelContainer {
        guard let configuration = readOnlyConfiguration() else {
            throw SharedSwiftDataError.appGroupUnavailable
        }

        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

enum SharedSwiftDataError: Error {
    case appGroupUnavailable
}
