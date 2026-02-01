#!/bin/zsh
# Setup merihari

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${HOME}/.config/merihari"
CONFIG_FILE="$CONFIG_DIR/config"
HAMMERSPOON_DIR="${HOME}/.hammerspoon"

echo "=== Merihari setup ==="

# Check if Hammerspoon is installed
if [[ ! -d "/Applications/Hammerspoon.app" ]]; then
  echo "ERROR: Hammerspoon is not installed."
  echo "Please install it from: https://www.hammerspoon.org/"
  echo "Or use: brew install --cask hammerspoon"
  exit 1
fi

# Create config directory
mkdir -p "$CONFIG_DIR"

# Prompt for time window
read "start_input?Start time (e.g. 21:00 or 2100): "
read "end_input?End time (e.g. 06:00 or 0600): "

# Normalize to HHMM
START=$(echo "$start_input" | tr -d ':')
END=$(echo "$end_input" | tr -d ':')

# Validate input
if [[ ! "$START" =~ ^[0-9]{4}$ ]] || [[ ! "$END" =~ ^[0-9]{4}$ ]]; then
  echo "ERROR: Time must be in format HHMM or HH:MM (e.g., 2100 or 21:00)"
  exit 1
fi

if [[ "$START" -ge 2400 ]] || [[ "$END" -ge 2400 ]]; then
  echo "ERROR: Time must be between 0000 and 2359"
  exit 1
fi

# Save config
cat > "$CONFIG_FILE" <<EOF
START=$START
END=$END
EOF

# Copy Hammerspoon config
mkdir -p "$HAMMERSPOON_DIR"
cp "$REPO_DIR/init.lua" "$HAMMERSPOON_DIR/merihari.lua"

# Add to Hammerspoon init.lua
if [[ ! -f "$HAMMERSPOON_DIR/init.lua" ]]; then
  echo 'require("merihari")' > "$HAMMERSPOON_DIR/init.lua"
else
  if ! grep -q 'require("merihari")' "$HAMMERSPOON_DIR/init.lua"; then
    echo 'require("merihari")' >> "$HAMMERSPOON_DIR/init.lua"
  fi
fi

echo ""
echo "Installed!"
echo ""
echo "Next steps:"
echo "1. Open Hammerspoon (it should be in your Applications folder)"
echo "2. Grant Accessibility permissions when prompted"
echo "3. Hammerspoon will show a menu bar icon"
echo "4. Click the icon → Reload Config"
echo ""
echo "Config: $CONFIG_FILE (START=$START END=$END)"
echo "Hammerspoon config: $HAMMERSPOON_DIR/merihari.lua"
echo ""
echo "To change time window: run this script again"
echo "=== Setup complete ==="
