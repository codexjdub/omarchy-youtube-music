#!/usr/bin/env python3
"""Exercise real launcher argument handling without opening a browser."""

import json
import os
from pathlib import Path
import subprocess
import signal
import time
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="ytmusic-launch-")
        self.addCleanup(self.scratch.cleanup)
        self.base = Path(self.scratch.name)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.data = self.base / "data with spaces; $literal"
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        XDG_DATA_HOME=str(self.data), MOCK_BROWSER="google-chrome.desktop")
        self.mock("omarchy", "#!/usr/bin/env python3\nimport json, sys\nprint(json.dumps(sys.argv[1:]))\n")
        self.mock("xdg-settings", '#!/bin/bash\nprintf "%s\\n" "$MOCK_BROWSER"\n')
        self.env["MOCK_CLIENTS"] = "[]"
        self.env["MOCK_FOCUS_LOG"] = str(self.base / "focused")
        self.mock("hyprctl", r'''#!/usr/bin/env python3
import os, re, sys
if sys.argv[1:] == ['clients', '-j']:
    print(os.environ['MOCK_CLIENTS'])
else:
    if os.environ.get('MOCK_FOCUS_FAIL') == '1':
        sys.exit(1)
    if os.environ.get('MOCK_HYPR_MODE') == 'legacy':
        if sys.argv[1:3] != ['dispatch', 'focuswindow']:
            sys.exit(1)
        address = sys.argv[3]
    else:
        match = re.fullmatch(r'hl\.dsp\.focus\(\{ window = "(address:0x[0-9a-fA-F]+)" \}\)', sys.argv[-1])
        if sys.argv[1] != 'dispatch' or not match:
            sys.exit(1)
        address = match[1]
    open(os.environ['MOCK_FOCUS_LOG'], 'w').write(address)
''')
        self.mock("mkdir", '''#!/bin/bash
if [[ ${MOCK_MKDIR_FAIL:-} == 1 ]]; then
  echo "Profile directory unavailable" >&2
  exit 1
fi
if [[ ${MOCK_MKDIR_RECORD_ONLY:-} != 1 ]]; then
  exec /usr/bin/mkdir "$@"
fi
''')

    def mock(self, name, source):
        path = self.bin / name
        path.write_text(source)
        path.chmod(0o755)

    def run_launcher(self, *args):
        return subprocess.run(["bash", str(ROOT / "launch.sh"), *args],
                              env=self.env, text=True, capture_output=True)

    def arguments(self, *args):
        result = self.run_launcher(*args)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def profile(self, browser="google-chrome.desktop"):
        return self.data / "dj.youtube-music" / "browser" / browser

    def window(self, *arguments, flattened=False):
        if flattened:
            title = "browser " + " ".join(arguments)
            process = subprocess.Popen(["bash", "-c", 'exec -a "$1" cat', "bash", title],
                                       stdin=subprocess.PIPE)
            deadline = time.monotonic() + 2
            while Path(f"/proc/{process.pid}/cmdline").read_bytes() != title.encode() + b'\0':
                self.assertLess(time.monotonic(), deadline, "Mock browser did not start")
                time.sleep(0.01)
        else:
            process = subprocess.Popen(["python3", "-c", "import time; time.sleep(60)", *arguments])
        def cleanup():
            process.terminate()
            process.wait(timeout=5)
            if process.stdin:
                process.stdin.close()
        self.addCleanup(cleanup)
        self.env["MOCK_CLIENTS"] = json.dumps([{
            "class": "chrome-music.youtube.com__-Default",
            "pid": process.pid, "address": "0x123abc",
        }])
        return process.pid

    def test_flattened_browser_arguments_require_matching_profile_lock(self):
        pid = self.window(f"--user-data-dir={self.profile()}", "--no-first-run", flattened=True)
        self.profile().mkdir(parents=True)
        self.profile().joinpath("SingletonLock").symlink_to(f"{os.uname().nodename}-{pid}")
        self.assertEqual(self.arguments("--isolated", "--prepare"), [])
        self.assertEqual(Path(self.env["MOCK_FOCUS_LOG"]).read_text(), "address:0x123abc")

    def test_flattened_arguments_without_profile_lock_are_not_reused(self):
        self.window(f"--user-data-dir={self.profile()}", flattened=True)
        self.assertIn(f"--user-data-dir={self.profile()}", self.arguments("--isolated", "--prepare"))
        self.assertFalse(Path(self.env["MOCK_FOCUS_LOG"]).exists())

    def test_profile_lock_for_other_process_or_host_is_not_reused(self):
        pid = self.window(f"--user-data-dir={self.profile()}", flattened=True)
        self.profile().mkdir(parents=True)
        lock = self.profile().joinpath("SingletonLock")
        for target in (f"{os.uname().nodename}-{pid + 1}", f"other-host-{pid}"):
            with self.subTest(target=target):
                lock.symlink_to(target)
                self.assertIn(f"--user-data-dir={self.profile()}", self.arguments("--isolated", "--prepare"))
                self.assertFalse(Path(self.env["MOCK_FOCUS_LOG"]).exists())
                lock.unlink()

    def test_shared_window_cannot_bypass_default_isolation(self):
        self.window("--app=https://music.youtube.com")
        self.assertIn(f"--user-data-dir={self.profile()}", self.arguments("--isolated", "--prepare"))
        self.assertFalse(Path(self.env["MOCK_FOCUS_LOG"]).exists())

    def test_matching_profile_is_focused_without_launching(self):
        self.window(f"--user-data-dir={self.profile()}")
        self.assertEqual(self.arguments("--isolated", "--prepare"), [])
        self.assertEqual(Path(self.env["MOCK_FOCUS_LOG"]).read_text(), "address:0x123abc")

    def test_legacy_hyprland_focus_remains_supported(self):
        self.window(f"--user-data-dir={self.profile()}")
        self.env["MOCK_HYPR_MODE"] = "legacy"
        self.assertEqual(self.arguments("--isolated", "--prepare"), [])
        self.assertEqual(Path(self.env["MOCK_FOCUS_LOG"]).read_text(), "address:0x123abc")

    def test_separate_profile_argument_is_recognized(self):
        self.window("--user-data-dir", str(self.profile()))
        self.assertEqual(self.arguments("--isolated", "--prepare"), [])

    def test_another_browser_profile_is_not_reused(self):
        self.window(f"--user-data-dir={self.profile('brave-browser.desktop')}")
        self.assertIn(f"--user-data-dir={self.profile()}", self.arguments("--isolated", "--prepare"))
        self.assertFalse(Path(self.env["MOCK_FOCUS_LOG"]).exists())

    def test_unreadable_process_is_not_reused(self):
        self.env["MOCK_CLIENTS"] = json.dumps([{
            "class": "chrome-music.youtube.com__-Default", "pid": 999999999, "address": "0x123abc",
        }])
        self.assertIn(f"--user-data-dir={self.profile()}", self.arguments("--isolated", "--prepare"))
        self.assertFalse(Path(self.env["MOCK_FOCUS_LOG"]).exists())

    def test_last_profile_argument_wins(self):
        self.window(f"--user-data-dir={self.profile()}", "--user-data-dir=/other-profile")
        self.assertIn(f"--user-data-dir={self.profile()}", self.arguments("--isolated", "--prepare"))
        self.assertFalse(Path(self.env["MOCK_FOCUS_LOG"]).exists())

    def test_failed_focus_launches_the_isolated_profile(self):
        self.window(f"--user-data-dir={self.profile()}")
        self.env["MOCK_FOCUS_FAIL"] = "1"
        self.assertIn(f"--user-data-dir={self.profile()}", self.arguments("--isolated", "--prepare"))

    def test_shared_mode_does_not_focus_an_isolated_window(self):
        self.window(f"--user-data-dir={self.profile()}")
        self.assertEqual(self.arguments("--shared", "--prepare"),
                         ["omarchy", "launch", "webapp", "https://music.youtube.com"])
        self.assertFalse(Path(self.env["MOCK_FOCUS_LOG"]).exists())

    def test_prepare_validates_profile_without_starting_browser(self):
        self.assertEqual(self.arguments("--isolated", "--prepare"), ["omarchy", *self.arguments()])
        self.env["MOCK_MKDIR_FAIL"] = "1"
        result = self.run_launcher("--isolated", "--prepare")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_browser_survives_quickshell_reload_and_shutdown(self):
        # Run the actual panel launcher and completion handler in a headless
        # Quickshell host, with a mock browser that stays alive until cleanup.
        source = (ROOT / "Panel.qml").read_text()
        start = source.index("  function openYoutubeMusic()")
        end = source.index("  function formatTime", start)
        launcher = source[start:end]
        qml = '''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
  id: root
  property bool isolatedProfile: true
  property string launchError: ""
  function open() { console.error(launchError); Qt.quit() }
  Component.onCompleted: openYoutubeMusic()
''' + launcher + "}\n"
        (self.base / "shell.qml").write_text(qml)
        (self.base / "launch.sh").symlink_to(ROOT / "launch.sh")
        self.env["MOCK_BROWSER_PID"] = str(self.base / "browser.pid")
        self.mock("omarchy", '''#!/usr/bin/env python3
import os, time
open(os.environ['MOCK_BROWSER_PID'], 'w').write(str(os.getpid()))
time.sleep(60)
''')
        runtime = self.base / "runtime"
        runtime.mkdir(mode=0o700)
        self.env.update(QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
                        XDG_RUNTIME_DIR=str(runtime),
                        XDG_CACHE_HOME=str(self.base / "cache"))
        log = self.base / "quickshell.log"
        browser_pid = None
        host = None
        try:
            with log.open("w") as output:
                host = subprocess.Popen(["quickshell", "--path", str(self.base)],
                                        env=self.env, stdout=output, stderr=output)
                deadline = time.monotonic() + 10
                pidfile = Path(self.env["MOCK_BROWSER_PID"])
                while not pidfile.exists() and host.poll() is None and time.monotonic() < deadline:
                    time.sleep(0.05)
                self.assertTrue(pidfile.exists(), log.read_text())
                browser_pid = int(pidfile.read_text())
                (self.base / "shell.qml").write_text('''import QtQuick
import Quickshell
ShellRoot {
  Component.onCompleted: console.log("LifecycleReloadComplete")
}
''')
                deadline = time.monotonic() + 5
                while "LifecycleReloadComplete" not in log.read_text() and time.monotonic() < deadline:
                    time.sleep(0.05)
                self.assertIn("LifecycleReloadComplete", log.read_text())
                self.assertNotIn("State:\tZ", Path(f"/proc/{browser_pid}/status").read_text(),
                                 "Browser died when the panel was destroyed")
                host.terminate()
                host.wait(timeout=5)
                time.sleep(0.1)
                os.kill(browser_pid, 0)
                status = Path(f"/proc/{browser_pid}/status").read_text()
                self.assertNotIn("State:\tZ", status, "Browser died with the shell")
        finally:
            if host is not None and host.poll() is None:
                host.kill()
                host.wait(timeout=5)
            if browser_pid is not None:
                try:
                    os.kill(browser_pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass

    def test_default_is_isolated_and_persistent(self):
        expected = ["launch", "webapp", "https://music.youtube.com",
                    f"--user-data-dir={self.profile()}",
                    "--no-first-run", "--no-default-browser-check"]
        self.assertEqual(self.arguments(), expected)
        self.assertEqual(self.profile().stat().st_mode & 0o777, 0o700)
        marker = self.profile() / "existing-login"
        marker.write_text("keep this session")
        self.assertEqual(self.arguments(), expected)
        self.assertEqual(marker.read_text(), "keep this session")

    def test_shared_requires_explicit_opt_out(self):
        self.assertEqual(self.arguments("--shared"),
                         ["launch", "webapp", "https://music.youtube.com"])
        self.assertFalse(self.data.exists())

    def test_browser_profiles_are_separate(self):
        for browser in ("brave-browser.desktop", "google-chrome-beta.desktop",
                        "microsoft-edge.desktop", "opera.desktop",
                        "vivaldi-stable.desktop", "helium.desktop"):
            with self.subTest(browser=browser):
                self.env["MOCK_BROWSER"] = browser
                self.assertIn(f"--user-data-dir={self.profile(browser)}", self.arguments())

    def test_unsupported_default_uses_chromium_profile(self):
        self.env["MOCK_BROWSER"] = "firefox.desktop"
        self.assertIn(f"--user-data-dir={self.profile('chromium.desktop')}", self.arguments())

    def test_missing_default_uses_chromium_profile(self):
        self.mock("xdg-settings", "#!/bin/bash\nexit 1\n")
        self.assertIn(f"--user-data-dir={self.profile('chromium.desktop')}", self.arguments())

    def test_xdg_unset_or_relative_uses_absolute_home_fallback(self):
        self.env["MOCK_MKDIR_RECORD_ONLY"] = "1"
        expected = Path(os.environ["HOME"]) / ".local/share/dj.youtube-music/browser/google-chrome.desktop"
        for value in (None, "relative/path"):
            with self.subTest(value=value):
                self.env.pop("XDG_DATA_HOME", None)
                if value is not None:
                    self.env["XDG_DATA_HOME"] = value
                self.assertIn(f"--user-data-dir={expected}", self.arguments())

    def test_profile_failure_never_launches_shared(self):
        self.env["MOCK_MKDIR_FAIL"] = "1"
        result = self.run_launcher()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("Profile directory unavailable", result.stderr)

    def test_invalid_mode_does_not_launch(self):
        result = self.run_launcher("--unknown")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")

    def test_setting_defaults_to_isolation(self):
        widget = json.loads((ROOT / "manifest.json").read_text())["barWidget"]
        self.assertIs(widget["defaults"]["isolatedProfile"], True)
        setting = next(item for item in widget["schema"] if item["key"] == "isolatedProfile")
        self.assertIs(setting["defaultValue"], True)


if __name__ == "__main__":
    unittest.main()
