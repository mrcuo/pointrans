#!/bin/bash
set -e

# Define directories
APP_NAME="Pointrans"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR=".build"

echo "=== Building ${APP_NAME} ==="

# Build the executable using Swift PM
swift build -c release

# Find the binary
BINARY_PATH=$(swift build -c release --show-bin-path)/${APP_NAME}

if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Binary not found at $BINARY_PATH"
    exit 1
fi

echo "=== Packaging as ${APP_BUNDLE} ==="

# Clean existing app bundle
rm -rf "$APP_BUNDLE"

# Create directories
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy binary & resources
cp "$BINARY_PATH" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Sources/Pointrans/local_dict.json" "${APP_BUNDLE}/Contents/Resources/local_dict.json"
cp "Sources/Pointrans/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

# Create Info.plist
cat << 'EOF' > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.tailcasso.Pointrans</string>
    <key>CFBundleName</key>
    <string>Pointrans</string>
    <key>CFBundleDisplayName</key>
    <string>Pointrans</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleExecutable</key>
    <string>Pointrans</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.2</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Pointrans requires screen recording permission to capture text under the cursor. / Pointrans需要屏幕录制权限以识别鼠标光标处的单词。</string>
</dict>
</plist>
EOF

# Ad-hoc code sign so macOS registers the app for privacy permissions (Screen Recording)
echo "=== Code Signing (ad-hoc) ==="
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "=== Build Successful! ==="
echo "You can run the application with: open ${APP_BUNDLE}"
