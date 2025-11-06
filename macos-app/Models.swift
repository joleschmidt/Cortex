import Foundation

// MARK: - SavedContent
struct SavedContent: Codable, Identifiable {
    let id: UUID
    let url: String
    let title: String
    let contentText: String
    let contentMarkdown: String?
    let metadata: [String: AnyCodable]?
    let videoId: String?
    let createdAt: Date
    let processedAt: Date?
    let status: ProcessingStatus
    
    enum CodingKeys: String, CodingKey {
        case id
        case url
        case title
        case contentText = "content_text"
        case contentMarkdown = "content_markdown"
        case metadata
        case videoId = "video_id"
        case createdAt = "created_at"
        case processedAt = "processed_at"
        case status
    }
}

// MARK: - Summary
struct Summary: Codable, Identifiable {
    let id: UUID
    let contentId: UUID
    let shortSummary: String
    let detailedSummary: String
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case contentId = "content_id"
        case shortSummary = "short_summary"
        case detailedSummary = "detailed_summary"
        case createdAt = "created_at"
    }
}

// MARK: - ProcessingStatus
enum ProcessingStatus: String, Codable {
    case pending = "pending"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
}

// MARK: - ProcessingQueueItem
struct ProcessingQueueItem: Codable, Identifiable {
    let id: UUID
    let contentId: UUID
    let status: ProcessingStatus
    let retryCount: Int
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case contentId = "content_id"
        case status
        case retryCount = "retry_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - AnyCodable (for flexible JSON metadata)
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            let codableArray = array.map { AnyCodable($0) }
            try container.encode(codableArray)
        case let dictionary as [String: Any]:
            let codableDictionary = dictionary.mapValues { AnyCodable($0) }
            try container.encode(codableDictionary)
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded"))
        }
    }
}

