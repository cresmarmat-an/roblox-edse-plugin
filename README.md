# EDSE

**Easy DataStore Editor**: edit Roblox data stores without leaving Studio.

EDSE is a Roblox Studio plugin for browsing, editing and repairing the data your live servers read and write.

## Requirements

- Roblox Studio, with the place **published**.
- **Game Settings → Security → Enable Studio Access to API Services** turned on.

Saving in EDSE writes to your **live** data stores immediately, the same data your players use.

## Install

EDSE uses [Rojo](https://rojo.space) and [Rokit](https://github.com/rojo-rbx/rokit).

```sh
rokit install                       # installs rojo, selene, stylua, luau-lsp, luau
rojo build --plugin EDSE.rbxm       # builds straight into Studio's Plugins folder
```

Restart Studio (or reload plugins). The **EDSE** button appears in the Plugins tab and opens the **EDSE Easy DataStore Editor** window.

## Keyboard shortcuts

EDSE registers these actions. Bind keys to them in **File → Customize Shortcuts** (search "EDSE"):

| Action | What it does |
| --- | --- |
| EDSE: Save entry | Save the open key (with diff review) |
| EDSE: Reload entry | Reload the open key from the data store |
| EDSE: Search keys | Focus the key search box |
| EDSE: Toggle window | Show or hide EDSE |
| EDSE: Toggle output | Show or hide the Output log |

## Limitations

- Studio plugins can't write to the clipboard, so Export selects the text and you press Ctrl+C.
- The JSON tab edits values up to about 200 KB of text. Larger values open read-only there, and you edit them in the Tree tab.
- EDSE runs in edit mode only. It doesn't start inside play-test sessions.
- MemoryStores and `AllScopes` listings aren't supported yet.
