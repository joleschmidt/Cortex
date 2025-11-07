import SwiftUI

struct ContentView: View {
    @EnvironmentObject var supabaseManager: SupabaseManager
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false
    @State private var processingQueue: [SavedContent] = []
    @State private var allItems: [SavedContent] = []
    @State private var recentSummaries: [SummaryWithContent] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var isLoadingAllItems = false
    @State private var refreshTimer: Timer?
    
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
                VStack(spacing: 0) {
                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                            Spacer()
                            Button("Dismiss") {
                                errorMessage = nil
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                    }
                    
                    TabView {
                        // All Items
                        AllItemsView(items: $allItems, isLoading: $isLoadingAllItems) {
                            loadData()
                        }
                        .tabItem {
                            Label("All Items", systemImage: "folder")
                        }
                        
                        // Processing Queue
                        ProcessingQueueView(queue: $processingQueue, isLoading: $isLoading) {
                            loadData()
                        }
                        .tabItem {
                            Label("Queue", systemImage: "list.bullet")
                        }
                        
                        // Recent Summaries
                        RecentSummariesView(summaries: $recentSummaries)
                        .tabItem {
                            Label("Summaries", systemImage: "doc.text")
                        }
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
            // Start periodic refresh every 10 seconds
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
                loadData()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
        .onChange(of: supabaseManager.isConfigured) { configured in
            if configured {
                supabaseManager.startPolling()
                loadData()
            }
        }
        .onChange(of: supabaseManager.processingCompleted) { _ in
            // Refresh all views when processing completes
            loadData()
        }
    }
    
    private func loadData() {
        Task {
            await refreshAllItems()
            await refreshProcessingQueue()
            await refreshRecentSummaries()
        }
    }
    
    private func refreshAllItems() async {
        await MainActor.run {
            isLoadingAllItems = true
        }
        
        do {
            let items = try await supabaseManager.fetchAllContent()
            await MainActor.run {
                allItems = items
                isLoadingAllItems = false
                print("✅ Loaded \(items.count) items total")
            }
        } catch {
            await MainActor.run {
                isLoadingAllItems = false
                let errorDesc = error.localizedDescription
                errorMessage = "Error loading items: \(errorDesc)"
                print("❌ Error loading all items: \(error)")
            }
        }
    }
    
    private func refreshProcessingQueue() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let items = try await supabaseManager.fetchUnprocessedContent()
            await MainActor.run {
                processingQueue = items
                isLoading = false
                print("✅ Loaded \(items.count) items from queue")
            }
        } catch {
            await MainActor.run {
                isLoading = false
                let errorDesc = error.localizedDescription
                errorMessage = "Error loading queue: \(errorDesc)"
                print("❌ Error loading queue: \(error)")
            }
        }
    }
    
    private func refreshRecentSummaries() async {
        guard let url = supabaseManager.supabaseUrl, let key = supabaseManager.supabaseKey else {
            return
        }
        
        do {
            let endpoint = "\(url)/rest/v1/summaries?order=created_at.desc&limit=10&select=*,saved_content(id,title,content_type)"
            
            var request = URLRequest(url: URL(string: endpoint)!)
            request.httpMethod = "GET"
            request.setValue(key, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return
            }
            
            let decoder = SupabaseManager.createSupabaseDateDecoder()
            
            struct SummaryResponse: Codable {
                let id: UUID
                let contentId: UUID
                let shortSummary: String
                let detailedSummary: String
                let extractedData: ExtractedData?
                let createdAt: Date
                let savedContent: SavedContentRef?
                
                enum CodingKeys: String, CodingKey {
                    case id
                    case contentId = "content_id"
                    case shortSummary = "short_summary"
                    case detailedSummary = "detailed_summary"
                    case extractedData = "extracted_data"
                    case createdAt = "created_at"
                    case savedContent = "saved_content"
                }
            }
            
            struct SavedContentRef: Codable {
                let id: UUID
                let title: String
                let contentType: ContentType?
                
                enum CodingKeys: String, CodingKey {
                    case id
                    case title
                    case contentType = "content_type"
                }
            }
            
            let summaries = try decoder.decode([SummaryResponse].self, from: data)
            
            await MainActor.run {
                recentSummaries = summaries.map { summary in
                    SummaryWithContent(
                        id: summary.id,
                        contentTitle: summary.savedContent?.title ?? "Unknown",
                        contentType: summary.savedContent?.contentType,
                        shortSummary: summary.shortSummary,
                        detailedSummary: summary.detailedSummary,
                        extractedData: summary.extractedData,
                        createdAt: summary.createdAt
                    )
                }
            }
        } catch {
            print("Error loading summaries: \(error)")
        }
    }
}

