#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh
ARCH=$(uname -m)
mkdir -p automation/taurine-control/bin
xcrun swiftc -swift-version 5 -O -target "$ARCH-apple-macos13.0" \
  Sources/TaurineControl.swift -framework AppKit \
  -o automation/taurine-control/bin/taurine-control
codesign --force --sign - automation/taurine-control/bin/taurine-control
codesign --verify --strict automation/taurine-control/bin/taurine-control
print "Built automation. Install with: python3 scripts/install-automation.py"
