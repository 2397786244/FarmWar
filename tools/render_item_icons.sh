#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BLENDER_BIN=${BLENDER_BIN:-/Applications/Blender-4.4.app/Contents/MacOS/Blender}

if [ ! -x "$BLENDER_BIN" ]; then
	BLENDER_BIN=/Applications/Blender.app/Contents/MacOS/Blender
fi

exec "$BLENDER_BIN" --background --python "$PROJECT_ROOT/tools/render_item_icons.py" -- --project "$PROJECT_ROOT" "$@"
