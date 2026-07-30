#!/bin/bash
set -e
APP="HeartbleedOptimizer"
DIR="$APP.app"
DMG="HeartbleedOptimizer.dmg"

rm -rf "$DIR" "$DMG"
mkdir -p "$DIR/Contents/MacOS" "$DIR/Contents/Resources"

echo ""
echo "🔨 Компиляция Heartbleed Optimizer v3..."
echo ""
for f in Sources/*.swift; do
    printf "   • %-25s %4d строк\n" "$(basename $f)" "$(wc -l < "$f")"
done
TOTAL=$(cat Sources/*.swift | wc -l)
echo ""
echo "   Всего: $TOTAL строк Swift"
echo ""

swiftc \
  Sources/Theme.swift \
  Sources/Models.swift \
  Sources/Services.swift \
  Sources/ViewModels.swift \
  Sources/Views.swift \
  Sources/App.swift \
  -o "$DIR/Contents/MacOS/$APP" \
  -framework SwiftUI \
  -framework AppKit \
  -framework Foundation \
  -framework Combine \
  -framework Charts \
  -framework IOKit \
  -O \
  -parse-as-library

cp Info.plist "$DIR/Contents/Info.plist"
codesign --force --deep --sign - "$DIR" 2>/dev/null || true
xattr -cr "$DIR" 2>/dev/null || true

echo "💿 Создание DMG..."
hdiutil create \
  -srcfolder "$DIR" \
  -volname "Heartbleed Optimizer" \
  -format UDZO \
  -ov "$DMG" >/dev/null 2>&1

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   ✅  Heartbleed Optimizer v3 собран!           ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  📦 $DIR ($(du -h "$DIR" | cut -f1))"
echo "║  💿 $DMG ($(du -h "$DMG" | cut -f1))"
echo "║  📝 $TOTAL строк"
echo "╠══════════════════════════════════════════════════╣"
echo "║  🚀 ./$DIR/Contents/MacOS/$APP"
echo "║  💿 DMG для распространения готов"
echo "╚══════════════════════════════════════════════════╝"