struct AllItemsView: View {
    @Binding var items: [SavedContent]
    @Binding var isLoading: Bool
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("All Items")
                    .font(.headline)
                Spacer()
                Text("\(items.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)
            }
            .padding()
            
            Divider()
            
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                } else if items.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)
                        Text("No items yet")
                            .font(.headline)
                        Text("Saved content will appear here.")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    ForEach(items) { item in
                        AllItemRow(item: item)
                    }
                }
            }
        }
    }
}

struct AllItemRow: View {
    let item: SavedContent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                if let contentType = item.contentType {
                    ContentTypeBadge(contentType: contentType)
                }
            }
            
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

struct ProcessingQueueView: View {
    @Binding var queue: [SavedContent]
    @Binding var isLoading: Bool
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Processing Queue")
                    .font(.headline)
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)
            }
            .padding()
            
            Divider()
            
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                } else if queue.isEmpty {
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
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(summary.contentTitle)
                    .font(.headline)
                Spacer()
                if let contentType = summary.contentType {
                    ContentTypeBadge(contentType: contentType)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Short Summary")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Text(summary.shortSummary)
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detailed Summary")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Text(summary.detailedSummary)
                        .font(.body)
                        .foregroundColor(.primary)
                }
                
                if let extractedData = summary.extractedData {
                    StructuredDataView(extractedData: extractedData)
                }
            }
            
            Button(action: { isExpanded.toggle() }) {
                Text(isExpanded ? "Show Less" : "Show More")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 8)
    }
}

struct ContentTypeBadge: View {
    let contentType: ContentType
    
    var body: some View {
        Text(contentType.rawValue.capitalized)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(8)
    }
    
    private var backgroundColor: Color {
        switch contentType {
        case .product: return .blue.opacity(0.2)
        case .article: return .green.opacity(0.2)
        case .video: return .purple.opacity(0.2)
        case .listing: return .orange.opacity(0.2)
        case .general: return .gray.opacity(0.2)
        }
    }
    
    private var foregroundColor: Color {
        switch contentType {
        case .product: return .blue
        case .article: return .green
        case .video: return .purple
        case .listing: return .orange
        case .general: return .gray
        }
    }
}

struct StructuredDataView: View {
    let extractedData: ExtractedData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Structured Data")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            if let structuredData = extractedData.structuredData, !structuredData.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(structuredData.keys.sorted()), id: \.self) { key in
                        HStack(alignment: .top) {
                            Text("\(key.capitalized):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(formatValue(structuredData[key]?.value))
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
            
            if let keyPoints = extractedData.keyPoints, !keyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Key Points")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    ForEach(Array(keyPoints.prefix(5).enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .top, spacing: 4) {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(point)
                                .font(.caption)
                        }
                    }
                }
            }
            
            if let insights = extractedData.actionableInsights, !insights.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Actionable Insights")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    ForEach(Array(insights.prefix(3).enumerated()), id: \.offset) { _, insight in
                        HStack(alignment: .top, spacing: 4) {
                            Text("→")
                                .foregroundColor(.blue)
                            Text(insight)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }
    
    private func formatValue(_ value: Any?) -> String {
        guard let value = value else { return "N/A" }
        
        if let string = value as? String {
            return string
        } else if let number = value as? NSNumber {
            return number.stringValue
        } else if let array = value as? [Any] {
            return array.map { formatValue($0) }.joined(separator: ", ")
        } else if let dict = value as? [String: Any] {
            return dict.map { "\($0.key): \(formatValue($0.value))" }.joined(separator: ", ")
        }
        
        return String(describing: value)
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
    let contentType: ContentType?
    let shortSummary: String
    let detailedSummary: String
    let extractedData: ExtractedData?
    let createdAt: Date
}

