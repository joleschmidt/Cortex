import Foundation
import NaturalLanguage

struct Summaries {
    let short: String
    let detailed: String
}

struct ProcessingResult {
    let summaries: Summaries
    let contentType: ContentType
    let extractedData: ExtractedData
    let keyPoints: [String]?
    let reviews: [String]?
}

class AppleIntelligenceProcessor {
    private let isAvailable: Bool
    
    init() {
        if #available(macOS 15.0, *) {
            self.isAvailable = true
        } else {
            self.isAvailable = false
        }
    }
    
    func processContent(url: String, title: String, content: String, markdown: String, metadata: [String: AnyCodable]?) async throws -> ProcessingResult {
        // Validate input
        let text = markdown.isEmpty ? content : markdown
        
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProcessingError.emptyContent
        }
        
        // Handle very long content - increased limit to capture full product descriptions
        // Product pages can have very detailed descriptions, so we use a higher limit
        let maxLength = 100000 // Increased from 50000 to capture full descriptions
        let processedText = text.count > maxLength ? String(text.prefix(maxLength)) : text
        
        // Detect content type
        let contentType = detectContentType(url: url, title: title, text: processedText, metadata: metadata)
        
        // Extract structured data based on content type (basic extraction)
        var extractedData = try await extractStructuredData(
            contentType: contentType,
            url: url,
            title: title,
            text: processedText,
            metadata: metadata
        )
        
        // Generate summaries with content-aware strategies
        // This also gives us scoredSentences for comprehensive keyPoints extraction
        let summaries: Summaries
        let scoredSentences: [(sentence: String, score: Double)]
        
        if isAvailable {
            if #available(macOS 15.0, *) {
                let result = try await generateWithAppleIntelligenceAndScoredSentences(
                    text: processedText,
                    contentType: contentType
                )
                summaries = result.summaries
                scoredSentences = result.scoredSentences
            } else {
                let result = try generateEnhancedSummariesWithScoredSentences(
                    text: processedText,
                    contentType: contentType
                )
                summaries = result.summaries
                scoredSentences = result.scoredSentences
            }
        } else {
            let result = try generateEnhancedSummariesWithScoredSentences(
                text: processedText,
                contentType: contentType
            )
            summaries = result.summaries
            scoredSentences = result.scoredSentences
        }
        
        // Extract comprehensive keyPoints using scoredSentences
        let comprehensiveKeyPoints = extractComprehensiveKeyPoints(
            contentType: contentType,
            text: processedText,
            scoredSentences: scoredSentences
        )
        
        // Extract reviews separately (not part of ExtractedData)
        let reviews = extractReviews(text: processedText)
        
        // Update ExtractedData with comprehensive keyPoints (but not reviews)
        if !comprehensiveKeyPoints.isEmpty {
            extractedData = ExtractedData(
                type: extractedData.type,
                structuredData: extractedData.structuredData,
                keyPoints: comprehensiveKeyPoints,
                actionableInsights: extractedData.actionableInsights,
                metadata: extractedData.metadata
            )
        }
        
        return ProcessingResult(
            summaries: summaries,
            contentType: contentType,
            extractedData: extractedData,
            keyPoints: comprehensiveKeyPoints.isEmpty ? nil : comprehensiveKeyPoints,
            reviews: reviews.isEmpty ? nil : reviews
        )
    }
    
    // MARK: - Content Type Detection
    
    private func detectContentType(url: String, title: String, text: String, metadata: [String: AnyCodable]?) -> ContentType {
        let lowerUrl = url.lowercased()
        let lowerText = text.lowercased()
        
        // Check metadata for type hints
        if let metadata = metadata {
            // Check JSON-LD for schema.org types
            if let jsonLd = metadata["jsonLd"]?.value as? [[String: Any]] {
                for item in jsonLd {
                    if let type = item["@type"] as? String {
                        if type.contains("Product") {
                            return .product
                        }
                        if type.contains("Article") || type.contains("BlogPosting") || type.contains("NewsArticle") {
                            return .article
                        }
                        if type.contains("VideoObject") {
                            return .video
                        }
                    }
                }
            }
            
            // Check Open Graph
            if let openGraph = metadata["openGraph"]?.value as? [String: Any] {
                if let type = openGraph["type"] as? String {
                    if type == "product" {
                        return .product
                    }
                    if type == "article" {
                        return .article
                    }
                    if type == "video" {
                        return .video
                    }
                }
            }
        }
        
        // URL pattern detection
        if lowerUrl.contains("youtube.com") || lowerUrl.contains("youtu.be") || lowerUrl.contains("vimeo.com") {
            return .video
        }
        
        if lowerUrl.contains("/product/") || lowerUrl.contains("/p/") || lowerUrl.contains("/item/") ||
           lowerUrl.contains("shop") || lowerUrl.contains("store") || lowerUrl.contains("buy") {
            return .product
        }
        
        if lowerUrl.contains("/article/") || lowerUrl.contains("/post/") || lowerUrl.contains("/blog/") ||
           lowerUrl.contains("/news/") {
            return .article
        }
        
        if lowerUrl.contains("/search") || lowerUrl.contains("/listing") || lowerUrl.contains("/results") ||
           lowerText.contains("filter") && lowerText.contains("sort") {
            return .listing
        }
        
        // Content analysis
        let productIndicators = ["price", "€", "$", "£", "add to cart", "buy now", "in stock", "out of stock", "shipping"]
        let productCount = productIndicators.filter { lowerText.contains($0) }.count
        if productCount >= 2 {
            return .product
        }
        
        let articleIndicators = ["published", "author", "read more", "article", "by ", "posted on"]
        let articleCount = articleIndicators.filter { lowerText.contains($0) }.count
        if articleCount >= 2 {
            return .article
        }
        
        return .general
    }
    
    // MARK: - Structured Data Extraction
    
    private func extractStructuredData(
        contentType: ContentType,
        url: String,
        title: String,
        text: String,
        metadata: [String: AnyCodable]?
    ) async throws -> ExtractedData {
        var structuredData: [String: AnyCodable] = [:]
        var keyPoints: [String] = []
        var actionableInsights: [String] = []
        var extractedMetadata: [String: AnyCodable] = [:]
        
        switch contentType {
        case .product:
            let productData = extractProductData(text: text, metadata: metadata)
            structuredData = productData.structured
            keyPoints = productData.keyPoints
            actionableInsights = productData.insights
            
        case .article:
            let articleData = extractArticleData(text: text, metadata: metadata)
            structuredData = articleData.structured
            keyPoints = articleData.keyPoints
            actionableInsights = articleData.insights
            
        case .video:
            let videoData = extractVideoData(text: text, metadata: metadata)
            structuredData = videoData.structured
            keyPoints = videoData.keyPoints
            actionableInsights = videoData.insights
            
        case .listing:
            let listingData = extractListingData(text: text, metadata: metadata)
            structuredData = listingData.structured
            keyPoints = listingData.keyPoints
            actionableInsights = listingData.insights
            
        case .general:
            let generalData = extractGeneralData(text: text, metadata: metadata)
            structuredData = generalData.structured
            keyPoints = generalData.keyPoints
            actionableInsights = generalData.insights
        }
        
        // Extract reviews from text (for all content types)
        let reviews = extractReviews(text: text)
        
        // Extract metadata if available
        if let metadata = metadata {
            extractedMetadata = metadata
        }
        
        // Note: reviews are extracted but not stored in ExtractedData
        // They will be stored separately in the Summary
        return ExtractedData(
            type: contentType.rawValue,
            structuredData: structuredData.isEmpty ? nil : structuredData,
            keyPoints: keyPoints.isEmpty ? nil : keyPoints,
            actionableInsights: actionableInsights.isEmpty ? nil : actionableInsights,
            metadata: extractedMetadata.isEmpty ? nil : extractedMetadata
        )
    }
    
    // MARK: - Review Extraction
    
    private func extractReviews(text: String) -> [String] {
        var reviews: [String] = []
        let lowerText = text.lowercased()
        
        // Look for review sections - common patterns
        let reviewIndicators = [
            "rezension", "review", "bewertung", "kundenbewertung", "kundenrezension",
            "basierend auf rezensionen", "based on reviews", "customer review",
            "sterne", "stars", "rating", "bewertet", "rated"
        ]
        
        // Check if text contains review indicators
        let hasReviewSection = reviewIndicators.contains { lowerText.contains($0) }
        
        if hasReviewSection {
            // Split text into paragraphs
            let paragraphs = text.components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            // Also try single newlines if paragraphs don't work
            var allSections = paragraphs
            if paragraphs.count < 3 {
                allSections = text.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0.count > 50 }
            }
            
            // Look for review-like content
            for section in allSections {
                let lowerSection = section.lowercased()
                let trimmed = section.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Skip if too short or too long
                guard trimmed.count > 50 && trimmed.count < 1000 else { continue }
                
                // Look for review patterns
                let isReview = (
                    // Contains review keywords
                    reviewIndicators.contains(where: { lowerSection.contains($0) }) ||
                    // Contains personal experience language
                    lowerSection.contains("ich habe") || lowerSection.contains("i have") ||
                    lowerSection.contains("ich bin") || lowerSection.contains("i am") ||
                    lowerSection.contains("ich kann") || lowerSection.contains("i can") ||
                    lowerSection.contains("meine") || lowerSection.contains("my ") ||
                    // Contains rating language
                    lowerSection.contains("sterne") || lowerSection.contains("stars") ||
                    lowerSection.contains("empfehlung") || lowerSection.contains("recommend") ||
                    // Contains satisfaction language
                    lowerSection.contains("zufrieden") || lowerSection.contains("satisfied") ||
                    lowerSection.contains("begeistert") || lowerSection.contains("excited") ||
                    lowerSection.contains("traum") || lowerSection.contains("dream")
                ) && (
                    // Exclude if it's just a heading or navigation
                    !lowerSection.contains("finden sie") &&
                    !lowerSection.contains("find here") &&
                    !lowerSection.contains("previous") &&
                    !lowerSection.contains("next") &&
                    !lowerSection.contains("zurück") &&
                    !lowerSection.contains("weiter")
                )
                
                if isReview {
                    // Clean up the review text
                    var cleanedReview = trimmed
                    
                    // Remove markdown links but keep text
                    cleanedReview = cleanedReview.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
                    
                    // Remove excessive whitespace
                    while cleanedReview.contains("  ") {
                        cleanedReview = cleanedReview.replacingOccurrences(of: "  ", with: " ")
                    }
                    
                    // Only add if it's substantial and not already in the list
                    if cleanedReview.count > 50 && !reviews.contains(cleanedReview) {
                        reviews.append(cleanedReview)
                    }
                }
            }
        }
        
        // Limit to top 10 reviews
        return Array(reviews.prefix(10))
    }
    
    private func extractProductData(text: String, metadata: [String: AnyCodable]?) -> (structured: [String: AnyCodable], keyPoints: [String], insights: [String]) {
        var structured: [String: AnyCodable] = [:]
        var keyPoints: [String] = []
        var insights: [String] = []
        
        // Extract price
        let pricePattern = #"[\$€£¥]\s*[\d,]+\.?\d*"#
        if let priceRange = text.range(of: pricePattern, options: .regularExpression) {
            let price = String(text[priceRange])
            structured["price"] = AnyCodable(price)
            keyPoints.append("Price: \(price)")
        }
        
        // Extract availability
        let lowerText = text.lowercased()
        if lowerText.contains("in stock") || lowerText.contains("available") {
            structured["availability"] = AnyCodable("in_stock")
            insights.append("Product is currently available")
        } else if lowerText.contains("out of stock") || lowerText.contains("unavailable") {
            structured["availability"] = AnyCodable("out_of_stock")
            insights.append("Product is currently out of stock")
        }
        
        // Extract features/specifications (look for lists)
        let lines = text.components(separatedBy: .newlines)
        var features: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("-") || trimmed.hasPrefix("•") || trimmed.hasPrefix("*") {
                let feature = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if feature.count > 10 && feature.count < 200 {
                    features.append(String(feature))
                }
            }
        }
        if !features.isEmpty {
            structured["features"] = AnyCodable(features.prefix(10).map { AnyCodable($0) })
            keyPoints.append(contentsOf: features.prefix(5))
        }
        
        // Extract description text - look for large text blocks that are likely descriptions
        // Split text into paragraphs and find the longest ones (likely descriptions)
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 100 } // Only substantial paragraphs
        
        if !paragraphs.isEmpty {
            // Find the longest paragraphs (likely product descriptions)
            let longParagraphs = paragraphs.sorted { $0.count > $1.count }.prefix(3)
            let descriptionText = longParagraphs.joined(separator: "\n\n")
            
            // Store full description if it's substantial
            if descriptionText.count > 200 {
                structured["description"] = AnyCodable(descriptionText)
                // Add first part of description as key point
                let firstPart = String(descriptionText.prefix(300))
                if firstPart.count > 100 {
                    keyPoints.append(firstPart + (descriptionText.count > 300 ? "..." : ""))
                }
            }
        }
        
        return (structured, keyPoints, insights)
    }
    
    private func extractArticleData(text: String, metadata: [String: AnyCodable]?) -> (structured: [String: AnyCodable], keyPoints: [String], insights: [String]) {
        var structured: [String: AnyCodable] = [:]
        var keyPoints: [String] = []
        var insights: [String] = []
        
        // Extract author
        if let metadata = metadata, let metaTags = metadata["metaTags"]?.value as? [String: Any] {
            if let author = metaTags["author"] as? String {
                structured["author"] = AnyCodable(author)
            }
            if let date = metaTags["date"] as? String ?? metaTags["published_time"] as? String {
                structured["published_date"] = AnyCodable(date)
            }
        }
        
        // Extract key points from headings
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("#") || line.hasPrefix("##") {
                let heading = line.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
                if heading.count > 5 && heading.count < 100 {
                    keyPoints.append(heading)
                }
            }
        }
        
        // Extract main points (first few sentences of paragraphs)
        let paragraphs = text.components(separatedBy: "\n\n")
        for paragraph in paragraphs.prefix(5) {
            let sentences = paragraph.components(separatedBy: ". ")
            if let firstSentence = sentences.first, firstSentence.count > 20 && firstSentence.count < 200 {
                keyPoints.append(firstSentence.trimmingCharacters(in: .whitespaces))
            }
        }
        
        return (structured, Array(keyPoints.prefix(10)), insights)
    }
    
    private func extractVideoData(text: String, metadata: [String: AnyCodable]?) -> (structured: [String: AnyCodable], keyPoints: [String], insights: [String]) {
        var structured: [String: AnyCodable] = [:]
        var keyPoints: [String] = []
        var insights: [String] = []
        
        // Extract topics from transcript
        let sentences = text.components(separatedBy: ". ")
        var topics: [String] = []
        
        // Look for repeated keywords (likely topics)
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 4 }
        
        var wordCounts: [String: Int] = [:]
        for word in words {
            wordCounts[word, default: 0] += 1
        }
        
        let topWords = wordCounts.sorted { $0.value > $1.value }.prefix(5)
        topics = topWords.map { $0.key.capitalized }
        
        if !topics.isEmpty {
            structured["topics"] = AnyCodable(topics.map { AnyCodable($0) })
            keyPoints.append(contentsOf: topics)
        }
        
        // Extract key moments (sentences with important keywords)
        for sentence in sentences {
            let lowerSentence = sentence.lowercased()
            if lowerSentence.contains("important") || lowerSentence.contains("key") ||
               lowerSentence.contains("main") || lowerSentence.contains("summary") {
                if sentence.count > 20 && sentence.count < 200 {
                    keyPoints.append(sentence.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        
        return (structured, Array(keyPoints.prefix(10)), insights)
    }
    
    private func extractListingData(text: String, metadata: [String: AnyCodable]?) -> (structured: [String: AnyCodable], keyPoints: [String], insights: [String]) {
        var structured: [String: AnyCodable] = [:]
        var keyPoints: [String] = []
        var insights: [String] = []
        
        // Extract count
        let countPattern = #"\d+\s+(results|items|products|offers)"#
        if let countRange = text.range(of: countPattern, options: .regularExpression) {
            let countText = String(text[countRange])
            structured["count"] = AnyCodable(countText)
            keyPoints.append(countText.capitalized)
        }
        
        // Extract filter options
        let lines = text.components(separatedBy: .newlines)
        var filters: [String] = []
        for line in lines {
            let lowerLine = line.lowercased()
            if lowerLine.contains("filter") || lowerLine.contains("sort") {
                let filter = line.trimmingCharacters(in: .whitespaces)
                if filter.count > 5 && filter.count < 100 {
                    filters.append(filter)
                }
            }
        }
        if !filters.isEmpty {
            structured["filters"] = AnyCodable(filters.prefix(5).map { AnyCodable($0) })
        }
        
        return (structured, keyPoints, insights)
    }
    
    private func extractGeneralData(text: String, metadata: [String: AnyCodable]?) -> (structured: [String: AnyCodable], keyPoints: [String], insights: [String]) {
        var structured: [String: AnyCodable] = [:]
        var keyPoints: [String] = []
        var insights: [String] = []
        
        // Extract headings as key points
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("#") {
                let heading = line.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
                if heading.count > 5 {
                    keyPoints.append(heading)
                }
            }
        }
        
        return (structured, Array(keyPoints.prefix(10)), insights)
    }
    
    // MARK: - Enhanced Summarization
    
    @available(macOS 15.0, *)
    private func generateWithAppleIntelligence(text: String, contentType: ContentType) async throws -> Summaries {
        // Use TF-IDF based summarization with content-aware strategies
        return try generateEnhancedSummaries(text: text, contentType: contentType)
    }
    
    @available(macOS 15.0, *)
    private func generateWithAppleIntelligenceAndScoredSentences(text: String, contentType: ContentType) async throws -> (summaries: Summaries, scoredSentences: [(sentence: String, score: Double)]) {
        // Use TF-IDF based summarization with content-aware strategies
        return try generateEnhancedSummariesWithScoredSentences(text: text, contentType: contentType)
    }
    
    private func generateEnhancedSummariesWithScoredSentences(text: String, contentType: ContentType) throws -> (summaries: Summaries, scoredSentences: [(sentence: String, score: Double)]) {
        let sentences = extractSentences(text: text)
        
        guard !sentences.isEmpty else {
            return (Summaries(short: text.prefix(150).description, detailed: text.prefix(400).description), [])
        }
        
        // Score sentences using TF-IDF
        let scoredSentences = scoreSentences(sentences: sentences, contentType: contentType)
        
        // Extract key points for bullet list
        let keyPoints = extractKeyPointsForSummary(text: text, contentType: contentType, scoredSentences: scoredSentences)
        
        // Generate short summary (flowing narrative, ~150 words)
        let shortSummary = buildFlowingSummary(
            scoredSentences: scoredSentences,
            targetWords: 150,
            maxSentences: 5
        )
        
        // Generate extensive detailed summary based on content type
        let detailedSummary: String
        switch contentType {
        case .product:
            // For products, create a very comprehensive summary with full descriptions
            detailedSummary = buildExtensiveProductSummary(
                text: text,
                scoredSentences: scoredSentences,
                keyPoints: keyPoints
            )
        case .article:
            // For articles, include more content (1000+ words)
            let narrativeSummary = buildFlowingSummary(
                scoredSentences: scoredSentences,
                targetWords: 1000,
                maxSentences: 40
            )
            if !keyPoints.isEmpty {
                let bulletPoints = keyPoints.map { "• \($0)" }.joined(separator: "\n")
                detailedSummary = "\(narrativeSummary)\n\n\nKey Highlights:\n\(bulletPoints)"
            } else {
                detailedSummary = narrativeSummary
            }
        default:
            // For other types, use moderate length (600 words)
            let narrativeSummary = buildFlowingSummary(
                scoredSentences: scoredSentences,
                targetWords: 600,
                maxSentences: 25
            )
            if !keyPoints.isEmpty {
                let bulletPoints = keyPoints.map { "• \($0)" }.joined(separator: "\n")
                detailedSummary = "\(narrativeSummary)\n\n\nKey Highlights:\n\(bulletPoints)"
            } else {
                detailedSummary = narrativeSummary
            }
        }
        
        return (Summaries(short: shortSummary, detailed: detailedSummary), scoredSentences)
    }
    
    private func extractComprehensiveKeyPoints(
        contentType: ContentType,
        text: String,
        scoredSentences: [(sentence: String, score: Double)]
    ) -> [String] {
        switch contentType {
        case .product:
            return extractProductKeyPoints(text: text, scoredSentences: scoredSentences)
        case .article:
            return extractArticleKeyPoints(text: text, scoredSentences: scoredSentences)
        case .video:
            return extractVideoKeyPoints(text: text, scoredSentences: scoredSentences)
        case .listing, .general:
            return extractGeneralKeyPoints(text: text, scoredSentences: scoredSentences)
        }
    }
    
    private func generateEnhancedSummaries(text: String, contentType: ContentType) throws -> Summaries {
        let sentences = extractSentences(text: text)
        
        guard !sentences.isEmpty else {
            return Summaries(short: text.prefix(150).description, detailed: text.prefix(400).description)
        }
        
        // Score sentences using TF-IDF
        let scoredSentences = scoreSentences(sentences: sentences, contentType: contentType)
        
        // Extract key points for bullet list
        let keyPoints = extractKeyPointsForSummary(text: text, contentType: contentType, scoredSentences: scoredSentences)
        
        // Generate short summary (flowing narrative, ~150 words)
        let shortSummary = buildFlowingSummary(
            scoredSentences: scoredSentences,
            targetWords: 150,
            maxSentences: 5
        )
        
        // Generate extensive detailed summary based on content type
        let detailedSummary: String
        switch contentType {
        case .product:
            // For products, create a very comprehensive summary with full descriptions
            detailedSummary = buildExtensiveProductSummary(
                text: text,
            scoredSentences: scoredSentences,
                keyPoints: keyPoints
            )
        case .article:
            // For articles, include more content (1000+ words)
            let narrativeSummary = buildFlowingSummary(
                scoredSentences: scoredSentences,
                targetWords: 1000,
                maxSentences: 40
            )
            if !keyPoints.isEmpty {
                let bulletPoints = keyPoints.map { "• \($0)" }.joined(separator: "\n")
                detailedSummary = "\(narrativeSummary)\n\n\nKey Highlights:\n\(bulletPoints)"
            } else {
                detailedSummary = narrativeSummary
            }
        default:
            // For other types, use moderate length (600 words)
            let narrativeSummary = buildFlowingSummary(
            scoredSentences: scoredSentences,
                targetWords: 600,
                maxSentences: 25
            )
            if !keyPoints.isEmpty {
                let bulletPoints = keyPoints.map { "• \($0)" }.joined(separator: "\n")
                detailedSummary = "\(narrativeSummary)\n\n\nKey Highlights:\n\(bulletPoints)"
            } else {
                detailedSummary = narrativeSummary
            }
        }
        
        return Summaries(short: shortSummary, detailed: detailedSummary)
    }
    
    private func extractSentences(text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.count > 10 { // Filter very short sentences
                sentences.append(sentence)
            }
            return true
        }
        
        return sentences
    }
    
    private func scoreSentences(sentences: [String], contentType: ContentType) -> [(sentence: String, score: Double)] {
        // Calculate TF-IDF scores
        var scores: [(sentence: String, score: Double)] = []
        
        // Build vocabulary
        var allWords: [String] = []
        for sentence in sentences {
            let words = tokenize(sentence)
            allWords.append(contentsOf: words)
        }
        
        let vocabulary = Set(allWords)
        let documentFrequency: [String: Int] = Dictionary(grouping: allWords, by: { $0 })
            .mapValues { $0.count }
        
        // Score each sentence
        for sentence in sentences {
            var score = 0.0
            let words = tokenize(sentence)
            let wordCount = words.count
            
            // TF-IDF calculation
            var termFrequencies: [String: Double] = [:]
            for word in words {
                termFrequencies[word, default: 0.0] += 1.0
            }
            
            for (word, tf) in termFrequencies {
                let normalizedTF = tf / Double(wordCount)
                let df = Double(documentFrequency[word] ?? 1)
                let idf = log(Double(sentences.count) / df)
                score += normalizedTF * idf
            }
            
            // Content-aware bonuses
            let lowerSentence = sentence.lowercased()
            
            switch contentType {
            case .product:
                // Prioritize descriptive content over technical specs
                if lowerSentence.contains("beschreibung") || lowerSentence.contains("description") {
                    score += 3.0
                }
                // Penalize price-only or spec-only sentences
                if lowerSentence.range(of: #"^[\$€£¥]\s*[\d.,]+\s*$"#, options: .regularExpression) != nil {
                    score -= 5.0 // Heavy penalty for price-only lines
                }
                // Penalize short spec lines (format: "Key: Value")
                if sentence.contains(":") && sentence.count < 150 {
                    let parts = sentence.components(separatedBy: ":")
                    if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces).count < 30 {
                        score -= 3.0 // Penalize spec lines
                    }
                }
                // Bonus for descriptive language
                let descriptiveWords = ["ist", "sind", "wird", "werden", "hat", "haben", "zeigt", "bietet", "garantiert", "gefertigt", "handgefertigt", "entworfen", "bekannt für", "gilt als"]
                if descriptiveWords.contains(where: { lowerSentence.contains($0) }) {
                    score += 2.0
                }
                // Bonus for longer descriptive sentences
                if sentence.count > 150 {
                    score += 1.5
                }
                
            case .article:
                if sentence.hasPrefix("#") || sentence.hasPrefix("##") {
                    score += 3.0
                }
                if lowerSentence.contains("conclusion") || lowerSentence.contains("summary") {
                    score += 2.0
                }
                
            case .video:
                if lowerSentence.contains("important") || lowerSentence.contains("key") {
                    score += 2.0
                }
                
            case .listing, .general:
                break
            }
            
            // Position bonus (earlier sentences often more important)
            if let index = sentences.firstIndex(where: { $0 == sentence }) {
                let positionBonus = 1.0 / (1.0 + Double(index) * 0.1)
                score += positionBonus
            }
            
            // Length penalty (very long or very short sentences are less ideal)
            let length = sentence.count
            if length < 20 {
                score *= 0.5
            } else if length > 300 {
                score *= 0.7
            }
            
            scores.append((sentence: sentence, score: score))
        }
        
        // Sort by score
        return scores.sorted { $0.score > $1.score }
    }
    
    private func tokenize(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text.lowercased()
        
        var words: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).lowercased()
            // Filter out very short words and common stop words
            if word.count > 2 && !isStopWord(word) {
                words.append(word)
            }
            return true
        }
        
        return words
    }
    
    private func isStopWord(_ word: String) -> Bool {
        let stopWords = Set(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "is", "are", "was", "were", "be", "been", "have", "has", "had", "do", "does", "did", "will", "would", "should", "could", "may", "might", "must", "can", "this", "that", "these", "those", "i", "you", "he", "she", "it", "we", "they"])
        return stopWords.contains(word.lowercased())
    }
    
    private func buildFlowingSummary(scoredSentences: [(sentence: String, score: Double)], targetWords: Int, maxSentences: Int) -> String {
        var selectedSentences: [String] = []
        var wordCount = 0
        
        // Select top sentences up to target word count
        for (sentence, _) in scoredSentences.prefix(maxSentences) {
            let words = sentence.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if wordCount + words.count <= targetWords {
                selectedSentences.append(sentence)
                wordCount += words.count
            } else {
                break
            }
        }
        
        if selectedSentences.isEmpty && !scoredSentences.isEmpty {
            // Fallback: use first sentence
            let firstSentence = scoredSentences[0].sentence
            let words = firstSentence.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            let truncated = words.prefix(targetWords).joined(separator: " ")
            return truncated + (words.count > targetWords ? "..." : "")
        }
        
        // Create flowing text by intelligently combining sentences
        return createFlowingText(from: selectedSentences)
    }
    
    private func createFlowingText(from sentences: [String]) -> String {
        guard !sentences.isEmpty else { return "" }
        
        var flowingSentences: [String] = []
        
        for (index, sentence) in sentences.enumerated() {
            var cleaned = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Remove redundant sentence starters if not first sentence
            if index > 0 {
                // Remove common redundant phrases at the start
                let redundantStarters = [
                    "This ", "The ", "It ", "That ", "These ", "Those ",
                    "In addition, ", "Furthermore, ", "Moreover, ",
                    "Additionally, ", "Also, ", "Plus, "
                ]
                for starter in redundantStarters {
                    if cleaned.hasPrefix(starter) {
                        cleaned = String(cleaned.dropFirst(starter.count))
                        break
                    }
                }
            }
            
            // Ensure sentence ends with punctuation
            if !cleaned.isEmpty {
                let lastChar = cleaned.suffix(1)
                if lastChar != "." && lastChar != "!" && lastChar != "?" {
                    cleaned += "."
                }
                flowingSentences.append(cleaned)
            }
        }
        
        // Join sentences with proper spacing
        var flowingText = flowingSentences.joined(separator: " ")
        
        // Ensure proper capitalization of first letter
        if !flowingText.isEmpty {
            let firstChar = flowingText.prefix(1).uppercased()
            let rest = flowingText.dropFirst()
            flowingText = firstChar + rest
        }
        
        // Clean up multiple spaces
        while flowingText.contains("  ") {
            flowingText = flowingText.replacingOccurrences(of: "  ", with: " ")
        }
        
        return flowingText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractKeyPointsForSummary(text: String, contentType: ContentType, scoredSentences: [(sentence: String, score: Double)]) -> [String] {
        var keyPoints: [String] = []
        
        switch contentType {
        case .product:
            // Extract product features, specs, and highlights
            keyPoints = extractProductKeyPoints(text: text, scoredSentences: scoredSentences)
            
        case .article:
            // Extract main points from article
            keyPoints = extractArticleKeyPoints(text: text, scoredSentences: scoredSentences)
            
        case .video:
            // Extract key topics and moments
            keyPoints = extractVideoKeyPoints(text: text, scoredSentences: scoredSentences)
            
        case .listing, .general:
            // Extract general highlights
            keyPoints = extractGeneralKeyPoints(text: text, scoredSentences: scoredSentences)
        }
        
        // Limit to top 8-10 key points
        return Array(keyPoints.prefix(10))
    }
    
    private func extractMainProductPrice(text: String) -> String? {
        // Find all prices in the text with their context
        let pricePattern = #"[\$€£¥]\s*[\d.,]+\.?\d*"#
        let regex = try? NSRegularExpression(pattern: pricePattern, options: [])
        let nsText = text as NSString
        let matches = regex?.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) ?? []
        
        struct PriceCandidate {
            let price: String
            let value: Double
            let context: String
            let score: Double
        }
        
        var candidates: [PriceCandidate] = []
        
        for match in matches {
            let priceRange = match.range
            let priceString = nsText.substring(with: priceRange)
            
            // Extract numeric value (handle both European comma and US period formats)
            var numericString = priceString
                .replacingOccurrences(of: "[€$£¥\\s]", with: "", options: .regularExpression)
            
            // Handle European format (comma as decimal, period as thousands)
            if numericString.contains(",") && numericString.contains(".") {
                // Period is thousands separator, comma is decimal
                numericString = numericString.replacingOccurrences(of: ".", with: "")
                numericString = numericString.replacingOccurrences(of: ",", with: ".")
            } else if numericString.contains(",") && !numericString.contains(".") {
                // Only comma - could be decimal or thousands separator
                // If there are 3+ digits after comma, it's likely thousands separator
                let parts = numericString.components(separatedBy: ",")
                if parts.count == 2 && parts[1].count >= 3 {
                    // Thousands separator
                    numericString = numericString.replacingOccurrences(of: ",", with: "")
                } else {
                    // Decimal separator
                    numericString = numericString.replacingOccurrences(of: ",", with: ".")
                }
            } else if numericString.contains(".") && !numericString.contains(",") {
                // Only period - could be decimal or thousands separator
                let parts = numericString.components(separatedBy: ".")
                if parts.count == 2 && parts[1].count >= 3 {
                    // Likely thousands separator (e.g., 1.500 = 1500)
                    numericString = numericString.replacingOccurrences(of: ".", with: "")
                }
                // Otherwise treat as decimal (US format)
            }
            
            guard let value = Double(numericString) else { continue }
            
            // Get context (50 chars before and after)
            let contextStart = max(0, priceRange.location - 50)
            let contextLength = min(100, nsText.length - contextStart)
            let context = nsText.substring(with: NSRange(location: contextStart, length: contextLength)).lowercased()
            
            // Skip if it's clearly a shipping/delivery cost
            let shippingKeywords = [
                "versand", "shipping", "lieferung", "delivery", "zustellung",
                "schnelle lieferung", "fast delivery", "standardlieferung", "standard delivery",
                "express", "expresslieferung", "express delivery"
            ]
            if shippingKeywords.contains(where: { context.contains($0) }) {
                continue
            }
            
            // Skip if it's a discount percentage or small amount (likely shipping)
            if context.contains("-") && context.contains("%") {
                continue
            }
            if value < 20 && (context.contains("versand") || context.contains("shipping") || context.contains("lieferung")) {
                continue
            }
            
            // Score the price based on context
            var score: Double = 0.0
            
            // High priority: explicit price labels
            if context.contains("preis:") || context.contains("price:") ||
               context.contains("uvp") || context.contains("msrp") ||
               context.contains("ab") || context.contains("from") {
                score += 10.0
            }
            
            // Medium priority: near product-related terms
            if context.contains("produkt") || context.contains("product") ||
               context.contains("artikel") || context.contains("item") {
                score += 5.0
            }
            
            // Bonus for larger prices (likely main product price)
            if value > 50 {
                score += 3.0
            }
            if value > 100 {
                score += 2.0
            }
            if value > 500 {
                score += 1.0
            }
            
            // Penalty for very small prices (likely shipping)
            if value < 10 {
                score -= 5.0
            }
            
            // Penalty if near discount/sale keywords
            if context.contains("rabatt") || context.contains("discount") ||
               context.contains("reduziert") || context.contains("reduced") ||
               context.contains("sonderpreis") || context.contains("special price") {
                score -= 3.0
            }
            
            candidates.append(PriceCandidate(price: priceString.trimmingCharacters(in: .whitespaces), value: value, context: context, score: score))
        }
        
        // Sort by score (highest first) and return the best match
        let sortedCandidates = candidates.sorted { $0.score > $1.score }
        
        // Return the highest scoring price, but only if it has a reasonable score
        if let best = sortedCandidates.first, best.score > 0 {
            return best.price
        }
        
        // Fallback: return the largest price that's not clearly shipping
        let nonShippingCandidates = candidates.filter { $0.value >= 20 && $0.score >= -2 }
        if let largest = nonShippingCandidates.max(by: { $0.value < $1.value }) {
            return largest.price
        }
        
        return nil
    }
    
    private func extractProductKeyPoints(text: String, scoredSentences: [(sentence: String, score: Double)]) -> [String] {
        var points: [String] = []
        let lowerText = text.lowercased()
        
        // Smart price extraction - find the main product price, not shipping costs
        if let mainPrice = extractMainProductPrice(text: text) {
            points.append("Price: \(mainPrice)")
        }
        
        // Extract availability (German and English)
        if lowerText.contains("in stock") || lowerText.contains("available") || 
           lowerText.contains("ab lager") || lowerText.contains("verfügbar") {
            points.append("Available in stock")
        }
        
        // Extract key specifications and features
        let lines = text.components(separatedBy: .newlines)
        var features: [String] = []
        var specs: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Look for bullet points or list items
            if trimmed.hasPrefix("-") || trimmed.hasPrefix("•") || trimmed.hasPrefix("*") {
                let feature = trimmed
                    .replacingOccurrences(of: "^[-•*]\\s*", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                if feature.count > 10 && feature.count < 150 && !features.contains(feature) {
                    features.append(feature)
                }
            }
            
            // Look for specification lines (format: "Key: Value" or "Key - Value")
            if trimmed.contains(":") && trimmed.count > 15 && trimmed.count < 150 {
                // Check if it's a spec line (not just a colon in text)
                let parts = trimmed.components(separatedBy: ":")
                if parts.count == 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    let value = parts[1].trimmingCharacters(in: .whitespaces)
                    // Only add if key is short (likely a spec label)
                    if key.count < 50 && value.count > 5 && value.count < 100 {
                        let spec = "\(key): \(value)"
                        if !specs.contains(spec) {
                            specs.append(spec)
                        }
                    }
                }
            }
        }
        
        // Add top features (short, concise)
        points.append(contentsOf: features.prefix(5))
        
        // Add key specifications (limit to most important, keep concise)
        let importantSpecs = specs.filter { spec in
            let lowerSpec = spec.lowercased()
            return lowerSpec.contains("material") || lowerSpec.contains("finish") ||
                   lowerSpec.contains("mensur") || lowerSpec.contains("scale") ||
                   lowerSpec.contains("radius") || lowerSpec.contains("breite") ||
                   lowerSpec.contains("width") || lowerSpec.contains("übersetzung") ||
                   lowerSpec.contains("ratio") || lowerSpec.contains("tonabnehmer") ||
                   lowerSpec.contains("pickup") || lowerSpec.contains("korpus") ||
                   lowerSpec.contains("hals") || lowerSpec.contains("griffbrett") ||
                   lowerSpec.contains("sattel") || lowerSpec.contains("mechanik")
        }
        points.append(contentsOf: importantSpecs.prefix(8))
        
        // Extract concise key highlights (short phrases only, no long sentences)
        for (sentence, score) in scoredSentences.prefix(30) {
            let lowerSentence = sentence.lowercased()
            // Look for sentences mentioning key features, materials, or special characteristics
            if score > 2.0 && (
                lowerSentence.contains("hand") || lowerSentence.contains("custom") ||
                lowerSentence.contains("premium") || lowerSentence.contains("vintage") ||
                lowerSentence.contains("special edition") || lowerSentence.contains("limited") ||
                lowerSentence.contains("exclusive") || lowerSentence.contains("golden era")
            ) {
                // Extract only the key phrase, not the full sentence
                let cleaned = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Create very concise key point (max 80 chars)
                if cleaned.count <= 80 {
                    if !points.contains(cleaned) {
                        points.append(cleaned)
                    }
                } else {
                    // Extract key phrase from longer sentence
                    let words = cleaned.components(separatedBy: .whitespaces)
                    // Try to find the key phrase (usually at the start or contains keywords)
                    var keyPhrase = ""
                    for (index, word) in words.enumerated() {
                        let lowerWord = word.lowercased()
                        if lowerWord.contains("hand") || lowerWord.contains("custom") ||
                           lowerWord.contains("premium") || lowerWord.contains("vintage") ||
                           lowerWord.contains("special") || lowerWord.contains("limited") {
                            // Take 8-12 words around this keyword
                            let start = max(0, index - 2)
                            let end = min(words.count, index + 10)
                            let phraseWords = Array(words[start..<end])
                            keyPhrase = phraseWords.joined(separator: " ")
                            break
                        }
                    }
                    
                    // Fallback: take first 10 words
                    if keyPhrase.isEmpty && words.count > 5 {
                        keyPhrase = words.prefix(10).joined(separator: " ")
                    }
                    
                    // Only add if it's concise and not already in list
                    if !keyPhrase.isEmpty && keyPhrase.count <= 100 && !points.contains(keyPhrase) {
                        points.append(keyPhrase)
                    }
                }
            }
        }
        
        // Remove duplicates while preserving order
        var uniquePoints: [String] = []
        for point in points {
            if !uniquePoints.contains(point) {
                uniquePoints.append(point)
            }
        }
        
        return Array(uniquePoints.prefix(10))
    }
    
    private func extractArticleKeyPoints(text: String, scoredSentences: [(sentence: String, score: Double)]) -> [String] {
        var points: [String] = []
        
        // Extract headings
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("#") || line.hasPrefix("##") {
                let heading = line.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
                if heading.count > 5 && heading.count < 100 {
                    points.append(heading)
                }
            }
        }
        
        // Extract main points from top sentences
        for (sentence, _) in scoredSentences.prefix(8) {
            let cleaned = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.count > 30 && cleaned.count < 150 {
                points.append(cleaned)
            }
        }
        
        return points
    }
    
    private func extractVideoKeyPoints(text: String, scoredSentences: [(sentence: String, score: Double)]) -> [String] {
        var points: [String] = []
        
        // Extract topics from high-frequency words
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 4 }
        
        var wordCounts: [String: Int] = [:]
        for word in words {
            wordCounts[word, default: 0] += 1
        }
        
        let topWords = wordCounts.sorted { $0.value > $1.value }.prefix(5)
        points.append(contentsOf: topWords.map { $0.key.capitalized })
        
        // Extract key moments
        for (sentence, _) in scoredSentences.prefix(8) {
            let cleaned = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.count > 20 && cleaned.count < 150 {
                points.append(cleaned)
            }
        }
        
        return points
    }
    
    private func extractGeneralKeyPoints(text: String, scoredSentences: [(sentence: String, score: Double)]) -> [String] {
        var points: [String] = []
        
        // Extract headings
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("#") {
                let heading = line.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
                if heading.count > 5 {
                    points.append(heading)
                }
            }
        }
        
        // Extract top sentences
        for (sentence, _) in scoredSentences.prefix(8) {
            let cleaned = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.count > 20 && cleaned.count < 150 {
                points.append(cleaned)
            }
        }
        
        return points
    }
    
    private func buildExtensiveProductSummary(
        text: String,
        scoredSentences: [(sentence: String, score: Double)],
        keyPoints: [String]
    ) -> String {
        // Build a comprehensive, flowing narrative summary ONLY from descriptive content
        // This function specifically excludes specs, prices, and technical details
        return buildNarrativeProductDescription(text: text)
    }
    
    private func buildNarrativeProductDescription(text: String) -> String {
        // Extract descriptive paragraphs from the text
        // Split by double newlines first (paragraphs), then by single newlines
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // Also try splitting by single newlines if we don't have good paragraphs
        var allParagraphs = paragraphs
        if paragraphs.count < 5 {
            let singleLineParagraphs = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count > 50 }
            allParagraphs.append(contentsOf: singleLineParagraphs)
        }
        
        // Filter to get ONLY descriptive paragraphs (exclude specs, prices, UI elements)
        let descriptiveParagraphs = allParagraphs.filter { paragraph in
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowerParagraph = trimmed.lowercased()
            
            // Must be substantial
            guard trimmed.count > 100 else { return false }
            
            // Exclude if it's mostly specs (has many colons with short keys)
            let colonCount = trimmed.components(separatedBy: ":").count - 1
            if colonCount > 2 {
                // Check if keys before colons are short (likely specs)
                let parts = trimmed.components(separatedBy: ":")
                let shortKeys = parts.prefix(3).filter { part in
                    let key = part.trimmingCharacters(in: .whitespaces)
                    return key.count < 30 && key.count > 0
                }
                if shortKeys.count >= 2 {
                    return false // Too many spec-like patterns
                }
            }
            
            // Exclude if it contains mostly prices
            let pricePattern = #"[\$€£¥]\s*[\d.,]+"#
            let priceMatches = trimmed.range(of: pricePattern, options: .regularExpression) != nil
            if priceMatches && trimmed.count < 200 {
                // If it's short and has a price, likely a price line
                return false
            }
            
            // Exclude UI/navigation elements
            let uiKeywords = [
                "anrede", "optional", "bitte geben", "frage stellen", "schreiben sie", "rufen sie",
                "galerie anzeigen", "video anzeigen", "in den warenkorb", "artikel-nr", "serie-nr",
                "sie haben fragen", "basierend auf rezensionen", "finden sie", "previous", "next",
                "zurück", "weiter", "ab 0% finanzieren", "infos zur", "preise inkl", "versandkostenfrei",
                "ab lager verfügbar", "mit * gekennzeichnete", "ich stimme zu"
            ]
            if uiKeywords.contains(where: { lowerParagraph.contains($0) }) {
                return false
            }
            
            // Exclude review sections (often start with "Nach" or contain review language)
            if lowerParagraph.contains("rezension") || lowerParagraph.contains("review") {
                if trimmed.count < 300 {
                    return false // Short review mentions
                }
            }
            
            // Exclude specification sections
            if lowerParagraph.contains("spezifikation") && trimmed.count < 500 {
                return false
            }
            
            // Must contain descriptive language (verbs, adjectives, narrative structure)
            let descriptiveIndicators = [
                "ist", "sind", "wird", "werden", "hat", "haben", "kann", "können",
                "zeigt", "zeigt sich", "bietet", "garantiert", "ermöglicht", "zeichnet sich",
                "gilt als", "bekannt für", "inspiriert", "gefertigt", "handgefertigt",
                "hergestellt", "entworfen", "ausgestattet", "behandelt", "abgerichtet",
                "präsentiert", "kombiniert", "verbindet", "erzeugt", "liefert", "schafft"
            ]
            let hasDescriptiveLanguage = descriptiveIndicators.contains(where: { lowerParagraph.contains($0) })
            
            // Must have narrative structure (multiple sentences, not just a list)
            let sentenceCount = trimmed.components(separatedBy: CharacterSet(charactersIn: ".!?")).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            let hasNarrativeStructure = sentenceCount >= 2 || trimmed.count > 200
            
            return hasDescriptiveLanguage && hasNarrativeStructure
        }
        
        // If we have good descriptive paragraphs, use them
        if descriptiveParagraphs.count >= 3 {
            // Extract sentences from descriptive paragraphs
            var allDescriptiveSentences: [String] = []
            for paragraph in descriptiveParagraphs {
                let sentences = extractSentences(text: paragraph)
                // Filter sentences within paragraphs
                let goodSentences = sentences.filter { sentence in
                    let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.count > 30 && trimmed.count < 500 else { return false }
                    
                    // Exclude spec-like sentences
                    if trimmed.contains(":") && trimmed.count < 150 {
                        let parts = trimmed.components(separatedBy: ":")
                        if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces).count < 30 {
                            return false
                        }
                    }
                    
                    // Exclude price-only
                    if trimmed.range(of: #"^[\$€£¥]\s*[\d.,]+\s*$"#, options: .regularExpression) != nil {
                        return false
                    }
                    
                    return true
                }
                allDescriptiveSentences.append(contentsOf: goodSentences)
            }
            
            // Create narrative paragraphs from descriptive sentences
            return createNarrativeParagraphs(from: allDescriptiveSentences)
        }
        
        // Fallback: extract sentences from full text and filter heavily
        let allSentences = extractSentences(text: text)
        let narrativeSentences = allSentences.filter { sentence in
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowerSentence = trimmed.lowercased()
            
            guard trimmed.count > 50 && trimmed.count < 600 else { return false }
            
            // Exclude specs
            if trimmed.contains(":") && trimmed.count < 150 {
                let parts = trimmed.components(separatedBy: ":")
                if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces).count < 30 {
                    return false
                }
            }
            
            // Exclude prices, UI, measurements
            if trimmed.range(of: #"^[\$€£¥]\s*[\d.,]+\s*$"#, options: .regularExpression) != nil {
                return false
            }
            
            let uiKeywords = ["anrede", "optional", "artikel-nr", "serie-nr", "galerie anzeigen"]
            if uiKeywords.contains(where: { lowerSentence.contains($0) }) {
                return false
            }
            
            // Must have descriptive language
            let descriptiveWords = ["ist", "sind", "wird", "werden", "hat", "haben", "zeigt", "bietet", "gefertigt"]
            return descriptiveWords.contains(where: { lowerSentence.contains($0) }) || trimmed.count > 150
        }
        
        if narrativeSentences.count >= 10 {
            return createNarrativeParagraphs(from: Array(narrativeSentences.prefix(100)))
        }
        
        // Last resort: return empty or minimal summary
        return "Detailed product description is being processed."
    }
    
    private func buildFlowingNarrativeSummary(
        text: String,
        scoredSentences: [(sentence: String, score: Double)],
        targetWords: Int,
        maxSentences: Int
    ) -> String {
        // Extract all sentences from the text (handles both paragraph-separated and concatenated text)
        let allSentences = extractSentences(text: text)
        
        // Filter out noise: specs, prices, UI elements, reviews, navigation
        let filteredSentences = allSentences.filter { sentence in
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowerSentence = trimmed.lowercased()
            
            // Must be substantial
            guard trimmed.count > 30 && trimmed.count < 600 else { return false }
            
            // Filter out technical specs (lines with colons and short keys, measurement units)
            if trimmed.contains(":") && trimmed.count < 150 {
                let parts = trimmed.components(separatedBy: ":")
                if parts.count == 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    // If key is very short, it's likely a spec line
                    if key.count < 30 {
                        return false
                    }
                }
            }
            
            // Filter out measurement-only lines
            if trimmed.range(of: #"^\d+[\.\d]*\s*["']"#, options: .regularExpression) != nil {
                return false
            }
            
            // Filter out price-only lines
            if trimmed.range(of: #"^[\$€£¥]\s*[\d.,]+\s*$"#, options: .regularExpression) != nil {
                return false
            }
            
            // Filter out UI/navigation elements
            let uiKeywords = ["anrede", "optional", "bitte geben", "frage stellen", "schreiben sie", "rufen sie", "galerie anzeigen", "video anzeigen", "in den warenkorb", "artikel-nr", "serie-nr", "sie haben fragen", "basierend auf rezensionen", "finden sie", "previous", "next", "zurück", "weiter"]
            if uiKeywords.contains(where: { lowerSentence.contains($0) }) {
                return false
            }
            
            // Filter out review fragments (very short review snippets)
            if lowerSentence.hasPrefix("nach ") && trimmed.count < 100 {
                return false
            }
            
            // Filter out standalone numbers or very short fragments
            if trimmed.components(separatedBy: .whitespaces).count < 5 {
                return false
            }
            
            // Prioritize descriptive content: look for sentences with descriptive language
            let descriptiveIndicators = ["ist", "sind", "wird", "werden", "hat", "haben", "kann", "können", "zeigt", "zeigt sich", "bietet", "garantiert", "ermöglicht", "zeichnet sich", "gilt als", "bekannt für", "inspiriert", "gefertigt", "handgefertigt", "hergestellt", "entworfen", "ausgestattet", "behandelt", "abgerichtet"]
            let hasDescriptiveLanguage = descriptiveIndicators.contains(where: { lowerSentence.contains($0) })
            
            // Prioritize longer, more descriptive sentences
            let isDescriptive = hasDescriptiveLanguage || trimmed.count > 100
            
            return isDescriptive
        }
        
        // If we have good filtered sentences, prioritize them; otherwise use scored sentences
        let sentencesToUse: [String]
        if filteredSentences.count > 30 {
            // Use filtered sentences, prioritizing longer ones
            sentencesToUse = filteredSentences.sorted { $0.count > $1.count }
        } else {
            // Fall back to scored sentences, but filter out noise
            let scoredFiltered = scoredSentences.map { $0.sentence }.filter { sentence in
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                let lowerSentence = trimmed.lowercased()
                
                guard trimmed.count > 30 && trimmed.count < 600 else { return false }
                
                // Filter out specs, prices, UI elements
                if trimmed.contains(":") && trimmed.count < 150 {
                    let parts = trimmed.components(separatedBy: ":")
                    if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces).count < 30 {
                        return false
                    }
                }
                
                let uiKeywords = ["anrede", "optional", "bitte geben", "artikel-nr", "serie-nr", "galerie anzeigen"]
                if uiKeywords.contains(where: { lowerSentence.contains($0) }) {
                    return false
                }
                
                return true
            }
            sentencesToUse = scoredFiltered
        }
        
        var selectedSentences: [String] = []
        var wordCount = 0
        
        // Select sentences up to target word count, prioritizing longer descriptive ones
        for sentence in sentencesToUse {
            let words = sentence.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            
            // Skip if adding this would exceed target
            if wordCount + words.count > targetWords && selectedSentences.count >= 30 {
                break
            }
            
            // Add sentence if we haven't exceeded limits
            if selectedSentences.count < maxSentences {
                selectedSentences.append(sentence)
                wordCount += words.count
            } else {
                break
            }
        }
        
        if selectedSentences.isEmpty && !sentencesToUse.isEmpty {
            // Fallback: use first substantial sentences
            let firstSentences = sentencesToUse.prefix(min(30, maxSentences))
            selectedSentences = Array(firstSentences)
        }
        
        // Group sentences into coherent paragraphs with proper structure
        return createNarrativeParagraphs(from: selectedSentences)
    }
    
    private func createNarrativeParagraphs(from sentences: [String]) -> String {
        guard !sentences.isEmpty else { return "" }
        
        var paragraphs: [String] = []
        var currentParagraph: [String] = []
        var currentWordCount = 0
        let targetWordsPerParagraph = 150 // Aim for ~150 words per paragraph
        
        for sentence in sentences {
            let words = sentence.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            let sentenceWordCount = words.count
            
            // If adding this sentence would exceed paragraph target, start new paragraph
            if currentWordCount > 0 && currentWordCount + sentenceWordCount > targetWordsPerParagraph && currentParagraph.count >= 3 {
                // Finalize current paragraph
                let paragraph = createFlowingParagraph(from: currentParagraph)
                paragraphs.append(paragraph)
                currentParagraph = []
                currentWordCount = 0
            }
            
            currentParagraph.append(sentence)
            currentWordCount += sentenceWordCount
        }
        
        // Add final paragraph
        if !currentParagraph.isEmpty {
            let paragraph = createFlowingParagraph(from: currentParagraph)
            paragraphs.append(paragraph)
        }
        
        // Join paragraphs with double newlines
        return paragraphs.joined(separator: "\n\n")
    }
    
    private func createFlowingParagraph(from sentences: [String]) -> String {
        guard !sentences.isEmpty else { return "" }
        
        var flowingSentences: [String] = []
        
        for (index, sentence) in sentences.enumerated() {
            var cleaned = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip if too short or looks like noise
            if cleaned.count < 20 {
                continue
            }
            
            // Remove redundant sentence starters if not first sentence
            if index > 0 {
                // Remove common redundant phrases at the start (both English and German)
                let redundantStarters = [
                    "This ", "The ", "It ", "That ", "These ", "Those ",
                    "In addition, ", "Furthermore, ", "Moreover, ",
                    "Additionally, ", "Also, ", "Plus, ", "And ", "But ",
                    "Die ", "Der ", "Das ", "Diese ", "Dieser ", "Und ", "Aber "
                ]
                for starter in redundantStarters {
                    if cleaned.hasPrefix(starter) {
                        cleaned = String(cleaned.dropFirst(starter.count))
                        break
                    }
                }
            }
            
            // Clean up markdown links and formatting
            cleaned = cleaned.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: #"\*\*([^\*]+)\*\*"#, with: "$1", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: #"\*([^\*]+)\*"#, with: "$1", options: .regularExpression)
            
            // Remove standalone bullet points and dashes at start
            if cleaned.hasPrefix("- ") || cleaned.hasPrefix("• ") || cleaned.hasPrefix("* ") {
                cleaned = String(cleaned.dropFirst(2))
            }
            
            // Remove leading/trailing quotes if they wrap the whole sentence
            if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count > 2 {
                cleaned = String(cleaned.dropFirst().dropLast())
            }
            
            // Ensure sentence ends with punctuation
            if !cleaned.isEmpty {
                let lastChar = cleaned.suffix(1)
                if lastChar != "." && lastChar != "!" && lastChar != "?" && lastChar != ":" {
                    cleaned += "."
                }
                
                // Capitalize first letter (handle German umlauts and special chars)
                if !cleaned.isEmpty {
                    let firstChar = String(cleaned.prefix(1))
                    let rest = cleaned.dropFirst()
                    let capitalized = firstChar.uppercased() + rest
                    cleaned = capitalized
                }
                
                flowingSentences.append(cleaned)
            }
        }
        
        if flowingSentences.isEmpty {
            return ""
        }
        
        // Join sentences with proper spacing
        var flowingText = flowingSentences.joined(separator: " ")
        
        // Clean up multiple spaces and fix spacing around punctuation
        flowingText = flowingText.replacingOccurrences(of: "  ", with: " ")
        flowingText = flowingText.replacingOccurrences(of: " .", with: ".")
        flowingText = flowingText.replacingOccurrences(of: " ,", with: ",")
        flowingText = flowingText.replacingOccurrences(of: " :", with: ":")
        flowingText = flowingText.replacingOccurrences(of: " ;", with: ";")
        flowingText = flowingText.replacingOccurrences(of: "„", with: "\"")
        flowingText = flowingText.replacingOccurrences(of: "''", with: "\"")
        
        // Ensure proper capitalization of first letter
        if !flowingText.isEmpty {
            let firstChar = String(flowingText.prefix(1))
            let rest = flowingText.dropFirst()
            let capitalized = firstChar.uppercased() + rest
            flowingText = capitalized
        }
        
        return flowingText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func log(_ value: Double) -> Double {
        return Foundation.log(value + 1.0) // Add 1 to avoid log(0)
    }
}

enum ProcessingError: LocalizedError {
    case emptyContent
    case summarizationFailed
    
    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "Content is empty and cannot be summarized"
        case .summarizationFailed:
            return "Failed to generate summary"
        }
    }
}

