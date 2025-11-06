#!/bin/bash

# Cortex Configuration Helper
# This script helps configure the Chrome extension and macOS app

echo "🔧 Cortex Configuration Helper"
echo "=============================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

SUPABASE_URL="https://uymrpsfrzjkhsofnouqn.supabase.co"

echo "Project URL: $SUPABASE_URL"
echo ""

# Get Anon Key
echo -e "${YELLOW}Step 1: Chrome Extension (Anon Key)${NC}"
read -p "Enter your Supabase anon/public key: " ANON_KEY

if [ -z "$ANON_KEY" ]; then
    echo -e "${RED}Error: Anon key is required${NC}"
    exit 1
fi

# Get Service Role Key
echo ""
echo -e "${YELLOW}Step 2: macOS App (Service Role Key)${NC}"
read -p "Enter your Supabase service_role key: " SERVICE_KEY

if [ -z "$SERVICE_KEY" ]; then
    echo -e "${RED}Error: Service role key is required${NC}"
    exit 1
fi

# Optional: YouTube API Key
echo ""
read -p "Enter YouTube API Key (optional, press Enter to skip): " YOUTUBE_KEY

echo ""
echo -e "${GREEN}Configuring...${NC}"

# Create config file for reference
cat > .cortex_config << EOF
# Cortex Configuration
# Generated: $(date)

SUPABASE_URL=$SUPABASE_URL
ANON_KEY=$ANON_KEY
SERVICE_KEY=$SERVICE_KEY
YOUTUBE_KEY=$YOUTUBE_KEY
EOF

echo "✅ Configuration saved to .cortex_config"
echo ""

# Instructions
echo -e "${GREEN}Next Steps:${NC}"
echo ""
echo "1. Chrome Extension:"
echo "   - Click Cortex icon → ⚙️ settings"
echo "   - Paste URL: $SUPABASE_URL"
echo "   - Paste Anon Key: [your anon key]"
if [ ! -z "$YOUTUBE_KEY" ]; then
    echo "   - Paste YouTube Key: [your youtube key]"
fi
echo "   - Click Save"
echo ""
echo "2. macOS App:"
echo "   - Open app → ⚙️ settings"
echo "   - Paste URL: $SUPABASE_URL"
echo "   - Paste Service Role Key: [your service key]"
echo "   - Click Save"
echo ""
echo -e "${GREEN}Configuration complete!${NC}"

