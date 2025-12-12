import SwiftUI
import SwiftData

@main
struct Rail_Watch_AppApp: App {
    
    // 1. Definisci il container come proprietà statica o calcolata
    // Questo è il modo corretto per gestire configurazioni complesse (come gli App Groups)
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Train.self,
            Stop.self
        ])
        
        let modelConfiguration: ModelConfiguration
        
        // ⚠️ IMPORTANTE: Sostituisci con il TUO App Group ID esatto
        // Deve essere identico a quello configurato in "Signing & Capabilities"
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.francescoparadis.Rail") {
            let storeURL = containerURL.appendingPathComponent("default.store")
            // Usa il file nel gruppo condiviso
            modelConfiguration = ModelConfiguration(url: storeURL, allowsSave: true)
        } else {
            // Fallback (solo se qualcosa va storto, es. nel simulatore senza gruppo)
            print("⚠️ Fallback to default configuration (No App Group found)")
            modelConfiguration = ModelConfiguration()
        }
        
        do {
            return try ModelContainer(for: schema, configurations: modelConfiguration)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // Inizializza la connettività
        _ = ConnectivityManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // 2. Passa direttamente il container creato sopra
        .modelContainer(sharedModelContainer)
    }
}
