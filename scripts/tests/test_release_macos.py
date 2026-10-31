import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "release_macos.py"
SPEC = importlib.util.spec_from_file_location("release_macos", SCRIPT)
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def assets(self, directory):
        (directory / release.DMG_NAME).write_bytes(b"example dmg bytes")
        checksum = hashlib.sha256(b"example dmg bytes").hexdigest()
        (directory / "SHA256SUMS.txt").write_text(f"{checksum}  {release.DMG_NAME}\n", encoding="utf-8")
        manifest = {"tag": "v1.2.3", "version": "1.2.3", "file": release.DMG_NAME,
                    "sha256": checksum, "architectures": ["arm64", "x86_64"], "signed_and_notarized": False}
        (directory / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
        return manifest

    def test_rejects_invalid_versions_before_workflow_output_or_cli(self):
        for value in ["1.0.0", "v1.0", "v01.0.0", "v1.0.0\ntag=evil", "v1.0.0;pwd", "../v1.0.0", "v1.0.0-beta"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                release.version_from_tag(value)
        self.assertEqual(release.version_from_tag("v10.0.12"), "10.0.12")

    def test_missing_credentials_support_test_build_but_partial_configuration_fails(self):
        self.assertIsNone(release.signing_configuration({}))
        with self.assertRaisesRegex(ValueError, "Missing secrets"):
            release.signing_configuration({"APPLE_ID": "example@example.com"})
        configuration = {key: "configured" for key in release.SIGNING_KEYS}
        with self.assertRaisesRegex(ValueError, "Developer ID Application"):
            release.signing_configuration(configuration)
        configuration["MACOS_SIGNING_IDENTITY"] = "Developer ID Application: Example (TEAMID)"
        self.assertEqual(release.signing_configuration(configuration), configuration)

    def test_tampered_download_is_never_published(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.assets(directory)
            (directory / release.DMG_NAME).write_bytes(b"changed bytes")
            with patch.object(release, "run") as run, self.assertRaisesRegex(ValueError, "checksum"):
                release.publish("v1.2.3", directory, "example/ClipFlow", "a" * 40)
            run.assert_not_called()

    def test_wrong_tag_or_nonuniversal_app_is_not_published(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            manifest = self.assets(directory)
            with self.assertRaisesRegex(ValueError, "metadata"):
                release.validate_assets("v1.2.4", directory)
            manifest["architectures"] = ["arm64"]
            (directory / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "universal"):
                release.validate_assets("v1.2.3", directory)

    def test_published_notes_have_real_download_url_and_honest_signing_status(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.assets(directory)
            with patch.object(release, "run") as run, patch("builtins.print"):
                release.publish("v1.2.3", directory, "example/ClipFlow", "a" * 40)
            command = run.call_args.args
            self.assertEqual(command[:4], ("gh", "release", "create", "v1.2.3"))
            self.assertIn(directory / "ClipFlow.dmg", command)
            self.assertIn("--notes-file", command)
            self.assertNotIn("--clobber", command)
            notes = (directory / "release-notes.md").read_text(encoding="utf-8")
            self.assertIn("https://github.com/example/ClipFlow/releases/download/v1.2.3/ClipFlow.dmg", notes)
            self.assertIn("без нотариализации", notes)
            self.assertNotIn("Проверка Gatekeeper пройдена", notes)

    def test_failed_subprocess_does_not_echo_password_or_command(self):
        with patch.object(release.subprocess, "run") as subprocess_run:
            subprocess_run.return_value.returncode = 1
            subprocess_run.return_value.stderr = "sensitive stderr"
            with self.assertRaises(RuntimeError) as failure:
                release.run("security", "import", "--password", "secret-password")
            self.assertNotIn("secret-password", str(failure.exception))
            self.assertNotIn("sensitive stderr", str(failure.exception))

    def test_notary_rejection_cannot_pass_as_success(self):
        configuration = {key: "configured" for key in release.SIGNING_KEYS}
        with patch.object(release, "run", return_value='{"status": "Invalid"}'):
            with self.assertRaisesRegex(RuntimeError, "not accept"):
                release.notarize(Path("app.zip"), configuration)

    def test_readme_button_targets_stable_release_filename(self):
        root = SCRIPT.parent.parent
        readme = (root / "README.md").read_text(encoding="utf-8")
        self.assertIn('href="../../releases/latest/download/ClipFlow.dmg"', readme)
        self.assertTrue((root / "docs/download-macos.svg").is_file())
        self.assertIn("Проверка Gatekeeper пройдена", release.release_notes("1.2.3", True))

    def test_packaging_produces_a_verified_download_with_a_stable_filename(self):
        # Simulate only macOS tools; exercise real staging, metadata and checksum generation
        # on Windows too. Real codesign/hdiutil execution still belongs to macOS CI.
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            app = directory / "ClipFlow.app"
            (app / "Contents").mkdir(parents=True)
            with (app / "Contents/Info.plist").open("wb") as handle:
                plistlib.dump({"CFBundleShortVersionString": "1.2.3", "CFBundleExecutable": "ClipFlow",
                              "CFBundleIdentifier": "app.clipflow.ClipFlow"}, handle)
            output = directory / "dist"

            def macos_tool(*arguments):
                if arguments[0] == "lipo":
                    return "x86_64 arm64\n"
                if arguments[0] == "hdiutil":
                    Path(arguments[-1]).write_bytes(b"packaged-dmg")
                return ""

            with patch.object(release.sys, "platform", "darwin"), patch.dict(release.os.environ, {}, clear=True), \
                 patch.object(release, "run", side_effect=macos_tool), patch.object(Path, "symlink_to"), patch("builtins.print"):
                release.package("v1.2.3", app, output)
            manifest = release.validate_assets("v1.2.3", output)
            self.assertFalse(manifest["signed_and_notarized"])
            self.assertEqual(manifest["file"], "ClipFlow.dmg")
            self.assertNotIn("certificate.p12", {path.name for path in output.iterdir()})
            self.assertIn("без нотариализации", (output / "release-notes.md").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
