import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// slick: a tray-style button for the bar. Opens the slick terminal window,
// parks it in a special workspace so it keeps running out of sight, badges
// what is waiting and previews it on hover. Everything slick knows reaches
// the widget through one JSON file slick rewrites in the runtime dir.
BarWidget {
  id: root
  moduleName: "leonavas.slick"

  // ---------------------------------------------------------------- settings
  readonly property string launchCommand: String(setting("launchCommand", ""))
  readonly property string windowClass: String(setting("windowClass", "org.omarchy.slick"))
  readonly property string iconStyle: String(setting("iconStyle", "Outline"))
  readonly property string glyph: String(setting("glyph", "󰒱"))
  readonly property int glyphSize: Math.max(0, Number(setting("glyphSize", 0)))
  readonly property real glyphOffsetY: Number(setting("glyphOffsetY", 0))
  readonly property string badgeStyle: String(setting("badge", "Count"))
  readonly property string channelBadgeMode: String(setting("channelBadge", "Mentions"))
  readonly property bool combinedBadge: String(setting("badgeLayout", "Split")) === "Combined"
  readonly property string dmColorSetting: String(setting("dmColor", "#b65f4e"))
  readonly property string channelColorSetting: String(setting("channelColor", "#467996"))
  readonly property real badgeScale: Math.max(0.2, Math.min(0.9, Number(setting("badgeScale", 0.45))))
  readonly property bool tintWhenUnread: setting("tintWhenUnread", false) === true
  readonly property string hideMode: String(setting("hideMode", "Special workspace"))
  readonly property string specialName: String(setting("specialWorkspace", "scratchpad"))
  readonly property bool openInSpecial: setting("openInSpecial", true) !== false
  readonly property bool autoStart: setting("autoStart", false) === true
  readonly property bool launchForeground: setting("launchForeground", true) !== false
  readonly property bool dimWhenClosed: setting("dimWhenClosed", true) !== false
  readonly property bool hideWhenNotRunning: setting("hideWhenNotRunning", false) === true
  readonly property bool closeOnMiddle: setting("middleClickCloses", true) !== false
  readonly property bool hoverPreview: setting("hoverPreview", true) !== false
  readonly property int previewRows: Math.max(1, Number(setting("previewRows", 6)))
  readonly property bool previewChannels: setting("previewChannels", false) === true
  readonly property string mutedIndicator: String(setting("mutedIndicator", "Bell"))

  // ------------------------------------------------------------------- theme
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgentColor: bar ? bar.urgent : Color.urgent
  // slick's own red and blue: DMs and group DMs in one, channels in the other.
  // An empty setting falls back to the theme's urgent color.
  readonly property color directColor: root.dmColorSetting.length > 0 ? root.dmColorSetting : root.urgentColor
  readonly property color channelColor: root.channelColorSetting.length > 0 ? root.channelColorSetting : root.urgentColor
  readonly property color badgeDigitColor: "#ffffff"
  readonly property color badgeTextColor: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ------------------------------------------------------------------ window
  readonly property var toplevels: Hyprland.toplevels ? (Hyprland.toplevels.values || []) : []
  readonly property var window: Model.findWindow(root.toplevels, root.windowClass)
  readonly property bool running: root.window !== null && root.window !== undefined
  readonly property bool focused: Model.isActive(root.window)
  readonly property bool parked: Model.isParked(root.window, root.specialName)
  readonly property bool specialShown: Model.specialShown(Hyprland, root.specialName)

  // ------------------------------------------------------------- slick state
  //
  // Gated on the window: slick writes `running: false` when it quits, but a
  // crash writes nothing, and a file left behind must not keep a badge up.
  readonly property string statePath: Quickshell.env("XDG_RUNTIME_DIR") + "/slick/state.json"
  property var rawState: null
  readonly property var slickState: root.running && root.rawState !== null
    && root.rawState.running !== false ? root.rawState : null
  readonly property bool stateLive: root.slickState !== null

  // Wall clock for relative times and DND expiry, coarse on purpose.
  property real nowSec: Date.now() / 1000
  Timer {
    interval: 20000
    repeat: true
    running: true
    onTriggered: root.nowSec = Date.now() / 1000
  }

  readonly property int attention: Model.attention(root.slickState)
  readonly property var totals: Model.totals(root.slickState)
  readonly property bool muted: Model.snoozed(root.slickState, root.nowSec)
  readonly property bool dndActive: Model.dndActive(root.slickState, root.nowSec)
  readonly property var preview: Model.previewRows(root.slickState, root.previewRows, root.previewChannels)

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.rawState = Model.parseState(text())
    onLoadFailed: root.rawState = null
  }

  // The watch only helps once the file exists; until slick's first write
  // lands, poke the reader ourselves.
  Timer {
    interval: 3000
    repeat: true
    running: root.running && root.rawState === null
    onTriggered: stateFile.reload()
  }

  onRunningChanged: {
    stateFile.reload()
    if (!root.running) return
    // A new slick window goes straight to the special workspace. `settled`
    // keeps a shell restart from yanking one that is already open.
    if (root.openInSpecial && settleTimer.settled) root.placeInSpecial()
    if (root.launchForeground && settleTimer.settled) foregroundTimer.restart()
  }

  Timer {
    id: foregroundTimer
    interval: 400
    onTriggered: root.showWindow()
  }
  Timer {
    id: settleTimer
    property bool settled: false
    interval: 3000
    running: true
    onTriggered: settled = true
  }

  property string homeWorkspace: ""
  onWindowChanged: root.rememberHome()
  Connections {
    target: root.window
    ignoreUnknownSignals: true
    function onWorkspaceChanged() { root.rememberHome() }
  }

  function rememberHome() {
    var name = Model.workspaceName(root.window)
    if (name.length > 0 && name.indexOf("special:") !== 0) root.homeWorkspace = name
  }

  // ------------------------------------------------------------------- icons
  // Outline (default) is slick's white mark with a faint dark edge, so it
  // reads on light and dark bars without the color mark's loudness. Color is
  // the mark as shipped; Mono is the white one tinted like a glyph; Glyph is
  // any Nerd Font character.
  readonly property url outlineIconSource: Qt.resolvedUrl("assets/slick-outline.svg")
  readonly property url colorIconSource: Qt.resolvedUrl("assets/slick.svg")
  readonly property url monoIconSource: Qt.resolvedUrl("assets/slick-white.svg")
  readonly property color tintColor: root.dmCount > 0 || root.combinedBadge ? root.directColor : root.channelColor
  readonly property color glyphColor: root.anyBadge && root.tintWhenUnread ? root.tintColor : root.foreground
  readonly property int glyphPixelSize: root.glyphSize > 0 ? root.glyphSize : Math.max(8, Style.bar.iconFont)
  // A pause you set fades the mark under the bell-off.
  readonly property real markOpacity: root.muted && root.mutedIndicator === "Bell" ? 0.45 : 1

  // Two counts, two corners. A manual pause hides both; Slack's scheduled
  // DND does not.
  readonly property bool badgesOn: !root.muted && root.badgeStyle !== "None" && !root.notInstalled
  readonly property int dmCount: root.badgesOn ? Model.directMessages(root.slickState) : 0
  readonly property int channelCount: root.badgesOn ? Model.channelBadgeCount(root.slickState, root.channelBadgeMode) : 0
  readonly property bool anyBadge: root.dmCount > 0 || root.channelCount > 0
  // "Combined" folds both into one badge in the DM color and corner.
  readonly property int combinedCount: root.dmCount + root.channelCount

  // Which corner each badge takes. Change these two to move them.
  readonly property string dmCorner: "bottom-right"
  readonly property string channelCorner: "top-right"

  // ----------------------------------------------------------------- actions
  function dispatch(luaForm, legacyForm) {
    Hyprland.dispatch(Hyprland.usingLua === true ? luaForm : legacyForm)
  }

  function windowAddress() {
    var target = root.window
    if (!target || !target.address) return ""
    var value = String(target.address)
    if (value.indexOf("0x") !== 0) value = "0x" + value
    return "address:" + value
  }

  // omarchy-launch-tui names the window org.omarchy.<command>, which is the
  // class this widget watches. The launch goes through Hyprland with window
  // rules, so a slick headed for the scratchpad is born there: it never
  // flashes on the current workspace or takes the focus on its way out, which
  // would also tell slick its open conversation was seen. Launch in
  // Foreground then shows it (onRunningChanged), however it was launched.
  function launch() {
    var cmd = root.launchCommand.length > 0 ? root.launchCommand
                                            : "omarchy-launch-tui --app-id=" + root.windowClass + " slick"
    var lua = {}
    if (root.openInSpecial) lua.workspace = "special:" + root.specialName + " silent"
    if (root.openInSpecial || !root.launchForeground) lua.no_initial_focus = true
    if (Hyprland.usingLua === true) {
      var rules = Object.keys(lua).map(function (k) {
        return k + " = " + (typeof lua[k] === "string" ? Model.luaString(lua[k]) : String(lua[k]))
      })
      Util.execArgv(["hyprctl", "eval", "hl.exec_cmd(" + Model.luaString(cmd) + ", { " + rules.join(", ") + " })"])
    } else {
      var legacy = []
      if (lua.workspace) legacy.push("workspace " + lua.workspace)
      if (lua.no_initial_focus) legacy.push("noinitialfocus")
      Util.execArgv(["hyprctl", "dispatch", "exec", (legacy.length > 0 ? "[" + legacy.join(";") + "] " : "") + cmd])
    }
  }

  function focusWindow() {
    var address = root.windowAddress()
    if (address.length === 0) return
    root.dispatch('hl.dsp.focus({ window = "' + address + '" })', "focuswindow " + address)
    refocusTimer.address = address
    refocusTimer.restart()
  }

  function park() {
    var address = root.windowAddress()
    if (address.length === 0) return
    if (root.parked && root.specialShown) { root.toggleSpecial(); return }
    var workspace = "special:" + root.specialName
    root.dispatch(
      'hl.dsp.window.move({ window = "' + address + '", workspace = "' + workspace + '", silent = true })',
      "movetoworkspacesilent " + workspace + "," + address)
  }

  function showWindow() {
    var address = root.windowAddress()
    if (address.length === 0) return
    if (root.openInSpecial && root.parked) {
      if (!root.specialShown) root.toggleSpecial()
      root.focusWindow()
      return
    }
    var target = root.homeWorkspace.length > 0 ? root.homeWorkspace
                                               : Model.activeWorkspaceName(Hyprland)
    if (target.length > 0) {
      root.dispatch(
        'hl.dsp.window.move({ window = "' + address + '", workspace = "' + target + '" })',
        "movetoworkspace " + target + "," + address)
    }
    root.focusWindow()
  }

  function toggleSpecial() {
    root.dispatch('hl.dsp.workspace.toggle_special("' + root.specialName + '")',
                  "togglespecialworkspace " + root.specialName)
  }

  function placeInSpecial() {
    var address = root.windowAddress()
    if (address.length === 0 || root.parked) return
    var workspace = "special:" + root.specialName
    root.dispatch(
      'hl.dsp.window.move({ window = "' + address + '", workspace = "' + workspace + '", silent = true })',
      "movetoworkspacesilent " + workspace + "," + address)
  }

  function closeWindow() {
    var address = root.windowAddress()
    if (address.length === 0) return
    root.dispatch('hl.dsp.window.close({ window = "' + address + '" })', "closewindow " + address)
  }

  // Ask slick to quit, so it writes its goodbye; closing the window is the
  // fallback for a slick that refuses (an old one, without `slick quit`) or
  // does not answer.
  function quit() {
    if (!root.running) return
    if (root.stateLive && !quitProc.running) {
      quitProc.running = true
      quitFallbackTimer.restart()
    } else {
      root.closeWindow()
    }
  }
  Process {
    id: quitProc
    command: ["slick", "quit"]
    onExited: function (code) { if (code !== 0) root.closeWindow() }
  }
  Timer {
    id: quitFallbackTimer
    interval: 4000
    onTriggered: if (root.running) root.closeWindow()
  }

  // Left click: open it, bring it back, put it away.
  function toggle() {
    if (!root.running) root.launch()
    else if (root.focused && root.hideMode === "Special workspace") root.park()
    else if (root.parked) root.showWindow()
    else root.focusWindow()
  }

  function open() {
    if (!root.running) root.launch()
    else if (root.parked) root.showWindow()
    else root.focusWindow()
  }

  // The window is brought up first: slick's own focuswindow lands after, on a
  // workspace that is already showing, so the two never toggle each other.
  function openConversation(row) {
    root.popupOpen = false
    root.open()
    Util.execArgv(Model.openArgs(row))
  }

  function pause(minutes) { Util.execArgv(["slick", "dnd", "pause", String(Math.max(1, Math.round(minutes)))]) }
  function resume() { Util.execArgv(["slick", "dnd", "resume"]) }

  function writeSetting(key, value) {
    var shell = root.bar ? root.bar.shell : null
    if (!shell || typeof shell.updateEntryInline !== "function") return
    var merged = JSON.parse(JSON.stringify(root.settings || {}))
    merged[key] = value
    shell.updateEntryInline(root.moduleName, merged)
  }

  Timer {
    id: refocusTimer
    property string address: ""
    interval: 120
    repeat: false
    onTriggered: if (address.length > 0)
      root.dispatch('hl.dsp.focus({ window = "' + address + '" })', "focuswindow " + address)
  }

  // One bar surface per monitor means N copies of this widget; only the first
  // may act on the session as a whole.
  function isPrimaryInstance() {
    var peers = root.bar && typeof root.bar.moduleWidgets === "function"
      ? root.bar.moduleWidgets(root.moduleName) : []
    return peers.length === 0 || peers[0] === root
  }

  Timer {
    interval: 2500
    repeat: false
    running: root.autoStart
    onTriggered: if (!root.running && root.isPrimaryInstance()) root.launch()
  }

  // ----------------------------------------------------------- hover preview
  property bool popupOpen: false
  property bool menuOpen: false
  function close() {
    root.popupOpen = false
    root.menuOpen = false
  }

  onMenuOpenChanged: {
    if (!menuOpen) return
    root.popupOpen = false
    if (root.notInstalled) root.checkInstalled()
    else if (!root.stateLive && !dndStatus.running) dndStatus.running = true
  }

  // ---------------------------------------------------------- not installed
  //
  // Without a `slick` on PATH the widget turns into a way to get it: a dimmed
  // mark, and a card with the install command. Assumed installed until the
  // first check says otherwise, so the bar does not flash the empty state at
  // login; re-checked every 30 s while missing, so an install is picked up
  // without restarting the shell.
  readonly property string installCommand: "curl -fsSL https://slick.leonavas.com/install.sh | sh"
  readonly property string websiteUrl: "https://slick.leonavas.com"
  property bool installed: true
  readonly property bool notInstalled: !root.installed && !root.running

  function checkInstalled() {
    if (!installCheck.running) installCheck.running = true
  }
  Process {
    id: installCheck
    command: ["bash", "-lc", "command -v slick >/dev/null"]
    onExited: function (code) { root.installed = code === 0 }
  }
  Component.onCompleted: root.checkInstalled()
  Timer {
    interval: 30000
    repeat: true
    running: !root.installed
    onTriggered: root.checkInstalled()
  }

  property bool copied: false
  Timer {
    id: copiedTimer
    interval: 1500
    onTriggered: root.copied = false
  }
  function copyInstallCommand() {
    Util.execArgv(["wl-copy", root.installCommand])
    root.copied = true
    copiedTimer.restart()
  }
  function installInTerminal() {
    Util.execArgv(["omarchy-launch-tui", "--app-id=org.omarchy.slick-install", "bash", "-c",
      root.installCommand + '; echo; read -n1 -rsp "Press any key to close"'])
  }
  function openWebsite() { Util.execArgv(["xdg-open", root.websiteUrl]) }

  // `slick dnd` talks to Slack itself, so pausing works with slick closed.
  // Whether a pause is on then comes from `slick dnd status` ("notifications
  // paused until ..." or "notifications on"), asked when the menu opens.
  property bool offlinePaused: false
  Process {
    id: dndStatus
    command: ["bash", "-lc", "slick dnd status"]
    stdout: StdioCollector {
      onStreamFinished: root.offlinePaused = /paused/i.test(this.text)
    }
  }

  // Available whenever slick is running and publishing, empty or not, muted
  // or not: "nothing waiting" is an answer worth hovering for.
  readonly property bool previewAvailable: ((root.hoverPreview && root.stateLive) || root.notInstalled)
    && !root.menuOpen
  readonly property bool previewHovered: button.tooltipHovered || popup.containsMouse

  onPreviewAvailableChanged: if (!previewAvailable) root.popupOpen = false
  onPreviewHoveredChanged: {
    if (root.previewHovered && root.previewAvailable) {
      closePreviewTimer.stop()
      if (!root.popupOpen) openPreviewTimer.restart()
    } else {
      openPreviewTimer.stop()
      if (root.popupOpen) closePreviewTimer.restart()
    }
  }
  onPopupOpenChanged: {
    if (!popupOpen) return
    root.nowSec = Date.now() / 1000
    if (root.notInstalled) root.checkInstalled()
  }

  Timer {
    id: openPreviewTimer
    interval: 350
    repeat: false
    onTriggered: if (root.previewHovered && root.previewAvailable) root.popupOpen = true
  }

  Timer {
    id: closePreviewTimer
    interval: 250
    repeat: false
    onTriggered: if (!root.previewHovered) root.popupOpen = false
  }

  // ------------------------------------------------------------------ layout
  visible: root.running || !root.hideWhenNotRunning
  implicitWidth: root.visible ? button.implicitWidth : 0
  implicitHeight: root.visible ? button.implicitHeight : 0

  readonly property string pauseLabel: {
    var until = Model.clockLabel(Model.dndUntil(root.slickState), root.nowSec)
    var head = root.muted ? "Notifications paused" : "Do not disturb"
    return until.length > 0 ? head + " until " + until : head
  }

  readonly property string tooltip: {
    if (!root.running) return "slick: click to open"
    var text = "slick"
    if (root.attention > 0) text += ": " + root.attention + " waiting"
    if (root.muted) text += " (notifications paused)"
    else if (root.parked) text += root.attention > 0 ? "" : ", hidden"
    return text
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    iconComponent: root.iconStyle === "Glyph" ? glyphIcon
      : root.iconStyle === "Mono" ? monoIcon
      : root.iconStyle === "Color" ? colorIcon : outlineIcon
    active: root.anyBadge
    useActiveColor: root.tintWhenUnread
    dimmed: root.notInstalled || (!root.running && root.dimWhenClosed)
      || (root.muted && root.mutedIndicator === "Dim")
    tooltipText: root.previewAvailable ? "" : root.tooltip
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) {
        if (root.closeOnMiddle && !root.notInstalled) root.quit()
      } else if (mouseButton === Qt.RightButton) {
        root.menuOpen = !root.menuOpen
      } else if (root.notInstalled) {
        // Nothing to launch: the left button opens the install card.
        root.menuOpen = false
        root.popupOpen = true
      } else {
        root.toggle()
      }
    }
  }

  Component {
    id: glyphIcon

    Item {
      opacity: root.markOpacity

      TextMetrics {
        id: metrics
        font.family: root.fontFamily
        font.pixelSize: root.glyphPixelSize
        text: root.glyph
      }

      Text {
        id: painted
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: painted.implicitWidth / 2
          - (metrics.tightBoundingRect.x + Math.max(1, metrics.tightBoundingRect.width) / 2)
        anchors.verticalCenterOffset: root.glyphOffsetY
        text: root.glyph
        color: root.glyphColor
        font.family: root.fontFamily
        font.pixelSize: root.glyphPixelSize
        renderType: Text.NativeRendering

        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }
    }
  }

  Component {
    id: outlineIcon

    Image {
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      sourceSize.width: Math.round(width * Screen.devicePixelRatio)
      sourceSize.height: Math.round(height * Screen.devicePixelRatio)
      source: root.outlineIconSource
      opacity: root.markOpacity
      smooth: true
    }
  }

  Component {
    id: colorIcon

    Image {
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      // Decode at physical pixels: the logical size leaves it blurry on HiDPI.
      sourceSize.width: Math.round(width * Screen.devicePixelRatio)
      sourceSize.height: Math.round(height * Screen.devicePixelRatio)
      source: root.colorIconSource
      opacity: root.markOpacity
      smooth: true
    }
  }

  Component {
    id: monoIcon

    Item {
      opacity: root.markOpacity

      Image {
        id: monoImage
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        sourceSize.width: Math.round(width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(height * Screen.devicePixelRatio)
        source: root.monoIconSource
        smooth: true
        // Hidden layer so the effect can sample it, the way the tray tints
        // symbolic icons.
        visible: false
        layer.enabled: true
      }

      MultiEffect {
        anchors.fill: monoImage
        source: monoImage
        colorization: 1.0
        colorizationColor: root.glyphColor
      }
    }
  }

  // A small count pill on one corner of the icon canvas. A dot fits inside
  // the canvas; a count is nearly as tall as the canvas, so it is centred on
  // the corner instead, out into the slot's padding, like a tray badge.
  component CornerBadge: Rectangle {
    id: cornerBadge

    property int count: 0
    property string corner: "bottom-right"
    readonly property bool dotOnly: root.badgeStyle === "Dot"
    readonly property int sx: corner.indexOf("left") >= 0 ? -1 : 1
    readonly property int sy: corner.indexOf("top") === 0 ? -1 : 1

    visible: count > 0
    z: 2
    height: dotOnly ? Math.round(Style.bar.iconCanvas * root.badgeScale)
                    : Math.round(digits.implicitHeight + Style.space(1))
    width: dotOnly ? height : Math.max(height, Math.round(digits.implicitWidth + Style.space(5)))
    radius: height / 2

    // Vertically a little past the corner: with a badge on each right-hand
    // corner, that keeps the two off each other and off most of the mark.
    readonly property int reachX: dotOnly ? Math.round((Style.bar.iconCanvas - height) / 2)
                                          : Math.round(Style.bar.iconCanvas / 2)
    readonly property int reachY: dotOnly ? reachX : Math.round(Style.bar.iconCanvas / 2 + 1)
    readonly property int maxX: Math.max(0, Math.round((root.width - width) / 2))
    readonly property int maxY: Math.max(0, Math.round((root.height - height) / 2))

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.horizontalCenterOffset: sx * Math.min(reachX, maxX)
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: sy * Math.min(reachY, maxY)

    Text {
      id: digits
      anchors.centerIn: parent
      visible: !cornerBadge.dotOnly
      text: Model.badgeLabel(cornerBadge.count)
      color: root.badgeDigitColor
      font.family: root.fontFamily
      font.pixelSize: Math.max(7, Math.round(Style.font.caption * 0.85))
      font.bold: true
      renderType: Text.NativeRendering
    }
  }

  CornerBadge {
    count: root.combinedBadge ? root.combinedCount : root.dmCount
    corner: root.dmCorner
    color: root.directColor
  }

  CornerBadge {
    count: root.combinedBadge ? 0 : root.channelCount
    corner: root.channelCorner
    color: root.channelColor
  }

  // Paused by hand: no badge. The mark fades and a bell-off takes the
  // badge's corner, outlined in the background color so it stays its own
  // shape where it overlaps the mark.
  Text {
    id: mutedMark
    readonly property int size: Math.max(8, Math.round(Style.bar.iconCanvas * 0.6))
    readonly property int corner: Math.round(Style.bar.iconCanvas / 2 - 1)
    visible: root.muted && root.mutedIndicator === "Bell"
    z: 2
    text: "󰂛"
    color: root.foreground
    style: Text.Outline
    styleColor: root.badgeTextColor
    font.family: root.fontFamily
    font.pixelSize: size
    renderType: Text.NativeRendering
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.horizontalCenterOffset: Math.min(corner, Math.max(0, Math.round((root.width - implicitWidth) / 2)))
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: Math.min(corner, Math.max(0, Math.round((root.height - implicitHeight) / 2)))
  }

  // ----------------------------------------------------------- preview card
  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    triggerMode: "hover"
    contentWidth: popup.fittedContentWidth(Style.space(400))
    contentHeight: popup.fittedContentHeight(root.notInstalled ? installColumn.implicitHeight
                                                               : previewColumn.implicitHeight)

    readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
    readonly property color dim: Qt.rgba(popup.fg.r, popup.fg.g, popup.fg.b, 0.6)

    // slick not installed: what it is and how to get it.
    Column {
      id: installColumn
      anchors.fill: parent
      spacing: Style.space(8)
      visible: root.notInstalled

      Text {
        text: "slick not detected"
        color: popup.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Text {
        width: parent.width
        text: "slick is a fast Slack client for the terminal. Install it with:"
        color: popup.dim
        wrapMode: Text.Wrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      // The command, in a box; a click copies it.
      Rectangle {
        width: parent.width
        height: commandText.implicitHeight + Style.space(14)
        radius: Style.spacing.labelGap
        color: Qt.rgba(popup.fg.r, popup.fg.g, popup.fg.b, copyArea.containsMouse ? 0.14 : 0.08)

        Text {
          id: commandText
          anchors.left: parent.left
          anchors.right: copyHint.left
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: root.installCommand
          color: popup.fg
          wrapMode: Text.WrapAnywhere
          font.family: "monospace"
          font.pixelSize: Style.font.caption
        }

        Text {
          id: copyHint
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: root.copied ? "Copied" : "Copy"
          color: root.copied ? popup.fg : popup.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: root.copied
        }

        MouseArea {
          id: copyArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.copyInstallCommand()
        }
      }

      Row {
        spacing: Style.space(12)

        Text {
          text: "Install in terminal"
          color: popup.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          font.underline: installArea.containsMouse

          MouseArea {
            id: installArea
            anchors.fill: parent
            anchors.margins: -Style.space(3)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.popupOpen = false
              root.installInTerminal()
            }
          }
        }

        Text {
          text: "slick.leonavas.com"
          color: siteArea.containsMouse ? popup.fg : popup.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.underline: true

          MouseArea {
            id: siteArea
            anchors.fill: parent
            anchors.margins: -Style.space(3)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.popupOpen = false
              root.openWebsite()
            }
          }
        }
      }
    }

    Column {
      id: previewColumn
      anchors.fill: parent
      spacing: Style.space(6)
      visible: !root.notInstalled

      Text {
        width: parent.width
        text: {
          var team = root.slickState && root.slickState.team ? String(root.slickState.team) : "slick"
          return root.attention > 0 ? team + " · " + root.attention + " waiting" : team
        }
        color: popup.fg
        elide: Text.ElideRight
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      // Paused (or in Slack's scheduled DND): when it ends, and a way out.
      Row {
        visible: root.dndActive
        spacing: Style.space(6)

        Text {
          text: "󰂛"
          color: popup.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          text: root.pauseLabel + " ·"
          color: popup.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          text: "Resume"
          color: popup.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          font.underline: resumeArea.containsMouse

          MouseArea {
            id: resumeArea
            anchors.fill: parent
            anchors.margins: -Style.space(3)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.resume()
          }
        }
      }

      PanelSeparator {
        foreground: popup.fg
      }

      Text {
        visible: root.preview.rows.length === 0
        text: root.totals.channels > 0 && !root.previewChannels
          ? "No unread DMs or mentions" : "No unread messages"
        color: popup.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Repeater {
        model: root.preview.rows

        Rectangle {
          id: convRow
          required property var modelData

          width: previewColumn.width
          height: convInner.implicitHeight + Style.space(12)
          radius: Style.spacing.labelGap
          color: rowArea.containsMouse
            ? Qt.rgba(popup.fg.r, popup.fg.g, popup.fg.b, 0.08) : "transparent"

          readonly property int indent: Math.round(Style.font.bodySmall * 1.5)

          Column {
            id: convInner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            spacing: Style.space(3)

            Item {
              width: parent.width
              height: nameText.implicitHeight

              Text {
                id: kindText
                width: convRow.indent
                text: convRow.modelData.glyph
                color: convRow.modelData.kind === "dm" || convRow.modelData.kind === "group"
                  ? root.directColor : root.channelColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                anchors.left: parent.left
                anchors.baseline: nameText.baseline
              }

              Text {
                id: nameText
                text: convRow.modelData.name
                color: popup.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                elide: Text.ElideRight
                anchors.left: kindText.right
                anchors.right: marker.left
                anchors.rightMargin: Style.space(8)
              }

              // Mention count as a pill; a plain unread conversation gets a dot.
              Rectangle {
                id: marker
                readonly property bool hasCount: convRow.modelData.mentions > 0
                visible: hasCount || convRow.modelData.unread
                width: hasCount ? Math.max(height, mentionText.implicitWidth + Style.space(8))
                                : Math.round(Style.font.bodySmall * 0.45)
                height: hasCount ? mentionText.implicitHeight + Style.space(2)
                                 : width
                radius: height / 2
                readonly property bool direct: convRow.modelData.kind === "dm" || convRow.modelData.kind === "group"
                color: direct ? root.directColor : hasCount ? root.channelColor : popup.dim
                anchors.right: timeText.left
                anchors.rightMargin: timeText.text !== "" ? Style.space(8) : 0
                anchors.verticalCenter: nameText.verticalCenter

                Text {
                  id: mentionText
                  anchors.centerIn: parent
                  visible: marker.hasCount
                  text: Model.badgeLabel(convRow.modelData.mentions)
                  color: root.badgeDigitColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              Text {
                id: timeText
                text: Model.relativeTime(convRow.modelData.latest, root.nowSec)
                color: popup.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.baseline: nameText.baseline
              }
            }

            Text {
              visible: text !== ""
              text: convRow.modelData.line
              x: convRow.indent
              width: convInner.width - x
              color: Qt.darker(popup.fg, 1.3)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
            }
          }

          MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openConversation(convRow.modelData)
          }
        }
      }

      Text {
        readonly property var parts: {
          var out = []
          if (root.preview.hidden > 0) out.push("+" + root.preview.hidden + " more")
          if (!root.previewChannels && root.totals.channels > 0)
            out.push("+" + root.totals.channels + (root.totals.channels === 1
              ? " channel with unread messages, no mentions" : " channels with unread messages, no mentions"))
          return out
        }
        visible: parts.length > 0
        text: parts.join(" · ")
        color: popup.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // ------------------------------------------------------------------- menu
  PopupCard {
    id: menu
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.menuOpen
    contentWidth: menu.fittedContentWidth(Style.space(210))
    contentHeight: menu.fittedContentHeight(menuColumn.implicitHeight)

    readonly property color fg: root.bar ? root.bar.foreground : Color.foreground

    component MenuEntry: Rectangle {
      id: entry

      property string label: ""
      property bool showCheck: false
      property bool checked: false
      property bool clickable: true
      property int indent: 0

      signal activated()

      width: menuColumn.width
      height: entryText.implicitHeight + Style.space(12)
      radius: Style.spacing.labelGap
      color: entry.clickable && entryArea.containsMouse && entry.enabled
        ? Qt.rgba(menu.fg.r, menu.fg.g, menu.fg.b, 0.08) : "transparent"
      opacity: !entry.enabled ? 0.4 : (entry.clickable ? 1 : 0.6)

      Text {
        id: entryText
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8) + entry.indent
        anchors.verticalCenter: parent.verticalCenter
        text: entry.label
        color: menu.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        visible: entry.showCheck
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: entry.checked ? "✓" : ""
        color: menu.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      MouseArea {
        id: entryArea
        anchors.fill: parent
        enabled: entry.clickable
        hoverEnabled: true
        cursorShape: entry.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: entry.activated()
      }
    }

    Column {
      id: menuColumn
      anchors.fill: parent
      spacing: Style.space(2)

      // slick not installed: only the ways to get it.
      MenuEntry {
        visible: root.notInstalled
        label: root.copied ? "Copied" : "Copy install command"
        onActivated: root.copyInstallCommand()
      }

      MenuEntry {
        visible: root.notInstalled
        label: "Install in terminal"
        onActivated: {
          root.close()
          root.installInTerminal()
        }
      }

      MenuEntry {
        visible: root.notInstalled
        label: "Open slick.leonavas.com"
        onActivated: {
          root.close()
          root.openWebsite()
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(2)
        visible: !root.notInstalled

        MenuEntry {
          label: !root.running ? "Open slick"
            : root.parked && !root.specialShown ? "Show slick"
            : (root.focused && root.hideMode === "Special workspace") ? "Hide slick"
            : "Focus slick"
          onActivated: {
            root.close()
            root.toggle()
          }
        }

        PanelSeparator { foreground: menu.fg }

        // Closed before the write: saving shell.json can rebuild the bar's
        // widgets, and a menu owned by a destroyed widget dies mid-click.
        MenuEntry {
          label: "Launch on Login"
          showCheck: true
          checked: root.autoStart
          onActivated: {
            root.close()
            root.writeSetting("autoStart", !root.autoStart)
          }
        }

        MenuEntry {
          label: "Launch in Foreground"
          showCheck: true
          checked: root.launchForeground
          onActivated: {
            root.close()
            root.writeSetting("launchForeground", !root.launchForeground)
          }
        }

        MenuEntry {
          label: "Open in Scratchpad"
          showCheck: true
          checked: root.openInSpecial
          onActivated: {
            root.close()
            root.writeSetting("openInSpecial", !root.openInSpecial)
          }
        }

        MenuEntry {
          label: "Group notifications"
          showCheck: true
          checked: root.combinedBadge
          onActivated: {
            root.close()
            root.writeSetting("badgeLayout", root.combinedBadge ? "Split" : "Combined")
          }
        }

        PanelSeparator { foreground: menu.fg }

        MenuEntry {
          visible: root.stateLive ? root.dndActive : root.offlinePaused
          label: "Resume notifications"
          onActivated: {
            root.close()
            root.resume()
          }
        }

        MenuEntry {
          label: "Pause notifications"
          clickable: false
        }

        Repeater {
          model: [
            { label: "30 minutes", minutes: 30 },
            { label: "1 hour", minutes: 60 },
            { label: "2 hours", minutes: 120 },
            { label: "Until tomorrow", minutes: -1 },
          ]

          MenuEntry {
            required property var modelData
            label: modelData.label
            indent: Style.space(10)
            onActivated: {
              root.close()
              root.pause(modelData.minutes > 0 ? modelData.minutes
                                               : Model.minutesUntilTomorrow(Date.now() / 1000))
            }
          }
        }

        PanelSeparator { foreground: menu.fg }

        MenuEntry {
          label: "Quit slick"
          enabled: root.running
          onActivated: {
            root.close()
            root.quit()
          }
        }
      }
    }
  }
}
