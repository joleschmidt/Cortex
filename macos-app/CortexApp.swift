import SwiftUI

@main
struct CortexApp: App {
    @StateObject private var supabaseManager = SupabaseManager()
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        let windowGroup = WindowGroup {
            ContentView()
                .environmentObject(supabaseManager)
                .environmentObject(appState)
                .onAppear {
                    if supabaseManager.isConfigured {
                        supabaseManager.startPolling()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        
        if #available(macOS 13.0, *) {
            return windowGroup.windowResizability(.contentSize)
        } else {
            return windowGroup
        }
    }
}

class AppState: ObservableObject {
    @Published var isProcessing: Bool = false
    @Published var processingCount: Int = 0
    @Published var completedCount: Int = 0
}

