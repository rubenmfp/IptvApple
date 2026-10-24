#!/usr/bin/env python3
"""Generates IptvApple.xcodeproj/project.pbxproj.

Two app targets share the code in Shared/:
  - IptvApple    (iPhone / iPad)
  - IptvAppleTV  (Apple TV)
Files in iOS/ go only to the iPhone target, files in tvOS/ only to the TV target.
Run again after adding or removing files:  python3 tools/gen_project.py
Format kept compatible with Xcode 15 (objectVersion 56).
"""
import hashlib
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = "IptvApple"
BUNDLE = "com.rubenmfp.iptvapple"
DEPLOY = "17.0"
VERSION = "0.11"
BUILD = "20"
DISPLAY_NAME = "IptvTV"

SOURCE_EXT = {".swift": "sourcecode.swift"}
RESOURCE_EXT = {".xcassets": "folder.assetcatalog", ".json": "text.json", ".strings": "text.plist.strings"}
GROUPS = [("Shared", ("ios", "tv")), ("iOS", ("ios",)), ("tvOS", ("tv",))]


def uid(*parts):
    return hashlib.sha1("|".join(parts).encode()).hexdigest()[:24].upper()


def q(s):
    s = str(s)
    if re.fullmatch(r"[A-Za-z0-9_./]+", s):
        return s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def scan(folder):
    """Returns sorted relative paths of sources/resources under folder (asset catalogs as one item)."""
    out = []
    base = os.path.join(ROOT, folder)
    if not os.path.isdir(base):
        return out
    for dirpath, dirnames, filenames in os.walk(base):
        keep = []
        for d in sorted(dirnames):
            ext = os.path.splitext(d)[1]
            if ext in RESOURCE_EXT:
                out.append(os.path.relpath(os.path.join(dirpath, d), ROOT))
            elif not d.startswith("."):
                keep.append(d)
        dirnames[:] = keep
        for f in sorted(filenames):
            ext = os.path.splitext(f)[1]
            if ext in SOURCE_EXT or ext in RESOURCE_EXT:
                out.append(os.path.relpath(os.path.join(dirpath, f), ROOT))
    return sorted(out)


def settings_block(d, indent):
    pad = "\t" * indent
    lines = []
    for k in sorted(d):
        v = d[k]
        if isinstance(v, list):
            lines.append(f"{pad}{k} = (")
            for item in v:
                lines.append(f"{pad}\t{q(item)},")
            lines.append(f"{pad});")
        else:
            lines.append(f"{pad}{k} = {q(v)};")
    return "\n".join(lines)


