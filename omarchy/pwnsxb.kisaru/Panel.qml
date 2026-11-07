import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "strings.js" as Strings

// One bar icon that opens a small menu: Anime / Manga / Novels. Each entry
// runs `kisaru <key>`, which toggles the matching reader panel
// (the wrapper talks to the app over IPC).
//
// The rows are qs.Ui Buttons (icon + left-aligned label, shared hover/selected
// states) inside the kit's KeyboardPanel, so the popup reads like the rest of
// Omarchy instead of a hand-drawn column.
Panel {
  id: root
  moduleName: "pwnsxb.kisaru"
  ipcTarget: "pwnsxb.kisaru"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The app's settings.json, read-only: its language, when set, beats LANG but
  // not QS_LANG (same precedence as services/I18n.qml). Panel.qml cannot import
  // Kisaru's I18n, so the table and resolver live in strings.js.
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
  readonly property string settingsFile: Strings.settingsFile(root.configHome, false)
  readonly property string legacySettingsFile: Strings.settingsFile(root.configHome, true)
  // The files to try, in order: the app's own folder first, the inherited one
  // only when the first is missing. Sequential on purpose: probing both at
  // once lets completion order decide, so the legacy file could win while the
  // new one exists (review finding R3-SettingsProbeRace).
  readonly property var _settingsCandidates: Strings.settingsCandidates(root.configHome)
  property int _candidateIndex: 0
  readonly property string settingsPath: root._settingsCandidates[root._candidateIndex]
  property string settingsLang: ""

  readonly property string lang:
    Strings.resolveLanguage(Quickshell.env("QS_LANG"), root.settingsLang, Quickshell.env("LANG"))

  function t(key) {
    return Strings.t(root.lang, key)
  }

  // Glyphs are Material Design Icons (Nerd Font). Swap freely.
  readonly property var entries: [
    { key: "anime", label: root.t("entry.anime"), icon: "󰿊" },
    { key: "manga", label: root.t("entry.manga"), icon: "󰃶" },
    { key: "novel", label: root.t("entry.novel"), icon: "󰗚" }
  ]

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function launch(key) {
    opener.command = ["kisaru", key]
    opener.running = true
    root.close()
  }

  Process {
    id: opener
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  // Read the app's language once; the panels' own reader would be a second
  // writer of the same file, so this one never writes.
  FileView {
    id: reader
    path: root.settingsPath
    onLoaded: root.settingsLang = Strings.languageFromSettings(reader.text())
    onLoadFailed: {
      // The new file is missing: try the inherited one once, then settle.
      if (root._candidateIndex === 0) {
        root._candidateIndex = 1
        return
      }
      root.settingsLang = ""
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰂺"
    tooltipText: root.t("menu.tooltip")
    onPressed: function(code) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(240))
    contentHeight: panel.fittedContentHeight(menu.implicitHeight)

    Column {
      id: menu
      width: parent.width
      spacing: Style.spacing.sm

      PanelSectionHeader {
        width: parent.width
        text: root.t("menu.title")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Repeater {
        model: root.entries

        delegate: Button {
          required property var modelData

          width: menu.width
          leftAlign: true
          bordered: true
          iconText: modelData.icon
          text: modelData.label
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.launch(modelData.key)
        }
      }
    }
  }
}
