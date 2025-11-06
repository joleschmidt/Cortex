# Icons

Place icon files here:
- icon16.png (16x16 pixels)
- icon48.png (48x48 pixels)
- icon128.png (128x128 pixels)

## Quick Creation Options

### Option 1: Online Tool (Easiest)
1. Go to https://www.favicon-generator.org/
2. Upload or create a simple icon with "C" on blue background (#007bff)
3. Download and extract the PNG files
4. Rename to icon16.png, icon48.png, icon128.png

### Option 2: Using Preview (macOS)
1. Create a 128x128 image in any app
2. Save as PNG
3. Use `sips` to resize:
   ```bash
   sips -z 16 16 icon128.png --out icon16.png
   sips -z 48 48 icon128.png --out icon48.png
   ```

### Option 3: Placeholder (for testing)
The extension will work without custom icons - Chrome will use a default icon.
You can add proper icons later.

## Design Suggestion
- Blue background (#007bff)
- White "C" letter
- Simple, clean design

