# Cortex

A content capture system with AI-powered summarization using Chrome extension + macOS app.

## Features

- **Web Content Capture**: Save any webpage with one click
- **YouTube Video Support**: Automatically extract transcripts from YouTube videos
- **AI Summarization**: Generate short and detailed summaries using Apple Intelligence
- **Markdown Preservation**: Maintains document structure (headings, lists, links)
- **Real-time Processing**: Automatic background processing of saved content
- **Dual Summaries**: Get both concise and detailed summaries

## Architecture

```
Chrome Extension → Supabase → macOS App → Apple Intelligence → Supabase → Chrome Extension
```

1. **Chrome Extension**: Captures web content and YouTube videos, saves to Supabase
2. **Supabase**: Stores raw content and generated summaries
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

