extends SceneTree
## Launcher note: the live capture path is Studio (-- --capture).
## Use tools/capture_thumbs.ps1 from the repo root.


func _initialize() -> void:
	push_warning("Run tools/capture_thumbs.ps1 instead of this script.")
	quit()
