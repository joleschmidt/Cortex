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
        
        // Extract structured data based on content type
        let extractedData = try await extractStructuredData(
            contentType: contentType,
            url: url,
            title: title,
            text: processedText,
            metadata: metadata
        )
        
        // Generate summaries with content-aware strategies
        let summaries: Summaries
        if isAvailable {
            if #available(macOS 15.0, *) {
                summaries = try await generateWithAppleIntelligence(
                    text: processedText,
                    contentType: contentType
                )
            } else {
                summaries = try generateEnhancedSummaries(
                    text: processedText,
                    contentType: contentType
                )
            }
        } else {
            summaries = try generateEnhancedSummaries(
                text: processedText,
                contentType: contentType
            )
        }
        
        return ProcessingResult(
            summaries: summaries,
            contentType: contentType,
            extractedData: extractedData
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
        
        // Extract metadata if available
        if let metadata = metadata {
            extractedMetadata = metadata
        }
        
        return ExtractedData(
            type: contentType.rawValue,
            structuredData: structuredData.isEmpty ? nil : structuredData,
            keyPoints: keyPoints.isEmpty ? nil : keyPoints,
            actionableInsights: actionableInsights.isEmpty ? nil : actionableInsights,
            metadata: extractedMetadata.isEmpty ? nil : extractedMetadata
        )
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
        
        // Generate detailed summary (flowing narrative + key points)
        let narrativeSummary = buildFlowingSummary(
            scoredSentences: scoredSentences,
            targetWords: 350,
            maxSentences: 12
        )
        
        let detailedSummary: String
        if !keyPoints.isEmpty {
            let bulletPoints = keyPoints.map { "• \($0)" }.joined(separator: "\n")
            detailedSummary = "\(narrativeSummary)\n\n\nKey Highlights:\n\(bulletPoints)"
        } else {
            detailedSummary = narrativeSummary
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
                if lowerSentence.contains("price") || lowerSentence.contains("€") || lowerSentence.contains("$") {
                    score += 2.0
                }
                if lowerSentence.contains("feature") || lowerSentence.contains("specification") {
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
    
    private func extractProductKeyPoints(text: String, scoredSentences: [(sentence: String, score: Double)]) -> [String] {
        var points: [String] = []
        let lowerText = text.lowercased()
        
        // Extract price (including German format with comma)
        let pricePattern = #"[\$€£¥]\s*[\d.,]+\s*[\d]*"#
        if let priceRange = text.range(of: pricePattern, options: .regularExpression) {
            let price = String(text[priceRange]).trimmingCharacters(in: .whitespaces)
            points.append("Price: \(price)")
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
        
        // Add top features
        points.append(contentsOf: features.prefix(5))
        
        // Add key specifications (limit to most important)
        let importantSpecs = specs.filter { spec in
            let lowerSpec = spec.lowercased()
            return lowerSpec.contains("material") || lowerSpec.contains("finish") ||
                   lowerSpec.contains("mensur") || lowerSpec.contains("scale") ||
                   lowerSpec.contains("radius") || lowerSpec.contains("breite") ||
                   lowerSpec.contains("width") || lowerSpec.contains("übersetzung") ||
                   lowerSpec.contains("ratio") || lowerSpec.contains("tonabnehmer") ||
                   lowerSpec.contains("pickup")
        }
        points.append(contentsOf: importantSpecs.prefix(5))
        
        // Extract key highlights from high-scoring sentences
        for (sentence, score) in scoredSentences.prefix(20) {
            let lowerSentence = sentence.lowercased()
            // Look for sentences mentioning key features, materials, or special characteristics
            if score > 2.5 && (
                lowerSentence.contains("hand") || lowerSentence.contains("custom") ||
                lowerSentence.contains("premium") || lowerSentence.contains("vintage") ||
                lowerSentence.contains("material") || lowerSentence.contains("finish") ||
                lowerSentence.contains("feature") || lowerSentence.contains("specification") ||
                lowerSentence.contains("golden era") || lowerSentence.contains("special edition") ||
                lowerSentence.contains("limited") || lowerSentence.contains("exclusive")
            ) {
                // Create concise key point from sentence
                let cleaned = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                // Truncate very long sentences to key phrase
                if cleaned.count > 120 {
                    // Try to extract the key phrase
                    let words = cleaned.components(separatedBy: .whitespaces)
                    if words.count > 15 {
                        let keyPhrase = words.prefix(15).joined(separator: " ") + "..."
                        if !points.contains(keyPhrase) {
                            points.append(keyPhrase)
                        }
                    }
                } else if cleaned.count > 20 && !points.contains(cleaned) {
                    points.append(cleaned)
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

