extends Node3D
class_name BaseProjectile

## Straight-flying projectile. Damage is delivered two ways so it works for both
## sides of the rails game:
##   - area_entered  -> enemy HitBox (Area3D exposing receive_hit(amount))
##   - body_entered  -> a body in group_to_damage exposing take_damage/receive_attack
## Collision masks on the scene's Area3D decide what each projectile can hit.

@export var speed: float = 60.0
@export var damage: float = 10.0
@export var life_time: float = 2.0
## Group a hit *body* must belong to for body-based damage (e.g. "player").
@export var group_to_damage: StringName = &"enemy"

@onready var collider: Area3D = $Area3D

var _direction: Vector3 = Vector3.FORWARD
var _shooter: Node = null


func _ready() -> void:
	get_tree().create_timer(life_time).timeout.connect(queue_free)
	collider.body_entered.connect(_on_body_entered)
	collider.area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	global_position += _direction * speed * delta


func launch(from: Transform3D, initial_direction: Vector3, shooter: Node = null) -> void:
	global_transform = from
	_direction = initial_direction.normalized()
	_shooter = shooter


func _on_area_entered(area: Area3D) -> void:
	# Enemy HitBox path: the area knows how to route damage to its enemy.
	if area.has_method("receive_hit"):
		var amount: int = roundi(damage)
		area.call("receive_hit", amount)
		if Events:
			Events.attack_hit.emit(_shooter, area, amount)
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body == _shooter:
		return

	if body.is_in_group(group_to_damage):
		var damage_amount: int = roundi(damage)
		if body.has_method("take_damage"):
			body.call("take_damage", damage_amount)
		elif body.has_method("receive_attack"):
			body.call("receive_attack", damage_amount)
		elif body.has_method("on_damage"):
			body.call("on_damage", damage_amount)
		if Events:
			Events.attack_hit.emit(_shooter, body, damage_amount)

	queue_free()
