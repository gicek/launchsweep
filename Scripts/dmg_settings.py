# dmgbuild settings for the LaunchSweep DMG (used by Scripts/release.sh; not run on its own).
# dmgbuild writes the volume's .DS_Store directly instead of scripting Finder, so it needs no automation
# permission and gives the same layout every time.
# ruff: noqa: F821  # `defines` is injected by dmgbuild

import os.path

app = defines["app"]  # path to LaunchSweep.app
app_name = os.path.basename(app)

format = "UDZO"  # zlib; opens on every supported macOS version
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}

# The volume shows the app's own icon.
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")

# The app on the left, the Applications folder on the right, on Finder's plain background.
window_rect = ((200, 160), (600, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
icon_locations = {
    app_name: (160, 170),
    "Applications": (440, 170),
}
# No hide_extensions: it sets Finder info on the app bundle, which then fails `codesign --strict` after
# it is copied to Applications. Finder hides the .app extension by default anyway.
