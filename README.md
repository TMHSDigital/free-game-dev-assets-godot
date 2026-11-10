<div align="center">

# Free Game Dev Assets for Godot

**The Free Game Dev Assets catalog inside the Godot editor: find free assets and tools, with each licence shown on every row.**

[**The catalog**](https://tmhsdigital.github.io/Free-Game-Dev-Assets/)  ·  [What it does](#what-it-does)  ·  [Status](#status)  ·  [Install](#install)  ·  [Privacy](#what-it-sends-over-the-network)  ·  [Develop](#develop)

[![CI](https://img.shields.io/github/actions/workflow/status/TMHSDigital/free-game-dev-assets-godot/ci.yml?label=CI)](https://github.com/TMHSDigital/free-game-dev-assets-godot/actions/workflows/ci.yml)
[![Godot 4.3+](https://img.shields.io/badge/Godot-4.3%2B-478cbf?logo=godotengine&logoColor=white)](https://godotengine.org/)
[![GDScript only](https://img.shields.io/badge/GDScript-only-informational)](#requirements)
[![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey.svg)](LICENSE)
<br />
[![Status: early development](https://img.shields.io/badge/status-early%20development-orange)](#status)
[![Sponsor](https://img.shields.io/badge/Sponsor-TMHSDigital-ea4aaa?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/TMHSDigital)

<img src="docs/images/dock.png" alt="The Free Assets dock in the Godot editor: a search for &quot;pixel&quot; showing 50 of 419 entries, each row with its name, category and a licence badge such as CC0, SIL OFL, CC-BY-4.0, GPL-3.0-or-later or custom" width="420" />

<sub>The dock in Godot 4.7, searching for "pixel". The licence is written on every row; the colour only groups licence families.</sub>

</div>

The [Free Game Dev Assets](https://github.com/TMHSDigital/Free-Game-Dev-Assets) catalog records,
for each free asset source and tool, what its licence says, where it says it and when someone last
read it there. This plugin puts that catalog in a dock in the Godot editor, so you can check a
licence without leaving the editor, and later keep track of what your project uses and what it owes.

The plugin never downloads, rehosts or imports assets. It shows the catalog's records and links
to the source.

> [!NOTE]
> The plugin shows the catalog's reading of each licence, not legal advice. Licences change:
> read the source's own terms before you ship.

> [!IMPORTANT]
> Early development, not yet released. The dock already browses, searches and filters the
> catalog; entry details, credit lines and `CREDITS.md` export are still to come. See [Status](#status).

## Contents

[What it does](#what-it-does) · [Status](#status) · [Requirements](#requirements) · [Install](#install) · [What it sends over the network](#what-it-sends-over-the-network) · [Develop](#develop) · [Contributing](#contributing) · [Support](#support) · [Licence](#licence)

## What it does

| | Feature | |
| :--- | :--- | :--- |
| ✅ | **Browse the catalog** in a "Free Assets" dock, entries made for Godot first | Works now |
| ✅ | **Search** by name, tags, publisher and summary | Works now |
| ✅ | **Filter** by category, licence family, commercial use, "no credit needed" and "works in Godot" (on by default); the filters are kept between editor sessions | Works now |
| ✅ | **See the licence on every row** as text, on a background coloured by licence family, with entries still under review marked | Works now |
| ✅ | **Work offline** from a cached copy of the catalog | Works now |
| ⏳ | **Open an entry**: its source, and its catalog page where the licence is quoted | [#281](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/281) |
| ⏳ | **Copy the recorded credit line** | [#281](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/281) |
| ⏳ | **Track the assets your project uses** and export a `CREDITS.md` | [#282](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/282) |

## Status

Planned work is tracked in the catalog repository under
[TMHSDigital/Free-Game-Dev-Assets#116](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/116):

- [x] Plugin feed published by the catalog build ([#277](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/277))
- [x] Skeleton addon with an empty dock ([#278](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/278))
- [x] Fetch and cache the feed, offline fallback ([#279](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/279))
- [x] Browse list with search and filters ([#280](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/280))
- [ ] Entry details and actions ([#281](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/281))
- [ ] Project asset list and `CREDITS.md` export ([#282](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/282))
- [ ] Tests in CI ([#283](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/283)): running on every push; stays open for the credits-export tests
- [ ] Release and Asset Library listing ([#284](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues/284))

## Requirements

Godot 4.3 or later. GDScript only: no GDExtension, no C#, nothing to compile. CI tests every
push on Godot 4.3 (the oldest supported) and the latest stable release.

## Install

Not released yet. Once it is:

1. Install **Free Game Dev Assets** from the Godot Asset Library, or copy
   `addons/free_game_dev_assets/` into your project's `addons/` folder.
2. Turn it on under **Project → Project Settings → Plugins**.
3. The **Free Assets** dock appears on the right.

To try it today, open this repository's folder in Godot (see [Develop](#develop)).

## What it sends over the network

One request, to
[`plugin-feed.json`](https://tmhsdigital.github.io/Free-Game-Dev-Assets/plugin-feed.json) on the
catalog's GitHub Pages site. Nothing about you or your project is sent.

- **How often:** when the dock opens, at most once a day, or when you press **Refresh**. Within a
  day the saved copy is used and no request is made.
- **What it sends:** a plain `GET` with a `User-Agent` naming this plugin, plus the
  `If-None-Match` / `If-Modified-Since` validators from the last download, so an unchanged
  catalog comes back as an empty `304`.
- **Where it saves things:** the catalog goes in the editor's cache folder and the filter
  settings in the editor's config folder, never in your project.
- **When it can't connect:** it uses the saved copy and says why. A server error, a Wi-Fi login
  page or a catalog format newer than the plugin understands never replaces a good saved copy.

## Develop

The repository root is a small Godot project with the plugin turned on. Open it in Godot 4.3 or
later and the dock appears on the right. Only `addons/free_game_dev_assets/` goes into the Asset
Library download; `project.godot`, `tests/`, `tools/` and `docs/` are left out.

```
addons/free_game_dev_assets/
  plugin.gd         adds and removes the dock
  dock.gd           the dock UI
  browse.gd         search, filters, sort and saved filter state (no editor APIs)
  feed.gd           parses and checks plugin-feed.json (no editor APIs)
  feed_cache.gd     the saved copy and its download metadata
  feed_client.gd    the request, and falling back to the saved copy
tests/
  run_tests.gd      headless unit tests against a fixture feed
  check_feed_file.gd  checks a downloaded live feed
  fixtures/feed_v1.json
tools/
  screenshot.sh     retakes the README screenshot of the dock
  screenshot/       the dev-only editor plugin it uses
```

Run the unit tests (no network, no editor):

```
godot --headless --path . --script tests/run_tests.gd
```

Check that the plugin loads and unloads cleanly in the editor:

```
godot --headless --editor --quit-after 300 --verbose --path .
```

The output should include `free_game_dev_assets: dock added` and `dock removed`, and no
`SCRIPT ERROR`.

Retake the README screenshot after changing how the dock looks:

```
tools/screenshot.sh                      # writes docs/images/dock.png
tools/screenshot.sh --query "font" --height 0 --out shot.png
```

It opens a real editor window for about ten seconds, on a temporary copy of the project, so
it needs a display and either a connection or a catalog cached by an earlier run. Your repo
and your saved dock filters are left alone. It also checks every licence on screen: if one is
cut short it still saves the image but exits with code 2. `tools/screenshot.sh --help` lists
the options, and `GODOT=/path/to/godot` picks the binary.

[CI](.github/workflows/ci.yml) runs both of these on Godot 4.3 and the latest stable on every
push and every Monday, each on a Godot download pinned by SHA-512. Each run also downloads the
live `plugin-feed.json` and runs it through the plugin's own parser, so a feed change that would
break the plugin shows up before users see it. The feed's format is documented in the catalog's
[`docs/data.md`](https://github.com/TMHSDigital/Free-Game-Dev-Assets/blob/main/docs/data.md#plugin-feed).

## Contributing

Bug reports and ideas are welcome. Issues for the plugin are filed in the
[catalog repository](https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues) alongside the
roadmap above. To correct a licence or add a source, change the catalog itself; the plugin picks
it up on the next deploy.

For a pull request here, keep the scripts GDScript-only and working on Godot 4.3, add a test in
`tests/run_tests.gd` for logic that doesn't need the editor, and run both commands under
[Develop](#develop) before opening it.

## Support

If the catalog or the plugin saves you time, you can
[sponsor TMHSDigital on GitHub](https://github.com/sponsors/TMHSDigital). Entirely optional.

<p align="right"><a href="#free-game-dev-assets-for-godot">Back to top ↑</a></p>

## Licence

Plugin code: [MIT](LICENSE). Catalog data: [CC0 1.0](https://github.com/TMHSDigital/Free-Game-Dev-Assets/blob/main/LICENSE).
The assets the catalog lists keep their own licences: check the source before you ship.
