# Omarchy Quick Settings Plugin

One configurable menu for your Omarchy plugin controls. Select the plugins you want, open their native panels from the menu, and keep their individual icons out of the bar.

## Features

- Choose installed plugins with a searchable selection editor.
- Open the original Audio, Network, Bluetooth, Power and other compatible plugin panels.
- Hide selected widgets from the bar while keeping their services and controls available.
- Display each widget’s native icon, including custom artwork, theme colors and live status.
- Refresh icons every five seconds while the chooser is open.
- Restore a widget’s bar position and settings when you deselect it.
- Use a three-column grid with scrolling for larger selections.

## Requirements

An Omarchy installation with the Quickshell plugin system, Python 3, Git, and the `omarchy`, `omarchy-shell`, and `omarchy-plugin-catalog` commands. Tested on Omarchy **4.0.4-1**. The plugin uses Omarchy shell internals; older releases and future shell changes may require adjustments.

## Install

```bash
omarchy plugin add https://github.com/nickpstone/omarchy-quick-settings-plugin.git --enable
```

The plugin ID is `nick.quick-settings`. If it is installed but disabled:

```bash
omarchy plugin enable nick.quick-settings --section right
```

For a manual installation, copy the repository contents into `~/.config/omarchy/plugins/nick.quick-settings`, then run:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/nick.quick-settings
omarchy plugin enable nick.quick-settings --section right
```

## Use

1. Click the gear in the bar to open Quick Settings.
2. Click the pencil, or right-click the gear, to edit your selection.
3. Check the plugins you want and choose **Save selection**.
4. Click a tile to open that plugin’s own controls.

Tiles follow the order in which you select plugins. Cancel discards pending edits. The refresh button rescans installed plugins. Disabled plugins can be enabled using the play button in the editor.

The initial selection includes Audio, Network, Bluetooth, Power and ABC Radio if installed. ABC Radio is optional and is not bundled or installed by this repository.

Selected bar widgets disappear from the bar, but their native instances remain loaded. Saving also restores a missing bar entry as a hidden host so the panel can open. Standalone panels and overlays have no bar icon to hide and use a fallback tile icon. Trays, pure indicators and service-only plugins are excluded.

## Data and integration

Preferences and integration metadata live under `~/.local/state/quick-settings/`, or `$XDG_STATE_HOME/quick-settings/` when set:

| File or directory | Purpose |
| --- | --- |
| `settings.json` | Selected plugin IDs |
| `hosts.json` | Original user-plugin entry points |
| `backups/` | Original manifests and bar configuration before grouping |
| `icons/` | Rendered native icon cache |

Quick Settings modifies selected entries in `~/.config/omarchy/shell.json`. Built-in widgets are loaded through generated wrappers in this plugin’s `wrappers/` directory; packaged Omarchy files remain untouched. For user plugins, the original QML remains intact, while their manifest points to a generated `_QuickSettingsHost.qml` beside it. Each host retains the plugin’s service facade and forwards native panel controls.

The hosts occupy no bar space and conceal their bar buttons to prevent hidden widgets from receiving clicks intended for Quick Settings. Opening or refreshing the chooser synchronizes the selection and repairs entry points after plugin updates.

## Disable or remove

Disabling Quick Settings makes hosted icons visible again:

```bash
omarchy plugin disable nick.quick-settings
```

For removal, first deselect all plugins and save to restore the original built-in bar entries. Then run:

```bash
omarchy plugin remove nick.quick-settings --yes
```

User-plugin hosts are self-contained and continue to work without Quick Settings. Preferences and backups remain in the state directory. Keep them if you plan to reinstall or need the original manifest mappings.

## Troubleshooting

- **A tile does not open:** enable the plugin in the editor. Some third-party plugins use panel routing that Quick Settings does not support; launch failures appear in the menu.
- **A plugin is missing:** click refresh. Only installed plugins with compatible controls are listed.
- **Changes did not apply:** run `omarchy-shell shell rescanPlugins`. If needed, run `omarchy restart shell`.
- **An icon differs:** only native bar widgets have native icons. Panels and overlays without a bar widget use a fallback.
- **After a plugin update:** open Quick Settings or click refresh to synchronize the native host.

## Development and validation

The QML chooser is in `Panel.qml`, native-host integration is in `WidgetHost.qml`, and discovery and persistence are in `settings.py`. Generated wrappers are runtime files and are not committed.

```bash
python3 -m py_compile settings.py
omarchy plugin validate .
```

Live checks performed during development include a 14-plugin chooser, custom and dynamic native icon rendering, hidden-widget click routing, and opening native Battery controls. Grouping and restoration were also checked for preservation of existing bar settings. These are local verification results, not a guarantee that every third-party plugin is compatible.

## Credits and license

Created by **Nick Stone**, with development assistance from **OpenAI Codex**. See [CREDITS.md](CREDITS.md) for acknowledgments and [LICENSE](LICENSE) for the MIT license.

This is an independent community plugin.
