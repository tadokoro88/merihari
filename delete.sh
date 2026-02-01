#!/bin/zsh
# Delete merihari

set -euo pipefail

CONFIG_DIR="${HOME}/.config/merihari"
HAMMERSPOON_DIR="${HOME}/.hammerspoon"

echo "=== Merihari deletion ==="
echo ""
echo "This will remove:"
echo "  - ~/.hammerspoon/merihari.lua"
echo "  - ~/.config/merihari/"
echo "  - require(\"merihari\") from ~/.hammerspoon/init.lua"
echo ""
read "confirm?Are you sure you want to uninstall? (y/N): "

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Cancelled."
  exit 0
fi

echo ""

# Turn off grayscale if it's on
if defaults read com.apple.universalaccess grayscale 2>/dev/null | grep -q "1"; then
  echo "Turning off grayscale..."
  osascript -e 'tell application "System Events" to key code 96 using {command down, option down}'
  sleep 0.5
fi

# Remove from Hammerspoon init.lua
if [[ -f "$HAMMERSPOON_DIR/init.lua" ]]; then
  sed -i '' '/require("merihari")/d' "$HAMMERSPOON_DIR/init.lua"
fi

# Remove Hammerspoon config
rm -f "$HAMMERSPOON_DIR/merihari.lua"

# Remove config
rm -rf "$CONFIG_DIR"

echo "Removed."
echo ""
echo "Next steps:"
echo "1. Open Hammerspoon"
echo "2. Click menu bar icon → Reload Config"
echo ""
echo "=== Deletion complete ==="
