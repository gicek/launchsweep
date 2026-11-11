# LaunchSweep

A small macOS app that finds apps registered with Launch Services that probably should not be, and
unregisters the ones you pick.

During development macOS registers every copy of an app it sees: build output, unpacked archives, mounted
disk images. They all share one bundle identifier, so the app launcher, Spotlight and "Open With" can end up
pointing at a stale copy instead of the installed app.

## What it finds

LaunchSweep scans the whole database, needs no input, and lists:

| Group | What it contains | Selected by default |
| --- | --- | --- |
| No Longer on Disk | Deleted or moved apps, and apps on disk images that are no longer mounted | Yes |
| In the Trash | Apps in the Trash | Yes |
| Temporary Locations | Copies in temporary folders, including App Translocation | Yes |
| Build Output | Copies in `DerivedData`, `build`, `.build`, `dist` or `target` folders | Yes |
| Mounted Volumes | Apps on mounted disk images and external drives | No |
| Duplicate Copies | Copies outside the usual app folders that share a bundle identifier with another registered app | No |

Apps in the usual app folders (`/Applications`, `~/Applications`, `/System`, `/Library`, `~/Library`) and in
system or package manager locations (`/usr`, `/opt`, `/bin`, `/sbin`, `/private`, `/nix`) are listed only when
they no longer exist. Helper apps inside an app bundle are handled together with the app.

After unregistering, LaunchSweep registers the installed copy of the same app again (the one with the same
bundle identifier in a usual app folder). The app launcher keeps one app per bundle identifier, and when
that was a stale copy it does not fall back to the installed app by itself.

## Limits

- Unregistering is not permanent for copies that still exist. macOS registers them again when it next sees
  them, for example after another build or when Finder shows the folder. For those, use **Move to Trash and
  Unregister** from the context menu.
- There is no public API for this. LaunchSweep runs `lsregister` and reads the output of `lsregister -dump`,
  whose format is undocumented and may change between macOS versions.
- The app is not sandboxed, so it cannot be distributed through the Mac App Store.

## Requirements

- macOS 14 or later to run.
- Xcode 16 or later to build (Swift 6, String Catalogs, Swift Testing).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). `LaunchSweep.xcodeproj` is
  generated from `project.yml` and is not committed.

## Build

```sh
make run    # build and launch
make test   # unit tests
make open   # generate the project and open it in Xcode
make clean  # remove build output and unregister the build copies
make help   # everything else
```

The Makefile finds Xcode even when `xcode-select` points at the Command Line Tools; set `DEVELOPER_DIR` to
pick another Xcode.

### Signing

Builds are signed ad hoc by default, so any Mac can build and run them. To sign with your own certificate,
copy `Config/LaunchSweep.local.xcconfig.example` to `Config/LaunchSweep.local.xcconfig` (not committed) and
set your team.

## Project layout

```text
project.yml          XcodeGen project definition: targets, build settings, Info.plist keys
Config/              Signing settings (xcconfig)
LaunchSweep/
  App/               App entry point and window
  Model/             Reading the lsregister dump, deciding what is stale, window state
  Views/             SwiftUI views, colors and button styles
  Resources/         Asset catalog (app icon) and Localizable.xcstrings
  Info.plist         Generated from project.yml by XcodeGen; change project.yml instead
Tests/               Unit tests (Swift Testing) for the dump parser, the analyzer and the window state
Scripts/             build_icon.sh
design/logo/         Source SVG of the app icon
```

How a scan works: `LaunchServices` runs `lsregister -dump`, `LaunchServicesDump` turns the text into
`Registration` values, `Analyzer` groups them by app bundle and decides which are stale and why, and
`RegistrationModel` holds the result and the selection for the views. The model reaches the system through
the `RegistrationStore` protocol, so the tests run it against a database in memory. When the app is launched
as the host of the unit tests it shows no window and does not scan.

## Languages

English, Simplified Chinese, Traditional Chinese, Japanese, Spanish, Korean, French and German.

Text is written in English in the code; translations are in `LaunchSweep/Resources/Localizable.xcstrings`.
Building in Xcode adds new text to the catalog. Translate it into all seven other languages before
committing. Text that contains a count uses the catalog's plural variations ("Vary by Plural") rather than
separate texts chosen in code.

## App icon

The icon is drawn in `design/logo/launchsweep-icon-1024.svg`. After changing it, run `make icon` (needs Node)
to regenerate the PNGs in the asset catalog, and commit them. `LaunchSweep/Views/ListMotif.swift` draws the
same icon in code, so keep the two in step.

## License

[MIT](LICENSE)
