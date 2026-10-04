#!/usr/bin/env python3
"""Exercise real launcher argument handling without opening a browser."""

import json
import os
from pathlib import Path
import subprocess
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
