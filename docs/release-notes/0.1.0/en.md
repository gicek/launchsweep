The first release of LaunchSweep.

LaunchSweep finds apps registered with Launch Services that probably should not be, and unregisters the
ones you pick. Stale registrations are why the app launcher, Spotlight and "Open With" sometimes point at
a build copy or a deleted app instead of the installed one.

- **Scans the whole database** with no input, and groups what it finds: apps no longer on disk, in the
  Trash, in temporary locations, in build output, on mounted volumes, and duplicate copies.
- **Selects what is safe** to unregister by default; mounted volumes and duplicate copies are left for
  you to choose.
- **Registers the installed copy again** after unregistering, so the app launcher shows it.
- **Move to Trash and Unregister** for copies that macOS would otherwise register again.
- In English, Simplified Chinese, Traditional Chinese, Japanese, Spanish, Korean, French and German.

Requires macOS 14 or later. Open the disk image and drag LaunchSweep to Applications.
