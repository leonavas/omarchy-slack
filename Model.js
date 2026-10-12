.pragma library

// Pure helpers for the slick widget. The Hyprland readers only touch
// properties off the toplevel objects, which keeps QML binding capture
// working: the widget re-evaluates whenever a workspace or the window list
// moves. The state helpers take the parsed state.json and never throw on a
// field that is missing or of the wrong type.

// ------------------------------------------------------------------ windows

function classOf(toplevel) {
  if (!toplevel) return ""
  var wayland = toplevel.wayland
  if (wayland && wayland.appId) return String(wayland.appId)
  var ipc = toplevel.lastIpcObject
  if (ipc) {
    if (ipc["class"]) return String(ipc["class"])
    if (ipc["initialClass"]) return String(ipc["initialClass"])
  }
  return ""
}

function isActive(toplevel) {
  if (!toplevel) return false
  var wayland = toplevel.wayland
  return toplevel.activated === true || !!(wayland && wayland.activated)
}

// Exact, case-insensitive class match. slick's window carries a class of its
// own (org.omarchy.slick), so a substring match would only buy false hits on
// the terminals around it.
function findWindow(toplevels, windowClass) {
  var wanted = String(windowClass || "").toLowerCase()
  if (wanted.length === 0) return null
  var list = toplevels || []
  var found = null
  for (var i = 0; i < list.length; i++) {
    var toplevel = list[i]
    if (classOf(toplevel).toLowerCase() !== wanted) continue
    if (isActive(toplevel)) return toplevel
    if (!found) found = toplevel
  }
  return found
}

function workspaceName(toplevel) {
  if (!toplevel) return ""
  var workspace = toplevel.workspace
  if (workspace && workspace.name) return String(workspace.name)
  var ipc = toplevel.lastIpcObject
  if (ipc && ipc["workspace"] && ipc["workspace"]["name"]) return String(ipc["workspace"]["name"])
  return ""
}

function isParked(toplevel, specialName) {
  var name = String(specialName || "")
  if (name.length === 0) return false
  return workspaceName(toplevel) === "special:" + name
}

function specialShown(hyprland, specialName) {
  if (!hyprland || !hyprland.focusedMonitor) return false
  var ipc = hyprland.focusedMonitor.lastIpcObject
  var special = ipc ? ipc["specialWorkspace"] : null
  return !!special && String(special.name || "") === "special:" + String(specialName || "")
}

function activeWorkspaceName(hyprland) {
  if (!hyprland) return ""
  var workspace = hyprland.focusedWorkspace
  return workspace && workspace.name ? String(workspace.name) : ""
}

// -------------------------------------------------------------------- state

function countOf(value) {
  var count = Number(value)
  return isFinite(count) && count > 0 ? Math.floor(count) : 0
}

// Absent, malformed or from a schema this widget does not know is "no state":
// the widget then behaves as if slick published nothing.
function parseState(text) {
  var value = String(text || "").trim()
  if (value.length === 0) return null
  var data
  try {
    data = JSON.parse(value)
  } catch (e) {
    return null
  }
  if (!data || typeof data !== "object") return null
  if (Number(data.v) !== 1) return null
  if (!Array.isArray(data.conversations)) data.conversations = []
  return data
}

function attention(state) {
  return state ? countOf(state.attention) : 0
}

function totals(state) {
  var t = state && state.totals && typeof state.totals === "object" ? state.totals : {}
  return {
    mentions: countOf(t.mentions),
    dms: countOf(t.dms),
    groups: countOf(t.groups),
    channels: countOf(t.channels),
    channelsMentioned: countOf(t.channels_mentioned),
  }
}

// Unread messages in DMs and group DMs: the bottom badge. slick publishes it
// as totals.direct_messages; a file from before that field is summed from the
// conversations instead, at least one per unread conversation.
function directMessages(state) {
  if (!state) return 0
  var t = state.totals
  if (t && typeof t === "object" && t.direct_messages !== undefined) return countOf(t.direct_messages)
  var total = 0
  var list = state.conversations
  for (var i = 0; i < list.length; i++) {
    var conv = list[i]
    if (!conv || typeof conv !== "object") continue
    var kind = kindOf(conv.kind)
    if (kind !== "dm" && kind !== "group") continue
    if (conv.unread === false) continue
    total += Math.max(1, countOf(conv.mentions))
  }
  return total
}

// Messages mentioning you in channels: the top badge. Same fallback.
function channelMentions(state) {
  if (!state) return 0
  var t = state.totals
  if (t && typeof t === "object" && t.channel_mentions !== undefined) return countOf(t.channel_mentions)
  var total = 0
  var list = state.conversations
  for (var i = 0; i < list.length; i++) {
    var conv = list[i]
    if (!conv || typeof conv !== "object") continue
    var kind = kindOf(conv.kind)
    if (kind === "channel" || kind === "private") total += countOf(conv.mentions)
  }
  return total
}

// The channel badge's number for the `channelBadge` setting: "Mentions",
// "All unread" (mentions plus unread channels without one) or "None".
function channelBadgeCount(state, mode) {
  if (mode === "None") return 0
  var count = channelMentions(state)
  if (mode === "All unread") count += totals(state).channels
  return count
}

// Paused by the user (Slack's snooze), still in the future. Slack's scheduled
// night-time DND (`snooze: false`) is deliberately not "muted": the badge
// keeps counting through it.
function snoozed(state, nowSec) {
  var dnd = state ? state.dnd : null
  if (!dnd || typeof dnd !== "object" || dnd.paused !== true || dnd.snooze !== true) return false
  var until = Number(dnd.until)
  return !(isFinite(until) && until > 0 && until <= nowSec)
}

