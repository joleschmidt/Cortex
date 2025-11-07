# Cortex

A content capture system with AI-powered summarization using Chrome extension + macOS app. Cortex is designed with an AI-first approach to data storage, enabling users to build their own "Second Brain" that AI systems can work with to develop a deeper understanding of the user's interests, preferences, and knowledge base.

## Philosophy

Cortex stores all data in an AI-optimized format, prioritizing structured information that AI systems can easily parse and understand. The goal is to help users create a comprehensive "Second Brain" - a personal knowledge base that AI can leverage to provide more contextual, personalized, and insightful assistance. By capturing and processing content with rich metadata, structured data extraction, and intelligent categorization, Cortex enables AI to develop a better understanding of the user over time, making interactions more meaningful and relevant.

## Features

- **Web Content Capture**: Save any webpage with one click
- **YouTube Video Support**: Automatically extract transcripts from YouTube videos
- **AI Summarization**: Generate short and detailed summaries using Apple Intelligence
- **Markdown Preservation**: Maintains document structure (headings, lists, links)
- **Real-time Processing**: Automatic background processing of saved content
- **Dual Summaries**: Get both concise and detailed summaries
- **AI-First Data Storage**: All data stored in structured, AI-readable formats with rich metadata
- **Content Type Detection**: Automatic categorization (product, article, video, listing, general)
- **Structured Data Extraction**: Extracts prices, features, specifications, key points, and actionable insights
- **Personal Knowledge Base**: Build your Second Brain with searchable, categorized content

## Architecture

```
Chrome Extension → Supabase → macOS App → Apple Intelligence → Supabase → Chrome Extension
```

1. **Chrome Extension**: Captures web content and YouTube videos, saves to Supabase
2. **Supabase**: Stores raw content and generated summaries in AI-optimized formats
3. **macOS App**: Polls for unprocessed content, generates summaries using Apple Intelligence
4. **Apple Intelligence**: Provides native summarization capabilities

## Quick Start

1. **Set up Supabase** (see [setup-guide.md](docs/setup-guide.md))
2. **Load Chrome Extension** (see [setup-guide.md](docs/setup-guide.md))
3. **Run macOS App** (see [setup-guide.md](docs/setup-guide.md))
4. **Start saving content!**

## Project Structure

```
Cortex/
├── chrome-extension/       # Chrome extension (Manifest V3)
│   ├── manifest.json
│   ├── popup/             # Extension popup UI
│   ├── content/           # Content scripts
│   ├── background/        # Service worker
│   └── lib/               # Supabase client
├── macos-app/             # macOS SwiftUI app
│   ├── Models.swift
│   ├── SupabaseManager.swift
│   ├── AppleIntelligenceProcessor.swift
│   ├── ContentView.swift
│   └── SettingsView.swift
└── docs/                  # Documentation
```

## Requirements

- Chrome 88+ or Chromium-based browser
- macOS 12.0+ (Apple Silicon recommended)
- Supabase account (free tier works)
- YouTube Data API v3 key (optional, for YouTube transcripts)

## Documentation

- [Setup Guide](docs/setup-guide.md) - Complete setup instructions
- [Deployment Guide](docs/deployment.md) - How to package and distribute

## Development

### Chrome Extension
- Manifest V3
- Vanilla JavaScript
- Supabase REST API

### macOS App
- SwiftUI
- NaturalLanguage framework
- URLSession for API calls

## License

[Your License Here]

## Contributing

[Contributing guidelines]

