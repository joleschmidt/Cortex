import Foundation

// MARK: - ContentType
enum ContentType: String, Codable {
    case product = "product"
    case article = "article"
    case video = "video"
    case listing = "listing"
    case general = "general"
}

// MARK: - Category
struct Category: Codable, Identifiable {
    let id: UUID
    let name: String
    let parentId: UUID?
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case parentId = "parent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - SavedContent
struct SavedContent: Codable, Identifiable {
    let id: UUID
    let url: String
    let title: String
    let contentText: String
    let contentMarkdown: String?
    let metadata: [String: AnyCodable]?
    let videoId: String?
    let contentType: ContentType?
    let categoryId: UUID?
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
        case contentType = "content_type"
        case categoryId = "category_id"
        case createdAt = "created_at"
        case processedAt = "processed_at"
        case status
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        contentText = try container.decode(String.self, forKey: .contentText)
        contentMarkdown = try container.decodeIfPresent(String.self, forKey: .contentMarkdown)
        
        // Handle metadata - can be null, object, or missing
        if container.contains(.metadata) {
            if let metadataDict = try? container.decode([String: AnyCodable].self, forKey: .metadata) {
                metadata = metadataDict
            } else {
                metadata = nil
            }
        } else {
            metadata = nil
        }
        
        videoId = try container.decodeIfPresent(String.self, forKey: .videoId)
        contentType = try container.decodeIfPresent(ContentType.self, forKey: .contentType)
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        processedAt = try container.decodeIfPresent(Date.self, forKey: .processedAt)
        status = try container.decode(ProcessingStatus.self, forKey: .status)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(title, forKey: .title)
        try container.encode(contentText, forKey: .contentText)
        try container.encodeIfPresent(contentMarkdown, forKey: .contentMarkdown)
        try container.encodeIfPresent(metadata, forKey: .metadata)
        try container.encodeIfPresent(videoId, forKey: .videoId)
        try container.encodeIfPresent(contentType, forKey: .contentType)
        try container.encodeIfPresent(categoryId, forKey: .categoryId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(processedAt, forKey: .processedAt)
        try container.encode(status, forKey: .status)
    }
}

// MARK: - ExtractedData
struct ExtractedData: Codable {
    let type: String
    let structuredData: [String: AnyCodable]?
    let keyPoints: [String]?
    let actionableInsights: [String]?
    let metadata: [String: AnyCodable]?
    
    enum CodingKeys: String, CodingKey {
        case type
        case structuredData = "structured_data"
        case keyPoints = "key_points"
        case actionableInsights = "actionable_insights"
        case metadata
    }
    
    init(type: String, structuredData: [String: AnyCodable]?, keyPoints: [String]?, actionableInsights: [String]?, metadata: [String: AnyCodable]?) {
        self.type = type
        self.structuredData = structuredData
        self.keyPoints = keyPoints
        self.actionableInsights = actionableInsights
        self.metadata = metadata
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        structuredData = try container.decodeIfPresent([String: AnyCodable].self, forKey: .structuredData)
        keyPoints = try container.decodeIfPresent([String].self, forKey: .keyPoints)
        actionableInsights = try container.decodeIfPresent([String].self, forKey: .actionableInsights)
        
        if container.contains(.metadata) {
            if let metadataDict = try? container.decode([String: AnyCodable].self, forKey: .metadata) {
                metadata = metadataDict
            } else {
                metadata = nil
            }
        } else {
            metadata = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(structuredData, forKey: .structuredData)
        try container.encodeIfPresent(keyPoints, forKey: .keyPoints)
        try container.encodeIfPresent(actionableInsights, forKey: .actionableInsights)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}

// MARK: - Summary
struct Summary: Codable, Identifiable {
    let id: UUID
    let contentId: UUID
    let shortSummary: String
    let detailedSummary: String
    let extractedData: ExtractedData?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case contentId = "content_id"
        case shortSummary = "short_summary"
        case detailedSummary = "detailed_summary"
        case extractedData = "extracted_data"
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