function dndActive(state, nowSec) {
  var dnd = state ? state.dnd : null
  if (!dnd || typeof dnd !== "object" || dnd.paused !== true) return false
  var until = Number(dnd.until)
  return !(isFinite(until) && until > 0 && until <= nowSec)
}

function dndUntil(state) {
  var dnd = state ? state.dnd : null
  var until = dnd ? Number(dnd.until) : 0
  return isFinite(until) && until > 0 ? until : 0
}

function pad(n) {
  return n < 10 ? "0" + n : String(n)
}

// "14:30" today, "tomorrow 08:00", otherwise "Mon 08:00".
function clockLabel(unixSec, nowSec) {
  if (!unixSec) return ""
  var when = new Date(unixSec * 1000)
  var now = new Date(nowSec * 1000)
  var hm = pad(when.getHours()) + ":" + pad(when.getMinutes())
  var dayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
  var diffDays = Math.floor((when.getTime() - dayStart) / 86400000)
  if (diffDays <= 0) return hm
  if (diffDays === 1) return "tomorrow " + hm
  return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][when.getDay()] + " " + hm
}

// Minutes until 08:00 of the next morning. Past midnight but before 04:00
// "tomorrow" still means the coming morning, not the one after it.
function minutesUntilTomorrow(nowSec) {
  var now = new Date(nowSec * 1000)
  var target = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 8, 0, 0)
  if (now.getHours() >= 4) target.setDate(target.getDate() + 1)
  return Math.max(1, Math.ceil((target.getTime() - now.getTime()) / 60000))
}

// Slack timestamps are "seconds.micros" strings.
function tsSeconds(ts) {
  var value = parseFloat(String(ts || ""))
  return isFinite(value) && value > 0 ? value : 0
}

function relativeTime(ts, nowSec) {
  var then = tsSeconds(ts)
  if (!then) return ""
  var delta = Math.max(0, nowSec - then)
  if (delta < 60) return "now"
  if (delta < 3600) return Math.floor(delta / 60) + "m"
  if (delta < 86400) return Math.floor(delta / 3600) + "h"
  return Math.floor(delta / 86400) + "d"
}

function kindOf(value) {
  var kind = String(value || "")
  return kind === "dm" || kind === "group" || kind === "private" ? kind : "channel"
}

// Nerd Font glyphs: account, account-multiple, lock; a plain # for channels.
function kindGlyph(kind) {
  if (kind === "dm") return "󰀄"
  if (kind === "group") return "󰀎"
  if (kind === "private") return "󰌾"
  return "#"
}

// Does a conversation belong in the preview? DMs and group DMs always do;
// channels only with a mention, unless every unread channel was asked for.
function eligible(conv, includeChannels) {
  var kind = kindOf(conv.kind)
  if (kind === "dm" || kind === "group") return true
  return includeChannels || countOf(conv.mentions) > 0
}

function oneLine(text) {
  return String(text || "").replace(/\s+/g, " ").trim()
}

// The rows the hover popup renders, already trimmed so the QML side can trust
// every field to exist. Returns { rows, hidden } where hidden counts eligible
// conversations past the row cap.
function previewRows(state, max, includeChannels) {
  var result = { rows: [], hidden: 0 }
  if (!state) return result
  var limit = Math.max(1, Number(max) || 6)
  var list = state.conversations
  for (var i = 0; i < list.length; i++) {
    var conv = list[i]
    if (!conv || typeof conv !== "object" || !conv.id) continue
    if (!eligible(conv, includeChannels)) continue
    if (result.rows.length >= limit) { result.hidden += 1; continue }
    var kind = kindOf(conv.kind)
    var name = String(conv.name || conv.id).trim()
    var messages = Array.isArray(conv.messages) ? conv.messages : []
    var last = messages.length > 0 ? messages[messages.length - 1] : null
    var author = last ? String(last.author || "").trim() : ""
    var text = last ? oneLine(last.text) : ""
    // In a DM the author is the conversation's name; saying it twice wastes
    // the line the message needs.
    var showAuthor = author.length > 0 && !(kind === "dm" && author === name)
    var ts = last && last.ts ? String(last.ts) : String(conv.latest || "")
    var threadTs = last && last.thread_ts ? String(last.thread_ts) : ""
    result.rows.push({
      id: String(conv.id),
      kind: kind,
      glyph: kindGlyph(kind),
      name: kind === "channel" || kind === "private" ? name.replace(/^#/, "") : name,
      mentions: countOf(conv.mentions),
      unread: conv.unread !== false,
      latest: String(conv.latest || ts),
      line: text.length > 0 ? (showAuthor ? author + ": " + text : text) : "",
      ts: ts,
      threadTs: threadTs !== ts ? threadTs : "",
    })
  }
  return result
}

// argv for `slick open`, jumping to the newest unread message (and into its
// thread when it is a reply).
function openArgs(row) {
  var argv = ["slick", "open", row.id]
  if (row.ts) argv.push(row.ts)
  if (row.threadTs) argv.push("--thread", row.threadTs)
  return argv
}

function badgeLabel(count) {
  return count > 99 ? "99+" : String(count)
}

// A Lua string literal, for commands handed to `hyprctl eval`.
function luaString(text) {
  return '"' + String(text).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'
}
