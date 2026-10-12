# slick for the Omarchy bar

A bar widget for [Omarchy](https://omarchy.org) that puts
[slick](https://slick.leonavas.com) in your bar the way a tray icon would.
slick is a fast, lightweight Slack client for the terminal, written in Rust
([source](https://github.com/leonavas/slick)).

## What it does

- **Icon.** slick's mark in the bar (white with a faint outline by default,
  readable on light and dark bars). It is dimmed while slick is not running.
- **Badges.** Red at the bottom-right counts unread messages in DMs and group
  DMs. Blue at the top-right counts messages that mention you in channels. A
  badge with nothing to count is not drawn.
- **Combined mode.** "Group notifications" in the menu folds both into one
  red badge with their sum.
- **Hover preview.** Hover the icon to see the unread conversations: who, the
  last message ("Ana: can you review the PR?"), mention count and how long ago.
  Click a conversation to jump straight to it in slick.
- **Scratchpad parking.** slick lives in Omarchy's scratchpad (SUPER+S). A
  click shows it, another click puts it away without closing it, so it keeps
  running and counting.
- **Menu (right click).** Launch on Login, Launch in Foreground, Open in
  Scratchpad, Group notifications, pause notifications (30 minutes, 1 hour,
  2 hours, until tomorrow) or resume them, and Quit slick.
- **Pause notifications** uses Slack's own do-not-disturb, so the pause
  follows your account to every client and works even with slick closed.
  While a pause you set is on, the badges give way to a small bell-off mark.
  Slack's scheduled night-time DND keeps the badges.
- **Not installed?** Without slick on your `PATH`, the icon dims and its card
  shows the install command, with buttons to copy it or run it in a terminal.
  The widget picks slick up on its own once installed.

| Mouse | Action |
|---|---|
| Left click | Open slick, show it, or put it away |
| Middle click | Quit slick |
| Right click | The menu |
| Hover | Preview of unread conversations |

## Requirements

- Omarchy, with its shell (the Quickshell bar).
- slick installed and on your `PATH`:

  ```bash
  curl -fsSL https://slick.leonavas.com/install.sh | sh
  ```

  See [slick.leonavas.com](https://slick.leonavas.com) for details.

## Install

```bash
omarchy plugin add https://github.com/leonavas/omarchy-slick.git
omarchy plugin enable leonavas.slick --section right
```

To update later: `omarchy plugin update leonavas.slick`, then
`omarchy restart shell`.

## Settings

Change them in the bar's widget settings panel, or inline on the widget's entry
in `~/.config/omarchy/shell.json`, e.g.
`{ "id": "leonavas.slick", "badgeLayout": "Combined" }`.

| Key | Default | What it does |
|---|---|---|
| `launchCommand` | `""` | Empty runs `omarchy-launch-tui --app-id=<windowClass> slick`. Anything else must open a window with class `windowClass` |
| `windowClass` | `org.omarchy.slick` | The slick window the widget drives |
| `iconStyle` | `Outline` | `Outline`, `Color` (colored mark), `Mono` (tinted like the bar's glyphs) or `Glyph` |
| `glyph` | `󰒱` | Nerd Font character for the `Glyph` style |
| `glyphSize` | `0` | Glyph size in px; 0 follows the bar |
| `glyphOffsetY` | `0` | Vertical nudge for the glyph, in px |
| `badge` | `Count` | `Count`, `Dot` or `None` |
| `badgeLayout` | `Split` | `Split` (red DMs + blue channels) or `Combined` (one red badge) |
| `dmColor` | `#b65f4e` | DM badge color |
| `channelColor` | `#467996` | Channel badge color |
| `channelBadge` | `Mentions` | What the blue badge counts: `Mentions`, `All unread` or `None` |
| `badgeScale` | `0.45` | Dot size, as a fraction of the icon |
| `tintWhenUnread` | `false` | Color the mark too (`Mono` and `Glyph` styles) |
| `hideMode` | `Special workspace` | What a click on the open window does: park it, or `Never hide` |
| `specialWorkspace` | `scratchpad` | The special workspace slick parks in |
| `openInSpecial` | `true` | slick opens straight into that workspace |
| `autoStart` | `false` | Open slick when the shell starts (Launch on Login) |
| `launchForeground` | `true` | Show and focus slick when it opens; off, it opens hidden |
| `dimWhenClosed` | `true` | Dim the icon while slick is not running |
| `hideWhenNotRunning` | `false` | Remove the icon while slick is not running |
| `middleClickCloses` | `true` | Middle click quits slick |
| `hoverPreview` | `true` | Show the preview on hover |
| `previewRows` | `6` | Conversations in the preview |
| `previewChannels` | `false` | Also list unread channels without a mention |
| `mutedIndicator` | `Bell` | While paused: `Bell`, `Dim` or `None` |

## How it works

slick publishes what it knows to `$XDG_RUNTIME_DIR/slick/state.json`,
rewriting it atomically whenever something changes: unread counts, the latest
unread messages per conversation, and the do-not-disturb state. The widget
watches that file. It is ignored whenever no slick window is open, so a crash
never leaves a stale badge behind.

Actions go back through slick's command line:

- `slick open <conversation> [ts] [--thread <ts>]`: jump to a conversation
- `slick quit`: close slick
- `slick dnd pause <minutes>`, `slick dnd resume`, `slick dnd status`

The file format is documented in
[docs/events.md](https://github.com/leonavas/slick/blob/master/docs/events.md).
[`NOTES.md`](NOTES.md) has the design decisions that are not obvious from the
code.

## Troubleshooting

- **Changes to the plugin do not show up.** After updating or editing the
  plugin, run `omarchy restart shell`. The shell's own reload keeps running
  the old code.
- **Two slick icons.** slick also has a tray icon of its own. Turn it off with
  `tray = false` in `~/.config/slick/config`.
- **No badges or preview.** Check that slick is running and that
  `$XDG_RUNTIME_DIR/slick/state.json` exists. The widget only trusts it while
  a window of class `org.omarchy.slick` is open, so a slick started some other
  way needs `windowClass` set to its class.

## License

MIT, see [`LICENSE`](LICENSE).
