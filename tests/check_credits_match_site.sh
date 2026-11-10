#!/usr/bin/env bash
# Checks that the plugin's CREDITS.md wording matches the website's shortlist
# export, line for line, for every entry in the live catalog. Runs the site's
# own owes.js on its data.json, and the plugin's credits.gd on plugin-feed.json.
#
#   tests/check_credits_match_site.sh
#
# Needs curl, node 18+ and Godot (GODOT, or godot_console / godot on PATH).
# Exits 0 when the two files are identical, 1 with a diff otherwise.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
site="https://tmhsdigital.github.io/Free-Game-Dev-Assets"
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
for f in owes.js data.json plugin-feed.json; do
	curl -fsSL --retry 3 --compressed -o "$work/$f" "$site/$f"
done
mv "$work/owes.js" "$work/owes.mjs"

node "$root/tests/site_credits.mjs" "$work/owes.mjs" "$work/data.json" "$work/plugin-feed.json" "$work/site.md"
"$godot" --headless --path "$(native "$root")" --script tests/print_credits.gd -- \
	"$(native "$work/plugin-feed.json")" "$(native "$work/plugin.md")" 2>&1 | tee "$work/godot.log"
if grep -qE "SCRIPT ERROR|Parse Error" "$work/godot.log"; then exit 1; fi

if diff -u "$work/site.md" "$work/plugin.md" > "$work/diff.txt"; then
	echo "credits match the website: $(wc -l < "$work/site.md") lines identical"
else
	echo "credits differ from the website export:" >&2
	head -n 60 "$work/diff.txt" >&2
	exit 1
fi
