#!/bin/bash
# Create simple placeholder icons using sips

# Create a 128x128 blue square first
python3 << 'PYEOF'
from PIL import Image
img = Image.new('RGB', (128, 128), color='#007bff')
img.save('icon128.png')
print("Created icon128.png")
PYEOF

# Resize to other sizes using sips
sips -z 16 16 icon128.png --out icon16.png 2>/dev/null
sips -z 48 48 icon128.png --out icon48.png 2>/dev/null

echo "Icons created"
