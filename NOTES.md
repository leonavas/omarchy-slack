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

## Clicks that launch

A launch from a click shows the window as soon as it appears, whatever
`launchForeground` says; that setting is for launches nobody clicked (login,
a terminal). Without this, "Open in Scratchpad" plus a click would open slick
hidden.

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

## Pausing with slick closed

`slick dnd pause|resume|status` call Slack with the saved session, so the
pause entries stay enabled when slick is not running. Without a live state
file, the menu asks `slick dnd status` when it opens to decide whether to
offer Resume.
