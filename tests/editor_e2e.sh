#!/usr/bin/env bash
# End-to-end test in a real (headless) Godot editor: adds entries to the
# project's asset list through the dock, exports CREDITS.md around the user's
# own text, exports again, and checks dropped ids and broken files.
#
#   tests/editor_e2e.sh
#
# Runs on a temporary copy of the project with the dev-only plugin from
# tests/e2e/ turned on, so the repo is never modified. Needs the live catalog
# (or one cached by an earlier run). GODOT picks the binary.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot="${GODOT:-}"
if [ -z "$godot" ]; then
	for candidate in godot_console godot; do
		if command -v "$candidate" >/dev/null 2>&1; then godot="$candidate"; break; fi
	done
fi
[ -n "$godot" ] || { echo "no Godot found: put godot on PATH or set GODOT" >&2; exit 1; }
native() {
	if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/addons"
cp "$root/project.godot" "$work/"
cp -r "$root/addons/free_game_dev_assets" "$work/addons/"
# Import before the test plugin is turned on, or the import pass runs it too.
"$godot" --headless --editor --quit --path "$(native "$work")" > /dev/null 2>&1 || true
cp -r "$root/tests/e2e" "$work/addons/_e2e"
sed -i.bak 's|^enabled=PackedStringArray(\(.*\))$|enabled=PackedStringArray(\1, "res://addons/_e2e/plugin.cfg")|' "$work/project.godot"
rm -f "$work/project.godot.bak"
grep -q '_e2e/plugin.cfg' "$work/project.godot" || { echo "could not enable the e2e plugin" >&2; exit 1; }

status=0
"$godot" --headless --editor --path "$(native "$work")" > "$work/editor.log" 2>&1 || status=$?

grep -E "^e2e|^  - " "$work/editor.log" || true
if grep -qE "SCRIPT ERROR|Parse Error" "$work/editor.log"; then
	grep -E -A2 "SCRIPT ERROR|Parse Error" "$work/editor.log" >&2
	exit 1
fi
grep -q "^e2e ok:" "$work/editor.log" || { echo "e2e did not report ok" >&2; tail -n 15 "$work/editor.log" >&2; exit 1; }
exit "$status"
