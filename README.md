# leonavas.slick

[slick](https://github.com/leonavas/slick), the Slack TUI, as a tray-style icon
in the Omarchy bar. Click to open it, click again to park it out of sight
without closing it, red and blue badges for unread DMs and channel mentions,
and a preview of them when you hover the icon.

## Requirements

slick on `PATH`, recent enough to publish its state file
(`$XDG_RUNTIME_DIR/slick/state.json`) and answer `slick open`, `slick quit` and
`slick dnd`.

## Installing

```bash
omarchy plugin add https://github.com/leonavas/omarchy-slick.git
omarchy plugin enable leonavas.slick --section right
```

## Using it

| Action | What it does |
|---|---|
| Left click | Open slick, bring it back, or put it away |
| Middle click | Quit slick |
| Right click | Menu: show/hide, Launch on Login, Launch in Foreground, Open in Scratchpad, Group notifications, pause or resume notifications, Quit slick |
| Hover | Unread conversations; click one to jump to it |

Hiding does not close slick: the window lives in `special:scratchpad` (Omarchy's
SUPER+S), where it keeps running and counting.

**The badges** come in slick's own colors. Red, bottom-right: unread messages
in DMs and group DMs. Blue, top-right: messages that mention you in channels
(or every unread channel, with `channelBadge` set to `All unread`). A badge
with nothing to count is not drawn. "Group notifications" in the menu
(`badgeLayout: Combined`) folds both into one red badge with their sum.

**Pausing notifications** uses Slack's own do-not-disturb, so it follows your
account to every client, and works from the menu even with slick closed. While a pause you set is running the badges are
replaced by a small bell-off mark. Slack's scheduled night-time DND does not
hide them.

**The preview** lists DMs, group DMs and channels that mention you, newest
first, with the last unread message ("Ana: can you review the PR?"), the
mention count and how long ago it arrived. Other unread channels are only
counted at the bottom, unless `previewChannels` is on. While notifications are
paused the top line says until when, with a Resume link.

## Settings

All in the bar widget's settings panel, or inline in `~/.config/omarchy/shell.json`:

| Key | Default | |
|---|---|---|
| `launchCommand` | `""` | Empty runs `omarchy-launch-tui slick` (falls back to `xdg-terminal-exec`) |
| `windowClass` | `org.omarchy.slick` | The window the widget drives; also the app id it launches with |
| `iconStyle` | `Outline` | `Outline` (white mark, faint dark edge), `Color`, `Mono` (white mark tinted like a glyph) or `Glyph` |
| `glyph`, `glyphSize`, `glyphOffsetY` | `󰒱`, `0`, `0` | Only for the `Glyph` style |
| `badge` | `Count` | `Count`, `Dot` or `None` |
| `badgeLayout` | `Split` | `Split` (two badges) or `Combined` (one red badge with the sum) |
| `channelBadge` | `Mentions` | `Mentions`, `All unread` or `None` |
| `dmColor` | `#b65f4e` | DM badge |
| `channelColor` | `#467996` | Channel badge |
| `badgeScale` | `0.45` | Dot size |
| `tintWhenUnread` | `false` | Color the mark too (`Mono` and `Glyph`) |
| `hideMode` | `Special workspace` | Or `Never hide` |
| `specialWorkspace` | `scratchpad` | Used as `special:<name>` |
| `openInSpecial` | `true` | New slick windows go straight to the special workspace |
| `autoStart` | `false` | Open slick when the shell starts |
| `launchForeground` | `true` | Show and focus slick when it opens; off, it opens hidden in the scratchpad, also from the icon |
| `dimWhenClosed` | `true` | |
| `hideWhenNotRunning` | `false` | |
| `middleClickCloses` | `true` | |
| `hoverPreview` | `true` | |
| `previewRows` | `6` | |
| `previewChannels` | `false` | Give every unread channel a row |
| `mutedIndicator` | `Bell` | `Bell`, `Dim` or `None` while paused |

## Files

| File | Contents |
|---|---|
| `Slick.qml` | The bar widget |
| `Model.js` | Pure helpers: window lookup, state parsing, preview rows |
| `manifest.json` | Metadata and settings schema |
| `assets/` | slick's mark: color, white, and white with an outline |

[`NOTES.md`](NOTES.md) has the decisions that are not obvious from the code.

## License

MIT, see [`LICENSE`](LICENSE).
