extends "res://tests/network_test.gd"
## Compatibility entry; old --client flag maps to the migrated probe.
func _initialize() -> void:
	if "--client" in OS.get_cmdline_user_args():
		role = "client"
	super._initialize()
