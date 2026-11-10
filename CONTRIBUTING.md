# Contributing

Bug reports and ideas go in the
[catalog repository's issues](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues), where
the plugin's issues are tracked. To correct a licence or add a source, change the catalog itself;
the plugin picks it up on the next deploy.

For a pull request here: keep the scripts GDScript-only and working on Godot 4.3, add a test in
`tests/run_tests.gd` for logic that doesn't need the editor, run the checks below, and add a line
to [CHANGELOG.md](CHANGELOG.md).

## Layout

The repository root is a small Godot project with the plugin turned on. Open it in Godot 4.3 or
later and the dock appears on the right. Only `addons/free_game_dev_assets/` goes into the
release download and the Asset Library; everything else is export-ignored in `.gitattributes`.

```
addons/free_game_dev_assets/
  plugin.gd         adds and removes the dock
  dock.gd           the dock UI
  browse.gd         search, filters, sort and saved filter state (no editor APIs)
  entry_details.gd  what the details panel says, and which links are safe to open (no editor APIs)
  credits.gd        the project's asset list and CREDITS.md, ported from the website (no editor APIs)
  feed.gd           parses and checks plugin-feed.json (no editor APIs)
  feed_cache.gd     the saved copy and its download metadata
  feed_client.gd    the request, and falling back to the saved copy
tests/
  run_tests.gd      headless unit tests against a fixture feed
  fixtures/feed_v1.json
  check_feed_file.gd  checks a downloaded live feed
  editor_e2e.sh     drives the dock in a headless editor: add, export, export again
  e2e/              the dev-only editor plugin it uses
  install_from_archive.sh  installs the release download into a fresh project
  check_credits_match_site.sh  the website's export and the plugin's, compared on the live catalog
  site_credits.mjs, print_credits.gd  the two sides of that comparison
tools/
  screenshot.sh     retakes the README screenshots
  screenshot/       the dev-only editor plugin it uses
docs/
  images/           README and Asset Library images, and the icon
  asset-library.md  the Asset Library submission fields
```

## Checks

Unit tests (no network, no editor):

```
godot --headless --path . --script tests/run_tests.gd
```

The plugin loads and unloads cleanly in the editor; the output should include
`free_game_dev_assets: dock added` and `dock removed`, and no `SCRIPT ERROR`:

```
godot --headless --editor --quit-after 300 --verbose --path .
```

These need the live catalog, or one cached by an earlier run:

```
tests/editor_e2e.sh                 # add, export around hand-written text, export again, damaged files
tests/install_from_archive.sh       # the release download in a fresh project; writes nothing into it
tests/check_credits_match_site.sh   # the website's own export code against the plugin's (Node 18+)
```

The scripts run on temporary copies of the project, so the repository is never modified.
`GODOT=/path/to/godot` picks the binary; otherwise `godot_console` or `godot` on `PATH` is used.

[CI](.github/workflows/ci.yml) runs all of these on Godot 4.3 and the latest stable on every push
and every Monday, each on a Godot download pinned by SHA-512, plus a check of the live
`plugin-feed.json` against the plugin's own parser. A feed change that would break the plugin, or
a change to the website's credits wording, fails CI before users see it. The feed's format is
documented in the catalog's
[`docs/data.md`](https://github.com/TMHSDigital/Free-Game-Dev-Assets/blob/main/docs/data.md#plugin-feed).

## Screenshots

Retake the README images after changing how the dock looks:

```
tools/screenshot.sh
tools/screenshot.sh --query "accad" --select accad-mocap --height 0 --out docs/images/details.png
tools/screenshot.sh --query "" --project "accad-mocap,beehave,ox72-dungeon-tileset,kenney-ui-pack,poly-haven" --export --height 520 --out docs/images/credits.png
```

Each opens a real editor window for about ten seconds, on a temporary copy of the project, so it
needs a display. Your saved dock filters are left alone. It also checks every licence on screen:
if one is cut short it still saves the image but exits with code 2. `tools/screenshot.sh --help`
lists the options.

## Releasing

1. Set `version` in `addons/free_game_dev_assets/plugin.cfg` and date the entry in
   `CHANGELOG.md`.
2. Retake the screenshots if the dock changed.
3. Push, wait for CI, then tag `vX.Y.Z` and create the GitHub release from the changelog entry.
4. Update the Asset Library listing with the new version and the tag's commit hash
   (`docs/asset-library.md` has the fields).
