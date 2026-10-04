function isAppWindow(window) {
  if (!window) return false
  var classes = [window.class || "", window.initialClass || ""]
  return classes.some(function(value) {
    return /(^|-)music\.youtube\.com__(?:-|$)/i.test(String(value))
  })
}

function appPids(windows) {
  return windows.filter(isAppWindow).map(function(window) { return Number(window.pid) })
    .filter(function(pid) { return pid > 0 })
}

function score(candidate, browserFallback, pids) {
  if (!candidate) return 0
  // Chromium names its MPRIS instance after the browser process. The app
  // window's PID identifies our player even when song metadata has no URL.
  var instance = String(candidate.dbusName || "").match(/\.instance(\d+)$/)
  if (instance && pids.indexOf(Number(instance[1])) !== -1) return 3

  var metadata = candidate.metadata || {}
  var identity = String(candidate.identity || "").toLowerCase()
  var desktopEntry = String(candidate.desktopEntry || "").toLowerCase()
  var url = String(metadata["xesam:url"] || "").toLowerCase()
  if (identity.indexOf("youtube music") !== -1
      || desktopEntry.indexOf("youtube-music") !== -1
      || desktopEntry.indexOf("ytmusic") !== -1
      || /^https?:\/\/music\.youtube\.com(?::\d+)?(?:[/?#]|$)/.test(url)) return 2

  if (!browserFallback || !/(chrome|chromium|brave|firefox|zen|vivaldi|edge|opera|helium)/.test(identity + " " + desktopEntry)) return 0
  var album = String(metadata["xesam:album"] || candidate.trackAlbum || "")
  var art = String(candidate.trackArtUrl || candidate.artUrl || "").toLowerCase()
  return album !== "" || art.indexOf("ytimg.com") !== -1
    || art.indexOf("googleusercontent.com") !== -1 ? 1 : 0
}

function select(players, current, browserFallback, pids) {
  var bestScore = 0
  var matches = []
  players.forEach(function(candidate) {
    var candidateScore = score(candidate, browserFallback, pids)
    if (candidateScore > bestScore) {
      bestScore = candidateScore
      matches = [candidate]
    } else if (candidateScore > 0 && candidateScore === bestScore) {
      matches.push(candidate)
    }
  })
  for (var i = 0; i < matches.length; i++) {
    if (matches[i].isPlaying) return matches[i]
  }
  return matches.indexOf(current) !== -1 ? current : (matches[0] || null)
}

if (typeof module !== "undefined") {
  module.exports = { isAppWindow: isAppWindow, appPids: appPids, score: score, select: select }
}
