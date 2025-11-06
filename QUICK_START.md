# Quick Start Guide

## 🚀 Get Started in 3 Steps

### 1. Chrome Extension Setup (2 minutes)

1. **Load the extension:**
   - Open Chrome → `chrome://extensions/`
   - Enable "Developer mode" (top right toggle)
   - Click "Load unpacked"
   - Select the `chrome-extension` folder

2. **Configure:**
   - Click the Cortex icon in your toolbar
   - Click the ⚙️ settings icon
   - Enter:
     - **Supabase URL:** `https://uymrpsfrzjkhsofnouqn.supabase.co`
     - **Supabase Anon Key:** (from SUPABASE_CONFIG.md)
     - **YouTube API Key:** (optional, for YouTube transcripts)
   - Click "Save Settings"

3. **Test it:**
   - Go to any webpage
   - Click Cortex icon → "Save Current Page"
   - You should see a success notification!

### 2. macOS App Setup (5 minutes)

1. **Open in Xcode:**
   ```bash
   open macos-app/Cortex.xcodeproj
   ```
   (Or create new project if needed - see setup-guide.md)

2. **Configure:**
   - Run the app (⌘R)
   - Click ⚙️ settings
   - Enter:
     - **Supabase URL:** `https://uymrpsfrzjkhsofnouqn.supabase.co`
     - **Service Role Key:** (get from Supabase dashboard - Settings > API)
     - **Polling Interval:** 30 seconds (default)
   - Click "Save Settings"

3. **Watch it work:**
   - The app will automatically start processing saved content
   - View the "Queue" tab to see pending items
   - View the "Summaries" tab to see completed summaries

### 3. Get Service Role Key

1. Go to: https://supabase.com/dashboard/project/uymrpsfrzjkhsofnouqn/settings/api
2. Copy the "service_role" key (⚠️ keep it secret!)
3. Paste it in macOS app settings

## ✅ You're Ready!

- **Save content** from Chrome extension
- **View summaries** in extension popup (after processing)
- **Monitor processing** in macOS app

## 🐛 Troubleshooting

**Extension says "Supabase not configured":**
- Make sure you saved settings with the correct URL and anon key

**macOS app not processing:**
- Check that service_role key is correct
- Verify content is being saved (check Supabase dashboard)
- Check app logs in Console.app

**No summaries appearing:**
- Wait a few seconds for processing
- Check macOS app for errors
- Verify Apple Intelligence is available (macOS 15.0+)

## 📚 Full Documentation

- [Setup Guide](docs/setup-guide.md) - Detailed instructions
- [Deployment Guide](docs/deployment.md) - Packaging and distribution
- [Supabase Config](SUPABASE_CONFIG.md) - Project details
