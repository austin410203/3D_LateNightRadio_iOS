#!/bin/sh
# 在 Docker（swift:6.2-noble）編 LNRCore＋coretest 並跑對照測試。編譯快取在 docker volume "lnrbuild"。
cd "$(dirname "$0")/.."
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W 2>/dev/null || pwd):/w" -v lnrbuild:/tmp/b -w /w swift:6.2-noble bash -c "swift build -c release --scratch-path /tmp/b 2>&1 | grep -E 'error|warning: (var|imm)' -A3 | head -60; /tmp/b/release/coretest /w $*"
