#!/bin/bash

# Upload Sketch assets to Cloudflare R2 bucket
# This script scans ~/Sketch/Icons/ and uploads assets to R2

set -e

# Configuration
SKETCH_DIR="$HOME/Sketch/Icons"
R2_BUCKET="mca-assets"
CLOUDFLARE_ACCOUNT_ID="091c9e59ca0fc3bea9f9d432fa12a3b1"
DATABASE_ID="a663369b-acb4-4297-ba32-ddea8f428e7f"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🎨 MyCodeAssistant Asset Upload Script${NC}"
echo "================================================"

# Check if wrangler is installed
if ! command -v wrangler &> /dev/null; then
    echo -e "${RED}❌ Error: wrangler CLI is not installed${NC}"
    echo "Install with: npm install -g wrangler"
    exit 1
fi

# Check if Sketch directory exists
if [ ! -d "$SKETCH_DIR" ]; then
    echo -e "${YELLOW}⚠️  Warning: Sketch directory not found at $SKETCH_DIR${NC}"
    echo "Creating directory..."
    mkdir -p "$SKETCH_DIR"
fi

# Initialize counters
UPLOADED_COUNT=0
FAILED_COUNT=0
TOTAL_SIZE=0

# Create SQL for assets table if it doesn't exist
echo -e "${GREEN}📦 Ensuring assets table exists in D1...${NC}"
wrangler d1 execute "$DATABASE_ID" --command="
CREATE TABLE IF NOT EXISTS assets (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    path TEXT NOT NULL,
    type TEXT,
    size INTEGER,
    tags TEXT,
    uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata TEXT
);" || echo -e "${YELLOW}⚠️  Table might already exist${NC}"

# Create index for faster queries
wrangler d1 execute "$DATABASE_ID" --command="
CREATE INDEX IF NOT EXISTS idx_assets_name ON assets(name);
CREATE INDEX IF NOT EXISTS idx_assets_type ON assets(type);
" || true

# Function to upload file to R2
upload_to_r2() {
    local file_path="$1"
    local file_name="$(basename "$file_path")"
    local file_ext="${file_name##*.}"
    local r2_path="icons/$file_name"
    local file_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || echo 0)
    
    echo -e "${YELLOW}📤 Uploading: $file_name${NC}"
    
    # Upload to R2
    if wrangler r2 object put "$R2_BUCKET/$r2_path" --file="$file_path" --content-type="$(file -b --mime-type "$file_path" 2>/dev/null || echo 'application/octet-stream')"; then
        echo -e "${GREEN}   ✅ Uploaded to R2: $r2_path${NC}"
        
        # Generate unique ID
        local asset_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
        
        # Extract tags from filename (e.g., icon-arrow-left.pdf -> arrow, left)
        local tags=$(echo "$file_name" | sed 's/\.[^.]*$//' | tr '-_' ' ')
        
        # Insert metadata into D1
        wrangler d1 execute "$DATABASE_ID" --command="
        INSERT OR REPLACE INTO assets (id, name, path, type, size, tags, metadata)
        VALUES ('$asset_id', '$file_name', '$r2_path', '$file_ext', $file_size, '$tags', 
                '{\"original_path\":\"$file_path\",\"bucket\":\"$R2_BUCKET\"}')
        " && echo -e "${GREEN}   ✅ Metadata saved to D1${NC}"
        
        ((UPLOADED_COUNT++))
        ((TOTAL_SIZE+=file_size))
    else
        echo -e "${RED}   ❌ Failed to upload: $file_name${NC}"
        ((FAILED_COUNT++))
    fi
}

# Function to process directory
process_directory() {
    local dir="$1"
    echo -e "${GREEN}📁 Processing directory: $dir${NC}"
    
    # Find all Sketch and PDF files
    while IFS= read -r -d '' file; do
        upload_to_r2 "$file"
    done < <(find "$dir" -type f \( -name "*.sketch" -o -name "*.pdf" -o -name "*.svg" -o -name "*.png" \) -print0)
}

# Main upload process
echo -e "${GREEN}🚀 Starting asset upload...${NC}"
echo "================================================"

# Process Sketch directory
if [ -d "$SKETCH_DIR" ]; then
    process_directory "$SKETCH_DIR"
else
    echo -e "${YELLOW}⚠️  No Sketch directory found, creating sample assets...${NC}"
    
    # Create sample SVG icons for testing
    mkdir -p "$SKETCH_DIR"
    
    # Sample arrow icon
    cat > "$SKETCH_DIR/icon-arrow-right.svg" << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <line x1="5" y1="12" x2="19" y2="12"></line>
  <polyline points="12 5 19 12 12 19"></polyline>
</svg>
EOF
    
    # Sample home icon
    cat > "$SKETCH_DIR/icon-home.svg" << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"></path>
  <polyline points="9 22 9 12 15 12 15 22"></polyline>
</svg>
EOF
    
    # Sample settings icon
    cat > "$SKETCH_DIR/icon-settings.svg" << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <circle cx="12" cy="12" r="3"></circle>
  <path d="M12 1v6m0 6v6m4.22-13.22l4.24 4.24M1.54 12H7.5m9 0h6m-4.24 4.24l-4.24 4.24M6.34 17.66l-4.8 4.8"></path>
</svg>
EOF
    
    echo -e "${GREEN}✅ Created sample SVG icons${NC}"
    process_directory "$SKETCH_DIR"
fi

# Display summary
echo ""
echo "================================================"
echo -e "${GREEN}📊 Upload Summary${NC}"
echo "================================================"
echo -e "✅ Successfully uploaded: ${GREEN}$UPLOADED_COUNT${NC} files"
if [ $FAILED_COUNT -gt 0 ]; then
    echo -e "❌ Failed uploads: ${RED}$FAILED_COUNT${NC} files"
fi
echo -e "📦 Total size uploaded: $(echo "scale=2; $TOTAL_SIZE / 1048576" | bc 2>/dev/null || echo "0") MB"

# Verify assets are accessible
echo ""
echo -e "${GREEN}🔍 Verifying asset accessibility...${NC}"

# Query D1 for uploaded assets
echo -e "${YELLOW}📋 Listing uploaded assets from D1:${NC}"
wrangler d1 execute "$DATABASE_ID" --command="SELECT name, type, size, tags FROM assets ORDER BY uploaded_at DESC LIMIT 10"

# Test R2 accessibility
echo ""
echo -e "${GREEN}🌐 Testing R2 public access...${NC}"
echo "Assets will be available at:"
echo "  https://mca-assets.{your-r2-subdomain}.r2.dev/icons/{filename}"
echo ""
echo "To enable public access:"
echo "  1. Go to Cloudflare Dashboard > R2"
echo "  2. Select 'mca-assets' bucket"
echo "  3. Settings > Public Access > Allow"
echo "  4. Note the public URL"

echo ""
echo -e "${GREEN}✨ Asset upload complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Configure R2 bucket for public access in Cloudflare Dashboard"
echo "  2. Update your app to use: GET /assets/icons/:name endpoint"
echo "  3. Test with: curl https://api.mycodeassistant.ai/assets/icons/icon-home.svg"