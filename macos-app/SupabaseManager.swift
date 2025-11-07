import Foundation
import Combine


class SupabaseManager: ObservableObject {
    @Published var isConfigured: Bool = false
    @Published var lastError: String?
    @Published var processingCompleted: Bool = false // Triggers UI refresh
    @Published var isPollingActive: Bool = false
    @Published var lastProcessingAttempt: Date?
    
    var supabaseUrl: String?
    var supabaseKey: String? // Service role key
    private var pollingInterval: TimeInterval = 30.0
    private var pollingTimer: Timer?
    private var isPolling: Bool = false
    
    init() {
        loadConfiguration()
    }
    
    // MARK: - Configuration
    func loadConfiguration() {
        if let url = UserDefaults.standard.string(forKey: "supabaseUrl"),
           let key = UserDefaults.standard.string(forKey: "supabaseKey") {
            self.supabaseUrl = url
            self.supabaseKey = key
            self.isConfigured = true
        }
        
        let interval = UserDefaults.standard.double(forKey: "pollingInterval")
        if interval > 0 {
            self.pollingInterval = interval
        }
    }
    
    func saveConfiguration(url: String, key: String, interval: TimeInterval) {
        UserDefaults.standard.set(url, forKey: "supabaseUrl")
        UserDefaults.standard.set(key, forKey: "supabaseKey")
        UserDefaults.standard.set(interval, forKey: "pollingInterval")
        
        self.supabaseUrl = url
        self.supabaseKey = key
        self.pollingInterval = interval
        self.isConfigured = true
        
        // Restart polling with new interval
        stopPolling()
        startPolling()
    }
    
    // MARK: - Polling
    func startPolling() {
        guard isConfigured else {
            print("⚠️ Cannot start polling: Supabase not configured")
            return
        }
        
        guard !isPolling else {
            print("⚠️ Polling already active")
            return
        }
        
        print("🚀 Starting polling with interval: \(pollingInterval)s")
        isPolling = true
        
        // Use RunLoop.main to ensure timer runs on main thread
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            print("⏰ Polling timer fired")
            self?.processNextItem()
        }
        
