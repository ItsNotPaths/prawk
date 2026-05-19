#!/usr/bin/env bash
# Fetches third-party deps into vendor/. Run once before building.
#
# Layout (flat — no nested vendor/<pkg>/vendor/):
#   vendor/rawk-luigi/      Xrawk Nim FFI to wayluigi
#   vendor/rawk-bufferlib/  Xrawk text-buffer + editor widget
#   vendor/wayluigi/        luigi.h fork (rawk-luigi reads this via
#                           -d:rawkLuigiVendor — see prawk's config.nims)
#   vendor/wayluigi/freetype/  freetype headers for luigi.h's freetype path
#   vendor/libvterm/        terminal emulator core for prawk's term.nim
#
# After fetching, registers rawk-luigi and rawk-bufferlib via `nimble develop`
# and runs `nimble setup` so plain `nim c` resolves them through nimble.paths.
# Idempotent — safe to re-run.
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENDOR="$PROJECT_DIR/vendor"

fetch_repo() {
    local name="$1" url="$2"
    local dest="$VENDOR/$name"
    if [ -d "$dest/.git" ]; then
        # Existing clone (often from CI cache restore). Always refresh to
        # origin/HEAD so a stale cache can't bake an old dep into a release —
        # release 2.5 shipped pre-fix wayluigi because the vendor/ cache was
        # restored and this branch skipped the fetch entirely.
        echo "  refreshing $name..."
        git -C "$dest" fetch --depth=1 origin HEAD
        git -C "$dest" reset --hard FETCH_HEAD
    else
        echo "  cloning $name..."
        mkdir -p "$VENDOR"
        git clone --depth=1 "$url" "$dest"
    fi
}

echo "==> rawk-luigi (Xrawk Nim FFI to wayluigi)"
fetch_repo "rawk-luigi" "https://github.com/ItsNotPaths/rawk-luigi.git"

echo "==> rawk-bufferlib (Xrawk text-buffer + editor widget)"
fetch_repo "rawk-bufferlib" "https://github.com/ItsNotPaths/rawk-bufferlib.git"

echo "==> wayluigi (luigi.h fork — flat, not nested under rawk-luigi)"
fetch_repo "wayluigi" "https://github.com/ItsNotPaths/wayluigi.git"

echo "==> freetype headers (for luigi.h freetype path)"
FT_HEADERS="$VENDOR/wayluigi/freetype"
if [ -d "$FT_HEADERS" ] && [ -f "$FT_HEADERS/ft2build.h" ]; then
    echo "  already present: freetype headers"
else
    echo "  cloning freetype..."
    TMP=$(mktemp -d)
    git clone --depth=1 -q "https://gitlab.freedesktop.org/freetype/freetype.git" "$TMP/freetype"
    mkdir -p "$FT_HEADERS"
    cp -r "$TMP/freetype/include/." "$FT_HEADERS/"
    rm -rf "$TMP"
    echo "  done."
fi

echo "==> libvterm"
if [ -d "$VENDOR/libvterm" ] && [ -n "$(ls -A "$VENDOR/libvterm" 2>/dev/null)" ]; then
    echo "  already present: libvterm"
else
    echo "  cloning libvterm..."
    git clone --depth=1 "https://github.com/neovim/libvterm.git" "$VENDOR/libvterm"
fi

echo "==> registering develop links (nimble.paths)"
# Drop stale state before re-registering. `nimble develop -a` *loads* the
# existing nimble.develop before appending — if a teammate (or CI) inherits
# a copy with absolute paths from another machine, the load fails and the
# whole step errors out. Regenerate from scratch every run; the file is
# strictly machine-local state and lives in .gitignore.
rm -f "$PROJECT_DIR/nimble.develop" "$PROJECT_DIR/nimble.paths"
( cd "$PROJECT_DIR" && \
    nimble develop -a:"$VENDOR/rawk-luigi"      -y; \
    nimble develop -a:"$VENDOR/rawk-bufferlib"  -y; \
    nimble setup -y )

echo ""
echo "All deps ready."
