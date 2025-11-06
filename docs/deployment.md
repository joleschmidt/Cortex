# Deployment Guide

## Chrome Extension Deployment

### Option 1: Sideloading (Development/Personal Use)

1. **Package the Extension**
   ```bash
   cd chrome-extension
   zip -r cortex-extension.zip . -x "*.git*" "*.DS_Store" "icons/README.md"
   ```

2. **Load in Chrome**
   - Go to `chrome://extensions/`
   - Enable "Developer mode"
   - Click "Load unpacked"
   - Select the `chrome-extension` folder

### Option 2: Chrome Web Store (Public Distribution)

1. **Prepare for Submission**
   - Create proper icons (16x16, 48x48, 128x128)
   - Add a detailed description
   - Create screenshots
   - Prepare privacy policy

2. **Package**
   - Use the same zip command as above
   - Or use Chrome's "Pack extension" feature

3. **Submit**
   - Go to [Chrome Web Store Developer Dashboard](https://chrome.google.com/webstore/devconsole)
   - Pay one-time $5 registration fee
   - Upload zip file
   - Fill out store listing
   - Submit for review

## macOS App Deployment

### Option 1: Direct Distribution

1. **Build in Xcode**
   - Open project in Xcode
   - Product > Archive
   - Wait for archive to complete

2. **Export**
   - Click "Distribute App"
   - Choose "Developer ID" (for distribution outside App Store)
   - Follow export wizard
   - Save to desired location

3. **Create DMG** (optional)
   ```bash
   # Install create-dmg if needed: brew install create-dmg
   create-dmg \
     --volname "Cortex" \
     --window-pos 200 120 \
     --window-size 600 400 \
     --icon-size 100 \
     --icon "Cortex.app" 150 190 \
     --hide-extension "Cortex.app" \
     --app-drop-link 450 190 \
     "Cortex.dmg" \
     "Cortex.app"
   ```

### Option 2: App Store Distribution

1. **Prepare for App Store**
   - Add App Store icons
   - Create app description
   - Prepare screenshots
   - Set up App Store Connect listing

2. **Code Signing**
   - Ensure you have an Apple Developer account ($99/year)
   - Configure code signing in Xcode
   - Archive the app

3. **Upload**
   - In Xcode, click "Distribute App"
   - Choose "App Store Connect"
   - Follow upload process
   - Submit for review in App Store Connect

### Code Signing Requirements

For distribution outside the App Store, you need:
- Apple Developer account
- Developer ID certificate
- Notarization (required for macOS 10.15+)

Steps:
1. Get Developer ID certificate from Apple Developer portal
2. Configure in Xcode: Signing & Capabilities
3. Archive and export with "Developer ID"
4. Notarize using `xcrun notarytool` or Xcode's built-in notarization

## Installation Instructions for Users

### Chrome Extension

1. Download the extension zip file
2. Extract it
3. Open Chrome and go to `chrome://extensions/`
4. Enable "Developer mode"
5. Click "Load unpacked"
6. Select the extracted folder
7. Configure settings (Supabase URL and keys)

### macOS App

1. Download the DMG or zip file
2. Open the DMG or extract the zip
3. Drag "Cortex.app" to Applications folder
4. Open from Applications (may need to allow in System Preferences > Security)
5. Configure settings on first launch

## System Requirements

### Chrome Extension
- Chrome 88+ or Chromium-based browser
- Internet connection for Supabase

### macOS App
- macOS 12.0+ (Monterey or later)
- Apple Silicon recommended for Apple Intelligence features
- Internet connection for Supabase

## Distribution Checklist

- [ ] Extension icons created (16x16, 48x48, 128x128)
- [ ] App icons created (all required sizes)
- [ ] Code signed (for macOS app)
- [ ] Notarized (for macOS app distribution)
- [ ] Tested on clean systems
- [ ] Documentation updated
- [ ] Version numbers updated
- [ ] Changelog created
- [ ] Privacy policy (if distributing publicly)

## Version Management

Update version numbers in:
- `chrome-extension/manifest.json` (version field)
- `macos-app/Info.plist` (CFBundleShortVersionString, CFBundleVersion)
- Update changelog in docs

