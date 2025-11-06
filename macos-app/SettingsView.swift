import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var supabaseManager: SupabaseManager
    @Environment(\.dismiss) var dismiss
    
    @State private var supabaseUrl: String = ""
    @State private var supabaseKey: String = ""
    @State private var pollingInterval: Double = 30.0
    @State private var autoLaunch: Bool = false
    @State private var showSaveMessage = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            // Form
            Form {
                Section("Supabase Configuration") {
                    TextField("Supabase URL", text: $supabaseUrl)
                        .textFieldStyle(.roundedBorder)
                    
                    SecureField("Service Role Key", text: $supabaseKey)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("Your Supabase project URL and service role key. Find these in your Supabase dashboard under Settings > API.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Processing Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Polling Interval")
                            Spacer()
                            Text("\(Int(pollingInterval)) seconds")
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(value: $pollingInterval, in: 10...300, step: 10)
                    }
                    
                    Toggle("Auto-launch on login", isOn: $autoLaunch)
                }
                
                if showSaveMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Settings saved!")
                            .foregroundColor(.green)
                    }
                    .padding(.vertical, 8)
                }
            }
            .modifier(FormStyleModifier())
            .padding()
            
            // Save button
            HStack {
                Spacer()
                Button("Save Settings") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
                .disabled(supabaseUrl.isEmpty || supabaseKey.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 500)
        .onAppear {
            loadCurrentSettings()
        }
    }
    
    private func loadCurrentSettings() {
        if let url = UserDefaults.standard.string(forKey: "supabaseUrl") {
            supabaseUrl = url
        }
        if let key = UserDefaults.standard.string(forKey: "supabaseKey") {
            supabaseKey = key
        }
        let interval = UserDefaults.standard.double(forKey: "pollingInterval")
        if interval > 0 {
            pollingInterval = interval
        } else {
            pollingInterval = 30.0
        }
        autoLaunch = UserDefaults.standard.bool(forKey: "autoLaunch")
    }
    
    private func saveSettings() {
        // Validate URL
        guard URL(string: supabaseUrl) != nil else {
            // Show error
            return
        }
        
        supabaseManager.saveConfiguration(
            url: supabaseUrl,
            key: supabaseKey,
            interval: pollingInterval
        )
        
        // Save auto-launch setting
        UserDefaults.standard.set(autoLaunch, forKey: "autoLaunch")
        configureAutoLaunch(enabled: autoLaunch)
        
        showSaveMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSaveMessage = false
        }
    }
    
    private func configureAutoLaunch(enabled: Bool) {
        // Configure LaunchAgent for auto-launch
        let appPath = Bundle.main.bundlePath
        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.cortex.app.plist")
        
        if enabled {
            let plist: [String: Any] = [
                "Label": "com.cortex.app",
                "ProgramArguments": [appPath + "/Contents/MacOS/Cortex"],
                "RunAtLoad": true
            ]
            
            let plistData = try? PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            
            try? plistData?.write(to: plistPath)
        } else {
            try? FileManager.default.removeItem(at: plistPath)
        }
    }
}

// Helper to conditionally apply formStyle for macOS 13.0+
struct FormStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.formStyle(.grouped)
        } else {
            content
        }
    }
}

