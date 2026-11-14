extends SceneTree
## Comprueba que los emisores salen de data/particles.json y la escena arranca.

const Fx = preload("res://scripts/particle_fx.gd")


func _init() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/particles.json"))
	var host := Node.new()
	get_root().add_child(host)
	var fx := Node.new()
	fx.set_script(Fx)
	host.add_child(fx)
	await process_frame
	var bad := 0
	var presets: Dictionary = data["presets"]
	for id in presets.keys():
		var want := int(presets[id]["amount"])
		var got := int(fx.call("preset_amount", str(id)))
		if got != want:
			bad += 1
			print("MAL ", id, " ", got, " != ", want)
		else:
			print("OK ", id, " ", got)
	fx.call("play", "splash", Vector3(1.2, 0.15, 2.0), Color(0, 0, 0, 0))
	fx.call("play", "sparkle", Vector3(1.2, 0.15, 2.0), Color.html("#C45B86"))
	fx.call("stop", "bubbles")
	var packed := load("res://scenes/Main.tscn") as PackedScene
	var main := packed.instantiate()
	get_root().add_child(main)
	for _i in 6:
		await process_frame
	var fishing := main.get_node_or_null("Fishing")
	if fishing == null or fishing.get_node_or_null("ParticleFx") == null:
		bad += 1
		print("MAL sin ParticleFx")
	else:
		print("OK escena")
	if bad == 0:
		print("PARTICLE_AUDIT_OK")
		quit(0)
	else:
		print("PARTICLE_AUDIT_FAIL ", bad)
		quit(1)
