extends Resource
class_name FseEnemyData

## Stats for a rails-shooter enemy. The visible body and behavior components live
## on the enemy scene itself (editor-visible); this resource only carries tunable
## numbers shared across instances of an enemy type.

@export var display_name: StringName = &"Enemy"
@export var max_hp: int = 100
## Base movement speed in world units/sec; movement patterns scale off this.
@export var move_speed: float = 6.0
## Damage dealt to the player on body contact.
@export var contact_damage: int = 10
## Points awarded when destroyed (logged for now).
@export var score: int = 100