def main():
    targets = {
        "ios": dict(name=PROJECT, bundle=BUNDLE, sdk="iphoneos", vlc="MobileVLCKit",
                    extra={"IPHONEOS_DEPLOYMENT_TARGET": DEPLOY, "TARGETED_DEVICE_FAMILY": "1,2",
                           "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
                           "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
                           "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone":
                               "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
                           "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad":
                               "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"}),
        "tv": dict(name=PROJECT + "TV", bundle=BUNDLE + ".tv", sdk="appletvos", vlc="TVVLCKit",
                   extra={"TVOS_DEPLOYMENT_TARGET": DEPLOY, "TARGETED_DEVICE_FAMILY": "3"}),
    }

    objects = {}  # id -> (isa, body)
    def add(oid, isa, body):
        objects[oid] = (isa, body)

    main_group = uid("group", "main")
    products_group = uid("group", "products")
    config_group = uid("group", "Config")
    base_xcconfig = uid("file", "Config/Base.xcconfig")
    add(base_xcconfig, "PBXFileReference",
        "lastKnownFileType = text.xcconfig; path = Base.xcconfig; sourceTree = \"<group>\";")
    info_plist = uid("file", "Config/Info.plist")
    add(info_plist, "PBXFileReference",
        "lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\";")
    add(config_group, "PBXGroup",
        f"children = (\n\t\t\t\t{base_xcconfig} /* Base.xcconfig */,\n\t\t\t\t{info_plist} /* Info.plist */,\n\t\t\t);\n\t\t\tpath = Config;\n\t\t\tsourceTree = \"<group>\";")

    target_sources = {"ios": [], "tv": []}
    target_resources = {"ios": [], "tv": []}
    group_ids = []

    for folder, members in GROUPS:
        files = scan(folder)
        if not files:
            continue
        # build nested groups
        group_children = {folder: []}
        for rel in files:
            parts = rel.split(os.sep)
            for i in range(1, len(parts) - 1):
                sub = os.sep.join(parts[: i + 1])
                parent = os.sep.join(parts[:i])
                if sub not in group_children:
                    group_children[sub] = []
                    group_children[parent].append(("group", sub))
            name = parts[-1]
            ext = os.path.splitext(name)[1]
            ftype = SOURCE_EXT.get(ext) or RESOURCE_EXT.get(ext)
            fid = uid("file", rel)
            add(fid, "PBXFileReference", f"lastKnownFileType = {ftype}; path = {q(name)}; sourceTree = \"<group>\";")
            group_children[os.sep.join(parts[:-1])].append(("file", rel))
            for t in members:
                bid = uid("build", t, rel)
                add(bid, "PBXBuildFile", f"fileRef = {fid} /* {name} */;")
                (target_sources if ext in SOURCE_EXT else target_resources)[t].append((bid, name))
        for g, children in group_children.items():
            gid = uid("group", g)
            items = []
            for kind, ref in children:
                cid = uid(kind, ref)
                items.append(f"\t\t\t\t{cid} /* {os.path.basename(ref)} */,")
            add(gid, "PBXGroup",
                "children = (\n" + "\n".join(items) + f"\n\t\t\t);\n\t\t\tpath = {q(os.path.basename(g))};\n\t\t\tsourceTree = \"<group>\";")
        group_ids.append((uid("group", folder), folder))

    product_refs = []
    native_targets = []
    framework_refs = []
    for key, t in targets.items():
        name = t["name"]
        prod = uid("product", key)
        add(prod, "PBXFileReference",
            f"explicitFileType = wrapper.application; includeInIndex = 0; path = {q(name + '.app')}; sourceTree = BUILT_PRODUCTS_DIR;")
        product_refs.append((prod, name + ".app"))
        src_phase = uid("phase", key, "sources")
        res_phase = uid("phase", key, "resources")
        fw_phase = uid("phase", key, "frameworks")
        add(src_phase, "PBXSourcesBuildPhase",
            "buildActionMask = 2147483647;\n\t\t\tfiles = (\n" +
            "".join(f"\t\t\t\t{b} /* {n} in Sources */,\n" for b, n in target_sources[key]) +
            "\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        add(res_phase, "PBXResourcesBuildPhase",
            "buildActionMask = 2147483647;\n\t\t\tfiles = (\n" +
            "".join(f"\t\t\t\t{b} /* {n} in Resources */,\n" for b, n in target_resources[key]) +
            "\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        # moteur de lecture VLCKit (xcframework dynamique, récupéré par tools/fetch_vlckit.sh) : lié et embarqué
        vlc = t["vlc"]
        vref = uid("file", "Frameworks/" + vlc)
        add(vref, "PBXFileReference",
            f"lastKnownFileType = wrapper.xcframework; name = {vlc}.xcframework; path = Frameworks/{vlc}.xcframework; sourceTree = \"<group>\";")
        framework_refs.append((vref, vlc + ".xcframework"))
        vlink = uid("build", key, "link", vlc)
        vembed = uid("build", key, "embed", vlc)
        add(vlink, "PBXBuildFile", f"fileRef = {vref} /* {vlc}.xcframework */;")
        add(vembed, "PBXBuildFile", f"fileRef = {vref} /* {vlc}.xcframework */; settings = {{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }};")
        add(fw_phase, "PBXFrameworksBuildPhase",
            f"buildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t\t{vlink} /* {vlc}.xcframework in Frameworks */,\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        embed_phase = uid("phase", key, "embed")
        add(embed_phase, "PBXCopyFilesBuildPhase",
            f"buildActionMask = 2147483647;\n\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 10;\n\t\t\tfiles = (\n\t\t\t\t{vembed} /* {vlc}.xcframework in Embed Frameworks */,\n\t\t\t);\n\t\t\tname = \"Embed Frameworks\";\n\t\t\trunOnlyForDeploymentPostprocessing = 0;")

        common = {
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": BUILD,
            "ENABLE_PREVIEWS": "YES",
            "GENERATE_INFOPLIST_FILE": "YES",
            "INFOPLIST_FILE": "Config/Info.plist",
            "INFOPLIST_KEY_CFBundleDisplayName": DISPLAY_NAME,
            "INFOPLIST_KEY_UIUserInterfaceStyle": "Dark",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
            "MARKETING_VERSION": VERSION,
            "PRODUCT_BUNDLE_IDENTIFIER": t["bundle"],
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SDKROOT": t["sdk"],
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "SWIFT_VERSION": "5.0",
        }
        if os.path.isdir(os.path.join(ROOT, "Shared", "Assets.xcassets", "AppIcon.appiconset")) and key == "ios":
            common["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
        common.update(t["extra"])
        cfg_ids = []
        for cfg in ("Debug", "Release"):
            cid = uid("config", key, cfg)
            s = dict(common)
            if cfg == "Debug":
                s["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG $(inherited)"
            add(cid, "XCBuildConfiguration",
                f"baseConfigurationReference = {base_xcconfig} /* Base.xcconfig */;\n\t\t\tbuildSettings = {{\n" +
                settings_block(s, 4) + f"\n\t\t\t}};\n\t\t\tname = {cfg};")
            cfg_ids.append((cid, cfg))
        cl = uid("configlist", key)
        add(cl, "XCConfigurationList",
            "buildConfigurations = (\n" + "".join(f"\t\t\t\t{c} /* {n} */,\n" for c, n in cfg_ids) +
            "\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;")
        tid = uid("target", key)
        add(tid, "PBXNativeTarget",
            f"buildConfigurationList = {cl} /* Build configuration list for PBXNativeTarget \"{name}\" */;\n"
            f"\t\t\tbuildPhases = (\n\t\t\t\t{src_phase} /* Sources */,\n\t\t\t\t{fw_phase} /* Frameworks */,\n\t\t\t\t{res_phase} /* Resources */,\n\t\t\t\t{embed_phase} /* Embed Frameworks */,\n\t\t\t);\n"
            f"\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = {q(name)};\n"
            f"\t\t\tproductName = {q(name)};\n\t\t\tproductReference = {prod} /* {name}.app */;\n"
            f"\t\t\tproductType = \"com.apple.product-type.application\";")
        native_targets.append((tid, name))

    add(products_group, "PBXGroup",
        "children = (\n" + "".join(f"\t\t\t\t{p} /* {n} */,\n" for p, n in product_refs) +
        "\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";")
    fw_group = uid("group", "Frameworks")
    add(fw_group, "PBXGroup",
        "children = (\n" + "".join(f"\t\t\t\t{r} /* {n} */,\n" for r, n in framework_refs) +
        "\t\t\t);\n\t\t\tname = Frameworks;\n\t\t\tsourceTree = \"<group>\";")
    add(main_group, "PBXGroup",
        "children = (\n" + "".join(f"\t\t\t\t{g} /* {n} */,\n" for g, n in group_ids) +
        f"\t\t\t\t{config_group} /* Config */,\n\t\t\t\t{fw_group} /* Frameworks */,\n\t\t\t\t{products_group} /* Products */,\n"
        "\t\t\t);\n\t\t\tsourceTree = \"<group>\";")

    # project-level configs
    proj_common = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "SWIFT_VERSION": "5.0",
    }
    proj_cfgs = []
    for cfg in ("Debug", "Release"):
        s = dict(proj_common)
        if cfg == "Debug":
            s.update({"DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "GCC_OPTIMIZATION_LEVEL": "0",
                      "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"], "ONLY_ACTIVE_ARCH": "YES",
                      "SWIFT_OPTIMIZATION_LEVEL": "-Onone", "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE"})
        else:
            s.update({"DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "ENABLE_NS_ASSERTIONS": "NO",
                      "SWIFT_COMPILATION_MODE": "wholemodule", "SWIFT_OPTIMIZATION_LEVEL": "-O", "VALIDATE_PRODUCT": "YES",
                      "MTL_ENABLE_DEBUG_INFO": "NO"})
        cid = uid("config", "project", cfg)
        add(cid, "XCBuildConfiguration",
            "buildSettings = {\n" + settings_block(s, 4) + f"\n\t\t\t}};\n\t\t\tname = {cfg};")
        proj_cfgs.append((cid, cfg))
    proj_cl = uid("configlist", "project")
    add(proj_cl, "XCConfigurationList",
        "buildConfigurations = (\n" + "".join(f"\t\t\t\t{c} /* {n} */,\n" for c, n in proj_cfgs) +
        "\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;")

    project_id = uid("project")
    target_attrs = "".join(f"\t\t\t\t\t{t} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;\n\t\t\t\t\t}};\n" for t, _ in native_targets)
    add(project_id, "PBXProject",
        "attributes = {\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 1520;\n"
        "\t\t\t\tLastUpgradeCheck = 1520;\n\t\t\t\tTargetAttributes = {\n" + target_attrs + "\t\t\t\t};\n\t\t\t};\n"
        f"\t\t\tbuildConfigurationList = {proj_cl} /* Build configuration list for PBXProject \"{PROJECT}\" */;\n"
        "\t\t\tcompatibilityVersion = \"Xcode 14.0\";\n\t\t\tdevelopmentRegion = fr;\n"
        "\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\tfr,\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
        f"\t\t\tmainGroup = {main_group};\n\t\t\tproductRefGroup = {products_group} /* Products */;\n"
        "\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (\n" +
        "".join(f"\t\t\t\t{t} /* {n} */,\n" for t, n in native_targets) + "\t\t\t);")

    out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;", "\tobjects = {"]
    by_isa = {}
    for oid, (isa, body) in objects.items():
        by_isa.setdefault(isa, []).append((oid, body))
    for isa in sorted(by_isa):
        out.append(f"\n/* Begin {isa} section */")
        for oid, body in sorted(by_isa[isa]):
            if isa in ("PBXBuildFile", "PBXFileReference"):
                out.append(f"\t\t{oid} = {{isa = {isa}; {body} }};")
            else:
                out.append(f"\t\t{oid} = {{\n\t\t\tisa = {isa};\n\t\t\t{body}\n\t\t}};")
        out.append(f"/* End {isa} section */")
    out += ["\t};", f"\trootObject = {project_id} /* Project object */;", "}", ""]

    proj_dir = os.path.join(ROOT, PROJECT + ".xcodeproj")
    os.makedirs(proj_dir, exist_ok=True)
    with open(os.path.join(proj_dir, "project.pbxproj"), "w") as f:
        f.write("\n".join(out))
    print("project.pbxproj written:", len(objects), "objects;",
          "iOS sources", len(target_sources["ios"]), "| tvOS sources", len(target_sources["tv"]))


if __name__ == "__main__":
    sys.exit(main())
