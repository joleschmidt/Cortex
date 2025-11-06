#!/bin/bash
# Simple icon creation script

for size in 16 48 128; do
  # Create a simple blue square
  # Using ImageMagick if available, otherwise create a basic colored square
  if command -v convert &> /dev/null; then
    convert -size ${size}x${size} xc:'#007bff' -gravity center -pointsize $((size/2)) -fill white -font Helvetica-Bold -annotate +0+0 'C' "icon${size}.png"
  else
    # Fallback: create using Python with PIL or just create a note
    echo "Creating icon${size}.png placeholder..."
    # For now, we'll create a simple note file
    echo "Icon ${size}x${size} - Replace with actual icon" > "icon${size}.png.txt"
  fi
done
