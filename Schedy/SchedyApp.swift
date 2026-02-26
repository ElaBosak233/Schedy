//
//  schedyApp.swift
//  schedy
//
//  Created by ela on 2026/2/25.
//

import SwiftData
import SwiftUI

@main
struct SchedyApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Schedule.self,
            Course.self,
            TimeSlotPreset.self,
            TimeSlotItem.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("无法创建 ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
