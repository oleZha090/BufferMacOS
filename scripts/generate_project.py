"""Generate the checked-in, dependency-free Xcode project on Windows or macOS.

Run only after adding/removing source files. Xcode is not required for generation.
"""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]


def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def generate():
    objects = []

    def add(name, body):
        objects.append(f"\t\t{uid(name)} = {{ {body} }};")
        return uid(name)

    def array(values):
        return "(" + ", ".join(values) + ")"

    def settings(values):
        return "{ " + " ".join(f'{key} = {value};' for key, value in values.items()) + " }"

    app_files = sorted((ROOT / "Cliply").rglob("*.swift"))
    test_files = sorted((ROOT / "CliplyTests").rglob("*.swift"))
    groups = []
    source_phases = []
    resource_builds = []
    for target, files in [("Cliply", app_files), ("CliplyTests", test_files)]:
        references, builds = [], []
        for file in files:
            relative = file.relative_to(ROOT).as_posix()
            ref = add("ref:" + relative, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{relative}"; sourceTree = SOURCE_ROOT;')
            references.append(ref)
            builds.append(add("build:" + relative, f"isa = PBXBuildFile; fileRef = {ref};"))
        if target == "Cliply":
            references.append(add("info", 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Cliply/App/Info.plist; sourceTree = SOURCE_ROOT;'))
            translations = []
            for language in ["en", "ru"]:
                path = f"Cliply/Resources/{language}.lproj/Localizable.strings"
                translations.append(add("ref:" + path, f'isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = {language}; path = "{path}"; sourceTree = SOURCE_ROOT;'))
            localized_strings = add("localizations", f'isa = PBXVariantGroup; children = {array(translations)}; name = Localizable.strings; sourceTree = "<group>";')
            references.append(localized_strings)
            resource_builds.append(add("build:localizations", f"isa = PBXBuildFile; fileRef = {localized_strings};"))
            assets = add("ref:assets", 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "Cliply/Resources/Assets.xcassets"; sourceTree = SOURCE_ROOT;')
            references.append(assets)
            resource_builds.append(add("build:assets", f"isa = PBXBuildFile; fileRef = {assets};"))
        groups.append(add("group:" + target, f'isa = PBXGroup; children = {array(references)}; name = {target}; sourceTree = "<group>";'))
        source_phases.append(add("sources:" + target, f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(builds)}; runOnlyForDeploymentPostprocessing = 0;"))

    app_product = add("product:app", 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Cliply.app; sourceTree = BUILT_PRODUCTS_DIR;')
    test_product = add("product:tests", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = CliplyTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    products = add("products", f'isa = PBXGroup; children = {array([app_product, test_product])}; name = Products; sourceTree = "<group>";')
    main_group = add("main", f'isa = PBXGroup; children = {array(groups + [products])}; sourceTree = "<group>";')

    config_lists = {}
    for scope in ["project", "app", "tests"]:
        configs = []
        for mode in ["Debug", "Release"]:
            if scope == "project":
                values = {
                    "SDKROOT": "macosx", "MACOSX_DEPLOYMENT_TARGET": "14.0", "SWIFT_VERSION": "5.0",
                    "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
                    "SWIFT_STRICT_CONCURRENCY": "targeted", "ENABLE_HARDENED_RUNTIME": "YES",
                    "CODE_SIGN_STYLE": "Automatic", "CODE_SIGN_IDENTITY": '"-"',
                    "GCC_C_LANGUAGE_STANDARD": "gnu17", "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"' if mode == "Debug" else '"-O"',
                    "DEBUG_INFORMATION_FORMAT": "dwarf" if mode == "Debug" else '"dwarf-with-dsym"',
                    "ONLY_ACTIVE_ARCH": "YES" if mode == "Debug" else "NO",
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"' if mode == "Debug" else '"$(inherited)"',
                    "ENABLE_TESTABILITY": "YES" if mode == "Debug" else "NO",
                }
            elif scope == "app":
                # A stable bundle identifier preserves settings across the display-name change.
                values = {
                    "PRODUCT_NAME": '"$(TARGET_NAME)"', "PRODUCT_BUNDLE_IDENTIFIER": "app.clipflow.ClipFlow",
                    "INFOPLIST_FILE": "Cliply/App/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
                    "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0.0",
                    "ENABLE_APP_SANDBOX": "NO", "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/../Frameworks"',
                    "COMBINE_HIDPI_IMAGES": "YES", "SWIFT_EMIT_LOC_STRINGS": "YES",
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                }
            else:
                values = {
                    "PRODUCT_NAME": '"$(TARGET_NAME)"', "PRODUCT_BUNDLE_IDENTIFIER": "app.clipflow.ClipFlowTests",
                    "GENERATE_INFOPLIST_FILE": "YES", "BUNDLE_LOADER": '"$(TEST_HOST)"',
                    "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/Cliply.app/Contents/MacOS/Cliply"',
                    "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks"',
                }
            configs.append(add(f"config:{scope}:{mode}", f"isa = XCBuildConfiguration; buildSettings = {settings(values)}; name = {mode};"))
        config_lists[scope] = add("configs:" + scope, f"isa = XCConfigurationList; buildConfigurations = {array(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")

    app_id, tests_id = uid("target:app"), uid("target:tests")
    proxy = add("proxy", f"isa = PBXContainerItemProxy; containerPortal = {uid('project')}; proxyType = 1; remoteGlobalIDString = {app_id}; remoteInfo = Cliply;")
    dependency = add("dependency", f"isa = PBXTargetDependency; target = {app_id}; targetProxy = {proxy};")
    for name, scope, product, source in [("Cliply", "app", app_product, source_phases[0]), ("CliplyTests", "tests", test_product, source_phases[1])]:
        frameworks = add("frameworks:" + scope, "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
        resources = add("resources:" + scope, f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array(resource_builds if scope == 'app' else [])}; runOnlyForDeploymentPostprocessing = 0;")
        product_type = "com.apple.product-type.application" if scope == "app" else "com.apple.product-type.bundle.unit-test"
        add("target:" + scope, f'isa = PBXNativeTarget; buildConfigurationList = {config_lists[scope]}; buildPhases = {array([source, frameworks, resources])}; buildRules = (); dependencies = {array([dependency] if scope == "tests" else [])}; name = {name}; productName = {name}; productReference = {product}; productType = "{product_type}";')
    add("project", f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1500; TargetAttributes = {{ {app_id} = {{ CreatedOnToolsVersion = 15.0; }}; {tests_id} = {{ CreatedOnToolsVersion = 15.0; TestTargetID = {app_id}; }}; }}; }}; buildConfigurationList = {config_lists["project"]}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, ru, Base); mainGroup = {main_group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {array([app_id, tests_id])};')
    directory = ROOT / "Cliply.xcodeproj"
    directory.mkdir(exist_ok=True)
    (directory / "project.pbxproj").write_text("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n" + "\n".join(objects) + f"\n\t}};\n\trootObject = {uid('project')};\n}}\n", encoding="utf-8", newline="\n")
    scheme_dir = directory / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)

    def build_ref(identifier, name, product):
        return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:Cliply.xcodeproj"/>'

    app_ref = build_ref(app_id, "Cliply", "Cliply.app")
    test_ref = build_ref(tests_id, "CliplyTests", "CliplyTests.xctest")
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1500" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry></BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables><TestableReference skipped="NO" parallelizable="NO">{test_ref}</TestableReference></Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="YES" debugDocumentVersioning="NO" allowLocationSimulation="NO">
    <BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="NO"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    (scheme_dir / "Cliply.xcscheme").write_text(scheme, encoding="utf-8", newline="\n")
    print(f"Generated Xcode project: {len(app_files)} app sources, {len(test_files)} test sources.")


if __name__ == "__main__":
    generate()
