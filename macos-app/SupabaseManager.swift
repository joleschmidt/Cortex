import Foundation
import Combine

class SupabaseManager: ObservableObject {
    @Published var isConfigured: Bool = false
    @Published var lastError: String?
    
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
        guard isConfigured, !isPolling else { return }
        
        isPolling = true
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.processNextItem()
        }
        
        // Process immediately on start
        processNextItem()
    }
    
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        isPolling = false
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
        
        let endpoint = "\(url)/rest/v1/saved_content?status=eq.pending&order=created_at.asc&limit=10"
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
    
    func updateContentWithSummary(contentId: UUID, shortSummary: String, detailedSummary: String) async throws {
        guard let url = supabaseUrl, let key = supabaseKey else {
            throw SupabaseError.notConfigured
        }
        
        // First, create the summary
        let summaryEndpoint = "\(url)/rest/v1/summaries"
        let summaryPayload: [String: Any] = [
            "content_id": contentId.uuidString,
            "short_summary": shortSummary,
            "detailed_summary": detailedSummary
        ]
        
        var summaryRequest = URLRequest(url: URL(string: summaryEndpoint)!)
        summaryRequest.httpMethod = "POST"
        summaryRequest.setValue(key, forHTTPHeaderField: "apikey")
        summaryRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        summaryRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        summaryRequest.setValue("return=representation", forHTTPHeaderField: "Prefer")
        summaryRequest.httpBody = try JSONSerialization.data(withJSONObject: summaryPayload)
        
        let (summaryData, summaryResponse) = try await URLSession.shared.data(for: summaryRequest)
        
        guard let summaryHttpResponse = summaryResponse as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if summaryHttpResponse.statusCode != 201 {
            let errorMessage = String(data: summaryData, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.apiError(summaryHttpResponse.statusCode, errorMessage)
        }
        
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
        guard isConfigured else { return }
        
        Task {
            do {
                let items = try await fetchUnprocessedContent()
                
                guard let item = items.first else {
                    return // No items to process
                }
                
                // Mark as processing
                try await markAsProcessing(contentId: item.id)
                
                // Generate summaries with error handling
                let processor = AppleIntelligenceProcessor()
                let summaries: Summaries
                
                do {
                    summaries = try await processor.generateSummaries(
                        content: item.contentText,
                        markdown: item.contentMarkdown ?? item.contentText
                    )
                } catch {
                    // If summarization fails, mark as failed
                    try await markAsFailed(contentId: item.id)
                    throw error
                }
                
                // Save summaries
                try await updateContentWithSummary(
                    contentId: item.id,
                    shortSummary: summaries.short,
                    detailedSummary: summaries.detailed
                )
                
                // Clear error on success
                await MainActor.run {
                    self.lastError = nil
                }
                
                // Add jitter to avoid synchronized requests
                let jitter = Double.random(in: 0...5)
                try await Task.sleep(nanoseconds: UInt64(jitter * 1_000_000_000))
                
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                }
                print("Error processing content: \(error)")
                
                // Retry with exponential backoff (handled by timer)
            }
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

