import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "dj.youtube-music"
  ipcTarget: "dj.youtube-music"

  readonly property var players: Mpris.players ? Mpris.players.values : []
  property var player: null

  readonly property bool showTitle: setting("showTitle", true)
  readonly property int maxTitleWidth: Math.max(80, Number(setting("maxTitleWidth", 180)))
  readonly property bool showWhenIdle: setting("showWhenIdle", true)
  readonly property bool browserFallback: setting("browserFallback", true)

  readonly property bool playing: player && player.playbackState === MprisPlaybackState.Playing
  readonly property string artUrl: player ? (player.trackArtUrl || player.artUrl || "") : ""
  readonly property string artistName: player ? (player.trackArtist || "") : ""
  readonly property string trackTitle: player ? (player.trackTitle || "Untitled track") : ""
  readonly property string albumName: player ? (player.trackAlbum || "") : ""
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color dimForeground: Qt.darker(contentForeground, 1.45)
  readonly property color barColor: bar ? bar.barForeground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  visible: player !== null || showWhenIdle
  implicitWidth: visible ? controls.implicitWidth : 0
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

  function isBrowser(candidate) {
    var identity = String(candidate && candidate.identity || "").toLowerCase()
    var desktopEntry = String(candidate && candidate.desktopEntry || "").toLowerCase()
    var value = identity + " " + desktopEntry
    return value.indexOf("chrome") !== -1
      || value.indexOf("chromium") !== -1
      || value.indexOf("brave") !== -1
      || value.indexOf("firefox") !== -1
      || value.indexOf("zen") !== -1
      || value.indexOf("vivaldi") !== -1
      || value.indexOf("edge") !== -1
  }

  function isYoutubeMusic(candidate) {
    if (!candidate) return false
    var metadata = candidate.metadata || {}
    var identity = String(candidate.identity || "").toLowerCase()
    var desktopEntry = String(candidate.desktopEntry || "").toLowerCase()
    var url = String(metadata["xesam:url"] || "").toLowerCase()
    var art = String(candidate.trackArtUrl || candidate.artUrl || "").toLowerCase()

    if (identity.indexOf("youtube music") !== -1) return true
    if (desktopEntry.indexOf("youtube-music") !== -1 || desktopEntry.indexOf("ytmusic") !== -1) return true
    if (url.indexOf("music.youtube.com") !== -1) return true

    if (!browserFallback || !isBrowser(candidate)) return false

    // Chromium may omit xesam:url. YouTube Music normally provides album
    // metadata and artwork hosted by YouTube/Google, unlike a regular video.
    var album = String(metadata["xesam:album"] || candidate.trackAlbum || "")
    return album !== ""
      || art.indexOf("ytimg.com") !== -1
      || art.indexOf("googleusercontent.com") !== -1
  }

  function selectPlayer() {
    var firstMatch = null

    for (var i = 0; i < players.length; i++) {
      var candidate = players[i]
      if (!isYoutubeMusic(candidate)) continue
      if (!firstMatch) firstMatch = candidate
      if (candidate.isPlaying) {
        player = candidate
        return
      }
    }

    if (player && players.indexOf(player) !== -1 && isYoutubeMusic(player)) return
    player = firstMatch
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

  function openYoutubeMusic() {
    Quickshell.execDetached(["xdg-open", "https://music.youtube.com"])
  }

  function formatTime(seconds) {
    if (!seconds || seconds <= 0) return "0:00"
    var totalSeconds = Math.floor(seconds)
    var minutes = Math.floor(totalSeconds / 60)
    var remainingSeconds = totalSeconds % 60
    return minutes + ":" + (remainingSeconds < 10 ? "0" : "") + remainingSeconds
  }

  Component.onCompleted: selectPlayer()
  onPlayersChanged: selectPlayer()

  Instantiator {
    model: root.players
    onObjectAdded: root.selectPlayer()
    onObjectRemoved: root.selectPlayer()

    delegate: Connections {
      required property var modelData
      target: modelData

      function onIsPlayingChanged() { root.selectPlayer() }
      function onTrackTitleChanged() { root.selectPlayer() }
      function onTrackArtistChanged() { root.selectPlayer() }
      function onTrackAlbumChanged() { root.selectPlayer() }
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

    BarIconButton {
      id: panelButton
      bar: root.bar
      text: "󰗃"
      tooltipText: root.player
        ? root.trackTitle + (root.artistName ? " — " + root.artistName : "")
        : "Open YouTube Music"
      active: root.opened
      onPressed: function(buttonCode) {
        if (buttonCode === Qt.MiddleButton) root.togglePlayback()
        else if (buttonCode === Qt.RightButton) root.openYoutubeMusic()
        else root.toggle()
      }
      onWheelMoved: function(delta) {
        if (delta > 0) root.previousTrack()
        else if (delta < 0) root.nextTrack()
      }
    }

    Item {
      visible: root.player !== null && root.showTitle && !root.vertical
      width: visible ? Math.min(root.maxTitleWidth, titleText.implicitWidth) + Style.space(8) : 0
      height: root.implicitHeight

      Text {
        id: titleText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.trackTitle
        color: root.barColor
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onEntered: if (root.bar) root.bar.showTooltip(parent, root.trackTitle + (root.artistName ? " — " + root.artistName : ""))
        onExited: if (root.bar) root.bar.hideTooltip(parent)
        onClicked: function(mouse) {
          if (mouse.button === Qt.MiddleButton) root.togglePlayback()
          else if (mouse.button === Qt.RightButton) root.openYoutubeMusic()
          else root.toggle()
        }
        onWheel: function(wheel) {
          if (wheel.angleDelta.y > 0) root.previousTrack()
          else if (wheel.angleDelta.y < 0) root.nextTrack()
        }
      }
    }

    BarIconButton {
      visible: root.player !== null
      bar: root.bar
      text: "󰒮"
      tooltipText: "Previous track"
      interactive: root.player !== null && root.player.canGoPrevious
      dimmed: !interactive
      onPressed: root.previousTrack()
    }

    BarIconButton {
      visible: root.player !== null
      bar: root.bar
      text: root.playing ? "󰏤" : "󰐊"
      tooltipText: root.playing ? "Pause" : "Play"
      interactive: root.player !== null
      dimmed: !interactive
      onPressed: root.togglePlayback()
    }

    BarIconButton {
      visible: root.player !== null
      bar: root.bar
      text: "󰒭"
      tooltipText: "Next track"
      interactive: root.player !== null && root.player.canGoNext
      dimmed: !interactive
      onPressed: root.nextTrack()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: panelButton
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(root.player ? 360 : 250))
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
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

        Row {
          visible: root.player !== null
          width: parent.width
          spacing: Style.space(12)

          BorderSurface {
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

          PanelSlider {
            id: progressSlider
            width: parent.width
            bar: root.bar
            minimum: 0
            maximum: root.player ? Math.max(1, root.player.length) : 1
            value: root.player ? root.player.position : 0
            step: 5
            trackHeight: Math.max(3, Style.space(3))
            knobSize: Style.space(10)
            onReleased: function(nextPosition) {
              if (root.player && root.player.length > 0) root.player.position = nextPosition
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

            PanelActionButton {
              iconText: "󰒮"
              tooltipText: "Previous track"
              foreground: root.contentForeground
              hoverColor: Color.accent
              fontFamily: root.contentFontFamily
              size: Style.space(30)
              enabled: root.player && root.player.canGoPrevious
              onClicked: root.previousTrack()
            }

            PanelActionButton {
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

            PanelActionButton {
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
            text: "YouTube Music is idle"
            color: root.dimForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Button {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Open YouTube Music"
            foreground: root.contentForeground
            onClicked: root.openYoutubeMusic()
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
