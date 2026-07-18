extends CanvasLayer

## Global cinematic overlay + control-handoff broker. Autoloaded so it sits above
## every scene (HUD included) and is reachable from anywhere as `Cinematic`.
##
## Owns two things:
##   - the letterbox: two black bars that slide in from the top and bottom, and
##   - the cutscene bracket: `begin()` emits Events.cutscene_started (the player
##     freezes itself and hands over its camera) and `end()`, once the bars have
##     retracted, emits Events.cutscene_finished (control returns).
##
## Typical flow (see objects/cutscene/): a trigger calls `Cinematic.begin()` then
## plays a local AnimationPlayer timeline whose final Call-Method key calls
## `Cinematic.end()`.

## Height of each bar (px) at full letterbox.
@export var bar_height: float = 90.0
## How long the bars take to slide in / out (seconds).
@export var slide_duration: float = 0.4

var _top: ColorRect = null
var _bottom: ColorRect = null
var _tween: Tween = null


func _ready() -> void:
	# Above the HUD (a plain CanvasLayer sits at layer 1).
	layer = 128
	_top = _make_bar(true)
	_bottom = _make_bar(false)


## Start a cutscene: raise the letterbox and tell the world (the player suspends
## itself). Pass -1 to fall back to the exported defaults.
func begin(height: float = -1.0, duration: float = -1.0) -> void:
	var h: float = bar_height if height < 0.0 else height
	var d: float = slide_duration if duration < 0.0 else duration
	Events.cutscene_started.emit()
	_slide(h, -h, d)


## End a cutscene: drop the letterbox, and once it's gone return control.
func end(duration: float = -1.0) -> void:
	var d: float = slide_duration if duration < 0.0 else duration
	var tw := _slide(0.0, 0.0, d)
	tw.finished.connect(func() -> void: Events.cutscene_finished.emit(), CONNECT_ONE_SHOT)


## Move the bars to their targets, replacing any in-flight slide. `top_target` is
## the top bar's bottom edge; `bottom_target` is the bottom bar's top edge.
func _slide(top_target: float, bottom_target: float, duration: float) -> Tween:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_top, ^"offset_bottom", top_target, duration)
	_tween.tween_property(_bottom, ^"offset_top", bottom_target, duration)
	return _tween


## A full-width black bar anchored to the top (or bottom) edge, collapsed to zero
## height. Anchors keep it correct across viewport resizes.
func _make_bar(is_top: bool) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color.BLACK
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	if is_top:
		bar.anchor_top = 0.0
		bar.anchor_bottom = 0.0
	else:
		bar.anchor_top = 1.0
		bar.anchor_bottom = 1.0
	bar.offset_left = 0.0
	bar.offset_right = 0.0
	bar.offset_top = 0.0
	bar.offset_bottom = 0.0
	add_child(bar)
	return bar
