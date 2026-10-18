#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build
xcrun clang -std=c11 -Wall -Wextra -Werror -O1 -g \
  -fsanitize=address,undefined tests/session_test.c \
  -framework CoreFoundation -framework IOKit -o build/session-tests
./build/session-tests
xcrun swiftc -swift-version 5 Sources/Updates.swift tests/updates_test.swift -o build/update-tests
./build/update-tests
