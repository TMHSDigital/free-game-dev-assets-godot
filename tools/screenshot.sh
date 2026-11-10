#!/usr/bin/env bash
# Takes a screenshot of the Free Assets dock in a real Godot editor and saves
# it as a PNG (by default the README image, docs/images/dock.png).
#
#   tools/screenshot.sh [--query TEXT] [--select ID] [--height PX] [--out PATH]
#
#   --query   search to show in the dock (default: pixel; "" for none)
#   --select  id of an entry to select, to show its details (default: none)
#   --height  pixels of the dock to keep from the top (default: 600; 0 for all)
#   --out     where to write the PNG (default: docs/images/dock.png)
#
# Set GODOT to choose the Godot binary; otherwise godot_console or godot on
# PATH is used. Needs a display (it opens an editor window for a few seconds)
# and either a network connection or a catalog cached by an earlier run.
#
# The repo is never modified apart from the output file: the script copies
# project.godot and the addon into a temporary project, adds the dev-only
# plugin from tools/screenshot/ there, and runs the editor on that copy.
# Filter settings you have saved in the dock are not changed.
#
# Exit codes: 0 saved, 1 failed, 2 saved but some licence text is cut short.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
query="pixel"
select=""
height=600
out="$root/docs/images/dock.png"

while [ $# -gt 0 ]; do
	case "$1" in
		--query) query="$2"; shift 2 ;;
		--select) select="$2"; shift 2 ;;
		--height) height="$2"; shift 2 ;;
		--out) out="$2"; shift 2 ;;
		-h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown option: $1 (try --help)" >&2; exit 1 ;;
	esac
done

godot="${GODOT:-}"
if [ -z "$godot" ]; then
	for candidate in godot_console godot; do
		if command -v "$candidate" >/dev/null 2>&1; then godot="$candidate"; break; fi
	done
fi
if [ -z "$godot" ]; then
	echo "no Godot found: put godot on PATH or set GODOT" >&2
	exit 1
fi

case "$out" in
	/*|[A-Za-z]:*) ;;
	*) out="$PWD/$out" ;;
esac

# Godot on Windows wants C:/... paths, not Git Bash's /c/...
native() {
	if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/addons"
cp "$root/project.godot" "$work/"
cp -r "$root/addons/free_game_dev_assets" "$work/addons/"
cp -r "$root/tools/screenshot" "$work/addons/_screenshot"
sed -i.bak 's|^enabled=PackedStringArray(\(.*\))$|enabled=PackedStringArray(\1, "res://addons/_screenshot/plugin.cfg")|' "$work/project.godot"
rm -f "$work/project.godot.bak"
grep -q '_screenshot/plugin.cfg' "$work/project.godot" || { echo "could not enable the screenshot plugin in the copy of project.godot" >&2; exit 1; }

echo "Opening the editor on a temporary copy of the project..."
status=0
FGDA_SHOT_OUT="$(native "$out")" FGDA_SHOT_QUERY="$query" FGDA_SHOT_SELECT="$select" FGDA_SHOT_HEIGHT="$height" \
	"$godot" --editor --path "$(native "$work")" > "$work/editor.log" 2>&1 || status=$?

grep -E "^screenshot:" "$work/editor.log" || true
if grep -qE "SCRIPT ERROR|Parse Error" "$work/editor.log"; then
	grep -E -A2 "SCRIPT ERROR|Parse Error" "$work/editor.log" >&2
	exit 1
fi
if ! grep -q "^screenshot: saved" "$work/editor.log"; then
	echo "no screenshot was saved; the last lines of the editor log:" >&2
	tail -n 15 "$work/editor.log" >&2
	exit 1
fi
exit "$status"
