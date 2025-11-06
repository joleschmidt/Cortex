# Cortex Setup Guide - Step by Step

## Prerequisites

- Chrome or Chromium-based browser
- macOS 12.0+ (Apple Silicon recommended)
- Xcode (for macOS app)
- Supabase account (free tier works)
- YouTube Data API v3 key (optional, for YouTube transcripts)

---

## Part 1: Supabase Configuration (5 minutes)

### Step 1.1: Get Your API Keys

1. Go to your Supabase project dashboard:
   ```
   https://supabase.com/dashboard/project/uymrpsfrzjkhsofnouqn/settings/api
   ```

2. Copy these values (you'll need them later):
   - **Project URL**: `https://uymrpsfrzjkhsofnouqn.supabase.co`
   - **anon/public key**: (for Chrome extension)
   - **service_role key**: (for macOS app - ⚠️ keep this secret!)

3. The database is already set up with:
   - `saved_content` table
   - `summaries` table
   - `processing_queue` table
   - RLS policies configured

### Step 1.2: Verify Database (Optional)

1. Go to: https://supabase.com/dashboard/project/uymrpsfrzjkhsofnouqn/editor
2. You should see the three tables listed
3. If tables are missing, they'll be created automatically on first use

---

## Part 2: Chrome Extension Setup (5 minutes)

### Step 2.1: Load the Extension

1. Open Chrome and navigate to:
   ```
   chrome://extensions/
   ```

2. Enable Developer Mode:
   - Toggle the switch in the top-right corner

3. Load the extension:
   - Click "Load unpacked"
   - Navigate to: `/Users/janoleschmidt/Development/Chrome Extension/Cortex/chrome-extension`
   - Click "Select"

4. You should see "Cortex Content Capture" in your extensions list

### Step 2.2: Configure the Extension

1. Click the Cortex icon in your Chrome toolbar (or find it in the extensions menu)

2. Click the ⚙️ settings icon (top right)

3. Enter your Supabase credentials:
   - **Supabase URL**: `https://uymrpsfrzjkhsofnouqn.supabase.co`
   - **Supabase Anon Key**: (paste your anon key from Step 1.1)
   - **YouTube API Key**: (optional - see Step 2.3)

4. Click "Save Settings"

5. You should see a success message

### Step 2.3: YouTube API Key (Optional)

If you want to extract YouTube transcripts:

1. Go to [Google Cloud Console](https://console.cloud.google.com/)

2. Create a new project or select existing

3. Enable YouTube Data API v3:
   - Go to "APIs & Services" > "Library"
   - Search for "YouTube Data API v3"
   - Click "Enable"

4. Create credentials:
   - Go to "APIs & Services" > "Credentials"
   - Click "Create Credentials" > "API Key"
   - Copy the API key

5. Add to extension:
   - Open Cortex extension settings
   - Paste the YouTube API key
   - Save

### Step 2.4: Test the Extension

1. Navigate to any webpage (e.g., https://example.com)

2. Click the Cortex icon

3. Click "Save Current Page"

4. You should see:
   - A success notification
   - The page title in the saved items list

5. Verify in Supabase:
   - Go to: https://supabase.com/dashboard/project/uymrpsfrzjkhsofnouqn/editor
   - Click on `saved_content` table
   - You should see your saved page

---

## Part 3: macOS App Setup (10 minutes)

### Step 3.1: Open in Xcode

1. Open Xcode

2. Open the project:
   ```bash
   open "/Users/janoleschmidt/Development/Chrome Extension/Cortex/macos-app/Cortex.xcodeproj"
   ```
   
   Or in Xcode: File > Open > Navigate to `macos-app/Cortex.xcodeproj`

### Step 3.2: Verify Project Structure

1. In Xcode, check that you see these files in the Project Navigator:
   - `CortexApp.swift`
   - `ContentView.swift`
   - `SettingsView.swift`
   - `Models.swift`
   - `SupabaseManager.swift`
   - `AppleIntelligenceProcessor.swift`

2. If files are missing:
   - Right-click the project
   - "Add Files to Cortex..."
   - Select all `.swift` files from the `macos-app` folder
   - Make sure "Copy items if needed" is checked
   - Click "Add"

### Step 3.3: Build the Project

1. Select the scheme: "Cortex" (top toolbar)

2. Select destination: "My Mac" (or your Mac name)

3. Build the project:
   - Press `⌘B` (Cmd+B)
   - Or: Product > Build

4. Fix any errors:
   - If you see "No such module" errors, make sure all Swift files are added
   - If you see path errors, check file locations

### Step 3.4: Run the App

1. Run the app:
   - Press `⌘R` (Cmd+R)
   - Or: Product > Run

2. The app window should open

3. You should see "Supabase Not Configured" message

### Step 3.5: Configure the App

1. Click the ⚙️ settings icon (top right)

2. Enter your Supabase credentials:
   - **Supabase URL**: `https://uymrpsfrzjkhsofnouqn.supabase.co`
   - **Service Role Key**: (paste from Step 1.1 - ⚠️ this is secret!)
   - **Polling Interval**: 30 seconds (default is fine)
   - **Auto-launch on login**: (optional, enable if you want)

3. Click "Save Settings"

4. The app should:
   - Close the settings window
   - Start polling for unprocessed content
   - Show the main interface

### Step 3.6: Verify Processing

1. In the app, click the "Queue" tab

2. You should see any pending items from the extension

3. Wait a few seconds - items should start processing

4. Click the "Summaries" tab to see completed summaries

---

## Part 4: End-to-End Test (5 minutes)

### Step 4.1: Save Content from Extension

1. Go to any interesting webpage (e.g., a news article)

2. Click Cortex extension icon

3. Click "Save Current Page"

4. Verify:
   - Success notification appears
   - Item shows in extension popup with "pending" status

### Step 4.2: Watch Processing

1. Open the macOS app

2. Go to "Queue" tab

3. You should see your saved page appear

4. Status will change: `pending` → `processing` → `completed`

5. This usually takes 10-30 seconds

### Step 4.3: View Summaries

1. In macOS app, go to "Summaries" tab

2. You should see:
   - Short summary (~150 words)
   - Detailed summary (~400 words)

3. In Chrome extension:
   - Click the Cortex icon
   - Your saved item should now show both summaries

---

## Troubleshooting

### Extension Issues

**"Supabase not configured" error:**
- Make sure you saved settings with correct URL and anon key
- Check that keys don't have extra spaces

**"Failed to save" error:**
- Verify Supabase URL is correct
- Check anon key is valid
- Open Chrome DevTools (F12) > Console tab to see detailed errors

**Extension icon not showing:**
- Go to `chrome://extensions/`
- Find Cortex extension
- Click the puzzle piece icon > Pin to toolbar

**Content not extracting:**
- Make sure you're on a regular webpage (not chrome:// pages)
- Some pages block content scripts - try a different site

### macOS App Issues

**"Supabase not configured" error:**
- Make sure you entered the service_role key (not anon key)
- Verify URL is correct

**App won't build:**
- Check Xcode version (needs Xcode 14+)
- Make sure all Swift files are in the project
- Clean build folder: Product > Clean Build Folder (⇧⌘K)

**No items processing:**
- Check that content is being saved (verify in Supabase dashboard)
- Check app logs: Console.app > search for "Cortex"
- Verify service_role key has correct permissions

**Summaries not generating:**
- Check macOS version (needs 12.0+, 15.0+ for Apple Intelligence)
- Fallback summarization should still work
- Check app logs for errors

### Database Issues

**Permission errors:**
- Verify RLS policies are set up (they should be automatic)
- Check that you're using the correct keys:
  - Extension uses `anon` key
  - macOS app uses `service_role` key

**Tables missing:**
- Go to Supabase dashboard > SQL Editor
- Run the migrations manually if needed (see setup-guide.md)

---

## Quick Reference

### Supabase Keys
- **Project URL**: `https://uymrpsfrzjkhsofnouqn.supabase.co`
- **Get keys**: https://supabase.com/dashboard/project/uymrpsfrzjkhsofnouqn/settings/api

### Extension Settings
- **Location**: Click Cortex icon > ⚙️
- **Required**: Supabase URL, Anon Key
- **Optional**: YouTube API Key

### macOS App Settings
- **Location**: Click ⚙️ in app window
- **Required**: Supabase URL, Service Role Key
- **Optional**: Polling Interval, Auto-launch

### File Locations
- **Extension**: `/Users/janoleschmidt/Development/Chrome Extension/Cortex/chrome-extension`
- **macOS App**: `/Users/janoleschmidt/Development/Chrome Extension/Cortex/macos-app`

---

## Next Steps

Once everything is working:

1. **Customize summaries**: Adjust length in `AppleIntelligenceProcessor.swift`
2. **Change polling interval**: Adjust in macOS app settings
3. **Add more content sources**: Extend the content script
4. **Export summaries**: Add export functionality
5. **Add search**: Implement search in extension popup

---

## Support

If you encounter issues:

1. Check the error messages in:
   - Chrome: DevTools Console (F12)
   - macOS: Console.app (search for "Cortex")

2. Verify Supabase connection:
   - Check dashboard for saved content
   - Verify API keys are correct

3. Review logs:
   - Extension: `chrome://extensions/` > Cortex > "service worker" > "Inspect"
   - macOS: Console.app

4. Check documentation:
   - `TEST_CHECKLIST.md` - Testing procedures
   - `docs/setup-guide.md` - Detailed setup
   - `SUPABASE_CONFIG.md` - Database details

---

## Success Checklist

- [ ] Supabase project accessible
- [ ] Extension loaded in Chrome
- [ ] Extension configured with Supabase keys
- [ ] Test save works (content appears in Supabase)
- [ ] macOS app opens in Xcode
- [ ] macOS app builds successfully
- [ ] macOS app configured with service_role key
- [ ] Processing queue shows items
- [ ] Summaries are generated
- [ ] Summaries appear in extension popup

Once all checked, you're ready to use Cortex! 🎉

