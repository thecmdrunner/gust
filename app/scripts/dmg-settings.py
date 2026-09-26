# dmgbuild settings for Gust.dmg. Paths are passed with -D app=... -D root=...
import os.path

app = defines["app"]
root = defines["root"]

files = [app]
symlinks = {"Applications": "/Applications"}
format = "UDZO"
filesystem = "HFS+"
icon = os.path.join(root, "Resources/AppIcon.icns")
background = os.path.join(root, "Resources/dmg-background.tiff")

window_rect = ((200, 140), (660, 400))
icon_size = 112
text_size = 13
icon_locations = {os.path.basename(app): (180, 190), "Applications": (480, 190)}
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
hide_extension = [os.path.basename(app)]
