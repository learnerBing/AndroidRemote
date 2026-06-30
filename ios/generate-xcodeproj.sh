#!/usr/bin/env bash
# Regenerate AndroidRemote.xcodeproj from project.yml
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/tools/xcodegen-bin/xcodegen/bin/xcodegen" generate --spec "$ROOT/ios/project.yml" --project "$ROOT/ios"
echo "✓ Generated $ROOT/ios/AndroidRemote.xcodeproj"
