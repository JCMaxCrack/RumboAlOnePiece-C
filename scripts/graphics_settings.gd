extends Node
## GraphicsSettings (autoload, see project.godot): graphics quality of the game.
##
## Three presets (Bajo / Medio / Alto) change shadows, draw distance (how far chunks are loaded),
## vegetation distance and density, terrain detail, ambient occlusion, glow, antialiasing, the
## number of dynamic lights and occlusion culling. The render resolution (50-100 %) is separate:
## a lower value draws the 3D world with fewer pixels (FSR upscaling on Forward+/Mobile).
## The choice is kept in user://ajustes.cfg (not in the save slots). The first time, a preset is
## chosen from the device (phone -> Bajo/Medio, integrated GPU -> Medio, dedicated GPU -> Alto).
##
## The game scene calls apply_world() with its nodes; the rest (viewport, shadow atlas) is global.
## Light budget: lights in the group "dynamic_lights" are switched on only if they are among the
## N closest to the camera and inside the preset distance. A light that the game wants off (for
## example an inactive checkpoint) has the meta "wanted" = false.

signal changed

enum Preset { LOW, MEDIUM, HIGH }

const NAMES := ["Low", "Medium", "High"]
const FILE := "user://ajustes.cfg"
const PRESETS := {
	Preset.LOW: {
		"description": "For phones and low-end PCs: no shadows or effects, shorter view distance.",
		"shadows": false, "shadow_mode": DirectionalLight3D.SHADOW_ORTHOGONAL, "shadow_distance": 0.0, "shadow_atlas": 1024, "soft_shadows": 0,
		"chunk_radius": 110.0, "camera_far": 320.0, "fog_density": 0.0034,
		"grass_range": 30.0, "grass_density": 0.35, "bush_range": 65.0, "rock_range": 90.0, "terrain_detail_range": 60.0,
		"vegetation_shadows": false, "ssao": false, "glow": false, "msaa": Viewport.MSAA_DISABLED, "fxaa": true,
		"lights": 2, "light_distance": 18.0, "lod_threshold": 4.0, "occlusion": false,
	},
	Preset.MEDIUM: {
		"description": "Balanced: close shadows, glow and longer draw distance.",
		"shadows": true, "shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "shadow_distance": 60.0, "shadow_atlas": 2048, "soft_shadows": 1,
		"chunk_radius": 160.0, "camera_far": 450.0, "fog_density": 0.0026,
		"grass_range": 45.0, "grass_density": 0.65, "bush_range": 100.0, "rock_range": 140.0, "terrain_detail_range": 100.0,
		"vegetation_shadows": true, "ssao": false, "glow": true, "msaa": Viewport.MSAA_2X, "fxaa": false,
		"lights": 6, "light_distance": 35.0, "lod_threshold": 2.0, "occlusion": true,
	},
	Preset.HIGH: {
		"description": "For powerful PCs: soft distant shadows, ambient occlusion and the whole island.",
		"shadows": true, "shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "shadow_distance": 110.0, "shadow_atlas": 4096, "soft_shadows": 3,
		"chunk_radius": 240.0, "camera_far": 700.0, "fog_density": 0.0016,
		"grass_range": 70.0, "grass_density": 1.0, "bush_range": 170.0, "rock_range": 230.0, "terrain_detail_range": 150.0,
		"vegetation_shadows": true, "ssao": true, "glow": true, "msaa": Viewport.MSAA_4X, "fxaa": false,
		"lights": 12, "light_distance": 60.0, "lod_threshold": 1.0, "occlusion": true,
	},
}

var preset: int = Preset.MEDIUM
## 0.5 - 1.0 of the window resolution for the 3D world (the interface is always sharp).
var render_scale := 1.0
var show_fps := false
## PC: full screen (F11 or Alt+Enter also switch it). The image always fills the screen: the 3D
## view takes the whole window and the interface keeps its proportions (stretch "expand").
var fullscreen := true
var _light_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _load():
		_pick_default()
	apply_global()
	apply_window()


func settings() -> Dictionary:
	return PRESETS[preset]


func renderer() -> String:
	return RenderingServer.get_current_rendering_method()


func set_preset(p: int) -> void:
	preset = clampi(p, Preset.LOW, Preset.HIGH)
	_save()
	apply_global()
	changed.emit()


