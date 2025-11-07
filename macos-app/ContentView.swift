import SwiftUI
import AppKit

enum SelectedCategory: String, CaseIterable, Hashable {
    case all = "All Items"
    case product = "Products"
    case article = "Articles"
    case video = "Videos"
    case listing = "Listings"
    case general = "General"
    case queue = "Processing Queue"
    
    var icon: String {
        switch self {
        case .all: return "tray.fill"
        case .product: return "cube.box.fill"
        case .article: return "doc.text.fill"
        case .video: return "play.rectangle.fill"
        case .listing: return "list.bullet.rectangle.fill"
        case .general: return "folder.fill"
        case .queue: return "clock.fill"
        }
    }
    
    var contentType: ContentType? {
        switch self {
        case .product: return .product
        case .article: return .article
        case .video: return .video
        case .listing: return .listing
        case .general: return .general
        case .all, .queue: return nil
        }
    }
}

enum SortOption: String, CaseIterable {
    case dateDesc = "Newest First"
    case dateAsc = "Oldest First"
    case titleAsc = "Title A-Z"
    case titleDesc = "Title Z-A"
    case type = "By Type"
    
    func sort(_ summaries: [SummaryWithContent]) -> [SummaryWithContent] {
        switch self {
        case .dateDesc:
            return summaries.sorted { $0.createdAt > $1.createdAt }
        case .dateAsc:
            return summaries.sorted { $0.createdAt < $1.createdAt }
        case .titleAsc:
            return summaries.sorted { $0.contentTitle.localizedCompare($1.contentTitle) == .orderedAscending }
        case .titleDesc:
            return summaries.sorted { $0.contentTitle.localizedCompare($1.contentTitle) == .orderedDescending }
        case .type:
            return summaries.sorted { lhs, rhs in
                let lhsType = lhs.contentType?.rawValue ?? "zzz"
                let rhsType = rhs.contentType?.rawValue ?? "zzz"
                if lhsType != rhsType {
                    return lhsType < rhsType
                }
                return lhs.createdAt > rhs.createdAt
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var supabaseManager: SupabaseManager
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false
    @State private var selectedCategory: SelectedCategory = .all
    @State private var processingQueue: [SavedContent] = []
    @State private var allSummaries: [SummaryWithContent] = []
    @State private var searchText: String = ""
    @State private var sortOption: SortOption = .dateDesc
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var selectedItem: SummaryWithContent?
    @State private var showDetailView = false
    
    var filteredSummaries: [SummaryWithContent] {
        var summaries = allSummaries
        
        // Filter by category
        if let contentType = selectedCategory.contentType {
            summaries = summaries.filter { $0.contentType == contentType }
        } else if selectedCategory == .queue {
            return [] // Queue is handled separately
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            summaries = summaries.filter { summary in
                summary.contentTitle.localizedCaseInsensitiveContains(searchText) ||
                summary.shortSummary.localizedCaseInsensitiveContains(searchText) ||
                summary.detailedSummary.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply sorting
        return sortOption.sort(summaries)
    }
    
    var categoryCounts: [SelectedCategory: Int] {
        var counts: [SelectedCategory: Int] = [:]
        
        counts[.all] = allSummaries.count
        counts[.queue] = processingQueue.count
        
        for category in [SelectedCategory.product, .article, .video, .listing, .general] {
            if let contentType = category.contentType {
                counts[category] = allSummaries.filter { $0.contentType == contentType }.count
            }
        }
        
        return counts
    }
    
    var body: some View {
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
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(supabaseManager)
            }
            } else {
            HSplitView {
                // Sidebar
                SidebarView(
                    selectedCategory: $selectedCategory,
                    categoryCounts: categoryCounts,
                    onSettings: { showSettings = true }
                )
                .frame(minWidth: 250, idealWidth: 250, maxWidth: 300)
                
                // Main content area
                MainContentView(
                    selectedCategory: selectedCategory,
                    searchText: $searchText,
                    sortOption: $sortOption,
                    filteredSummaries: filteredSummaries,
                    processingQueue: processingQueue,
                    isLoading: isLoading,
                    onRefresh: loadData,
                    onItemSelect: { item in
                        selectedItem = item
                        showDetailView = true
                    },
                    onItemEdit: { item in
                        selectedItem = item
                        showDetailView = true
                    }
                )
            }
            .frame(minWidth: 800, minHeight: 600)
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(supabaseManager)
            }
            .sheet(item: $selectedItem) { item in
                DetailView(
                    summary: item,
                    onSave: { updatedItem in
                        Task {
                            // All updates are already done in saveChanges, just refresh data
                            await refreshAllSummaries()
                            // Update the selected item with fresh data from server
                            await MainActor.run {
                                if let refreshedItem = allSummaries.first(where: { $0.id == updatedItem.id }) {
                                    selectedItem = refreshedItem
                                    print("✅ Updated selected item with refreshed data, content type: \(refreshedItem.contentType?.rawValue ?? "nil")")
                                } else {
                                    print("⚠️ Could not find refreshed item with id: \(updatedItem.id)")
                                }
                            }
                        }
                    },
                    onDelete: {
                        Task {
                            await deleteContent(item)
                        }
                    }
                )
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
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
                // Refresh data when app becomes active
                loadData()
            }
        }
    }
    
    private func loadData() {
        Task {
            await refreshProcessingQueue()
            await refreshAllSummaries()
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
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = "Error loading queue: \(error.localizedDescription)"
            }
        }
    }
    
    private func refreshAllSummaries() async {
        guard let url = supabaseManager.supabaseUrl, let key = supabaseManager.supabaseKey else {
            return
        }
        
        do {
            // Fetch all summaries, not just 10
            let endpoint = "\(url)/rest/v1/summaries?order=created_at.desc&select=*,saved_content(id,title,content_type,url)"
            
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
                let url: String
                
                enum CodingKeys: String, CodingKey {
                    case id
                    case title
                    case contentType = "content_type"
                    case url
                }
            }
            
            let summaries = try decoder.decode([SummaryResponse].self, from: data)
            
            await MainActor.run {
                allSummaries = summaries.map { summary in
                    let url = summary.savedContent?.url ?? ""
                    if !url.isEmpty {
                        print("✅ Summary \(summary.id) has URL: \(url)")
                    } else {
                        print("⚠️ Summary \(summary.id) has no URL")
                    }
                    return SummaryWithContent(
                        id: summary.id,
                        contentId: summary.contentId,
                        contentTitle: summary.savedContent?.title ?? "Unknown",
                        contentType: summary.savedContent?.contentType,
                        shortSummary: summary.shortSummary,
                        detailedSummary: summary.detailedSummary,
                        url: url,
                        extractedData: summary.extractedData,
                        createdAt: summary.createdAt
                    )
                }
            }
        } catch {
            print("Error loading summaries: \(error)")
        }
    }
    
