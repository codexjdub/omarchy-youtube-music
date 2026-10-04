import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui as Ui
import "PlaybackModel.js" as PlaybackModel

Ui.Panel {
  id: root
  moduleName: "dj.youtube-music"
  ipcTarget: "dj.youtube-music"

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var appWindows: Hyprland.toplevels.values
  property var appPlayerPids: []
  property var player: null

  readonly property bool showTitle: setting("showTitle", true)
  readonly property int maxTitleWidth: Math.max(80, Number(setting("maxTitleWidth", 180)))
  readonly property bool showWhenIdle: setting("showWhenIdle", true)
  readonly property bool browserFallback: setting("browserFallback", true)
  readonly property bool isolatedProfile: setting("isolatedProfile", true)
  readonly property bool vertical: bar ? bar.vertical : false
  property string launchError: ""

  readonly property bool playing: player && player.playbackState === MprisPlaybackState.Playing
  readonly property string artUrl: player ? (player.trackArtUrl || player.artUrl || "") : ""
  readonly property string artistName: player ? (player.trackArtist || "") : ""
  readonly property string trackTitle: player ? (player.trackTitle || "Untitled track") : ""
  readonly property string barLabel: trackTitle + (artistName ? " — " + artistName : "")
  readonly property string albumName: player ? (player.trackAlbum || "") : ""
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color dimForeground: Qt.darker(contentForeground, 1.45)
  readonly property color barColor: bar ? bar.barForeground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  visible: player !== null || showWhenIdle
  implicitWidth: visible ? controls.implicitWidth : 0
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

  function selectPlayer() {
    player = PlaybackModel.select(players, player, browserFallback, appPlayerPids)
  }

  function updateAppPlayerPids() {
    appPlayerPids = PlaybackModel.appPids(appWindows.map(function(window) {
      return window.lastIpcObject
    }))
  }

  // Hyprland's complete window records are refreshed on request. A newly
  // opened app otherwise has no PID/class in lastIpcObject until shell restart.
  Timer {
    id: windowInfoTimer
    interval: 80
    onTriggered: Hyprland.refreshToplevels()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (["openwindow", "closewindow", "windowtitle", "windowtitlev2"].indexOf(event.name) !== -1)
        windowInfoTimer.restart()
    }
  }

  Instantiator {
    model: root.appWindows
    delegate: Connections {
      required property var modelData
      target: modelData
      function onLastIpcObjectChanged() { root.updateAppPlayerPids() }
    }
  }

  function togglePlayback() {
    if (!player) return
    if (player.canTogglePlaying) player.togglePlaying()
    else if (player.isPlaying && player.canPause) player.pause()
    else if (!player.isPlaying && player.canPlay) player.play()
  }

  function previousTrack() {
    if (player && player.canGoPrevious) player.previous()
  }

  function nextTrack() {
    if (player && player.canGoNext) player.next()
  }

  IpcHandler {
    enabled: root.manageIpc
    target: root.ipcTarget + ".controls"

    function status(): string {
      return JSON.stringify({
        appPids: root.appPlayerPids,
        selected: root.player ? root.player.dbusName : "",
        label: root.barLabel,
        players: root.players.map(function(candidate) {
          return {
            name: candidate.dbusName,
            title: candidate.trackTitle,
            artist: candidate.trackArtist,
            playing: candidate.isPlaying,
            matchScore: PlaybackModel.score(candidate, root.browserFallback, root.appPlayerPids),
            canPlay: candidate.canPlay,
            canPause: candidate.canPause,
            canGoNext: candidate.canGoNext,
            canGoPrevious: candidate.canGoPrevious
          }
        })
      })
    }

    function playPause(): void { root.togglePlayback() }
    function previous(): void { root.previousTrack() }
    function next(): void { root.nextTrack() }
  }

  function openYoutubeMusic() {
    if (appLauncher.running) return
    launchError = ""
    appLauncher.command = [
      "bash",
      decodeURIComponent(Qt.resolvedUrl("launch.sh").toString().replace(/^file:\/\//, "")),
      isolatedProfile ? "--isolated" : "--shared",
      "--prepare"
    ]
    appLauncher.running = true
  }

  Process {
    id: appLauncher
    stdout: StdioCollector { id: launchStdout }
    stderr: StdioCollector { id: launchStderr }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0 || exitStatus !== 0) {
        root.launchError = launchStderr.text.trim() || "Could not open YouTube Music. Check that a supported Chromium browser is installed."
        root.open()
        return
      }
      try {
        var command = JSON.parse(launchStdout.text)
        if (!Array.isArray(command) || !command.every(function(arg) { return typeof arg === "string" }))
          throw new Error("Invalid launcher response")
        if (command.length > 0) Quickshell.execDetached(command)
      } catch (error) {
        root.launchError = "Could not prepare the YouTube Music app: " + error
        root.open()
      }
    }
  }

  function formatTime(seconds) {
    if (!seconds || seconds <= 0) return "0:00"
    var totalSeconds = Math.floor(seconds)
    var minutes = Math.floor(totalSeconds / 60)
    var remainingSeconds = totalSeconds % 60
    return minutes + ":" + (remainingSeconds < 10 ? "0" : "") + remainingSeconds
  }

  Component.onCompleted: {
    windowInfoTimer.start()
    updateAppPlayerPids()
    selectPlayer()
  }
  onPlayersChanged: selectPlayer()
  onAppWindowsChanged: {
    updateAppPlayerPids()
    windowInfoTimer.restart()
  }
  onAppPlayerPidsChanged: selectPlayer()
  onBrowserFallbackChanged: selectPlayer()

  Instantiator {
    model: root.players
    onObjectAdded: root.selectPlayer()
    onObjectRemoved: root.selectPlayer()

    delegate: Connections {
      required property var modelData
      target: modelData

      function onReady() { root.selectPlayer() }
      function onMetadataChanged() { root.selectPlayer() }
      function onIdentityChanged() { root.selectPlayer() }
      function onDesktopEntryChanged() { root.selectPlayer() }
      function onIsPlayingChanged() { root.selectPlayer() }
      function onTrackTitleChanged() { root.selectPlayer() }
      function onTrackArtistChanged() { root.selectPlayer() }
      function onTrackAlbumChanged() { root.selectPlayer() }
      function onTrackArtUrlChanged() { root.selectPlayer() }
    }
  }

  Timer {
    interval: 1000
    running: root.playing
    repeat: true
    onTriggered: if (root.player) root.player.positionChanged()
  }

  Row {
    id: controls
    anchors.centerIn: parent
    spacing: 0

    Ui.BarIconButton {
      id: panelButton
      bar: root.bar
      text: "󰗃"
      tooltipText: (root.player
        ? root.trackTitle + (root.artistName ? " — " + root.artistName : "") + "\n"
        : "") + "YouTube Music app · " + (root.isolatedProfile ? "separate browser profile" : "shared browser profile")
        + "\nLeft-click: open app · Right-click: playback controls"
      active: root.opened
      onPressed: function(buttonCode) {
        if (buttonCode === Qt.MiddleButton) root.togglePlayback()
        else if (buttonCode === Qt.RightButton) root.toggle()
        else root.openYoutubeMusic()
      }
      onWheelMoved: function(delta) {
        if (delta > 0) root.previousTrack()
        else if (delta < 0) root.nextTrack()
      }
    }

    Item {
      visible: root.player !== null && root.showTitle && !root.vertical
      width: visible ? Math.min(root.maxTitleWidth, titleMetrics.advanceWidth) + Style.space(8) : 0
      height: root.implicitHeight

      TextMetrics {
        id: titleMetrics
        text: root.barLabel
        font: titleText.font
      }

      TextMetrics {
        id: artistMetrics
        text: root.artistName
        font: titleText.font
      }

      Text {
        id: titleText
        anchors.left: parent.left
        anchors.right: artistText.visible ? artistSeparator.left : parent.right
        anchors.rightMargin: artistText.visible ? Style.space(4) : 0
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.trackTitle
        color: root.barColor
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        id: artistSeparator
        visible: artistText.visible
        anchors.right: artistText.left
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        text: "—"
        color: root.barColor
        font: titleText.font
      }

      Text {
        id: artistText
        visible: root.artistName !== ""
        width: visible ? Math.min(artistMetrics.advanceWidth, parent.width * 0.45) : 0
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.artistName
        color: root.barColor
        opacity: 0.85
        font: titleText.font
        elide: Text.ElideRight
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onEntered: if (root.bar) root.bar.showTooltip(parent, root.barLabel)
        onExited: if (root.bar) root.bar.hideTooltip(parent)
        onClicked: function(mouse) {
          if (mouse.button === Qt.MiddleButton) root.togglePlayback()
          else if (mouse.button === Qt.RightButton) root.toggle()
          else root.openYoutubeMusic()
        }
        onWheel: function(wheel) {
          if (wheel.angleDelta.y > 0) root.previousTrack()
          else if (wheel.angleDelta.y < 0) root.nextTrack()
        }
      }
    }

    Ui.BarIconButton {
      visible: root.player !== null
      bar: root.bar
      text: "󰒮"
      tooltipText: "Previous track"
      interactive: root.player !== null && root.player.canGoPrevious
      dimmed: !interactive
      onPressed: root.previousTrack()
    }

    Ui.BarIconButton {
      visible: root.player !== null
      bar: root.bar
      text: root.playing ? "󰏤" : "󰐊"
      tooltipText: root.playing ? "Pause" : "Play"
      interactive: root.player !== null
      dimmed: !interactive
      onPressed: root.togglePlayback()
    }

    Ui.BarIconButton {
      visible: root.player !== null
      bar: root.bar
      text: "󰒭"
      tooltipText: "Next track"
      interactive: root.player !== null && root.player.canGoNext
      dimmed: !interactive
      onPressed: root.nextTrack()
    }
  }

  Ui.KeyboardPanel {
    id: popup
    anchorItem: panelButton
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight)

    Ui.PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dx > 0) root.nextTrack()
        else if (dx < 0) root.previousTrack()
      }
      onActivateRequested: root.player ? root.togglePlayback() : root.openYoutubeMusic()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === " ") root.togglePlayback()
        else if (text === "n") root.nextTrack()
        else if (text === "p") root.previousTrack()
        else if (text === "o") root.openYoutubeMusic()
      }

      Column {
        id: contentColumn
        width: parent.width
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(10)

        RowLayout {
          width: parent.width
          spacing: Style.space(12)

          Column {
            Layout.fillWidth: true
            spacing: Style.space(4)

            Text {
              width: parent.width
              text: "YouTube Music app"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: root.isolatedProfile ? "Separate browser profile" : "Shared browser profile"
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Ui.Button {
            text: "Open app"
            foreground: root.contentForeground
            onClicked: root.openYoutubeMusic()
          }
        }

        Ui.PanelSeparator {
          width: parent.width
          foreground: root.contentForeground
        }

        Text {
          visible: root.launchError !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.launchError
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        Row {
          visible: root.player !== null
          width: parent.width
          spacing: Style.space(12)

          Ui.BorderSurface {
            id: cover
            width: Style.space(88)
            height: width
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.contentForeground, Color.accent)
            borderSpec: Border.controlSpec("normal", root.contentForeground, Color.accent)

            Image {
              id: albumArt
              anchors.fill: parent
              anchors.margins: Style.space(2)
              visible: root.artUrl !== "" && status !== Image.Error
              source: root.artUrl
              sourceSize.width: Style.space(220)
              sourceSize.height: Style.space(220)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: true
            }

            Text {
              anchors.centerIn: parent
              visible: root.artUrl === "" || albumArt.status === Image.Error
              text: "󰝚"
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.displayLarge
            }
          }

          Column {
            width: parent.width - cover.width - parent.spacing
            anchors.verticalCenter: cover.verticalCenter
            spacing: Style.space(4)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.trackTitle
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              wrapMode: Text.Wrap
              elide: Text.ElideRight
              maximumLineCount: 2
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.artistName || "YouTube Music"
              color: root.contentForeground
              opacity: 0.82
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              maximumLineCount: 1
            }

            Text {
              visible: root.albumName !== ""
              width: parent.width
              textFormat: Text.PlainText
              text: root.albumName
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              maximumLineCount: 1
            }
          }
        }

        Column {
          visible: root.player !== null
          width: parent.width
          spacing: Style.space(2)

          Ui.PanelSlider {
            id: progressSlider
            width: parent.width
            bar: root.bar
            minimum: 0
            maximum: root.player ? Math.max(1, root.player.length) : 1
            value: root.player ? root.player.position : 0
            step: 5
            enabled: root.player !== null && root.player.canSeek && root.player.length > 0
            opacity: enabled ? 1 : 0.45
            trackHeight: Math.max(3, Style.space(3))
            knobSize: Style.space(10)
            onReleased: function(nextPosition) {
              if (root.player && root.player.canSeek && root.player.length > 0) root.player.position = nextPosition
            }
          }

          RowLayout {
            width: parent.width

            Text {
              text: root.formatTime(progressSlider.dragging ? progressSlider.liveValue : (root.player ? root.player.position : 0))
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }

            Item { Layout.fillWidth: true }

            Text {
              text: root.formatTime(root.player ? root.player.length : 0)
              color: root.dimForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Item {
          visible: root.player !== null
          width: parent.width
          height: Style.space(36)

          Row {
            anchors.centerIn: parent
            spacing: Style.space(14)

            Ui.PanelActionButton {
              iconText: "󰒮"
              tooltipText: "Previous track"
              foreground: root.contentForeground
              hoverColor: Color.accent
              fontFamily: root.contentFontFamily
              size: Style.space(30)
              enabled: root.player && root.player.canGoPrevious
              onClicked: root.previousTrack()
            }

            Ui.PanelActionButton {
              iconText: root.playing ? "󰏤" : "󰐊"
              tooltipText: root.playing ? "Pause" : "Play"
              foreground: Color.accent
              hoverColor: Color.accent
              fontFamily: root.contentFontFamily
              fontSize: Style.font.iconLarge
              size: Style.space(36)
              enabled: root.player !== null
              onClicked: root.togglePlayback()
            }

            Ui.PanelActionButton {
              iconText: "󰒭"
              tooltipText: "Next track"
              foreground: root.contentForeground
              hoverColor: Color.accent
              fontFamily: root.contentFontFamily
              size: Style.space(30)
              enabled: root.player && root.player.canGoNext
              onClicked: root.nextTrack()
            }
          }
        }

        Column {
          visible: root.player === null
          width: parent.width
          spacing: Style.space(12)

          Text {
            width: parent.width
            text: root.appPlayerPids.length > 0
              ? "Start a song in the app to enable playback controls."
              : "Open the app and start a song to enable playback controls."
            color: root.dimForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

        }

        Text {
          width: parent.width
          text: root.player
            ? "Space play/pause  •  n/p or ←/→ track  •  o open  •  Esc close"
            : "Enter or o opens music.youtube.com  •  Esc closes"
          color: root.dimForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
