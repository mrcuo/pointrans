#!/usr/bin/env python3
"""Generate the native Pointrans Xcode project deterministically.

The repository keeps this small generator so adding a source file does not
require hand-editing opaque PBX object identifiers.
"""

from __future__ import annotations

import hashlib
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PROJECT_DIR = ROOT / "Pointrans.xcodeproj"

LEGACY = {
    "Secrets.swift",
}


def oid(name: str) -> str:
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def quote(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def setting(value) -> str:
    if isinstance(value, list):
        return "(\n" + "".join(f"\t\t\t\t\t{quote(v)},\n" for v in value) + "\t\t\t\t)"
    if value in {"YES", "NO"} or str(value).replace(".", "").isdigit():
        return str(value)
    return quote(str(value))


def file_type(path: Path) -> str:
    if path.suffix == ".swift":
        return "sourcecode.swift"
    if path.suffix == ".xcassets":
        return "folder.assetcatalog"
    if path.suffix == ".icon":
        return "folder.iconcomposer.icon"
    if path.suffix == ".xcstrings":
        return "text.json.xcstrings"
    if path.suffix == ".xcprivacy":
        return "text.xml"
    if path.suffix == ".sqlite3":
        return "file"
    if path.suffix in {".plist", ".entitlements"}:
        return "text.plist.xml"
    if path.suffix == ".xcconfig":
        return "text.xcconfig"
    return "text"


class Project:
    def __init__(self) -> None:
        self.objects: dict[str, str] = {}

    def add(self, identifier: str, body: str) -> str:
        self.objects[identifier] = body
        return identifier

    def render(self, root_id: str) -> str:
        objects = "\n".join(
            f"\t\t{identifier} = {{\n{body}\n\t\t}};"
            for identifier, body in sorted(self.objects.items())
        )
        return f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{}};
