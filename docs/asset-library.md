# Godot Asset Library submission

Everything the [Asset Library submission form](https://godotengine.org/asset-library/asset/submit)
asks for, for version 0.1.0. Submitting needs a Godot Asset Library account. Image URLs point
at the `v0.1.0` tag, so they only work once that tag is pushed.

| Field | Value |
| :--- | :--- |
| Asset name | Free Game Dev Assets |
| Category | Tools |
| Godot version | 4.3 |
| Version | 0.1.0 |
| Repository host | GitHub |
| Repository URL | https://github.com/TMHSDigital/free-game-dev-assets-godot |
| Issues URL | https://github.com/TMHSDigital/Free-Game-Dev-Assets/issues |
| Download commit | the full commit hash of the `v0.1.0` tag (`git rev-list -n 1 v0.1.0`) |
| Icon URL | https://raw.githubusercontent.com/TMHSDigital/free-game-dev-assets-godot/v0.1.0/docs/images/icon.png |
| License | MIT |

## Description

```
Browse the Free Game Dev Assets catalog (https://tmhsdigital.github.io/Free-Game-Dev-Assets/) inside the Godot editor: over 400 free asset sources and tools, each with its licence as read at the source.

- Search, and filter by category, licence family, commercial use, "no credit needed" and "works in Godot".
- See the licence on every row, and an entry's details: licence, commercial use, credit, formats and the date the licence was read.
- Open the source, or the entry's catalog page where the licence is quoted.
- Copy the recorded credit line.
- Keep a list of the assets your project uses and export a CREDITS.md, worded like the catalog website's export. Your own text in the file is kept.

Where the data comes from: the plugin downloads one file, plugin-feed.json, from the catalog's website, at most once a day or when you press Refresh, and works offline from a saved copy. Nothing about you or your project is sent. It never downloads or imports assets; it links to their sources.

Licences are as recorded by the catalog on the date shown for each entry. This is the catalog's reading, not legal advice: check the source's own terms before you ship.

GDScript only. Godot 4.3 or later.
```

## Previews

Type **Image** for each; the thumbnail can be the same URL.

1. Browsing and searching:
   https://raw.githubusercontent.com/TMHSDigital/free-game-dev-assets-godot/v0.1.0/docs/images/dock.png
2. An entry's details:
   https://raw.githubusercontent.com/TMHSDigital/free-game-dev-assets-godot/v0.1.0/docs/images/details.png
3. The project's asset list after Export credits:
   https://raw.githubusercontent.com/TMHSDigital/free-game-dev-assets-godot/v0.1.0/docs/images/credits.png

## Before submitting

- CI is green on the tagged commit (it installs the download into a fresh project on Godot 4.3
  and the latest stable).
- The download holds only `addons/free_game_dev_assets/`:
  `tests/install_from_archive.sh v0.1.0` checks this.
- The screenshots are current: `tools/screenshot.sh` (see the README's Develop section).
