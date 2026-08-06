extends Component
class_name FloatingTextComponent

## Pops a short-lived line of text above the host that drifts upward and fades —
## the WoW damage-number idiom, used here to call out whether a bump landed on a
## creature's FRONT or BACK.
##
## Deliberately a DUMB RENDERER. It knows how to make text float; it does not know
## what the text means. Callers pass the string and the colour, which is what lets
## the same component serve the hit-direction callout today and damage numbers,
## status callouts or pickup counts later without gaining a single branch.
##
## Per-enemy rather than global because the one number that must differ per
## creature is `height_offset` — a label pitched for a Manicoppo floats inside an
## Essurou's head and above a mushroom's.
##
## LABELS ARE PARENTED TO THE SCENE, NOT TO THE HOST. A killing blow is exactly
## when you most want to read the feedback, and a label parented to the creature
## would be freed along with it — so it goes in the scene root, the same place
## Blast and PowerDrop go for the same reason. The trade is that it does not track
## a moving target: it marks WHERE the hit landed and stays there, which for a
## sub-second float reads better than chasing the body anyway.
##
## Label3D does the hard parts natively — `billboard` keeps it facing the camera,
## `fixed_size` holds one screen size at any distance so it stays readable across
## the room, and `no_depth_test` draws it over geometry so a hit behind a pillar
## is not silently swallowed. No shader, no viewport, no unproject math.

@export var enabled: bool = true

@export_group("Placement")
## Height above the host's origin the text spawns at. The one value worth setting
## per creature.
@export var height_offset: float = 2.2
## Random horizontal scatter, so two hits in quick succession don't stack into an
## unreadable smear.
@export_range(0.0, 2.0, 0.05) var horizontal_jitter: float = 0.35

@export_group("Motion")
## How far it drifts up over its life.
@export var rise_distance: float = 1.3
## Seconds from pop to gone.
@export var duration: float = 0.9

@export_group("Appearance")
## Glyph resolution, NOT on-screen size — `pixel_size` sets that. Keep this high
## for crisp text and scale with pixel_size instead.
@export var font_size: int = 64
## World units per glyph pixel, and the knob that actually controls how big the
## callout looks. With `fixed_screen_size` on, font_size alone reads as a
## screen-space measure, so leaving this at Godot's 0.005 default renders a word
## roughly a third of the viewport wide.
@export_range(0.0001, 0.02, 0.0001) var pixel_size: float = 0.0009
@export var outline_size: int = 14
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.85)
## Constant on-screen size regardless of distance. Off = true 3D perspective
## scaling, which makes distant callouts unreadable.
@export var fixed_screen_size: bool = true
## Draw over geometry rather than being occluded by it.
@export var draw_through_walls: bool = true


## Pop a line of text. The whole public surface.
func show_text(text: String, color: Color) -> void:
	if not enabled or text.is_empty():
		return
	var host3d := host as Node3D
	var world: Node = get_tree().current_scene
	if host3d == null or world == null:
		return

	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.outline_size = outline_size
	label.outline_modulate = outline_color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = fixed_screen_size
	label.no_depth_test = draw_through_walls
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Above the world it annotates, and above other transparent surfaces.
	label.render_priority = 10
	label.outline_render_priority = 9

	world.add_child(label)
	var start: Vector3 = host3d.global_position + Vector3(
		randf_range(-horizontal_jitter, horizontal_jitter),
		height_offset,
		randf_range(-horizontal_jitter, horizontal_jitter))
	label.global_position = start

	# Tween created ON THE LABEL, not on this component. A tween is bound to the
	# node that made it, so one made here would be killed the moment the creature
	# is freed — taking the killing blow's own callout with it.
	var tween: Tween = label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", start.y + rise_distance, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Fades late rather than linearly, so it is legible for most of its life and
	# then leaves quickly.
	tween.tween_property(label, "modulate:a", 0.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.finished.connect(label.queue_free)