\tobjectVersion = 60;
\tobjects = {{
{objects}
\t}};
\trootObject = {root_id};
}}
"""


def main() -> None:
    app_root = ROOT / "Sources" / "Pointrans"
    app_sources = sorted(
        path for path in app_root.rglob("*.swift")
        if path.name not in LEGACY and "Resources" not in path.parts
    )
    unit_sources = sorted((ROOT / "Tests" / "PointransTests").glob("*.swift"))
    ui_sources = sorted((ROOT / "Tests" / "PointransUITests").glob("*.swift"))
    unit_support_sources = [
        app_root / "Core" / "ApplicationLifetime.swift",
        app_root / "Core" / "AppPreferences.swift",
        app_root / "Core" / "DomainModels.swift",
        app_root / "Core" / "HoverIntentMachine.swift",
        app_root / "Core" / "LanguagePackManager.swift",
        app_root / "Core" / "PermissionCoordinator.swift",
        app_root / "Core" / "ProviderProtocols.swift",
        app_root / "Core" / "SafeCorridor.swift",
        app_root / "Core" / "ScreenCoordinates.swift",
        app_root / "Core" / "TranslationController.swift",
        app_root / "Services" / "AccessibilityTextExtractor.swift",
        app_root / "Services" / "BaseTranslationService.swift",
        app_root / "Services" / "CloudContextClient.swift",
        app_root / "Services" / "ContextAnalyzer.swift",
        app_root / "Services" / "DictionaryStore.swift",
        app_root / "Services" / "EventTapMonitor.swift",
        app_root / "Services" / "HybridTextExtractor.swift",
        app_root / "Services" / "InstallationIdentity.swift",
        app_root / "Services" / "OCRTextExtractor.swift",
        app_root / "Services" / "TextTokenizer.swift",
        app_root / "UI" / "ControlCenterView.swift",
        app_root / "UI" / "DesignSystem.swift",
        app_root / "UI" / "GuidedSampleView.swift",
        app_root / "UI" / "TranslationCardView.swift",
    ]
    resources = [
        app_root / "Resources" / "AppIcon.icon",
        app_root / "Resources" / "Assets.xcassets",
        app_root / "Resources" / "Dictionary.sqlite3",
        app_root / "Resources" / "Localizable.xcstrings",
        app_root / "Resources" / "PrivacyInfo.xcprivacy",
    ]
    configs = [
        ROOT / "Config" / "Info.plist",
        ROOT / "Config" / "Base.xcconfig",
        ROOT / "Config" / "Debug.xcconfig",
        ROOT / "Config" / "Release.xcconfig",
        ROOT / "Config" / "Pointrans.entitlements",
    ]

    project = Project()

    # File references.
    refs: dict[Path, str] = {}
    for path in app_sources + unit_sources + ui_sources + resources + configs:
        relative = path.relative_to(ROOT)
        ref = oid(f"file:{relative}")
        refs[path] = ref
        project.add(ref, f"\t\t\tisa = PBXFileReference;\n\t\t\tlastKnownFileType = {file_type(path)};\n\t\t\tpath = {quote(path.name if path.parent.name in {'PointransTests', 'PointransUITests', 'Resources', 'Config'} else str(path.relative_to(app_root)))};\n\t\t\tsourceTree = \"<group>\";")

    products_group = oid("group:products")
    app_product = oid("product:app")
    unit_product = oid("product:unit")
    ui_product = oid("product:ui")
    project.add(app_product, "\t\t\tisa = PBXFileReference;\n\t\t\texplicitFileType = wrapper.application;\n\t\t\tincludeInIndex = 0;\n\t\t\tpath = Pointrans.app;\n\t\t\tsourceTree = BUILT_PRODUCTS_DIR;")
    project.add(unit_product, "\t\t\tisa = PBXFileReference;\n\t\t\texplicitFileType = wrapper.cfbundle;\n\t\t\tincludeInIndex = 0;\n\t\t\tpath = PointransCoreTests.xctest;\n\t\t\tsourceTree = BUILT_PRODUCTS_DIR;")
    project.add(ui_product, "\t\t\tisa = PBXFileReference;\n\t\t\texplicitFileType = wrapper.cfbundle;\n\t\t\tincludeInIndex = 0;\n\t\t\tpath = PointransUITests.xctest;\n\t\t\tsourceTree = BUILT_PRODUCTS_DIR;")

    sqlite_ref = oid("framework:sqlite3")
    project.add(sqlite_ref, "\t\t\tisa = PBXFileReference;\n\t\t\tlastKnownFileType = sourcecode.text-based-dylib-definition;\n\t\t\tname = libsqlite3.tbd;\n\t\t\tpath = usr/lib/libsqlite3.tbd;\n\t\t\tsourceTree = SDKROOT;")

    def group(name: str, paths: list[Path], path_value: str | None = None) -> str:
        identifier = oid(f"group:{name}")
        children = "".join(f"\t\t\t\t{refs[path]},\n" for path in paths)
        path_line = f"\n\t\t\tpath = {quote(path_value)};" if path_value else ""
        project.add(identifier, f"\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{children}\t\t\t);{path_line}\n\t\t\tsourceTree = \"<group>\";")
        return identifier

    sources_group = group("sources", app_sources, "Sources/Pointrans")
    unit_group = group("unit-tests", unit_sources, "Tests/PointransTests")
    ui_group = group("ui-tests", ui_sources, "Tests/PointransUITests")
    resources_group = group("resources", resources, "Sources/Pointrans/Resources")
    config_group = group("config", configs, "Config")
    frameworks_group = oid("group:frameworks")
    project.add(frameworks_group, f"\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{sqlite_ref},\n\t\t\t);\n\t\t\tname = Frameworks;\n\t\t\tsourceTree = \"<group>\";")
    project.add(products_group, f"\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{app_product},\n\t\t\t\t{unit_product},\n\t\t\t\t{ui_product},\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";")

    main_group = oid("group:main")
    project.add(main_group, f"\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{sources_group},\n\t\t\t\t{resources_group},\n\t\t\t\t{unit_group},\n\t\t\t\t{ui_group},\n\t\t\t\t{config_group},\n\t\t\t\t{frameworks_group},\n\t\t\t\t{products_group},\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";")

    def build_phase(name: str, isa: str, paths: list[Path], target: str) -> str:
        phase = oid(f"phase:{target}:{name}")
        build_ids = []
        for path in paths:
            build = oid(f"build:{target}:{path.relative_to(ROOT)}")
            build_ids.append(build)
            project.add(build, f"\t\t\tisa = PBXBuildFile;\n\t\t\tfileRef = {refs[path]};")
        files = "".join(f"\t\t\t\t{identifier},\n" for identifier in build_ids)
        project.add(phase, f"\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n{files}\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        return phase

    app_sources_phase = build_phase("sources", "PBXSourcesBuildPhase", app_sources, "app")
    app_resources_phase = build_phase("resources", "PBXResourcesBuildPhase", resources, "app")
    unit_sources_phase = build_phase("sources", "PBXSourcesBuildPhase", unit_support_sources + unit_sources, "unit")
    ui_sources_phase = build_phase("sources", "PBXSourcesBuildPhase", ui_sources, "ui")

    app_frameworks_phase = oid("phase:app:frameworks")
    sqlite_build = oid("build:app:sqlite3")
    project.add(sqlite_build, f"\t\t\tisa = PBXBuildFile;\n\t\t\tfileRef = {sqlite_ref};")
    project.add(app_frameworks_phase, f"\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t\t{sqlite_build},\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    unit_frameworks_phase = oid("phase:unit:frameworks")
    ui_frameworks_phase = oid("phase:ui:frameworks")
    unit_sqlite_build = oid("build:unit:sqlite3")
    project.add(unit_sqlite_build, f"\t\t\tisa = PBXBuildFile;\n\t\t\tfileRef = {sqlite_ref};")
    project.add(unit_frameworks_phase, f"\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t\t{unit_sqlite_build},\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    project.add(ui_frameworks_phase, "\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = ();\n\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    unit_resources_phase = build_phase(
        "resources",
        "PBXResourcesBuildPhase",
        [
            app_root / "Resources" / "Assets.xcassets",
            app_root / "Resources" / "Dictionary.sqlite3",
        ],
        "unit",
    )
    ui_resources_phase = build_phase("resources", "PBXResourcesBuildPhase", [], "ui")

    app_target = oid("target:app")
    unit_target = oid("target:unit")
    ui_target = oid("target:ui")

    # Target dependency proxies.
    ui_proxy = oid("proxy:ui-app")
    ui_dependency = oid("dependency:ui-app")
    project_id = oid("project")
    project.add(ui_proxy, f"\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {project_id};\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {app_target};\n\t\t\tremoteInfo = Pointrans;")
    project.add(ui_dependency, f"\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {app_target};\n\t\t\ttargetProxy = {ui_proxy};")

    debug_config_ref = refs[ROOT / "Config" / "Debug.xcconfig"]
    release_config_ref = refs[ROOT / "Config" / "Release.xcconfig"]

    def configurations(owner: str, debug: dict, release: dict, base_refs: tuple[str | None, str | None] = (None, None)) -> str:
        config_ids = []
        for name, values, base_ref in (("Debug", debug, base_refs[0]), ("Release", release, base_refs[1])):
            config_id = oid(f"config:{owner}:{name}")
            config_ids.append(config_id)
            settings = "".join(f"\t\t\t\t{key} = {setting(value)};\n" for key, value in sorted(values.items()))
            base_line = f"\t\t\tbaseConfigurationReference = {base_ref};\n" if base_ref else ""
            project.add(config_id, f"\t\t\tisa = XCBuildConfiguration;\n{base_line}\t\t\tbuildSettings = {{\n{settings}\t\t\t}};\n\t\t\tname = {name};")
        config_list = oid(f"config-list:{owner}")
        project.add(config_list, f"\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{config_ids[0]},\n\t\t\t\t{config_ids[1]},\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;")
        return config_list

    project_settings = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "COPY_PHASE_STRIP": "NO",
        "MACOSX_DEPLOYMENT_TARGET": "26.0",
        "SDKROOT": "macosx",
    }
    project_config_list = configurations("project", project_settings, {**project_settings, "COPY_PHASE_STRIP": "YES"})

    app_settings = {
        "CODE_SIGN_ENTITLEMENTS": "Config/Pointrans.entitlements",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"],
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SUPPORTED_PLATFORMS": "macosx",
    }
    app_config_list = configurations("app", app_settings, app_settings, (debug_config_ref, release_config_ref))

    unit_settings = {
        "CODE_SIGN_IDENTITY": "-",
        "CODE_SIGN_STYLE": "Automatic",
        "GENERATE_INFOPLIST_FILE": "YES",
        "MACOSX_DEPLOYMENT_TARGET": "26.0",
        "ONLY_ACTIVE_ARCH": "YES",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.cuostudio.PointransCoreTests",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_STRICT_CONCURRENCY": "complete",
        "SWIFT_VERSION": "6.0",
    }
    ui_settings = {
        "CODE_SIGN_IDENTITY": "-",
        "CODE_SIGN_STYLE": "Automatic",
        "GENERATE_INFOPLIST_FILE": "YES",
        "MACOSX_DEPLOYMENT_TARGET": "26.0",
        "ONLY_ACTIVE_ARCH": "YES",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.cuostudio.PointransUITests",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_STRICT_CONCURRENCY": "complete",
        "SWIFT_VERSION": "6.0",
        "TEST_TARGET_NAME": "Pointrans",
    }
    unit_config_list = configurations("unit", unit_settings, unit_settings)
    ui_config_list = configurations("ui", ui_settings, ui_settings)

    project.add(app_target, f"\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {app_config_list};\n\t\t\tbuildPhases = (\n\t\t\t\t{app_sources_phase},\n\t\t\t\t{app_frameworks_phase},\n\t\t\t\t{app_resources_phase},\n\t\t\t);\n\t\t\tbuildRules = ();\n\t\t\tdependencies = ();\n\t\t\tname = Pointrans;\n\t\t\tproductName = Pointrans;\n\t\t\tproductReference = {app_product};\n\t\t\tproductType = \"com.apple.product-type.application\";")
    project.add(unit_target, f"\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {unit_config_list};\n\t\t\tbuildPhases = (\n\t\t\t\t{unit_sources_phase},\n\t\t\t\t{unit_frameworks_phase},\n\t\t\t\t{unit_resources_phase},\n\t\t\t);\n\t\t\tbuildRules = ();\n\t\t\tdependencies = ();\n\t\t\tname = PointransCoreTests;\n\t\t\tproductName = PointransCoreTests;\n\t\t\tproductReference = {unit_product};\n\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";")
    project.add(ui_target, f"\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {ui_config_list};\n\t\t\tbuildPhases = (\n\t\t\t\t{ui_sources_phase},\n\t\t\t\t{ui_frameworks_phase},\n\t\t\t\t{ui_resources_phase},\n\t\t\t);\n\t\t\tbuildRules = ();\n\t\t\tdependencies = ({ui_dependency},);\n\t\t\tname = PointransUITests;\n\t\t\tproductName = PointransUITests;\n\t\t\tproductReference = {ui_product};\n\t\t\tproductType = \"com.apple.product-type.bundle.ui-testing\";")

    project.add(project_id, f"\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 2600;\n\t\t\t\tLastUpgradeCheck = 2600;\n\t\t\t\tTargetAttributes = {{\n\t\t\t\t\t{app_target} = {{ CreatedOnToolsVersion = 26.0; }};\n\t\t\t\t\t{unit_target} = {{ CreatedOnToolsVersion = 26.0; }};\n\t\t\t\t\t{ui_target} = {{ CreatedOnToolsVersion = 26.0; TestTargetID = {app_target}; }};\n\t\t\t\t}};\n\t\t\t}};\n\t\t\tbuildConfigurationList = {project_config_list};\n\t\t\tcompatibilityVersion = \"Xcode 15.0\";\n\t\t\tdevelopmentRegion = en;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (en, \"zh-Hans\", Base);\n\t\t\tmainGroup = {main_group};\n\t\t\tproductRefGroup = {products_group};\n\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = ({app_target}, {unit_target}, {ui_target});")

    PROJECT_DIR.mkdir(parents=True, exist_ok=True)
    (PROJECT_DIR / "project.pbxproj").write_text(project.render(project_id))

    scheme_dir = PROJECT_DIR / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="Pointrans.app" BlueprintName="Pointrans" ReferencedContainer="container:Pointrans.xcodeproj"/>
      </BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables>
      <TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{unit_target}" BuildableName="PointransCoreTests.xctest" BlueprintName="PointransCoreTests" ReferencedContainer="container:Pointrans.xcodeproj"/></TestableReference>
      <TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui_target}" BuildableName="PointransUITests.xctest" BlueprintName="PointransUITests" ReferencedContainer="container:Pointrans.xcodeproj"/></TestableReference>
    </Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="Pointrans.app" BlueprintName="Pointrans" ReferencedContainer="container:Pointrans.xcodeproj"/></BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="Pointrans.app" BlueprintName="Pointrans" ReferencedContainer="container:Pointrans.xcodeproj"/></BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
"""
    (scheme_dir / "Pointrans.xcscheme").write_text(scheme)
    core_scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{unit_target}" BuildableName="PointransCoreTests.xctest" BlueprintName="PointransCoreTests" ReferencedContainer="container:Pointrans.xcodeproj"/>
      </BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB">
    <Testables>
      <TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{unit_target}" BuildableName="PointransCoreTests.xctest" BlueprintName="PointransCoreTests" ReferencedContainer="container:Pointrans.xcodeproj"/></TestableReference>
    </Testables>
  </TestAction>
  <AnalyzeAction buildConfiguration="Debug"/>
</Scheme>
"""
    (scheme_dir / "PointransCoreTests.xcscheme").write_text(core_scheme)
    print(f"Generated {PROJECT_DIR} with {len(app_sources)} app sources, {len(unit_sources)} unit tests, and {len(ui_sources)} UI tests")


if __name__ == "__main__":
    main()
