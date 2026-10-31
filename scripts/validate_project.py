"""Cross-platform structural checks; these do not compile Swift or replace XCTest."""
from pathlib import Path
import hashlib
import json
import plistlib
import re
import subprocess
import struct
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def validate_app_icon(project, info):
    directory = ROOT / "Cliply/Resources/Assets.xcassets/AppIcon.appiconset"
    catalog = json.loads((directory / "Contents.json").read_text(encoding="utf-8"))
    entries = catalog["images"]
    assert len(entries) == 10, "macOS AppIcon must have all 10 standard/Retina slots"
    expected = {(f"{size}x{size}", f"{scale}x") for size in (16, 32, 128, 256, 512) for scale in (1, 2)}
    assert {(entry["size"], entry["scale"]) for entry in entries} == expected
    for entry in entries:
        assert entry["idiom"] == "mac"
        filename = entry["filename"]
        assert Path(filename).name == filename, "AppIcon files must remain inside the icon set"
        data = (directory / filename).read_bytes()
        assert data[:8] == b"\x89PNG\r\n\x1a\n", f"Invalid PNG: {filename}"
        pixels = int(entry["size"].split("x")[0]) * int(entry["scale"][0])
        assert struct.unpack(">II", data[16:24]) == (pixels, pixels), f"Wrong dimensions: {filename}"
        assert data[25] == 6, f"AppIcon must preserve RGBA transparency: {filename}"
    assert info["CFBundleDisplayName"] == "Cliply"
    assert info["CFBundleIconName"] == "AppIcon" and info["CFBundleIconFile"] == "AppIcon"
    assert "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;" in project
    assert 'path = "Cliply/Resources/Assets.xcassets";' in project
    return len(entries)


def validate_localizations(project):
    catalogs = {}
    for language in ["en", "ru"]:
        relative = f"Cliply/Resources/{language}.lproj/Localizable.strings"
        assert f'path = "{relative}";' in project, f"Missing localized resource in Xcode: {relative}"
        entries = {}
        for number, line in enumerate((ROOT / relative).read_text(encoding="utf-8").splitlines(), 1):
            if not line.strip() or line.strip().startswith("//"):
                continue
            match = re.fullmatch(r'\s*("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*");\s*', line)
            assert match, f"Invalid strings syntax: {relative}:{number}"
            key, value = map(json.loads, match.groups())
            assert key not in entries and value, f"Duplicate key or empty translation: {relative}:{number}"
            entries[key] = value
        catalogs[language] = entries
    assert catalogs["en"].keys() == catalogs["ru"].keys(), "English/Russian translation keys differ"
    for key, english in catalogs["en"].items():
        assert re.findall(r"%[@d]", english) == re.findall(r"%[@d]", catalogs["ru"][key]), f"Format placeholders differ: {key}"
    literal = r'"((?:[^"\\]|\\.)*)"'
    for source in (ROOT / "Cliply").rglob("*.swift"):
        text = source.read_text(encoding="utf-8")
        keys = re.findall(r'\btext\(\s*' + literal, text)
        # Keys are also passed to the shared AppKit menu factory and manual-paste hints.
        keys += re.findall(r'\bitem\(\s*' + literal, text)
        keys += re.findall(r'\.manual\(\s*' + literal, text)
        if source.name in {"PresentationPreferences.swift", "LaunchAtLoginService.swift"}:
            keys += re.findall(r'\breturn\s+' + literal, text)
        for key in keys:
            assert json.loads('"' + key + '"') in catalogs["en"], f"Missing translation in {source.name}: {key}"
    assert "isa = PBXVariantGroup;" in project and "knownRegions = (en, ru, Base);" in project
    return len(catalogs["en"])


def main():
    project_file = ROOT / "Cliply.xcodeproj/project.pbxproj"
    scheme_file = ROOT / "Cliply.xcodeproj/xcshareddata/xcschemes/Cliply.xcscheme"
    before = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in [project_file, scheme_file]}
    subprocess.run([sys.executable, str(ROOT / "scripts/generate_project.py")], check=True)
    assert all(hashlib.sha256(p.read_bytes()).hexdigest() == digest for p, digest in before.items()), "Xcode project was stale; generation updated it. Review and rerun validation."
    project = project_file.read_text(encoding="utf-8")
    definitions = re.findall(r"^\s*([A-F0-9]{24}) = \{", project, flags=re.M)
    assert len(definitions) == len(set(definitions)), "Duplicate PBX object IDs"
    references = set(re.findall(r"\b[A-F0-9]{24}\b", project))
    assert references == set(definitions), f"Undefined PBX IDs: {references - set(definitions)}"
    source_paths = re.findall(r'path = "([^"\n]+\.swift)";', project)
    actual = {p.relative_to(ROOT).as_posix() for folder in ["Cliply", "CliplyTests"] for p in (ROOT / folder).rglob("*.swift")}
    assert set(source_paths) == actual, "Source file membership mismatch"
    for relative in source_paths:
        assert (ROOT / relative).is_file(), f"Missing source: {relative}"
    with (ROOT / "Cliply/App/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    assert info["LSUIElement"] is True
    icon_count = validate_app_icon(project, info)
    scheme = ET.parse(scheme_file).getroot()
    for reference in scheme.findall(".//BuildableReference"):
        assert reference.attrib["BlueprintIdentifier"] in references
    assert scheme.find("TestAction/Testables/TestableReference") is not None
    assert 'MACOSX_DEPLOYMENT_TARGET = 14.0;' in project
    assert 'ENABLE_APP_SANDBOX = NO;' in project
    localized_count = validate_localizations(project)
    assert not any(re.search(r"\b(TODO|FIXME|fatalError)\b", (ROOT / relative).read_text(encoding="utf-8")) for relative in source_paths)
    test_count = sum(len(re.findall(r"func test\w+", p.read_text(encoding="utf-8"))) for p in (ROOT / "CliplyTests").glob("*.swift"))
    print(f"PASS: {len(source_paths)} source files, {len(definitions)} project objects, plist, scheme, {test_count} XCTest methods, {localized_count} English/Russian translations, {icon_count} app icon slots.")
    print("Swift compilation, XCTest execution and macOS integration were NOT checked by this script.")


if __name__ == "__main__":
    main()
