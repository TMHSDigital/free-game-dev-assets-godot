extends SceneTree
## Writes the plugin's CREDITS file for every entry of a feed file, in feed
## order, with the same options tests/site_credits.mjs gives the website's
## creditsFile. Used by tests/check_credits_match_site.sh.
##   godot --headless --path . --script tests/print_credits.gd -- FEED.json OUT.md

const Feed := preload("res://addons/free_game_dev_assets/feed.gd")
const Credits := preload("res://addons/free_game_dev_assets/credits.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("usage: -- FEED.json OUT.md")
		quit(1)
		return
	var parsed := Feed.parse(FileAccess.get_file_as_string(args[0]))
	if not parsed["ok"]:
		printerr("feed: " + parsed["error"])
		quit(1)
		return
	var feed: Dictionary = parsed["feed"]
	# The plugin's own link rule, so a difference from the site's links fails the diff.
	var text := Credits.credits_file(Credits.owes(feed["entries"]), {
		"page_url": Credits.page_url(feed),
		"date": "",
		"source": "Free Game Dev Assets",
		"made_from": "a shortlist",
	})
	var f := FileAccess.open(args[1], FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("plugin credits: %d entries, %d lines" % [feed["entries"].size(), text.count("\n")])
	quit(0)
