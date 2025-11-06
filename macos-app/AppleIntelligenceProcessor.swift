import Foundation
import NaturalLanguage

struct Summaries {
    let short: String
    let detailed: String
}

class AppleIntelligenceProcessor {
    private let isAvailable: Bool
    
    init() {
        // Check if Apple Intelligence is available (macOS 15.0+ with compatible hardware)
        if #available(macOS 15.0, *) {
            // Check for Apple Intelligence availability
            // For now, we'll assume it's available if we're on macOS 15+
            // In production, you'd check for actual Apple Intelligence availability
            self.isAvailable = true
        } else {
            self.isAvailable = false
        }
    }
    
    func generateSummaries(content: String, markdown: String) async throws -> Summaries {
        // Validate input
        let text = markdown.isEmpty ? content : markdown
        
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProcessingError.emptyContent
        }
        
        // Handle very long content
        let maxLength = 50000
        let processedText = text.count > maxLength ? String(text.prefix(maxLength)) : text
        
        if isAvailable {
            if #available(macOS 15.0, *) {
                return try await generateWithAppleIntelligence(text: processedText)
            } else {
                return try generateFallbackSummaries(text: processedText)
            }
        } else {
            return try generateFallbackSummaries(text: processedText)
        }
    }
    
    @available(macOS 15.0, *)
    private func generateWithAppleIntelligence(text: String) async throws -> Summaries {
        // Use NaturalLanguage framework for summarization
        // Note: Actual Apple Intelligence summarization APIs may vary
        // This is a placeholder implementation
        
        let shortSummary = try await summarizeText(text: text, targetLength: 150)
        let detailedSummary = try await summarizeText(text: text, targetLength: 400)
        
        return Summaries(short: shortSummary, detailed: detailedSummary)
    }
    
    @available(macOS 15.0, *)
    private func summarizeText(text: String, targetLength: Int) async throws -> String {
        // Use NaturalLanguage framework
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(String(text[range]))
            return true
        }
        
        // Simple extractive summarization: take first N sentences that fit target length
        var summary = ""
        for sentence in sentences {
            if summary.count + sentence.count > targetLength {
                break
            }
            summary += sentence + " "
        }
        
        // If we have very little content, use the whole text
        if summary.isEmpty && !text.isEmpty {
            // Truncate to target length
            let truncated = String(text.prefix(targetLength))
            return truncated + (text.count > targetLength ? "..." : "")
        }
        
        return summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func generateFallbackSummaries(text: String) throws -> Summaries {
        // Fallback: extractive summarization using sentence extraction
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(String(text[range]))
            return true
        }
        
        // Short summary: first 3-5 sentences or ~150 words
        let shortSentences = min(5, sentences.count)
        let shortSummary = sentences.prefix(shortSentences).joined(separator: " ")
        let shortTruncated = truncateToWords(shortSummary, targetWords: 150)
        
        // Detailed summary: first 10-15 sentences or ~400 words
        let detailedSentences = min(15, sentences.count)
        let detailedSummary = sentences.prefix(detailedSentences).joined(separator: " ")
        let detailedTruncated = truncateToWords(detailedSummary, targetWords: 400)
        
        return Summaries(short: shortTruncated, detailed: detailedTruncated)
    }
    
    private func truncateToWords(_ text: String, targetWords: Int) -> String {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        if words.count <= targetWords {
            return text
        }
        
        let truncated = words.prefix(targetWords).joined(separator: " ")
        return truncated + "..."
    }
    
    // Handle very long content by chunking
    private func chunkText(_ text: String, maxLength: Int = 10000) -> [String] {
        if text.count <= maxLength {
            return [text]
        }
        
        var chunks: [String] = []
        var currentChunk = ""
        
        let paragraphs = text.components(separatedBy: "\n\n")
        
        for paragraph in paragraphs {
            if (currentChunk + paragraph).count > maxLength {
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk)
                    currentChunk = paragraph
                } else {
                    // Paragraph itself is too long, split by sentences
                    let sentences = paragraph.components(separatedBy: ". ")
                    for sentence in sentences {
                        if (currentChunk + sentence).count > maxLength {
                            if !currentChunk.isEmpty {
                                chunks.append(currentChunk)
                            }
                            currentChunk = sentence
                        } else {
                            currentChunk += (currentChunk.isEmpty ? "" : ". ") + sentence
                        }
                    }
                }
            } else {
                currentChunk += (currentChunk.isEmpty ? "" : "\n\n") + paragraph
            }
        }
        
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        return chunks
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

