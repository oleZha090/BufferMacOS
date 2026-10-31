"""Build distribution assets on macOS; publish only the assets that passed checks.

No shell interpolation or third-party Python packages. Signing credentials come
only from environment variables configured as GitHub Actions secrets.
"""
import argparse
import base64
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import subprocess
import sys
import tempfile

DMG_NAME = "Cliply.dmg"
SIGNING_KEYS = (
    "MACOS_CERTIFICATE_P12_BASE64", "MACOS_CERTIFICATE_PASSWORD",
    "MACOS_SIGNING_IDENTITY", "APPLE_ID", "APPLE_APP_SPECIFIC_PASSWORD", "APPLE_TEAM_ID",
)


def version_from_tag(tag):
    if not re.fullmatch(r"v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", tag):
        raise ValueError("Use a version tag such as v1.0.0, without spaces or suffixes.")
    return tag[1:]


def signing_configuration(environment):
    values = {key: environment.get(key, "") for key in SIGNING_KEYS}
    if not any(values.values()):
        return None
    missing = [key for key, value in values.items() if not value]
    if missing:
        raise ValueError("Incomplete Apple signing configuration. Missing secrets: " + ", ".join(missing))
    if not values["MACOS_SIGNING_IDENTITY"].startswith("Developer ID Application: "):
        raise ValueError("MACOS_SIGNING_IDENTITY must be a Developer ID Application certificate identity.")
    return values


