extends SceneTree
## Contract check: runs a downloaded plugin-feed.json through the plugin's own
## parser, so a breaking change in the catalog's feed fails CI before users
## see it.
##   godot --headless --path . --script tests/check_feed_file.gd -- /path/to/plugin-feed.json

const Feed := preload("res://addons/free_game_dev_assets/feed.gd")

## Fewer entries than this means the feed lost most of the catalog.
const MIN_ENTRIES := 100


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not FileAccess.file_exists(args[0]):
		printerr("usage: -- <path to plugin-feed.json>")
		quit(2)
		return
	var r := Feed.parse(FileAccess.get_file_as_string(args[0]))
	if not r["ok"]:
		printerr("feed check failed: " + String(r["error"]))
		quit(1)
		return
	var feed: Dictionary = r["feed"]
	var problems: Array[String] = []
	if feed["entries"].size() < MIN_ENTRIES:
		problems.append("only %d entries" % feed["entries"].size())
	if r["dropped"] > 0:
		problems.append("%d malformed entries dropped" % r["dropped"])
	if feed["categories"].is_empty() or feed["licenseFamilies"].is_empty():
		problems.append("categories or licenseFamilies missing")
	var godot := 0
	for e in feed["entries"]:
		if "godot" in e["works_in"]:
			godot += 1
	if godot == 0:
		problems.append("no entry works in Godot")
	if not problems.is_empty():
		printerr("feed check failed: " + ", ".join(problems))
		quit(1)
		return
	print("feed ok: %s, %d entries, %d work in Godot" % [feed["version"], feed["entries"].size(), godot])
	quit(0)
