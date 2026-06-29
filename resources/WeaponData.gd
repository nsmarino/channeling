extends Resource
class_name WeaponData

@export var display_name: StringName = &"Blaster"
@export var fire_rate: float = 0.2
@export var projectile_scene: PackedScene
@export var muzzle_velocity: float = 60.0
@export var burst_count: int = 1
@export var damage: float = 10.0
@export var ammo_count: int = -1
@export var is_automatic: bool = true
