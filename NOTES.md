# Notes

Decisions that are not obvious from the code. The window handling (special
workspace parking, the `0x` address prefix, the double focus, Lua vs legacy
dispatch) is the same as the WhatsApp widget's and its NOTES explain it.

## The state file is trusted only while the window exists

slick writes `running: false` when it quits, but a crash writes nothing and
the file stays in the runtime dir. The widget therefore ignores the file
whenever no window of `windowClass` exists. It does not check `pid`: slick
runs inside the terminal it was launched with (`-e slick`), so the window and
the process die together.

## Muted vs night-time DND

Only a pause the user set (`dnd.snooze: true`) hides the badges. Slack's
scheduled DND (`snooze: false`) keeps it: the person did not ask for quiet,
the schedule did, and a badge is not a notification. A pause whose `until` is
already in the past counts as over even if slick has not rewritten the file
yet; the widget's clock ticks every 20 s for that and for the relative times.

## Badges

Two numbers from slick: `totals.direct_messages` (red) and
`totals.channel_mentions` (blue). A state file from before those fields gets
them summed from `conversations[]`: `mentions` per DM or group DM with at least
one per unread conversation, and `mentions` per channel. Since slick only
lists a capped number of conversations, the fallback can undercount.

Which corner each takes is two properties at the top of the icon section
(`dmCorner`, `channelCorner`), so moving them is a one-line change.

At bar size the icon canvas is ~13 px and a count badge ~11 px, so the
WhatsApp widget's "inside the canvas" placement would cover the mark. Counts
sit on the canvas corners instead, out into the slot's padding, and a pixel
past them vertically so the two do not touch. Dots keep the inside placement.

The Mono icon is the white SVG run through `MultiEffect` colorization, the
same way the shell's tray tints symbolic icons.

## Launching

Every launch, from a click, the menu or login, follows `launchForeground`.
slick cannot be born in the scratchpad: Ghostty does not start a window's
command until that window is first shown on screen, so a terminal created in
a hidden special workspace sits there titled "Ghostty" and slick only starts
once the scratchpad is opened.

So the window opens on the current workspace. With Launch in Foreground off
it opens with `no_initial_focus` (`hl.exec_cmd(cmd, { no_initial_focus = true
})` on Lua configs, `[noinitialfocus] cmd` on older ones): it flashes there
briefly without taking the focus, which matters because focusing slick tells
it the open conversation was seen and can be marked read. `onRunningChanged`
then moves it silently into the scratchpad (`placeInSpecial`), or, with Launch
in Foreground on, shows it there. Both wait for `settled`, so a shell restart
never moves a slick that was already open.

"Silent" is not enough there. Moving a window that just opened makes Hyprland
refocus, and it may pick a window that lives in the scratchpad (another app
parked there, or slick itself), which opens the scratchpad on screen. So a
background launch checks 200 ms later with `hyprctl monitors -j`: if the
scratchpad is showing it is hidden again and the focus goes back to the last
regular window you used. Measured: the window and the scratchpad flash for
about 200 ms, and slick is running in the hidden scratchpad well within a
second.

## Opening a conversation

The widget shows the window first and only then runs `slick open`. slick also
focuses its window; doing it in the other order could toggle the special
workspace closed again.

## "Until tomorrow"

Minutes until 08:00 the next morning. Between midnight and 04:00 that is the
coming 08:00, not the one a day later.

## Hot reload

Editing the QML while the widget is on the bar logs "Local plugin changed,
reloading" but keeps running the old component: the live instances pin it in
the component cache. `omarchy restart shell` picks up the change.

## The Outline icon

`assets/slick-outline.svg` is `slick-white.svg` with the same four masked
strokes drawn first in black, 6 units wider on each side (~0.6 px at bar
size), inside one `opacity="0.6"` group so crossings do not darken twice. The
masks are shared, so the weave's cuts come out as thin dark lines instead of
holes. Regenerate it from the white mark rather than editing it by hand.

## "Until a date and time"

The picker steps a day (today up to 30 days out), an hour and a minute in
quarters, and pauses for the minutes from the click to that time, rounded up
so the pause never ends early. The target is rebuilt from the calendar date
(`new Date(y, m, d + offset, h, min)`), so month ends and DST come out right.
Its label uses the same `clockLabel` as the card: a bare weekday only within
the coming six days, a date beyond that.

## Reactions

slick lists the reactions other people put on your messages in `reactions`
(newest first, up to 20, for a day). The card shows them in their own
section after the unread conversations; they never count toward a badge or
the "waiting" number. A state file without the field, from an older slick,
reads as no reactions.

Each reaction's emoji is drawn from what slick hands over in `emoji`: the
local `file` first (`AnimatedImage` for a GIF, `Image` otherwise), then the
`url`, then the Unicode `char`. Without it (an older slick) a small shortcode
table in `Model.js` stands in, and anything else shows as `:name:`.

A reaction is new when its key (conversation, message ts, reaction, user,
`at`) was not in the previous snapshot. The first snapshot after the shell or
slick starts only sets the baseline, so nothing replays at login. New ones
float out of the icon, staggered, unless a pause you set is on (same rule as
the badges) or "Show reactions" is off.

The bar's surface is only as tall as the bar, so the bubbles fly in a
`PopupWindow` anchored to the bar window, the same mechanism as the hover
card: transparent, `mask: Region {}` so it takes no input or focus, and only
mapped while a bubble is in the air. It starts on the icon and moves away
from the screen edge the bar is on (up from a bottom bar, down from a top
one). It does not go through the bar's popout coordinator, so it neither
closes nor is closed by an open card.

## Pausing with slick closed

`slick dnd pause|resume|status` call Slack with the saved session, so the
pause entries stay enabled when slick is not running. Without a live state
file, the menu asks `slick dnd status` when it opens to decide whether to
offer Resume.

## slick not installed

`command -v slick` runs through `bash -lc`, the same login shell every slick
call goes through, so "detected" means "the widget can run it". The widget
assumes slick is installed until the first check answers, so the empty state
never flashes at login. While slick is missing it checks again every 30 s and
whenever the card or the menu opens. A slick window that is open counts as
installed whatever the check says.
