#!/usr/bin/env bash
# Installs the plugin the way the Godot Asset Library does, from the
# repository archive of a commit (default HEAD), into a brand-new project,
# then opens it in a headless editor. Fails if the archive holds anything but
# the addon, if the dock doesn't load cleanly, or if opening the editor writes
# any file into the project.
#
#   tests/install_from_archive.sh [COMMIT]
#
# GODOT picks the binary (default: godot_console or godot on PATH).

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
commit="${1:-HEAD}"
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
project="$work/project"
mkdir -p "$project"

# What the download contains.
git -C "$root" archive --format=tar "$commit" | tar -x -C "$project"
extra="$(cd "$project" && find . -type f ! -path './addons/free_game_dev_assets/*' | sort)"
if [ -n "$extra" ]; then
	echo "the download holds files outside addons/free_game_dev_assets/:" >&2
	echo "$extra" >&2
	exit 1
fi
echo "download: $(cd "$project" && find . -type f | wc -l | tr -d ' ') files, all in addons/free_game_dev_assets/"

# A fresh project with the plugin turned on, as Project Settings > Plugins does.
cat > "$project/project.godot" <<'EOF'
config_version=5

[application]

config/name="Install test"

[editor_plugins]

enabled=PackedStringArray("res://addons/free_game_dev_assets/plugin.cfg")
EOF
before="$(cd "$project" && find . -type f ! -path './.godot/*' ! -name '*.uid' ! -name '*.import' | sort)"

"$godot" --headless --editor --quit --path "$(native "$project")" > "$work/import.log" 2>&1 || true
"$godot" --headless --editor --quit-after 600 --verbose --path "$(native "$project")" > "$work/editor.log" 2>&1 || true

if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$work/import.log" "$work/editor.log"; then
	grep -hE -A2 "SCRIPT ERROR|Parse Error|Failed to load script" "$work/import.log" "$work/editor.log" >&2
	exit 1
fi
grep -q "free_game_dev_assets: dock added" "$work/editor.log" || { echo "the dock was not added" >&2; tail -n 20 "$work/editor.log" >&2; exit 1; }
grep -q "free_game_dev_assets: dock removed" "$work/editor.log" || { echo "the dock was not removed on exit" >&2; exit 1; }

after="$(cd "$project" && find . -type f ! -path './.godot/*' ! -name '*.uid' ! -name '*.import' | sort)"
if [ "$before" != "$after" ]; then
	echo "opening the editor wrote files into the project:" >&2
	diff <(echo "$before") <(echo "$after") >&2 || true
	exit 1
fi
echo "install ok: the dock loads in a fresh project and writes nothing into it"