    private func updateSummary(_ item: SummaryWithContent) async {
        do {
            try await supabaseManager.updateSummary(
                id: item.id,
                shortSummary: item.shortSummary,
                detailedSummary: item.detailedSummary
            )
            await refreshAllSummaries()
        } catch {
            await MainActor.run {
                errorMessage = "Error updating summary: \(error.localizedDescription)"
            }
        }
    }
    
    private func deleteContent(_ item: SummaryWithContent) async {
        do {
            try await supabaseManager.deleteContent(id: item.contentId)
            await refreshAllSummaries()
            await refreshProcessingQueue()
        } catch {
            await MainActor.run {
                errorMessage = "Error deleting content: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Sidebar View
struct SidebarView: View {
    @Binding var selectedCategory: SelectedCategory
    let categoryCounts: [SelectedCategory: Int]
    let onSettings: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Cortex")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding()
            
            Divider()
            
            // Category list
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(SelectedCategory.allCases, id: \.self) { category in
                        CategoryRow(
                            category: category,
                            count: categoryCounts[category] ?? 0,
                            isSelected: selectedCategory == category
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedCategory = category
                        }
                    }
                }
            }
            
            Divider()
            
            // Settings button
            Button(action: onSettings) {
                    HStack {
                    Image(systemName: "gearshape")
                    Text("Settings")
                        Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(selectedCategory == .queue ? Color.clear : Color.clear)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct CategoryRow: View {
    let category: SelectedCategory
    let count: Int
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Image(systemName: category.icon)
                .frame(width: 20)
                .foregroundColor(isSelected ? .accentColor : .primary)
            Text(category.rawValue)
                .foregroundColor(isSelected ? .accentColor : .primary)
                        Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Main Content View
struct MainContentView: View {
    let selectedCategory: SelectedCategory
    @Binding var searchText: String
    @Binding var sortOption: SortOption
    let filteredSummaries: [SummaryWithContent]
    let processingQueue: [SavedContent]
    let isLoading: Bool
    let onRefresh: () -> Void
    let onItemSelect: (SummaryWithContent) -> Void
    let onItemEdit: (SummaryWithContent) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with search and sort
            HStack {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                
                Spacer()
                
                // Refresh button
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)
                .help("Refresh")
                
                // Sort picker (only show for summaries, not queue)
                if selectedCategory != .queue {
                    Picker("Sort", selection: $sortOption) {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content list
            if selectedCategory == .queue {
                ProcessingQueueListView(
                    queue: processingQueue,
                    isLoading: isLoading,
                    onRefresh: onRefresh
                )
            } else {
                SummariesListView(
                    summaries: filteredSummaries,
                    onItemSelect: onItemSelect,
                    onItemEdit: onItemEdit
                )
            }
        }
    }
}

struct ProcessingQueueListView: View {
    let queue: [SavedContent]
    let isLoading: Bool
    let onRefresh: () -> Void
    
    var body: some View {
        VStack {
                if isLoading {
                        ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                } else {
                List {
                    ForEach(queue) { item in
                        QueueItemRow(item: item)
                    }
                }
            }
        }
    }
}

struct SummariesListView: View {
    let summaries: [SummaryWithContent]
    let onItemSelect: (SummaryWithContent) -> Void
    let onItemEdit: (SummaryWithContent) -> Void
    
    var body: some View {
        if summaries.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "doc.text")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                Text("No items")
                    .font(.headline)
                Text("No summaries found in this category.")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(summaries) { summary in
                    SummaryListItem(
                        summary: summary,
                        onSelect: { onItemSelect(summary) },
                        onEdit: { onItemEdit(summary) }
                    )
                }
            }
        }
    }
}

struct SummaryListItem: View {
    let summary: SummaryWithContent
    let onSelect: () -> Void
    let onEdit: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(summary.contentTitle)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                if let contentType = summary.contentType {
                    ContentTypeBadge(contentType: contentType)
                }
            }
            
            Text(summary.shortSummary)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(3)
            
            HStack {
                Text(summary.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if isHovered {
                    HStack(spacing: 4) {
                        Button(action: {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(summary.shortSummary, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Copy summary")
                        
                        Button("Edit") {
                            onEdit()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(isHovered ? Color.accentColor.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Open Detail View") {
                onSelect()
            }
            Button("Edit") {
                onEdit()
            }
            Divider()
            Button("Copy Summary") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(summary.shortSummary, forType: .string)
            }
            Button("Copy Detailed Summary") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(summary.detailedSummary, forType: .string)
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

// MARK: - Detail View
struct DetailView: View {
    @EnvironmentObject var supabaseManager: SupabaseManager
    @Environment(\.dismiss) var dismiss
    
    @State var summary: SummaryWithContent
    @State private var isEditing = false
    @State private var editedShortSummary: String = ""
    @State private var editedDetailedSummary: String = ""
    @State private var editedTitle: String = ""
    @State private var editedContentType: ContentType?
    @State private var isSaving = false
    @State private var showDeleteConfirmation = false
    
    let onSave: (SummaryWithContent) -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom toolbar
            HStack {
                Button {
                    if isEditing {
                        isEditing = false
                        resetEditingState()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])
                .help("Cancel")
                
                Spacer()
                
                if isEditing {
                    Button {
                        saveChanges()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isSaving)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .help("Save")
                } else {
                    Menu {
                        Button("Copy Short Summary") {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(summary.shortSummary, forType: .string)
                        }
                        Button("Copy Detailed Summary") {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(summary.detailedSummary, forType: .string)
                        }
                        Button("Copy Title") {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(summary.contentTitle, forType: .string)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("More Options")
                    
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                    .keyboardShortcut(.delete, modifiers: [.command])
                    .help("Delete")
                    
                    Button {
                        startEditing()
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .help("Edit")
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    if isEditing {
                        TextField("Title", text: $editedTitle)
                            .textFieldStyle(.roundedBorder)
                            .font(.title2)
                    } else {
                        Text(summary.contentTitle)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    
                    // Content Type and URL
                    HStack {
                        if isEditing {
                            Picker("Type", selection: $editedContentType) {
                                Text("None").tag(ContentType?.none)
                                ForEach([ContentType.product, .article, .video, .listing, .general], id: \.self) { type in
                                    Text(type.rawValue.capitalized).tag(ContentType?.some(type))
                                }
                            }
                            .pickerStyle(.menu)
                        } else if let contentType = summary.contentType {
                            ContentTypeBadge(contentType: contentType)
                        }
                        
                        Spacer()
                        
                        Button {
                            if !summary.url.isEmpty, let url = URL(string: summary.url) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                Text("Open Original")
                            }
                            .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .disabled(summary.url.isEmpty)
                        .help(summary.url.isEmpty ? "No URL available" : "Open original page in browser")
                        
                        Text(summary.createdAt, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // Short Summary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Short Summary")
                            .font(.headline)
                        if isEditing {
                            TextEditor(text: $editedShortSummary)
                                .frame(minHeight: 100)
                                .padding(4)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(4)
                        } else {
                            Text(summary.shortSummary)
                                .font(.body)
                        }
                    }
                    
                    // Detailed Summary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Detailed Summary")
                        .font(.headline)
                        if isEditing {
                            TextEditor(text: $editedDetailedSummary)
                                .frame(minHeight: 200)
                                .padding(4)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(4)
                        } else {
                            Text(summary.detailedSummary)
                                .font(.body)
                        }
                    }
                    
                    // Extracted Data
                    if let extractedData = summary.extractedData {
                        StructuredDataView(extractedData: extractedData)
                    }
                }
                .padding()
            }
            .frame(minWidth: 600, minHeight: 500)
        }
        .confirmationDialog("Delete Item", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this item? This action cannot be undone.")
        }
        .onAppear {
            resetEditingState()
        }
    }
    
    private func startEditing() {
        editedShortSummary = summary.shortSummary
        editedDetailedSummary = summary.detailedSummary
        editedTitle = summary.contentTitle
        editedContentType = summary.contentType
        isEditing = true
    }
    
    private func resetEditingState() {
        editedShortSummary = summary.shortSummary
        editedDetailedSummary = summary.detailedSummary
        editedTitle = summary.contentTitle
        editedContentType = summary.contentType
    }
    
    private func saveChanges() {
        isSaving = true
        
        Task {
            var updateErrors: [String] = []
            
            // Update title if changed
            if editedTitle != summary.contentTitle {
                do {
                    try await supabaseManager.updateContentTitle(id: summary.contentId, title: editedTitle)
                    print("✅ Title updated successfully")
                } catch {
                    print("❌ Error updating title: \(error)")
                    updateErrors.append("Failed to update title: \(error.localizedDescription)")
                }
            }
            
            // Update content type if changed
            if editedContentType != summary.contentType {
                if let newType = editedContentType {
                    do {
                        try await supabaseManager.updateContentType(contentId: summary.contentId, contentType: newType)
                        print("✅ Content type updated to: \(newType.rawValue)")
                    } catch {
                        print("❌ Error updating content type: \(error)")
                        updateErrors.append("Failed to update content type: \(error.localizedDescription)")
                    }
                } else {
                    // Content type was set to nil - we might need a special API call for this
                    print("⚠️ Content type set to nil - this might not be supported")
                }
            }
            
            // Update summaries
            do {
                try await supabaseManager.updateSummary(
                    id: summary.id,
                    shortSummary: editedShortSummary,
                    detailedSummary: editedDetailedSummary
                )
                print("✅ Summary updated successfully")
            } catch {
                print("❌ Error updating summary: \(error)")
                updateErrors.append("Failed to update summary: \(error.localizedDescription)")
            }
            
            // Create updated summary with all changes
            let updatedSummary = SummaryWithContent(
                id: summary.id,
                contentId: summary.contentId,
                contentTitle: editedTitle,
                contentType: editedContentType,
                shortSummary: editedShortSummary,
                detailedSummary: editedDetailedSummary,
                url: summary.url,
                extractedData: summary.extractedData,
                createdAt: summary.createdAt
            )
            
            // Call onSave callback which will refresh data
            onSave(updatedSummary)
            
            await MainActor.run {
                summary = updatedSummary
                isEditing = false
                isSaving = false
            }
        }
    }
}

// MARK: - Supporting Views
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
                .font(.headline)
            
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
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    ForEach(Array(keyPoints.prefix(10).enumerated()), id: \.offset) { _, point in
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
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    ForEach(Array(insights.prefix(5).enumerated()), id: \.offset) { _, insight in
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

// MARK: - Models
struct SummaryWithContent: Identifiable, Hashable {
    let id: UUID
    let contentId: UUID
    var contentTitle: String
    var contentType: ContentType?
    var shortSummary: String
    var detailedSummary: String
    let url: String
    let extractedData: ExtractedData?
    let createdAt: Date
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
}

    static func == (lhs: SummaryWithContent, rhs: SummaryWithContent) -> Bool {
        lhs.id == rhs.id
    }
}
