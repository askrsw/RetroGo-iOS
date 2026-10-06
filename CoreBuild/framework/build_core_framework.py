import argparse, os, subprocess, shutil, tempfile


# Ad-hoc by default: Xcode re-signs every core framework on copy into the app
# (CodeSignOnCopy), so the signature applied here only has to be valid locally.
# Set CODE_SIGN_IDENTITY to use a real identity instead.
CODE_SIGN_IDENTITY_FOR_ITEMS = os.environ.get(
    "CODE_SIGN_IDENTITY", "-"
)
HERE = os.path.dirname(os.path.abspath(__file__))
BASE_DIR = os.path.join(HERE, "using")
SUFFIX = "_ios"
PLATFORM = "ios"
DEPLOYMENT_TARGET = "15.0"
OUTDIR = os.path.join(HERE, "frameworks")
INSTALL_DIR = os.path.join(HERE, "..", "..", "RetroGo", "Resources", "Cores")
FW_TMPL = os.path.join(HERE, "fw.tmpl")
PRIVACY_INFO = os.path.join(HERE, "PrivacyInfo.xcprivacy")
BUNDLE_ID_PREFIX = os.environ.get("BUNDLE_ID_PREFIX", "com.haharsw")

def find_using_cores():
    cores = []
    for file in sorted(os.listdir(BASE_DIR)):
        file_name, file_ext = os.path.splitext(file)
        if file_ext != '.info':
            continue
        dylib_path = os.path.join(BASE_DIR, file_name + '.dylib')
        if not os.path.isfile(dylib_path):
            dylib_path = os.path.join(BASE_DIR, file_name + SUFFIX + '.dylib')
            if not os.path.isfile(dylib_path):
                raise FileNotFoundError(f"Cannot find .dylib for {file_name}")
        cores.append((dylib_path, os.path.join(BASE_DIR, file)))
    return cores

def make_framework(dylib_path, info_path, outdir):
    # The framework is named after the .info file: dosbox_pure_libretro.info -> emu.dosbox-pure
    core_name = os.path.splitext(os.path.basename(info_path))[0]
    if core_name.endswith('_libretro'):
        core_name = core_name[:-9]
    core_name = core_name.replace('_', '-')
    fw_name = 'emu.' + core_name
    fw_dir = os.path.join(outdir, fw_name + '.framework')
    # Start from an empty bundle so no file from a previous build is left behind.
    if os.path.exists(fw_dir):
        shutil.rmtree(fw_dir)
    os.makedirs(fw_dir)

    # Get build_sdk
    result = subprocess.run(
        ["vtool", "-show-build", dylib_path],
        capture_output=True, text=True
    )
    build_sdk = ""
    for line in result.stdout.splitlines():
        if "sdk" in line:
            build_sdk = line.split()[1]
            break

    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_binary = os.path.join(tmp_dir, fw_name)

        # vtool
        vtool_cmd = [
            "vtool", "-set-build-version", PLATFORM, DEPLOYMENT_TARGET, build_sdk,
            "-set-build-tool", PLATFORM, "ld", "1115.7.3",
            "-set-source-version", "0.0",
            "-replace", "-output", tmp_binary, dylib_path
        ]
        subprocess.run(vtool_cmd, check=True)

        # lipo
        lipo_cmd = [
            "lipo", "-create", tmp_binary, "-output", os.path.join(fw_dir, fw_name)
        ]
        subprocess.run(lipo_cmd, check=True)

    # Info.plist
    with open(FW_TMPL, "r") as tmpl_file:
        content = tmpl_file.read()
    bindl_id = f"{BUNDLE_ID_PREFIX}.{fw_name}"
    content = content.replace("%CORE%", fw_name)\
                     .replace("%BUNDLE%", core_name)\
                     .replace("%IDENTIFIER%", bindl_id)\
                     .replace("%OSVER%", DEPLOYMENT_TARGET)
    with open(os.path.join(fw_dir, "Info.plist"), "w") as plist_file:
        plist_file.write(content)
    shutil.copyfile(info_path, os.path.join(fw_dir, "core.info"))
    shutil.copyfile(PRIVACY_INFO, os.path.join(fw_dir, "PrivacyInfo.xcprivacy"))
    # Sign only after all bundle resources are in place.
    print(f"signing {fw_name}", flush=True)
    codesign_cmd = [
        "codesign", "--force", "--verbose", "--sign", CODE_SIGN_IDENTITY_FOR_ITEMS, fw_dir
    ]
    subprocess.run(codesign_cmd, check=True)
    subprocess.run(["codesign", "--verify", "--strict", fw_dir], check=True)
    print(f"output {os.path.normpath(fw_dir)}", flush=True)

def check_core_files():
    core_folder = BASE_DIR
    for file in os.listdir(core_folder):
        file_name, file_ext = os.path.splitext(file)
        file_ext = file_ext.lstrip('.')
        if file_ext == 'info':
            name1 = file_name + '.dylib'
            name2 = file_name + '_ios.dylib'
            path1 = os.path.join(core_folder, name1)
            path2 = os.path.join(core_folder, name2)
            if not (os.path.isfile(path1) or os.path.isfile(path2)):
                print(f"{file} 缺少核心文件: {name1} 或 {name2}")
        if file_ext == 'dylib':
            if file_name.endswith('_ios'):
                name = file_name[:-4] + '.info'
            else:
                name = file_name + '.info'
            path = os.path.join(core_folder, name)
            if not os.path.isfile(path):
                print(f"{file} 缺少核心文件: {name}")

def main():
    parser = argparse.ArgumentParser(
        description="Wrap libretro core dylibs into emu.{core}.framework bundles. "
                    "Without arguments every core in using/ is packaged."
    )
    parser.add_argument("dylib", nargs="?", help="core dylib, e.g. flycast_libretro_ios.dylib")
    parser.add_argument("info", nargs="?", help="matching .info file, e.g. flycast_libretro.info")
    parser.add_argument("--install", action="store_true",
                        help="write into RetroGo/Resources/Cores, replacing an existing framework")
    args = parser.parse_args()

    if args.dylib is None:
        cores = find_using_cores()
    elif args.info is None:
        parser.error("the core dylib and its .info file must be given together")
    else:
        for path in (args.dylib, args.info):
            if not os.path.isfile(path):
                parser.error(f"file not found: {path}")
        cores = [(os.path.abspath(args.dylib), os.path.abspath(args.info))]

    outdir = INSTALL_DIR if args.install else OUTDIR
    if args.install and not os.path.isdir(outdir):
        parser.error(f"install directory not found: {os.path.normpath(outdir)}")
    os.makedirs(outdir, exist_ok=True)
    for dylib_path, info_path in cores:
        make_framework(dylib_path, info_path, outdir)

if __name__ == "__main__":
    main()
