import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "smorg.timemachine"
  ipcTarget: "smorg.timemachine"

  // --- paths ---------------------------------------------------------------
  readonly property string home: Quickshell.env("HOME")
  readonly property string helperPath: "/usr/local/bin/omarchy-timemachine"
  readonly property string scheduleScript: home + "/.local/bin/timemachine-schedule"
  readonly property string setupPath: decodeURIComponent(
    String(Qt.resolvedUrl("setup.sh")).replace(/^file:\/\//, ""))

  // --- state ---------------------------------------------------------------
  property var snapshots: []
  property bool helperExists: false
  property bool authBlocked: false
  property bool loading: false
  property bool busy: false
  property string notice: ""
  property bool noticeIsError: false
  property int pendingDelete: -1
  property bool confirmReboot: false
  property int bootSnapshot: 0
  property int frame: 0
  property string lastListError: ""
  property bool scheduleEnabled: false
  property string scheduleFrequency: "daily"
  property string scheduleNextRun: ""
  property bool scheduleBusy: false

  readonly property bool setupNeeded: !helperExists || authBlocked
  readonly property int savedCount: Model.countSaved(snapshots)
  readonly property int refreshIntervalSec: Math.max(10, Number(setting("refreshIntervalSec", 60)))
  readonly property color fg: root.barForeground
  readonly property string ff: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property var sandFrames: ["󰚭", "󰔟", "󰞌"]
  readonly property string glyph: busy ? sandFrames[frame % sandFrames.length] : "󰔟"
  readonly property int rowHeight: Style.space(50)
  readonly property real listHeight: Math.min(Style.space(258),
    Math.max(0, snapshots.length) * (rowHeight + Style.space(2)))

  // --- helpers -------------------------------------------------------------
  function setNotice(text, isError) {
    notice = String(text || "")
    noticeIsError = isError === true
  }

  function refresh() {
    if (!helperExists || listProc.running) return
    loading = true
    listProc.running = true
  }

  function checkHelper() {
    checkProc.running = true
  }

  function takeSnapshot(label) {
    if (busy || !helperExists) return
    var text = String(label === undefined || label === null ? "" : label).trim()
    if (text === "") text = Model.defaultDescription(new Date())
    busy = true
    setNotice("", false)
    createProc.command = ["/usr/bin/sudo", "-n", helperPath, "create", text]
    createProc.running = true
    descriptionField.text = ""
  }

  function quickSnapshot() {
    if (!helperExists) {
      openSetup()
      return
    }
    if (!busy) takeSnapshot("")
  }

  function deleteSnapshot(number) {
    if (busy || number <= 0) return
    busy = true
    setNotice("", false)
    pendingDelete = -1
    deleteProc.command = ["/usr/bin/sudo", "-n", helperPath, "delete", String(number)]
    deleteProc.running = true
  }

  function parseList(text) {
    var parsed = Model.parseSnapshotList(text)
    loading = false
    if (!parsed.ok) {
      lastListError = parsed.error
      if (Model.isAuthProblem(parsed.error)) {
        authBlocked = true
        helperExists = true
      } else {
        var shortError = String(parsed.error || "Could not read snapshots.")
        if (shortError.length > 300) shortError = "Could not read the snapshot list."
        setNotice(shortError, true)
      }
      return
    }
    lastListError = ""
    authBlocked = false
    helperExists = true
    snapshots = parsed.snapshots
  }

  function handleAction(text, successMessage) {
    var result = Model.parseEnvelope(text)
    if (result.ok === false) {
      var message = String(result.error || "Action failed.")
      if (Model.isAuthProblem(message)) authBlocked = true
      setNotice(message, true)
    } else {
      setNotice(successMessage, false)
    }
  }

  function parseBoot(text) {
    bootSnapshot = Model.parseBootSnapshot(text)
  }

  function openInTerminal(command) {
    if (!root.bar) return
    root.close()
    root.bar.run("omarchy-launch-terminal bash -lc " + root.bar.shellQuote(command))
  }

  function openSetup() {
    openInTerminal("sudo bash " + setupPath)
  }

  function openRestoreTerminal() {
    openInTerminal("omarchy-snapshot restore")
  }

  function rebootForRestore() {
    confirmReboot = false
    if (!root.bar) return
    root.close()
    root.bar.run("omarchy system reboot")
  }

  function refreshSchedule() {
    if (!scheduleStatusProc.running) scheduleStatusProc.running = true
  }

  function setSchedule(freq) {
    if (scheduleBusy) return
    scheduleBusy = true
    scheduleSetProc.command = [scheduleScript, "set", String(freq)]
    scheduleSetProc.running = true
  }

  function parseScheduleStatus(raw) {
    var text = String(raw || "").trim()
    if (text === "") return
    var data
    try { data = JSON.parse(text) } catch (e) { return }
    if (!data || typeof data !== "object") return
    scheduleEnabled = data.enabled === true
    scheduleFrequency = String(data.frequency || "daily")
    scheduleNextRun = String(data.nextRun || "")
  }

  // --- lifecycle -----------------------------------------------------------
  onOpenedChanged: {
    if (!opened) return
    pendingDelete = -1
    confirmReboot = false
    setNotice("", false)
    if (!helperExists) checkHelper()
    else refresh()
    refreshSchedule()
  }

  Component.onCompleted: {
    bootProc.running = true
    checkHelper()
  }

  Timer {
    interval: 220
    repeat: true
    running: root.busy
    onTriggered: root.frame = (root.frame + 1) % root.sandFrames.length
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: root.opened && root.helperExists && !root.busy
    onTriggered: root.refresh()
  }

  // --- processes -----------------------------------------------------------
  Process {
    id: checkProc
    command: ["/usr/bin/test", "-x", root.helperPath]
    onExited: function(exitCode) {
      root.helperExists = exitCode === 0
      if (root.helperExists) root.refresh()
      else root.loading = false
    }
  }

  Process {
    id: bootProc
    command: ["/usr/bin/findmnt", "-no", "FSROOT", "/"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseBoot(text)
    }
  }

  Process {
    id: listProc
    command: ["/usr/bin/sudo", "-n", root.helperPath, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseList(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message === "") return
        if (Model.isAuthProblem(message)) {
          root.authBlocked = true
          root.helperExists = true
          root.loading = false
        }
      }
    }
  }

  Process {
    id: createProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleAction(text, "Snapshot captured.")
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message !== "" && Model.isAuthProblem(message)) root.authBlocked = true
      }
    }
    onExited: function(exitCode) {
      root.busy = false
      if (root.helperExists) root.refresh()
    }
  }

  Process {
    id: deleteProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleAction(text, "Snapshot deleted.")
    }
    onExited: function(exitCode) {
      root.busy = false
      if (root.helperExists) root.refresh()
    }
  }

  Process {
    id: scheduleStatusProc
    command: [root.scheduleScript, "status-json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseScheduleStatus(text)
    }
  }

  Process {
    id: scheduleSetProc
    onExited: function(exitCode) {
      root.scheduleBusy = false
      root.refreshSchedule()
    }
  }

  // --- bar button ----------------------------------------------------------
  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    tooltipText: ""
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.quickSnapshot()
      else if (mouseButton === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  // A tiny pulse on the corner while a snapshot is being written.
  Rectangle {
    visible: root.busy
    width: Style.space(4)
    height: width
    radius: width / 2
    color: Commons.Color.accent
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: Style.space(4)
    anchors.topMargin: Style.space(4)
  }

  // --- popup ---------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: descriptionField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- hero ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroGlyph.implicitHeight, heroText.implicitHeight)

          Text {
            id: heroGlyph
            textFormat: Text.PlainText
            text: root.glyph
            color: root.fg
            font.family: root.ff
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroText
            anchors.left: heroGlyph.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Time Machine"
              color: root.fg
              font.family: root.ff
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: root.setupNeeded
                ? "One-time setup needed"
                : (root.savedCount + (root.savedCount === 1 ? " snapshot" : " snapshots")
                  + " · " + (root.busy ? "capturing…" : "btrfs system"))
              color: Qt.darker(root.fg, 1.4)
              font.family: root.ff
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        // ---------- one-time setup ----------
        Column {
          visible: root.setupNeeded
          width: parent.width
          spacing: Style.space(10)

          PanelSeparator { foreground: root.fg }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "Snapshots are read through a tiny root-owned helper. Run the setup once in a terminal; it installs the helper and a narrow sudoers rule."
            color: root.fg
            font.family: root.ff
            font.pixelSize: Style.font.bodySmall
          }

          Button {
            text: "Open setup terminal"
            iconText: "󰕥"
            foreground: root.fg
            fontFamily: root.ff
            bordered: true
            onClicked: root.openSetup()
          }

          Text {
            width: parent.width
            wrapMode: Text.WrapAnywhere
            textFormat: Text.PlainText
            text: "sudo bash " + root.setupPath
            color: Qt.darker(root.fg, 1.6)
            font.family: root.ff
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: root.lastListError !== "" && !root.authBlocked
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.lastListError
            color: Commons.Color.urgent
            font.family: root.ff
            font.pixelSize: Style.font.caption
          }
        }

        // ---------- new snapshot ----------
        Column {
          visible: !root.setupNeeded
          width: parent.width
          spacing: Style.space(10)

          Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: descriptionField
              width: parent.width - createButton.width - parent.spacing
              placeholderText: "What are you about to break? (optional)"
              foreground: root.fg
              font.family: root.ff
              enabled: !root.busy
              onAccepted: root.takeSnapshot(descriptionField.text)
            }

            Button {
              id: createButton
              text: root.busy ? "Capturing…" : "Snapshot"
              iconText: root.busy ? root.glyph : "󰵝"
              foreground: root.fg
              fontFamily: root.ff
              bordered: true
              enabled: !root.busy
              onClicked: root.takeSnapshot(descriptionField.text)
            }
          }

          Text {
            visible: root.notice !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            maximumLineCount: 5
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.notice
            color: root.noticeIsError ? Commons.Color.urgent : Qt.darker(root.fg, 1.3)
            font.family: root.ff
            font.pixelSize: Style.font.caption
          }
        }

        // ---------- snapshot list ----------
        Column {
          visible: !root.setupNeeded
          width: parent.width
          spacing: Style.space(8)

          PanelSeparator { foreground: root.fg }

          Item {
            width: parent.width
            implicitHeight: headerRow.implicitHeight

            Row {
              id: headerRow
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              PanelSectionHeader {
                text: "SNAPSHOTS"
                foreground: root.fg
                fontFamily: root.ff
              }

              Text {
                visible: root.loading
                text: "reading…"
                color: Qt.darker(root.fg, 1.6)
                font.family: root.ff
                font.pixelSize: Style.font.caption
              }
            }

            PanelActionButton {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰑐"
              tooltipText: "Refresh"
              foreground: root.fg
              fontFamily: root.ff
              enabled: !root.loading && root.helperExists
              onClicked: root.refresh()
            }
          }

          // Delete confirmation replaces the list header for a moment so it is
          // impossible to miss and impossible to trigger by accident. Buttons are
          // anchored to the right edge so they can never overflow off-screen; the
          // prompt text elides instead.
          Item {
            visible: root.pendingDelete > 0
            width: parent.width
            implicitHeight: Math.max(deletePrompt.implicitHeight, deleteActions.implicitHeight)

            Text {
              id: deletePrompt
              anchors.left: parent.left
              anchors.right: deleteActions.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Delete snapshot #" + root.pendingDelete + "?"
              color: Commons.Color.urgent
              font.family: root.ff
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Row {
              id: deleteActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Button {
                text: "Keep"
                foreground: root.fg
                fontFamily: root.ff
                fontSize: Style.font.bodySmall
                bordered: true
                onClicked: root.pendingDelete = -1
              }

              Button {
                text: "Delete"
                foreground: Commons.Color.urgent
                fontFamily: root.ff
                fontSize: Style.font.bodySmall
                bordered: true
                onClicked: root.deleteSnapshot(root.pendingDelete)
              }
            }
          }

          Text {
            visible: !root.loading && root.listHeight === 0
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "No snapshots yet. Take one before your next update."
            color: Qt.darker(root.fg, 1.5)
            font.family: root.ff
            font.pixelSize: Style.font.bodySmall
          }

          ListView {
            id: snapshotList
            width: parent.width
            height: root.listHeight
            visible: height > 0
            clip: true
            spacing: Style.space(2)
            model: root.snapshots
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
              required property var modelData
              required property int index

              width: snapshotList.width
              height: root.rowHeight

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: rowHover.containsMouse
                  ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
                  : "transparent"
              }

              MouseArea {
                id: rowHover
                anchors.fill: parent
                hoverEnabled: true
              }

              Text {
                id: numberText
                textFormat: Text.PlainText
                text: modelData.current ? "now" : "#" + modelData.number
                color: modelData.current ? Commons.Color.accent : Qt.darker(root.fg, 1.35)
                font.family: root.ff
                font.pixelSize: Style.font.bodySmall
                font.bold: modelData.current
                width: Style.space(38)
                anchors.left: parent.left
                anchors.leftMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                anchors.left: numberText.right
                anchors.right: actionSlot.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: Model.describe(modelData)
                  color: root.fg
                  font.family: root.ff
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: Model.subtitle(modelData)
                  color: Qt.darker(root.fg, 1.6)
                  font.family: root.ff
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              Item {
                id: actionSlot
                width: Style.space(30)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter

                PanelActionButton {
                  anchors.centerIn: parent
                  visible: !modelData.current
                  iconText: "󰩺"
                  tooltipText: "Delete snapshot #" + modelData.number
                  hoverColor: Commons.Color.urgent
                  foreground: root.fg
                  fontFamily: root.ff
                  enabled: !root.busy
                  onClicked: root.pendingDelete = modelData.number
                }
              }
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "Snapper keeps the newest 5 plus 5 important snapshots. Snapshots cover the system (@), not /home."
            color: Qt.darker(root.fg, 1.7)
            font.family: root.ff
            font.pixelSize: Style.font.caption
          }
        }

        // ---------- automatic snapshots ----------
        Column {
          visible: !root.setupNeeded
          width: parent.width
          spacing: Style.space(8)

          PanelSeparator { foreground: root.fg }

          Item {
            width: parent.width
            implicitHeight: scheduleHeaderRow.implicitHeight

            Row {
              id: scheduleHeaderRow
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              PanelSectionHeader {
                text: "AUTOMATIC SNAPSHOTS"
                foreground: root.fg
                fontFamily: root.ff
              }

              Text {
                visible: root.scheduleBusy
                text: "…"
                color: Qt.darker(root.fg, 1.6)
                font.family: root.ff
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(150)
              horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
              text: !root.scheduleEnabled ? "off"
                : (root.scheduleNextRun !== "" ? "next " + root.scheduleNextRun : "on")
              color: root.scheduleEnabled ? Qt.darker(root.fg, 1.4) : Qt.darker(root.fg, 1.8)
              font.family: root.ff
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Row {
            id: scheduleRow
            width: parent.width
            spacing: Style.space(6)

            readonly property var options: [
              { value: "off", label: "Off" },
              { value: "6h", label: "6h" },
              { value: "daily", label: "Daily" },
              { value: "weekly", label: "Weekly" }
            ]
            readonly property real cellWidth: (width - spacing * (options.length - 1)) / options.length

            Repeater {
              model: scheduleRow.options
              Button {
                required property var modelData
                width: scheduleRow.cellWidth
                text: modelData.label
                foreground: root.fg
                fontFamily: root.ff
                fontSize: Style.font.bodySmall
                bordered: true
                active: modelData.value === "off"
                  ? !root.scheduleEnabled
                  : (root.scheduleEnabled && root.scheduleFrequency === modelData.value)
                enabled: !root.scheduleBusy
                onClicked: root.setSchedule(modelData.value)
              }
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "A scheduled snapshot lands in the rolling pool and never evicts a manual one."
            color: Qt.darker(root.fg, 1.7)
            font.family: root.ff
            font.pixelSize: Style.font.caption
          }
        }

        // ---------- restore ----------
        Column {
          visible: !root.setupNeeded
          width: parent.width
          spacing: Style.space(8)

          PanelSeparator { foreground: root.fg }

          Text {
            visible: root.bootSnapshot > 0
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "You booted from snapshot #" + root.bootSnapshot + ". Make it the system again from a terminal; you will be asked to confirm."
            color: Commons.Color.accent
            font.family: root.ff
            font.pixelSize: Style.font.bodySmall
          }

          Button {
            visible: root.bootSnapshot > 0
            text: "Make this snapshot permanent"
            iconText: "󰦛"
            foreground: root.fg
            fontFamily: root.ff
            bordered: true
            onClicked: root.openRestoreTerminal()
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "To roll back: reboot, choose a snapshot in the Limine boot menu, then run  omarchy-snapshot restore  from a terminal once you are in it."
            color: Qt.darker(root.fg, 1.6)
            font.family: root.ff
            font.pixelSize: Style.font.caption
          }

          Row {
            visible: !root.confirmReboot
            spacing: Style.space(8)

            Button {
              text: "Reboot to restore…"
              iconText: "󰜉"
              foreground: root.fg
              fontFamily: root.ff
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.confirmReboot = true
            }
          }

          Item {
            visible: root.confirmReboot
            width: parent.width
            implicitHeight: Math.max(rebootPrompt.implicitHeight, rebootActions.implicitHeight)

            Text {
              id: rebootPrompt
              anchors.left: parent.left
              anchors.right: rebootActions.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Reboot now? Save your work first."
              color: Commons.Color.urgent
              font.family: root.ff
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Row {
              id: rebootActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Button {
                text: "Cancel"
                foreground: root.fg
                fontFamily: root.ff
                fontSize: Style.font.bodySmall
                bordered: true
                onClicked: root.confirmReboot = false
              }

              Button {
                text: "Reboot"
                foreground: Commons.Color.urgent
                fontFamily: root.ff
                fontSize: Style.font.bodySmall
                bordered: true
                onClicked: root.rebootForRestore()
              }
            }
          }
        }
      }
    }
  }
}