func set_render_scale(s: float) -> void:
	render_scale = clampf(s, 0.5, 1.0)
	_save()
	apply_global()
	changed.emit()


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_save()
	apply_window()
	changed.emit()


func can_change_window() -> bool:
	return not (OS.has_feature("mobile") or OS.has_feature("web") or DisplayServer.get_name() == "headless")


func apply_window() -> void:
	if not can_change_window():
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	var now := DisplayServer.window_get_mode()
	if fullscreen and (now == DisplayServer.WINDOW_MODE_FULLSCREEN or now == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN):
		return
	if not fullscreen and (now == DisplayServer.WINDOW_MODE_WINDOWED or now == DisplayServer.WINDOW_MODE_MAXIMIZED):
		return
	DisplayServer.window_set_mode(want)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen") and can_change_window():
		get_viewport().set_input_as_handled()
		set_fullscreen(not fullscreen)


func set_show_fps(on: bool) -> void:
	show_fps = on
	_save()
	changed.emit()


# ------------------------------------------------------------------ applying
## Settings that do not depend on the scene: root viewport and shadow atlas.
func apply_global() -> void:
	var s := settings()
	var vp := get_viewport()
	var rd_based := renderer() != "gl_compatibility"
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if rd_based and render_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = render_scale
	vp.msaa_3d = s.msaa
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if s.fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.mesh_lod_threshold = s.lod_threshold
	vp.use_occlusion_culling = s.occlusion and ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", false)
	RenderingServer.directional_shadow_atlas_set_size(s.shadow_atlas, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(s.soft_shadows)
	RenderingServer.positional_soft_shadow_filter_set_quality(s.soft_shadows)


## Settings of the game scene (environment, sun, camera, chunks, terrain).
func apply_world(env: Environment, sun: DirectionalLight3D, camera: Camera3D, chunks: ChunkManager) -> void:
	var s := settings()
	if env:
		env.ssao_enabled = s.ssao
		env.glow_enabled = s.glow
		env.fog_density = s.fog_density
	if sun:
		sun.shadow_enabled = s.shadows
		sun.directional_shadow_mode = s.shadow_mode
		sun.directional_shadow_max_distance = maxf(1.0, s.shadow_distance)
	if camera:
		camera.far = s.camera_far
	if chunks:
		chunks.apply_quality(s)


func _process(delta: float) -> void:
	_light_timer -= delta
	if _light_timer > 0.0:
		return
	_light_timer = 0.3
	_update_light_budget()


## Only the N closest dynamic lights (inside the preset distance) are on.
func _update_light_budget() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var s := settings()
	var p := cam.global_position
	var max_d2: float = s.light_distance * s.light_distance
	var candidates := []
	for n in get_tree().get_nodes_in_group("dynamic_lights"):
		var l := n as Light3D
		if l == null:
			continue
		var d2 := p.distance_squared_to(l.global_position)
		if bool(l.get_meta("wanted", true)) and d2 <= max_d2:
			candidates.append([d2, l])
		else:
			l.visible = false
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	for i in candidates.size():
		(candidates[i][1] as Light3D).visible = i < int(s.lights)


# ------------------------------------------------------------------ file
func _pick_default() -> void:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		preset = Preset.LOW if renderer() == "gl_compatibility" else Preset.MEDIUM
		render_scale = 0.75
	elif renderer() == "gl_compatibility":
		preset = Preset.LOW
	else:
		match RenderingServer.get_video_adapter_type():
			RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
				preset = Preset.HIGH
			RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
				preset = Preset.MEDIUM
			_:
				preset = Preset.MEDIUM


func _load() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(FILE) != OK:
		return false
	preset = clampi(int(cfg.get_value("graficos", "preset", Preset.MEDIUM)), Preset.LOW, Preset.HIGH)
	render_scale = clampf(float(cfg.get_value("graficos", "escala_render", 1.0)), 0.5, 1.0)
	show_fps = bool(cfg.get_value("graficos", "mostrar_fps", false))
	fullscreen = bool(cfg.get_value("graficos", "pantalla_completa", true))
	return true


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graficos", "preset", preset)
	cfg.set_value("graficos", "escala_render", render_scale)
	cfg.set_value("graficos", "mostrar_fps", show_fps)
	cfg.set_value("graficos", "pantalla_completa", fullscreen)
	cfg.save(FILE)
