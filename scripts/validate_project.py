"""Cross-platform structural checks; these do not compile Swift or replace XCTest."""
from pathlib import Path
import hashlib
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def main():
    project_file = ROOT / "ClipFlow.xcodeproj/project.pbxproj"
    scheme_file = ROOT / "ClipFlow.xcodeproj/xcshareddata/xcschemes/ClipFlow.xcscheme"
    before = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in [project_file, scheme_file]}
    subprocess.run([sys.executable, str(ROOT / "scripts/generate_project.py")], check=True)
    assert all(hashlib.sha256(p.read_bytes()).hexdigest() == digest for p, digest in before.items()), "Xcode project was stale; generation updated it. Review and rerun validation."
    project = project_file.read_text(encoding="utf-8")
    definitions = re.findall(r"^\s*([A-F0-9]{24}) = \{", project, flags=re.M)
    assert len(definitions) == len(set(definitions)), "Duplicate PBX object IDs"
    references = set(re.findall(r"\b[A-F0-9]{24}\b", project))
    assert references == set(definitions), f"Undefined PBX IDs: {references - set(definitions)}"
    source_paths = re.findall(r'path = "([^"\n]+\.swift)";', project)
    actual = {p.relative_to(ROOT).as_posix() for folder in ["ClipFlow", "ClipFlowTests"] for p in (ROOT / folder).rglob("*.swift")}
    assert set(source_paths) == actual, "Source file membership mismatch"
    for relative in source_paths:
        assert (ROOT / relative).is_file(), f"Missing source: {relative}"
    with (ROOT / "ClipFlow/App/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    assert info["LSUIElement"] is True
    scheme = ET.parse(scheme_file).getroot()
    for reference in scheme.findall(".//BuildableReference"):
        assert reference.attrib["BlueprintIdentifier"] in references
    assert scheme.find("TestAction/Testables/TestableReference") is not None
    assert 'MACOSX_DEPLOYMENT_TARGET = 14.0;' in project
    assert 'ENABLE_APP_SANDBOX = NO;' in project
    assert not any(re.search(r"\b(TODO|FIXME|fatalError)\b", (ROOT / relative).read_text(encoding="utf-8")) for relative in source_paths)
    test_count = sum(len(re.findall(r"func test\w+", p.read_text(encoding="utf-8"))) for p in (ROOT / "ClipFlowTests").glob("*.swift"))
    print(f"PASS: {len(source_paths)} source files, {len(definitions)} project objects, plist, scheme, {test_count} XCTest methods.")
    print("Swift compilation, XCTest execution and macOS integration were NOT checked by this script.")


if __name__ == "__main__":
    main()
