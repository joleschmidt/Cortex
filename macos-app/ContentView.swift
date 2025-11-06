import SwiftUI

struct ContentView: View {
    @EnvironmentObject var supabaseManager: SupabaseManager
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false
    @State private var processingQueue: [SavedContent] = []
    @State private var recentSummaries: [SummaryWithContent] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Cortex")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if !supabaseManager.isConfigured {
                // Not configured state
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    
                    Text("Supabase Not Configured")
                        .font(.headline)
                    
                    Text("Please configure your Supabase settings to start processing content.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    Button("Open Settings") {
                        showSettings = true
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Main content
                TabView {
                    // Processing Queue
                    ProcessingQueueView(queue: $processingQueue)
                        .tabItem {
                            Label("Queue", systemImage: "list.bullet")
                        }
                    
                    // Recent Summaries
                    RecentSummariesView(summaries: $recentSummaries)
                        .tabItem {
                            Label("Summaries", systemImage: "doc.text")
                        }
                }
                .frame(minWidth: 600, minHeight: 400)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(supabaseManager)
        }
        .onAppear {
            loadData()
        }
        .onChange(of: supabaseManager.isConfigured) { configured in
            if configured {
                supabaseManager.startPolling()
                loadData()
            }
        }
    }
    
    private func loadData() {
        Task {
            await refreshProcessingQueue()
            await refreshRecentSummaries()
        }
    }
    
    private func refreshProcessingQueue() async {
        do {
            let items = try await supabaseManager.fetchUnprocessedContent()
            await MainActor.run {
                processingQueue = items
            }
        } catch {
            print("Error loading queue: \(error)")
        }
    }
    
    private func refreshRecentSummaries() async {
        guard let url = supabaseManager.supabaseUrl, let key = supabaseManager.supabaseKey else {
            return
        }
        
        do {
            let endpoint = "\(url)/rest/v1/summaries?order=created_at.desc&limit=10&select=*,saved_content(id,title)"
            
            var request = URLRequest(url: URL(string: endpoint)!)
            request.httpMethod = "GET"
            request.setValue(key, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            struct SummaryResponse: Codable {
                let id: UUID
                let contentId: UUID
                let shortSummary: String
                let detailedSummary: String
                let createdAt: Date
                let savedContent: SavedContentRef?
                
                enum CodingKeys: String, CodingKey {
                    case id
                    case contentId = "content_id"
                    case shortSummary = "short_summary"
                    case detailedSummary = "detailed_summary"
                    case createdAt = "created_at"
                    case savedContent = "saved_content"
                }
            }
            
            struct SavedContentRef: Codable {
                let id: UUID
                let title: String
            }
            
            let summaries = try decoder.decode([SummaryResponse].self, from: data)
            
            await MainActor.run {
                recentSummaries = summaries.map { summary in
                    SummaryWithContent(
                        id: summary.id,
                        contentTitle: summary.savedContent?.title ?? "Unknown",
                        shortSummary: summary.shortSummary,
                        detailedSummary: summary.detailedSummary,
                        createdAt: summary.createdAt
                    )
                }
            }
        } catch {
            print("Error loading summaries: \(error)")
        }
    }
}

struct ProcessingQueueView: View {
    @Binding var queue: [SavedContent]
    
    var body: some View {
        List {
            if queue.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    Text("No items in queue")
                        .font(.headline)
                    Text("All content has been processed!")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ForEach(queue) { item in
                    QueueItemRow(item: item)
                }
            }
        }
    }
}

struct QueueItemRow: View {
    let item: SavedContent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.headline)
                .lineLimit(2)
            
            Text(item.url)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            HStack {
                StatusBadge(status: item.status)
                Spacer()
                Text(item.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct RecentSummariesView: View {
    @Binding var summaries: [SummaryWithContent]
    
    var body: some View {
        List {
            if summaries.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                    Text("No summaries yet")
                        .font(.headline)
                    Text("Summaries will appear here once content is processed.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ForEach(summaries) { summary in
                    SummaryRow(summary: summary)
                }
            }
        }
    }
}

struct SummaryRow: View {
    let summary: SummaryWithContent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary.contentTitle)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Short Summary")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Text(summary.shortSummary)
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Detailed Summary")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Text(summary.detailedSummary)
                    .font(.body)
                    .foregroundColor(.primary)
            }
        }
        .padding(.vertical, 8)
    }
}

struct StatusBadge: View {
    let status: ProcessingStatus
    
    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(8)
    }
    
    private var backgroundColor: Color {
        switch status {
        case .pending: return .yellow.opacity(0.3)
        case .processing: return .blue.opacity(0.3)
        case .completed: return .green.opacity(0.3)
        case .failed: return .red.opacity(0.3)
        }
    }
    
    private var foregroundColor: Color {
        switch status {
        case .pending: return .orange
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}

struct SummaryWithContent: Identifiable {
    let id: UUID
    let contentTitle: String
    let shortSummary: String
    let detailedSummary: String
    let createdAt: Date
}

