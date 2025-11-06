# Cortex Setup Guide

## Overview
Cortex is a content capture system that saves web content and YouTube videos to Supabase, then processes them with Apple Intelligence to generate summaries.

## Prerequisites
- Chrome or Chromium-based browser
- macOS 12.0+ (Apple Silicon recommended for Apple Intelligence)
- Supabase account (free tier works)
- YouTube Data API v3 key (optional, for YouTube transcript extraction)

## Part 1: Supabase Setup

1. **Create a Supabase Project**
   - Go to [supabase.com](https://supabase.com) and sign in
   - Create a new project (or use existing)
   - Note your project URL and API keys

2. **Get Your API Keys**
   - Go to Project Settings > API
   - Copy the "Project URL" (e.g., `https://xxxxx.supabase.co`)
   - Copy the "anon" key (for Chrome extension)
   - Copy the "service_role" key (for macOS app - keep this secret!)

3. **Database Schema**
   - The database tables are already created via migrations
   - Tables: `saved_content`, `summaries`, `processing_queue`

## Part 2: Chrome Extension Setup

1. **Load the Extension**
   - Open Chrome and go to `chrome://extensions/`
   - Enable "Developer mode" (toggle in top right)
   - Click "Load unpacked"
   - Select the `chrome-extension` folder

2. **Configure the Extension**
   - Click the Cortex extension icon in your toolbar
   - Click the settings gear icon
   - Enter your Supabase URL and anon key
   - (Optional) Enter your YouTube API key for transcript extraction
   - Click "Save Settings"

3. **Get YouTube API Key (Optional)**
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Create a new project or select existing
   - Enable "YouTube Data API v3"
   - Create credentials (API key)
   - Copy the key and paste it in extension settings

4. **Add Extension Icons**
   - Create or download icons (16x16, 48x48, 128x128 pixels)
   - Place them in `chrome-extension/icons/` as:
     - `icon16.png`
     - `icon48.png`
     - `icon128.png`

## Part 3: macOS App Setup

1. **Open in Xcode**
   - Open `macos-app/Cortex.xcodeproj` in Xcode
   - (Note: You'll need to create the Xcode project - see below)

2. **Create Xcode Project** (if not exists)
   - Open Xcode
   - File > New > Project
   - Choose "macOS" > "App"
   - Product Name: "Cortex"
   - Interface: SwiftUI
   - Language: Swift
   - Save in the `macos-app` folder
   - Add all the Swift files to the project

3. **Configure Settings**
   - Run the app
   - Click the settings gear icon
   - Enter your Supabase URL
   - Enter your Supabase service_role key
   - Set polling interval (default: 30 seconds)
   - (Optional) Enable "Auto-launch on login"

4. **Build and Run**
   - Product > Run (⌘R)
   - The app will start polling for unprocessed content
   - It will process items and generate summaries automatically

## Part 4: Usage

1. **Save Web Content**
   - Navigate to any webpage
   - Click the Cortex extension icon
   - Click "Save Current Page"
   - Content will be saved to Supabase

2. **Save YouTube Videos**
   - Navigate to a YouTube video
   - Click the Cortex extension icon
   - Click "Save Current Page"
   - The extension will fetch the transcript (if API key is configured)

3. **View Summaries**
   - Open the extension popup
   - View saved items and their processing status
   - Once processed, summaries will appear
   - View both short and detailed summaries

4. **Monitor Processing**
   - Open the macOS app
   - View the processing queue
   - See recently completed summaries
   - Check for any errors

## Troubleshooting

### Extension Issues
- **"Supabase not configured"**: Make sure you've entered the URL and anon key in settings
- **"Failed to save"**: Check your Supabase URL and key are correct
- **YouTube transcript fails**: Verify your YouTube API key is valid and has the YouTube Data API v3 enabled

### macOS App Issues
- **"Supabase not configured"**: Enter your service_role key in settings
- **No items processing**: Check that content is being saved from the extension
- **Summaries not generating**: Verify you're on macOS 15.0+ for Apple Intelligence, or the fallback will be used

### Database Issues
- **Permission errors**: Check your RLS policies are set up correctly
- **Connection errors**: Verify your Supabase project is active and not paused

## Security Notes

- **Never share your service_role key** - it has full database access
- The anon key is safe to use in the extension (RLS policies protect your data)
- Keep your YouTube API key private if you use it

## Architecture

```
Chrome Extension → Supabase (saved_content) → macOS App → Apple Intelligence → Supabase (summaries) → Chrome Extension
```

1. Extension saves content to `saved_content` table
2. macOS app polls for `status='pending'` items
3. App generates summaries using Apple Intelligence
4. Summaries saved to `summaries` table
5. Extension displays summaries in popup

## Next Steps

- Customize summary lengths
- Add more content sources
- Implement real-time updates (Supabase Realtime)
- Add export functionality
- Implement search and filtering

