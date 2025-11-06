# Testing Checklist

## Pre-Test Issues Found & Fixed

### ✅ Fixed Issues:
1. **Popup SupabaseClient usage** - Creates new instance (OK, but could use singleton)
2. **Background script** - Uses direct fetch (OK, avoids import issues in service workers)
3. **Swift compilation** - Need to verify Xcode project structure

### ⚠️ Potential Issues to Test:

1. **Chrome Extension:**
   - [ ] Manifest V3 syntax correct
   - [ ] Content script loads on pages
   - [ ] Background service worker starts
   - [ ] Popup can access chrome.storage
   - [ ] Supabase API calls work (CORS)
   - [ ] YouTube API integration (if key provided)

2. **macOS App:**
   - [ ] Xcode project opens
   - [ ] Swift files compile
   - [ ] SupabaseManager connects
   - [ ] Polling works
   - [ ] Apple Intelligence processor works (or fallback)

3. **Integration:**
   - [ ] Extension saves to Supabase
   - [ ] macOS app fetches unprocessed items
   - [ ] Summaries generated
   - [ ] Summaries saved back to Supabase
   - [ ] Extension displays summaries

## Quick Test Commands

### Test Chrome Extension:
```bash
# Check manifest syntax
cd chrome-extension
cat manifest.json | python3 -m json.tool

# Check for syntax errors in JS files
node --check popup/popup.js
node --check background/background.js
node --check content/content.js
```

### Test macOS App:
```bash
# Check Swift syntax (if swiftc available)
cd macos-app
swiftc -typecheck *.swift 2>&1 | head -20
```

## Manual Testing Steps

1. **Load Extension:**
   - chrome://extensions/
   - Developer mode ON
   - Load unpacked → select chrome-extension folder
   - Check for errors in console

2. **Configure Extension:**
   - Click extension icon
   - Open settings
   - Enter Supabase URL and anon key
   - Save

3. **Test Save:**
   - Go to any webpage
   - Click "Save Current Page"
   - Check for notification
   - Verify in Supabase dashboard

4. **Test macOS App:**
   - Open in Xcode
   - Build (⌘B)
   - Run (⌘R)
   - Configure settings
   - Watch for processing

