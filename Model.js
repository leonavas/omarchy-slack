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
  // Older slick publishes no reactions.
  if (!Array.isArray(data.reactions)) data.reactions = []
  // Nor threads.
  if (!data.threads || typeof data.threads !== "object") data.threads = {}
  if (!Array.isArray(data.threads.list)) data.threads.list = []
  return data
}

function attention(state) {
  return state ? countOf(state.attention) : 0
}

// `mentionsOnly` (the "Channel mentions only" setting) treats every unread
// channel without a mention as quiet, as before slick told them apart.
function totals(state, mentionsOnly) {
  var t = state && state.totals && typeof state.totals === "object" ? state.totals : {}
  var known = t.channels_quiet !== undefined && !mentionsOnly
  return {
    mentions: countOf(t.mentions),
    dms: countOf(t.dms),
    groups: countOf(t.groups),
    channels: countOf(t.channels),
    channelsMentioned: countOf(t.channels_mentioned),
    // Unread channels without a mention that are muted or set to mentions
    // only. A slick from before this field: all of them, as it was then.
    channelsQuiet: known ? countOf(t.channels_quiet) : countOf(t.channels),
    quietKnown: known,
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

// The channel badge's number for the `channelBadge` setting: "Unread"
// (mentions plus unread channels that notify you: not muted, not set to
// mentions only), "Mentions", "All unread" (mentions plus every unread
// channel) or "None".
function channelBadgeCount(state, mode, mentionsOnly) {
  if (mode === "None") return 0
  var count = channelMentions(state)
  var t = totals(state, mentionsOnly)
  if (mode === "All unread") count += t.channels
  else if (mode !== "Mentions") count += Math.max(0, t.channels - t.channelsQuiet)
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

var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// Calendar days from now's day to when's day; DST days are 23 or 25 hours
// long, so the difference is rounded rather than floored.
function dayOffset(when, now) {
  var a = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
  var b = new Date(when.getFullYear(), when.getMonth(), when.getDate()).getTime()
  return Math.round((b - a) / 86400000)
}

// "Oct 20", with the year only when it is not this one.
function dateLabel(when, now) {
  var text = MONTHS[when.getMonth()] + " " + when.getDate()
  return when.getFullYear() !== now.getFullYear() ? text + " " + when.getFullYear() : text
}

// "14:30" today, "tomorrow 08:00", "Tue 08:00" within the coming week,
// otherwise "Oct 20, 08:00". A bare weekday further out would point at the
// wrong week.
function clockLabel(unixSec, nowSec) {
  if (!unixSec) return ""
  var when = new Date(unixSec * 1000)
  var now = new Date(nowSec * 1000)
  var hm = pad(when.getHours()) + ":" + pad(when.getMinutes())
  var days = dayOffset(when, now)
  if (days === 0) return hm
  if (days === 1) return "tomorrow " + hm
  if (days > 1 && days <= 6) return WEEKDAYS[when.getDay()] + " " + hm
  return dateLabel(when, now) + ", " + hm
}

// The day picker's label for `offset` days from now: "Today", "Tomorrow",
// then "Wed, Oct 14".
function pickerDayLabel(offset, nowSec) {
  if (offset === 0) return "Today"
  if (offset === 1) return "Tomorrow"
  var now = new Date(nowSec * 1000)
  var day = new Date(now.getFullYear(), now.getMonth(), now.getDate() + offset)
  return WEEKDAYS[day.getDay()] + ", " + dateLabel(day, now)
}

// Unix seconds of hour:minute, `offset` days from now's day. Built from the
// calendar date, so month ends and DST come out right.
function pickerTarget(offset, hour, minute, nowSec) {
  var now = new Date(nowSec * 1000)
  return new Date(now.getFullYear(), now.getMonth(), now.getDate() + offset, hour, minute, 0).getTime() / 1000
}

// Where the picker starts: the full hour after the next one (14:20 gives
// 16:00), rolling over into tomorrow when that passes midnight.
function pickerDefault(nowSec) {
  var now = new Date(nowSec * 1000)
  var hour = now.getHours() + 2
  return { day: hour >= 24 ? 1 : 0, hour: hour % 24, minute: 0 }
}

// Whole minutes from now to the target, rounded up so the pause never ends
// before the time picked. 0 when the target is not in the future.
function minutesUntil(targetSec, nowSec) {
  var delta = targetSec - nowSec
  return delta > 0 ? Math.ceil(delta / 60) : 0
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
// DMs, group DMs, channels that mention you and channels that notify you
// get a row; muted or mentions-only channels only count in the footer.
function eligible(conv, includeChannels, mentionsOnly) {
  var kind = kindOf(conv.kind)
  if (kind === "dm" || kind === "group") return true
  return includeChannels || countOf(conv.mentions) > 0 || (!mentionsOnly && conv.quiet === false)
}

function oneLine(text) {
  return String(text || "").replace(/\s+/g, " ").trim()
}

// Text made safe to show as StyledText.
function escapeHtml(text) {
  return String(text || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

var STYLE_TAGS = { b: true, i: true, s: true }

// A message as tokens for a Flow: { kind: "text", html } per word, its
// style kept, and { kind: "img", src, animated } per custom emoji. The HTML
// is slick's `html` (escaped, only <b>, <i>, <s> and <img> of its own saved
// emoji), else the plain text escaped here: nothing a message says becomes
// markup, and an image only ever comes from a local file.
function messageTokens(message, prefix) {
  var html = message && typeof message.html === "string" ? message.html : escapeHtml(message ? message.text : "")
  html = escapeHtml(prefix || "") + html.replace(/\s+/g, " ").trim()
  var tokens = []
  var open = []
  var word = ""
  function flush() {
    if (word.length === 0) return
    var opening = open.map(function (t) { return "<" + t + ">" }).join("")
    var closing = open.slice().reverse().map(function (t) { return "</" + t + ">" }).join("")
    tokens.push({ kind: "text", html: opening + word + closing + "&nbsp;", src: "", animated: false })
    word = ""
  }
  var i = 0
  while (i < html.length) {
    var c = html[i]
    if (c === " ") { flush(); i++; continue }
    if (c === "<") {
      var end = html.indexOf(">", i)
      if (end < 0) break
      var tag = html.slice(i + 1, end)
      var name = tag.replace(/^\//, "").split(/\s/)[0].toLowerCase()
      if (STYLE_TAGS[name]) {
        // A word split by a tag ("ab<b>cd</b>") stays one word.
        if (word.length > 0) {
          var o = open.map(function (t) { return "<" + t + ">" }).join("")
          var cl = open.slice().reverse().map(function (t) { return "</" + t + ">" }).join("")
          tokens.push({ kind: "text", html: o + word + cl, src: "", animated: false })
          word = ""
        }
        if (tag[0] === "/") {
          var at = open.lastIndexOf(name)
          if (at >= 0) open.splice(at, 1)
        } else {
          open.push(name)
        }
      } else if (name === "img") {
        flush()
        var src = (tag.match(/src="([^"]*)"/) || [])[1] || ""
        src = src.replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
        if (src.indexOf("file://") === 0) {
          tokens.push({ kind: "img", html: "", src: src, animated: /\.gif$/i.test(src) })
        } else {
          var alt = (tag.match(/alt="([^"]*)"/) || [])[1] || ""
          if (alt.length > 0) tokens.push({ kind: "text", html: alt + "&nbsp;", src: "", animated: false })
        }
      }
      i = end + 1
      continue
    }
    word += c
    i++
  }
  flush()
  return tokens
}

// The rows the hover popup renders, already trimmed so the QML side can trust
// every field to exist. Returns { rows, hidden } where hidden counts eligible
// conversations past the row cap.
function previewRows(state, max, includeChannels, mentionsOnly) {
  var result = { rows: [], hidden: 0 }
  if (!state) return result
  var limit = Math.max(1, Number(max) || 6)
  var list = state.conversations
  for (var i = 0; i < list.length; i++) {
    var conv = list[i]
    if (!conv || typeof conv !== "object" || !conv.id) continue
    if (!eligible(conv, includeChannels, mentionsOnly)) continue
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
    // Every unread message slick sent, oldest first; the author only where
    // it changes, and never in a DM with that person.
    var lines = []
    var lastAuthor = ""
    for (var m = 0; m < messages.length; m++) {
      var msg = messages[m]
      if (!msg || typeof msg !== "object") continue
      var by = String(msg.author || "").trim()
      var prefixed = by.length > 0 && by !== lastAuthor && !(kind === "dm" && by === name)
      var tokens = messageTokens(msg, prefixed ? by + ": " : "")
      if (tokens.length === 0) continue
      lines.push({ tokens: tokens })
      lastAuthor = by
    }
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
      messages: lines,
      ts: ts,
      threadTs: threadTs !== ts ? threadTs : "",
    })
  }
  return result
}

// ------------------------------------------------------------------ threads

// A thread's new replies: `new`, or, from a slick before that field, `unread`.
function threadNew(item) {
  if (!item || typeof item !== "object") return 0
  return countOf(typeof item["new"] === "number" ? item["new"] : item.unread)
}

// New replies in the threads you follow: `threads.new`, else summed from the
// list (which slick caps).
function threadReplies(state) {
  var threads = state ? state.threads : null
  if (!threads || typeof threads !== "object") return 0
  if (typeof threads["new"] === "number") return countOf(threads["new"])
  var t = state.totals
  if (t && typeof t === "object" && typeof t.thread_new === "number") return countOf(t.thread_new)
  var list = Array.isArray(threads.list) ? threads.list : []
  var total = 0
  for (var i = 0; i < list.length; i++) total += threadNew(list[i])
  return total
}

// Thread replies that mention you: Slack's own count (`threads.mentions`),
// else one per thread in the list that mentions you.
function threadMentions(state) {
  var threads = state ? state.threads : null
  if (!threads || typeof threads !== "object") return 0
  if (threads.mentions !== undefined && threads.mentions !== null) return countOf(threads.mentions)
  var list = Array.isArray(threads.list) ? threads.list : []
  var total = 0
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].mention === true) total++
  return total
}

// The thread replies the blue badge adds, for the `channelBadge` setting:
// the new replies that do not mention you (those go to the red badge, as in
// Slack). None under "Mentions" or "None".
function threadBadgeCount(state, mode) {
  if (mode === "None" || mode === "Mentions") return 0
  return Math.max(0, threadReplies(state) - threadMentions(state))
}

// Unread threads as rows for the hover card, newest activity first as slick
// lists them: where, the thread's first message, and its latest new reply.
// Returns { rows, hidden } like previewRows. A click opens the thread at that
// reply.
function threadRows(state, max) {
  var result = { rows: [], hidden: 0 }
  var list = state && state.threads && Array.isArray(state.threads.list) ? state.threads.list : []
  var limit = Math.max(1, Number(max) || 6)
  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    if (!item || typeof item !== "object" || !item.ts) continue
    var conv = item.conversation && typeof item.conversation === "object" ? item.conversation : null
    if (!conv || !conv.id) continue
    if (result.rows.length >= limit) { result.hidden += 1; continue }
    var kind = kindOf(conv.kind)
    var name = String(conv.name || conv.id).trim()
    if (kind === "channel" || kind === "private") name = name.replace(/^#/, "")
    var rootMsg = item.root && typeof item.root === "object" ? item.root : {}
    var rootBy = String(rootMsg.author || "").trim()
    var rootText = oneLine(rootMsg.text)
    var messages = Array.isArray(item.messages) ? item.messages : []
    var last = messages.length > 0 ? messages[messages.length - 1] : null
    if (last && typeof last !== "object") last = null
    var by = last ? String(last.author || "").trim() : ""
    var reply = last ? messageTokens(last, by.length > 0 ? by + ": " : "") : []
    var threadTs = String(item.ts)
    var ts = last && last.ts ? String(last.ts) : threadTs
    result.rows.push({
      id: String(conv.id),
      kind: kind,
      glyph: kindGlyph(kind),
      name: name,
      count: threadNew(item),
      mention: item.mention === true,
      latest: String(item.latest || ts),
      root: rootText.length > 0 ? (rootBy.length > 0 ? rootBy + ": " + rootText : rootText) : "",
      reply: reply,
      ts: ts,
      threadTs: threadTs,
    })
  }
  return result
}

// ---------------------------------------------------------------- reactions

// Slack's shortcodes for the reactions people use most. Anything else,
// custom emoji included, shows as :name:.
var EMOJI = {
  "+1": "👍", "thumbsup": "👍", "-1": "👎", "thumbsdown": "👎",
  "heart": "❤️", "white_heart": "🤍", "blue_heart": "💙", "green_heart": "💚",
  "yellow_heart": "💛", "purple_heart": "💜", "orange_heart": "🧡", "black_heart": "🖤",
  "broken_heart": "💔", "sparkling_heart": "💖",
  "joy": "😂", "rolling_on_the_floor_laughing": "🤣", "smile": "😄", "smiley": "😃",
  "grinning": "😀", "grin": "😁", "laughing": "😆", "satisfied": "😆", "sweat_smile": "😅",
  "slightly_smiling_face": "🙂", "upside_down_face": "🙃", "wink": "😉", "blush": "😊",
  "heart_eyes": "😍", "star-struck": "🤩", "sunglasses": "😎", "hugging_face": "🤗",
  "thinking_face": "🤔", "face_with_monocle": "🧐", "neutral_face": "😐", "expressionless": "😑",
  "grimacing": "😬", "relieved": "😌", "confused": "😕", "open_mouth": "😮", "astonished": "😲",
  "scream": "😱", "sob": "😭", "cry": "😢", "disappointed": "😞", "rage": "😡",
  "saluting_face": "🫡", "melting_face": "🫠", "skull": "💀", "see_no_evil": "🙈",
  "face_palm": "🤦", "facepalm": "🤦", "shrug": "🤷",
  "tada": "🎉", "confetti_ball": "🎊", "eyes": "👀", "pray": "🙏", "fire": "🔥",
  "rocket": "🚀", "raised_hands": "🙌", "clap": "👏", "100": "💯", "ok_hand": "👌",
  "muscle": "💪", "wave": "👋", "handshake": "🤝", "point_up": "☝️", "v": "✌️",
  "star": "⭐", "star2": "🌟", "sparkles": "✨", "zap": "⚡", "bulb": "💡", "dart": "🎯",
  "trophy": "🏆", "medal": "🏅", "memo": "📝", "pushpin": "📌", "coffee": "☕", "beers": "🍻",
  "white_check_mark": "✅", "heavy_check_mark": "✔️", "ballot_box_with_check": "☑️",
  "x": "❌", "heavy_plus_sign": "➕", "warning": "⚠️", "question": "❓", "exclamation": "❗",
  "no_entry": "⛔", "rotating_light": "🚨", "hourglass_flowing_sand": "⏳", "ok": "🆗",
}

// skin-tone-2 to skin-tone-6, as Unicode modifiers.
var SKIN_TONES = { "2": "🏻", "3": "🏼", "4": "🏽", "5": "🏾", "6": "🏿" }

// "thumbsup" -> 👍, "thumbsup::skin-tone-3" -> 👍🏼, "partyparrot" -> :partyparrot:
function reactionEmoji(name) {
  var parts = String(name || "").replace(/^:|:$/g, "").split("::")
  var base = parts[0]
  if (base.length === 0) return ""
  var emoji = EMOJI.hasOwnProperty(base) ? EMOJI[base] : ""
  if (emoji.length === 0) return ":" + base + ":"
  var tone = parts.length > 1 ? /^skin-tone-(\d)$/.exec(parts[1]) : null
  return tone && SKIN_TONES[tone[1]] ? emoji + SKIN_TONES[tone[1]] : emoji
}

// How to draw a reaction: { text, image, animated }. slick hands over the
// real emoji when it knows it: a local copy (`file`, preferred), its `url`, or
// the Unicode `char`. An older slick sends none of it, and the shortcode table
// above stands in, then :name:.
function reactionVisual(item) {
  var emoji = item && item.emoji && typeof item.emoji === "object" ? item.emoji : {}
  var file = emoji.file ? String(emoji.file) : ""
  if (file.length > 0) {
    var encoded = file.split("/").map(function (part) { return encodeURIComponent(part) }).join("/")
    return { text: "", image: "file://" + encoded, animated: /\.gif$/i.test(file) }
  }
  var url = emoji.url ? String(emoji.url) : ""
  if (/^https?:\/\//i.test(url)) return { text: "", image: url, animated: /\.gif(\?|#|$)/i.test(url) }
  if (emoji.char) return { text: String(emoji.char), image: "", animated: false }
  return { text: reactionEmoji(item ? item.reaction || emoji.name : ""), image: "", animated: false }
}

// What tells one reaction from another across snapshots: a new key in the
// next snapshot is a reaction that just happened.
function reactionKey(item) {
  if (!item || typeof item !== "object") return ""
  var conv = item.conversation && typeof item.conversation === "object" ? item.conversation : {}
  var message = item.message && typeof item.message === "object" ? item.message : {}
  var user = item.user && typeof item.user === "object" ? item.user : {}
  return [conv.id, message.ts, item.reaction, user.id, item.at].join("|")
}

// Reactions in `state` whose keys are not in `seen` (a key -> true map), as
// visuals, newest first. Returns { keys, fresh }; `keys` replaces `seen`.
function newReactions(state, seen) {
  var result = { keys: {}, fresh: [] }
  var list = state && Array.isArray(state.reactions) ? state.reactions : []
  for (var i = 0; i < list.length; i++) {
    var key = reactionKey(list[i])
    if (key.length === 0) continue
    result.keys[key] = true
    if (seen && !seen[key]) result.fresh.push(reactionVisual(list[i]))
  }
  return result
}

// The reactions other people put on your messages, as rows for the hover
// card: newest first, as slick lists them. Returns { rows, hidden } like
// previewRows. They never count toward the badges.
function reactionRows(state, max) {
  var result = { rows: [], hidden: 0 }
  if (!state || !Array.isArray(state.reactions)) return result
  var limit = Math.max(1, Number(max) || 6)
  var list = state.reactions
  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    if (!item || typeof item !== "object") continue
    var conv = item.conversation && typeof item.conversation === "object" ? item.conversation : null
    var message = item.message && typeof item.message === "object" ? item.message : {}
    if (!conv || !conv.id) continue
    var visual = reactionVisual(item)
    if (visual.text.length === 0 && visual.image.length === 0) continue
    if (result.rows.length >= limit) { result.hidden += 1; continue }
    var kind = kindOf(conv.kind)
    var name = String(conv.name || conv.id).trim()
    if (kind === "channel" || kind === "private") name = name.replace(/^#/, "")
    var who = item.user && typeof item.user === "object"
      ? String(item.user.name || item.user.id || "").trim() : ""
    var ts = message.ts ? String(message.ts) : ""
    var threadTs = message.thread_ts ? String(message.thread_ts) : ""
    // In a DM with the person who reacted, the conversation's name is theirs:
    // the line goes to the message instead.
    var where = kind === "dm" && name === who ? "" : name
    var text = oneLine(message.text)
    result.rows.push({
      id: String(conv.id),
      kind: kind,
      glyph: kindGlyph(kind),
      who: who.length > 0 ? who : "Someone",
      emoji: visual,
      where: where,
      line: where.length > 0 && text.length > 0 ? where + " · " + text : (text.length > 0 ? text : where),
      latest: String(Number(item.at) || ts),
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