        // Add timer to main run loop
        if let timer = pollingTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.isPollingActive = true
        }
        
        print("✅ Polling started successfully")
        
        // Process immediately on start
        processNextItem()
    }
    
    func stopPolling() {
        print("🛑 Stopping polling")
        pollingTimer?.invalidate()
        pollingTimer = nil
        isPolling = false
        
        DispatchQueue.main.async { [weak self] in
            self?.isPollingActive = false
        }
    }
    
    // Manual trigger for processing (useful for debugging)
    func processNow() {
        print("🔧 Manual processing triggered")
        processNextItem()
    }
    
    // MARK: - Date Decoding Helper
    static func createSupabaseDateDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // Custom date formatter for Supabase ISO8601 dates (handles microseconds)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        // Try multiple ISO8601 formats
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // Try formats in order of likelihood
            let formats = [
                "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ",  // With microseconds and timezone
                "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",     // With milliseconds and timezone
                "yyyy-MM-dd'T'HH:mm:ssZZZZZ",          // Without fractional seconds
                "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'",     // With microseconds, UTC
                "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",        // With milliseconds, UTC
                "yyyy-MM-dd'T'HH:mm:ss'Z'"             // Without fractional seconds, UTC
            ]
            
            for format in formats {
                dateFormatter.dateFormat = format
                if let date = dateFormatter.date(from: dateString) {
                    return date
                }
            }
            
            // Fallback to ISO8601DateFormatter
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }
            
            // Last resort: try without fractional seconds
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateString)"
            )
        }
        return decoder
    }
    
    // MARK: - API Methods
    func fetchUnprocessedContent() async throws -> [SavedContent] {
        guard let url = supabaseUrl, let key = supabaseKey else {
            print("❌ Supabase not configured - URL: \(supabaseUrl ?? "nil"), Key: \(supabaseKey != nil ? "set" : "nil")")
            throw SupabaseError.notConfigured
        }
        
        // Fetch both pending and processing items (processing items might be stuck)
        let endpoint = "\(url)/rest/v1/saved_content?status=in.(pending,processing)&order=created_at.asc&limit=10"
        print("🔍 Fetching from: \(endpoint)")
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type")
            throw SupabaseError.invalidResponse
        }
        
        print("📡 Response status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 200 {
            // Log raw JSON for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📄 Raw JSON response: \(jsonString.prefix(500))")
            }
            
            let decoder = Self.createSupabaseDateDecoder()
            
            do {
                let items = try decoder.decode([SavedContent].self, from: data)
                print("✅ Decoded \(items.count) items")
                return items
            } catch {
                print("❌ Decoding error: \(error)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📄 Full JSON: \(jsonString.prefix(2000))")
                }
                throw error
            }
        } else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ API Error \(httpResponse.statusCode): \(errorMessage)")
            throw SupabaseError.apiError(httpResponse.statusCode, errorMessage)
        }
    }
    
    func fetchAllContent(categoryId: UUID? = nil) async throws -> [SavedContent] {
        guard let url = supabaseUrl, let key = supabaseKey else {
            print("❌ Supabase not configured - URL: \(supabaseUrl ?? "nil"), Key: \(supabaseKey != nil ? "set" : "nil")")
            throw SupabaseError.notConfigured
        }
        
        var endpoint = "\(url)/rest/v1/saved_content?order=created_at.desc"
        if let categoryId = categoryId {
            endpoint += "&category_id=eq.\(categoryId.uuidString)"
        }
        print("🔍 Fetching all content from: \(endpoint)")
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type")
            throw SupabaseError.invalidResponse
        }
        
        print("📡 Response status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 200 {
            let decoder = Self.createSupabaseDateDecoder()
            
            do {
                let items = try decoder.decode([SavedContent].self, from: data)
                print("✅ Decoded \(items.count) items")
                return items
            } catch {
                print("❌ Decoding error: \(error)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📄 Full JSON: \(jsonString.prefix(2000))")
                }
                throw error
            }
        } else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ API Error \(httpResponse.statusCode): \(errorMessage)")
            throw SupabaseError.apiError(httpResponse.statusCode, errorMessage)
        }
    }
    
    func markAsProcessing(contentId: UUID) async throws {
        guard let url = supabaseUrl, let key = supabaseKey else {
            throw SupabaseError.notConfigured
        }
        
        let endpoint = "\(url)/rest/v1/saved_content?id=eq.\(contentId.uuidString)"
        let payload: [String: Any] = ["status": "processing"]
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PATCH"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 && httpResponse.statusCode != 204 {
            throw SupabaseError.apiError(httpResponse.statusCode, "Failed to update status")
        }
    }
    
    func updateContentType(contentId: UUID, contentType: ContentType) async throws {
        guard let url = supabaseUrl, let key = supabaseKey else {
            throw SupabaseError.notConfigured
        }
        
        let endpoint = "\(url)/rest/v1/saved_content?id=eq.\(contentId.uuidString)"
        let payload: [String: Any] = ["content_type": contentType.rawValue]
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PATCH"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 && httpResponse.statusCode != 204 {
            throw SupabaseError.apiError(httpResponse.statusCode, "Failed to update content type")
        }
    }
    
    func updateContentWithSummary(contentId: UUID, shortSummary: String, detailedSummary: String, extractedData: ExtractedData, keyPoints: [String]? = nil, reviews: [String]? = nil) async throws {
        guard let url = supabaseUrl, let key = supabaseKey else {
            throw SupabaseError.notConfigured
        }
        
        print("💾 Saving summary for content: \(contentId)")
        print("   Short summary length: \(shortSummary.count)")
        print("   Detailed summary length: \(detailedSummary.count)")
        
        // Convert ExtractedData to JSON
        var extractedDataDict: [String: Any] = [:]
        do {
            let encoder = JSONEncoder()
            let extractedDataJSON = try encoder.encode(extractedData)
            extractedDataDict = try JSONSerialization.jsonObject(with: extractedDataJSON) as? [String: Any] ?? [:]
            print("   Extracted data keys: \(extractedDataDict.keys.joined(separator: ", "))")
        } catch {
            print("⚠️ Warning: Failed to encode extracted data: \(error)")
            // Continue without extracted_data if encoding fails
        }
        
        // First, create the summary
        let summaryEndpoint = "\(url)/rest/v1/summaries"
        var summaryPayload: [String: Any] = [
            "content_id": contentId.uuidString,
            "short_summary": shortSummary,
            "detailed_summary": detailedSummary
        ]
        
        // Add key_points as separate column if present
        if let keyPoints = keyPoints, !keyPoints.isEmpty {
            summaryPayload["key_points"] = keyPoints
            print("   Key points count: \(keyPoints.count)")
        } else if let keyPoints = extractedData.keyPoints, !keyPoints.isEmpty {
            // Fallback to extractedData if not provided separately
            summaryPayload["key_points"] = keyPoints
            print("   Key points count: \(keyPoints.count)")
        }
        
        // Add reviews as separate column if present
        if let reviews = reviews, !reviews.isEmpty {
            summaryPayload["reviews"] = reviews
            print("   Reviews count: \(reviews.count)")
        }
        
        // Add extracted_data if present (for backward compatibility and other data)
        if !extractedDataDict.isEmpty {
            summaryPayload["extracted_data"] = extractedDataDict
        }
        
        var summaryRequest = URLRequest(url: URL(string: summaryEndpoint)!)
        summaryRequest.httpMethod = "POST"
        summaryRequest.setValue(key, forHTTPHeaderField: "apikey")
        summaryRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        summaryRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        summaryRequest.setValue("return=representation", forHTTPHeaderField: "Prefer")
        
        do {
            summaryRequest.httpBody = try JSONSerialization.data(withJSONObject: summaryPayload)
        } catch {
            print("❌ Failed to serialize summary payload: \(error)")
            throw SupabaseError.apiError(500, "Failed to serialize summary payload: \(error.localizedDescription)")
        }
        
        let (summaryData, summaryResponse) = try await URLSession.shared.data(for: summaryRequest)
        
        guard let summaryHttpResponse = summaryResponse as? HTTPURLResponse else {
            print("❌ Invalid response type when saving summary")
            throw SupabaseError.invalidResponse
        }
        
        print("📡 Summary save response: \(summaryHttpResponse.statusCode)")
        
        if summaryHttpResponse.statusCode != 201 {
            let errorMessage = String(data: summaryData, encoding: .utf8) ?? "Unknown error"
            print("❌ Failed to save summary: \(errorMessage)")
            throw SupabaseError.apiError(summaryHttpResponse.statusCode, errorMessage)
        }
        
        print("✅ Summary saved successfully")
        
        // Then, update the content status to completed
        let contentEndpoint = "\(url)/rest/v1/saved_content?id=eq.\(contentId.uuidString)"
        let contentPayload: [String: Any] = [
            "status": "completed",
            "processed_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        var contentRequest = URLRequest(url: URL(string: contentEndpoint)!)
        contentRequest.httpMethod = "PATCH"
        contentRequest.setValue(key, forHTTPHeaderField: "apikey")
        contentRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        contentRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        contentRequest.httpBody = try JSONSerialization.data(withJSONObject: contentPayload)
        
        let (_, contentResponse) = try await URLSession.shared.data(for: contentRequest)
        
        guard let contentHttpResponse = contentResponse as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if contentHttpResponse.statusCode != 200 && contentHttpResponse.statusCode != 204 {
            throw SupabaseError.apiError(contentHttpResponse.statusCode, "Failed to update content status")
        }
    }
    
    // MARK: - Processing
    private func processNextItem() {
        guard isConfigured else {
            print("⚠️ Cannot process: Supabase not configured")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.lastProcessingAttempt = Date()
        }
        
        print("🔍 Looking for items to process...")
        
        Task {
            do {
                let items = try await fetchUnprocessedContent()
                print("📋 Found \(items.count) unprocessed items")
                
                guard let item = items.first else {
                    print("ℹ️ No items to process")
                    return // No items to process
                }
                
                print("📌 Processing item: \(item.title) (ID: \(item.id.uuidString))")
                
                // Skip if already processing (might be stuck, but let's try to complete it)
                // Only mark as processing if it's pending
                if item.status == .pending {
                    try await markAsProcessing(contentId: item.id)
                } else {
                    print("⚠️ Item \(item.id) is already in processing status, attempting to complete...")
                }
                
                // Process content with error handling
                let processor = AppleIntelligenceProcessor()
                let result: ProcessingResult
                
                do {
                    print("🔄 Processing item: \(item.title)")
                    result = try await processor.processContent(
                        url: item.url,
                        title: item.title,
                        content: item.contentText,
                        markdown: item.contentMarkdown ?? item.contentText,
                        metadata: item.metadata
                    )
                    print("✅ Processing completed for: \(item.title)")
                } catch {
                    // If processing fails, mark as failed
                    print("❌ Processing failed for \(item.title): \(error)")
                    try await markAsFailed(contentId: item.id)
                    throw error
                }
                
                // Update content type
                try await updateContentType(contentId: item.id, contentType: result.contentType)
                print("✅ Content type updated: \(result.contentType.rawValue)")
                
                // Save summaries with extracted data
                try await updateContentWithSummary(
                    contentId: item.id,
                    shortSummary: result.summaries.short,
                    detailedSummary: result.summaries.detailed,
                    extractedData: result.extractedData,
                    keyPoints: result.keyPoints,
                    reviews: result.reviews
                )
                print("✅ Summary saved for: \(item.title)")
                
                // Clear error on success and trigger UI refresh
                await MainActor.run {
                    self.lastError = nil
                    self.processingCompleted.toggle() // Toggle to trigger refresh
                }
                
                print("✅ Processing complete, UI refresh triggered")
                
                // Add jitter to avoid synchronized requests
                let jitter = Double.random(in: 0...5)
                try await Task.sleep(nanoseconds: UInt64(jitter * 1_000_000_000))
                
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                }
                print("❌ Error processing content: \(error)")
                if let nsError = error as NSError? {
                    print("   Domain: \(nsError.domain), Code: \(nsError.code)")
                    print("   UserInfo: \(nsError.userInfo)")
                }
                
                // Retry with exponential backoff (handled by timer)
            }
        }
    }
    
    // MARK: - Category Methods
    func fetchCategories() async throws -> [Category] {
        guard let url = supabaseUrl, let key = supabaseKey else {
            throw SupabaseError.notConfigured
        }
        
        let endpoint = "\(url)/rest/v1/categories?order=name.asc"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode == 200 {
            let decoder = Self.createSupabaseDateDecoder()
            return try decoder.decode([Category].self, from: data)
        } else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.apiError(httpResponse.statusCode, errorMessage)
        }
    }
    
    func createCategory(name: String, parentId: UUID? = nil) async throws -> Category {
        guard let url = supabaseUrl, let key = supabaseKey else {
            throw SupabaseError.notConfigured
        }
        
        let endpoint = "\(url)/rest/v1/categories"
        var payload: [String: Any] = ["name": name]
        if let parentId = parentId {
            payload["parent_id"] = parentId.uuidString
        }
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode == 201 {
            let decoder = Self.createSupabaseDateDecoder()
            let categories = try decoder.decode([Category].self, from: data)
            return categories[0]
        } else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.apiError(httpResponse.statusCode, errorMessage)
        }
    }
    
    func updateCategory(categoryId: UUID, name: String, parentId: UUID? = nil) async throws {
        guard let url = supabaseUrl, let key = supabaseKey else {
            throw SupabaseError.notConfigured
        }
        
        let endpoint = "\(url)/rest/v1/categories?id=eq.\(categoryId.uuidString)"
        var payload: [String: Any] = ["name": name, "updated_at": ISO8601DateFormatter().string(from: Date())]
        if let parentId = parentId {
            payload["parent_id"] = parentId.uuidString
        } else {
            payload["parent_id"] = NSNull()
        }
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PATCH"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 && httpResponse.statusCode != 204 {
            throw SupabaseError.apiError(httpResponse.statusCode, "Failed to update category")
        }
    }
    
    func deleteCategory(categoryId: UUID) async throws {
        guard let url = supabaseUrl, let key = supabaseKey else {
            throw SupabaseError.notConfigured
        }
        
        let endpoint = "\(url)/rest/v1/categories?id=eq.\(categoryId.uuidString)"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "DELETE"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 && httpResponse.statusCode != 204 {
            throw SupabaseError.apiError(httpResponse.statusCode, "Failed to delete category")
        }
    }
    
    func updateContentCategory(contentId: UUID, categoryId: UUID?) async throws {
        guard let url = supabaseUrl, let key = supabaseKey else {
            throw SupabaseError.notConfigured
        }
        
        let endpoint = "\(url)/rest/v1/saved_content?id=eq.\(contentId.uuidString)"
        var payload: [String: Any] = [:]
        if let categoryId = categoryId {
            payload["category_id"] = categoryId.uuidString
        } else {
            payload["category_id"] = NSNull()
        }
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PATCH"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 && httpResponse.statusCode != 204 {
            throw SupabaseError.apiError(httpResponse.statusCode, "Failed to update content category")
        }
    }
    
    private func markAsFailed(contentId: UUID) async throws {
        guard let url = supabaseUrl, let key = supabaseKey else {
            throw SupabaseError.notConfigured
        }
        
        let endpoint = "\(url)/rest/v1/saved_content?id=eq.\(contentId.uuidString)"
        let payload: [String: Any] = ["status": "failed"]
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PATCH"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 && httpResponse.statusCode != 204 {
            throw SupabaseError.apiError(httpResponse.statusCode, "Failed to mark as failed")
        }
    }
    
    // MARK: - Editing Methods
    
    func updateSummary(id: UUID, shortSummary: String, detailedSummary: String) async throws {
        guard let url = supabaseUrl, let key = supabaseKey else {
            throw SupabaseError.notConfigured
        }
        
        let endpoint = "\(url)/rest/v1/summaries?id=eq.\(id.uuidString)"
        let payload: [String: Any] = [
            "short_summary": shortSummary,
            "detailed_summary": detailedSummary
        ]
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PATCH"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 && httpResponse.statusCode != 204 {
            throw SupabaseError.apiError(httpResponse.statusCode, "Failed to update summary")
        }
    }
    
    func updateContentTitle(id: UUID, title: String) async throws {
        guard let url = supabaseUrl, let key = supabaseKey else {
            throw SupabaseError.notConfigured
        }
        
        let endpoint = "\(url)/rest/v1/saved_content?id=eq.\(id.uuidString)"
        let payload: [String: Any] = ["title": title]
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PATCH"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 && httpResponse.statusCode != 204 {
            throw SupabaseError.apiError(httpResponse.statusCode, "Failed to update title")
        }
    }
    
    func deleteContent(id: UUID) async throws {
        guard let url = supabaseUrl, let key = supabaseKey else {
            throw SupabaseError.notConfigured
        }
        
        // Delete summary first (if exists)
        let summaryEndpoint = "\(url)/rest/v1/summaries?content_id=eq.\(id.uuidString)"
        var summaryRequest = URLRequest(url: URL(string: summaryEndpoint)!)
        summaryRequest.httpMethod = "DELETE"
        summaryRequest.setValue(key, forHTTPHeaderField: "apikey")
        summaryRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        
        let (_, summaryResponse) = try await URLSession.shared.data(for: summaryRequest)
        
        // Delete content
        let contentEndpoint = "\(url)/rest/v1/saved_content?id=eq.\(id.uuidString)"
        var contentRequest = URLRequest(url: URL(string: contentEndpoint)!)
        contentRequest.httpMethod = "DELETE"
        contentRequest.setValue(key, forHTTPHeaderField: "apikey")
        contentRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        
        let (_, contentResponse) = try await URLSession.shared.data(for: contentRequest)
        
        guard let httpResponse = contentResponse as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 && httpResponse.statusCode != 204 {
            throw SupabaseError.apiError(httpResponse.statusCode, "Failed to delete content")
        }
    }
}

// MARK: - Errors
enum SupabaseError: LocalizedError {
    case notConfigured
    case invalidResponse
    case apiError(Int, String)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase is not configured. Please set up in settings."
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let code, let message):
            return "API Error \(code): \(message)"
        }
    }
}