def run(*arguments):
    # Never echo command lines: some macOS tools accept credentials as arguments.
    result = subprocess.run([str(value) for value in arguments], text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{Path(str(arguments[0])).name} failed (exit {result.returncode}). Release was not published.")
    return result.stdout


@contextmanager
def signing_keychain(configuration, directory):
    if configuration is None:
        yield None
        return
    certificate = directory / "certificate.p12"
    certificate.write_bytes(base64.b64decode("".join(configuration["MACOS_CERTIFICATE_P12_BASE64"].split()), validate=True))
    certificate.chmod(0o600)
    keychain = directory / "release.keychain-db"
    password = secrets.token_urlsafe(32)
    run("security", "create-keychain", "-p", password, keychain)
    try:
        run("security", "set-keychain-settings", "-lut", "21600", keychain)
        run("security", "unlock-keychain", "-p", password, keychain)
        run("security", "import", certificate, "-k", keychain, "-P", configuration["MACOS_CERTIFICATE_PASSWORD"], "-T", "/usr/bin/codesign")
        run("security", "set-key-partition-list", "-S", "apple-tool:,apple:", "-s", "-k", password, keychain)
        yield keychain
    finally:
        run("security", "delete-keychain", keychain)


def sign(path, configuration, keychain, application=False):
    arguments = ["codesign", "--force"]
    if application:
        arguments += ["--options", "runtime"]
    if configuration:
        arguments += ["--sign", configuration["MACOS_SIGNING_IDENTITY"], "--timestamp", "--keychain", keychain]
    else:
        arguments += ["--sign", "-", "--timestamp=none"]
    run(*arguments, path)
    run("codesign", "--verify", "--deep", "--strict", path)


def notarize(path, configuration):
    output = run("xcrun", "notarytool", "submit", path,
                 "--apple-id", configuration["APPLE_ID"],
                 "--password", configuration["APPLE_APP_SPECIFIC_PASSWORD"],
                 "--team-id", configuration["APPLE_TEAM_ID"],
                 "--wait", "--timeout", "30m", "--output-format", "json")
    if json.loads(output).get("status") != "Accepted":
        raise RuntimeError("Apple did not accept notarization. Release was not published.")


def digest(path):
    checksum = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            checksum.update(block)
    return checksum.hexdigest()


def release_notes(version, signed):
    status = (
        "Подписано Developer ID и нотариализовано Apple. Проверка Gatekeeper пройдена."
        if signed else
        "Тестовая сборка с локальной подписью, без нотариализации Apple. "
        "При первом запуске macOS может заблокировать приложение. "
        "Если вы доверяете этой сборке, разрешите её запуск в "
        "System Settings → Privacy & Security → Open Anyway."
    )
    return f"""Cliply {version} для macOS 14 и новее, Intel и Apple Silicon.

**[Скачать Cliply.dmg](Cliply.dmg)** — готовое приложение, Xcode не нужен.

1. Откройте скачанный DMG и перетащите Cliply в Applications.
2. Запустите Cliply из Applications. Значок появится в строке меню.
3. Для автоматической вставки включите Accessibility в настройках Cliply.

{status}

История текста и изображений хранится только в памяти: до 10 записей и 128 МБ. ⌘⇧V открывает панель у мыши.
SHA256SUMS.txt содержит SHA-256 образа.
"""


def package(tag, app, output):
    version = version_from_tag(tag)
    if sys.platform != "darwin":
        raise RuntimeError("DMG packaging requires macOS. Use the Publish macOS app GitHub workflow.")
    configuration = signing_configuration(os.environ)
    app, output = app.resolve(), output.resolve()
    with (app / "Contents/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    if info.get("CFBundleShortVersionString") != version:
        raise ValueError("Application version does not match the release tag.")
    if info.get("CFBundleExecutable") != "Cliply" or info.get("CFBundleIdentifier") != "app.clipflow.ClipFlow":
        raise ValueError("Expected the Cliply application bundle.")
    if info.get("CFBundleIconName") != "AppIcon" or not (app / "Contents/Resources/AppIcon.icns").is_file():
        raise ValueError("Cliply's compiled app icon is missing. Refusing to publish an unbranded application.")
    architectures = set(run("lipo", "-archs", app / "Contents/MacOS/Cliply").split())
    if architectures != {"arm64", "x86_64"}:
        raise ValueError("A release must contain both arm64 and x86_64.")
    output.mkdir(parents=True, exist_ok=True)
    dmg = output / DMG_NAME
    if dmg.exists():
        raise ValueError("Release DMG already exists. Use an empty output directory.")
    with tempfile.TemporaryDirectory(prefix="cliply-release-") as temporary:
        temporary = Path(temporary)
        stage = temporary / "volume"
        stage.mkdir()
        staged_app = stage / "Cliply.app"
        run("ditto", app, staged_app)
        (stage / "Applications").symlink_to("/Applications", target_is_directory=True)
        with signing_keychain(configuration, temporary) as keychain:
            sign(staged_app, configuration, keychain, application=True)
            if configuration:
                notary_zip = temporary / "Cliply-notarization.zip"
                run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", staged_app, notary_zip)
                notarize(notary_zip, configuration)
                run("xcrun", "stapler", "staple", staged_app)
                run("xcrun", "stapler", "validate", staged_app)
                run("spctl", "--assess", "--type", "execute", "--verbose=2", staged_app)
            (stage / "Installation.txt").write_text(release_notes(version, bool(configuration)), encoding="utf-8")
            run("hdiutil", "create", "-volname", "Cliply", "-srcfolder", stage, "-format", "UDZO", dmg)
            sign(dmg, configuration, keychain)
            if configuration:
                notarize(dmg, configuration)
                run("xcrun", "stapler", "staple", dmg)
                run("xcrun", "stapler", "validate", dmg)
                run("spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=2", dmg)
    checksum = digest(dmg)
    manifest = {"tag": tag, "version": version, "signed_and_notarized": bool(configuration),
                "file": DMG_NAME, "sha256": checksum, "architectures": sorted(architectures)}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (output / "SHA256SUMS.txt").write_text(f"{checksum}  {DMG_NAME}\n", encoding="utf-8")
    (output / "release-notes.md").write_text(release_notes(version, bool(configuration)), encoding="utf-8")
    print(f"Packaged {DMG_NAME}; Developer ID and notarization: {'yes' if configuration else 'no (test build)'}.")


def validate_assets(tag, output):
    version = version_from_tag(tag)
    manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("tag") != tag or manifest.get("version") != version or manifest.get("file") != DMG_NAME:
        raise ValueError("Release metadata does not match the requested version.")
    if set(manifest.get("architectures", [])) != {"arm64", "x86_64"}:
        raise ValueError("Release is not universal.")
    if not isinstance(manifest.get("signed_and_notarized"), bool):
        raise ValueError("Release signing status must be explicitly true or false.")
    checksum = digest(output / DMG_NAME)
    if checksum != manifest.get("sha256") or (output / "SHA256SUMS.txt").read_text(encoding="utf-8") != f"{checksum}  {DMG_NAME}\n":
        raise ValueError("Release checksum mismatch. Refusing to publish.")
    return manifest


def publish(tag, output, repository, commit):
    manifest = validate_assets(tag, output)
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repository) or not re.fullmatch(r"[a-fA-F0-9]{40}", commit):
        raise ValueError("Expected a GitHub owner/repository and full commit SHA.")
    notes = release_notes(manifest["version"], manifest["signed_and_notarized"])
    # Release descriptions need an absolute download URL, independent of Markdown's base path.
    notes = notes.replace("](" + DMG_NAME + ")", f"](https://github.com/{repository}/releases/download/{tag}/{DMG_NAME})")
    notes_file = output / "release-notes.md"
    notes_file.write_text(notes, encoding="utf-8")
    # Do not clobber existing assets or tags. GitHub rejects a duplicate release.
    run("gh", "release", "create", tag, output / DMG_NAME, output / "SHA256SUMS.txt", output / "manifest.json",
        "--repo", repository, "--target", commit, "--title", f"Cliply {manifest['version']}",
        "--notes-file", notes_file)
    print(f"Published https://github.com/{repository}/releases/tag/{tag}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare = commands.add_parser("prepare")
    prepare.add_argument("--tag", required=True)
    prepare.add_argument("--github-output", type=Path)
    package_parser = commands.add_parser("package")
    package_parser.add_argument("--tag", required=True)
    package_parser.add_argument("--app", type=Path, required=True)
    package_parser.add_argument("--output", type=Path, required=True)
    publish_parser = commands.add_parser("publish")
    publish_parser.add_argument("--tag", required=True)
    publish_parser.add_argument("--output", type=Path, required=True)
    publish_parser.add_argument("--repository", required=True)
    publish_parser.add_argument("--commit", required=True)
    arguments = parser.parse_args()
    if arguments.command == "prepare":
        version = version_from_tag(arguments.tag)
        if arguments.github_output:
            with arguments.github_output.open("a", encoding="utf-8") as handle:
                handle.write(f"tag={arguments.tag}\nversion={version}\n")
        print(f"Release {arguments.tag}")
    elif arguments.command == "package":
        package(arguments.tag, arguments.app, arguments.output)
    else:
        publish(arguments.tag, arguments.output, arguments.repository, arguments.commit)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError) as error:
        # Only our own messages are printed; subprocess exceptions could expose credentials.
        print(str(error), file=sys.stderr)
        sys.exit(1)
