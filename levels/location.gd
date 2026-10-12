extends Node3D
class_name Location

## Root of a location scene (see levels/template_scene.tscn). Main still loads any
## Node3D root; this script only adds a place for per-location notes and settings.
##
## OVERRIDES. Main holds what every location shares: the WorldEnvironment, the
## music, GameManager's fall limit. A location may replace any of these for as
## long as it is loaded; an empty or unticked override keeps Main's. Main applies
## them on every load (startup and portal trips) and restores its own defaults when
## a location doesn't set one, so nothing carries over into the next location.
##
## To add an override: export it here (empty/unticked must mean "keep Main's"),
## then apply it in Main._apply_location_overrides() and restore the harness
## default there when unset.

## What this location is for, what works, what to try next. Read it when you come
## back to the level after working on another.
@export_multiline var notes: String = ""

@export_group("Overrides")
## Replaces Main's WorldEnvironment while this location is loaded. Empty = Main's.
@export var environment: Environment
## Music for this location. Empty = Main's track. Unchanged if it's already playing.
@export var music: AudioStream
## Use this location's `fall_limit_y` instead of GameManager's.
@export var override_fall_limit: bool = false
## Restart when the player drops below this Y (only with `override_fall_limit`).
@export var fall_limit_y: float = -50.0
