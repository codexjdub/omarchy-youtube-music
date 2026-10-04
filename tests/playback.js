const assert = require('node:assert/strict');
const test = require('node:test');
const model = require('../PlaybackModel.js');

const app = { class: 'brave-music.youtube.com__-Default', pid: 42 };
const appPlayer = { dbusName: 'org.mpris.MediaPlayer2.brave.instance42', identity: 'Brave', metadata: {}, isPlaying: false };
const video = { dbusName: 'org.mpris.MediaPlayer2.brave.instance99', identity: 'Brave', trackArtUrl: 'https://i.ytimg.com/video.jpg', isPlaying: true };

test('matches the dedicated app even when URL, album, and artwork are missing', () => {
  assert.deepEqual(model.appPids([app]), [42]);
  assert.equal(model.select([appPlayer], null, false, [42]), appPlayer);
});

test('matches the observed Brave metadata with a local artwork file and empty album', () => {
  const player = { ...appPlayer, trackTitle: '我的歌', trackArtUrl: 'file:///tmp/.org.chromium.Chromium.art', metadata: { 'xesam:album': '' } };
  assert.equal(model.select([player], null, true, []), null);
  assert.equal(model.select([player], null, true, [42]), player);
});

test('a window opened after startup becomes selectable once its full record arrives', () => {
  const pending = [{ class: '', pid: 0 }];
  assert.equal(model.select([appPlayer], null, true, model.appPids(pending)), null);
  pending[0] = app;
  assert.equal(model.select([appPlayer], null, true, model.appPids(pending)), appPlayer);
});

test('prefers the paused app over a playing video in the normal browser', () => {
  assert.equal(model.select([video, appPlayer], video, true, [42]), appPlayer);
});

test('ordinary browser windows do not identify app players', () => {
  assert.deepEqual(model.appPids([{ class: 'brave-origin', title: 'YouTube Music', pid: 99 }]), []);
  assert.equal(model.isAppWindow({ class: 'chrome-music.youtube.com__-Default' }), true);
  assert.equal(model.isAppWindow({ class: 'chrome-evil-music.youtube.com.evil__-Default' }), false);
});

test('accepts an explicit YouTube Music URL without the heuristic fallback', () => {
  const player = { metadata: { 'xesam:url': 'https://music.youtube.com/watch?v=1' } };
  assert.equal(model.select([video, player], null, false, []), player);
  assert.equal(model.score({ metadata: { 'xesam:url': 'https://example.com/music.youtube.com/watch' } }, false, []), 0);
});

test('heuristic fallback remains optional', () => {
  assert.equal(model.select([video], null, true, []), video);
  assert.equal(model.select([video], null, false, []), null);
});

test('keeps the selected paused app among equally matched players', () => {
  const second = { ...appPlayer, dbusName: 'org.mpris.MediaPlayer2.chrome.instance43' };
  assert.equal(model.select([appPlayer, second], second, false, [42, 43]), second);
  second.isPlaying = true;
  assert.equal(model.select([appPlayer, second], appPlayer, false, [42, 43]), second);
});

test('drops a removed player and never identifies a player with a different PID', () => {
  assert.equal(model.select([], appPlayer, true, [42]), null);
  assert.equal(model.select([appPlayer], null, false, [420]), null);
});
