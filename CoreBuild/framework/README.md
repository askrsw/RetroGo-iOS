# Core framework packaging

Wraps a libretro core `.dylib` into the `emu.{core}.framework` bundle RetroGo embeds.
Used both for the prebuilt cores published by the RetroArch project and for the cores
RetroGo builds from source (see the sibling `*-patches/` folders).

## Usage

```bash
# Package every core in using/ (<core>_libretro_ios.dylib + <core>_libretro.info)
python3 CoreBuild/framework/build_core_framework.py

# Package a single core from anywhere
python3 CoreBuild/framework/build_core_framework.py path/to/flycast_libretro_ios.dylib path/to/flycast_libretro.info

# Either form, written straight into the app
python3 CoreBuild/framework/build_core_framework.py --install [<dylib> <info>]
```

Output goes to `frameworks/emu.{core}.framework`, or with `--install` to
`RetroGo/Resources/Cores/emu.{core}.framework`, where the Xcode project picks it up. An existing
framework of the same name is deleted first. Replacing a core the app already ships needs nothing
else; a core that is new to the app still has to be added in Xcode to the RetroGo target's Copy
Files phase that embeds the other cores into Frameworks, or it is not built into the app.

The framework name comes from the `.info` file name. The `*-patches/build_ios.sh --copy`
scripts stage their freshly built dylib and `.info` into `using/` for you; `--install` calls this
script with the fresh dylib and `.info` and replaces the framework in the app.

## What it does

For each `.dylib` in `using/`:

1. `vtool -set-build-version ios 15.0` — the prebuilt cores are often tagged for the
   simulator or an older minimum, which the App Store rejects.
2. `lipo` into the framework's binary slot.
3. Generates `Info.plist` from `fw.tmpl`.
4. Copies `PrivacyInfo.xcprivacy` and the core's `.info`.
5. `codesign`.

Framework naming: `emu.{core_name}` with underscores turned into hyphens and the
`_libretro` suffix dropped — `dosbox_pure_libretro` becomes `emu.dosbox-pure.framework`.

## Signing

Ad-hoc (`codesign --sign -`) by default, because Xcode re-signs every core framework with
the app's own identity when it copies them into the bundle (`CodeSignOnCopy`). The
signature produced here only has to be valid locally, so no developer certificate is
needed to run this script.

Override when you do need a specific identity:

```bash
CODE_SIGN_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)" \
  python3 CoreBuild/framework/build_core_framework.py
```

`BUNDLE_ID_PREFIX` works the same way (default `com.haharsw`); set it to your own prefix
when building a derivative app.

## Directories

| Path | Contents |
|---|---|
| `using/` | Input dylibs and `.info` files. Not tracked. |
| `used/` | Inputs already packaged, kept for reference. Not tracked. |
| `frameworks/` | Output bundles. Not tracked. |

MAME does not go through this script: it is too large for the generic path and
`../mame-patches/scripts/package.py` builds its framework directly.
