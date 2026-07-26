extends Destructible
class_name Breakable

## A destructible piece of scenery — HP and a death, but no brain.
##
## The third category alongside Enemy and the interactables: something the player
## can smash for a reward, that never makes a decision. A mushroom, a crate, a
## pot. Everything it does — taking damage, dying, the hit flash, the death VFX —
## already lives in Destructible, so this class is deliberately almost empty. Its
## job is to EXIST as a distinct type, so a level can ask for the breakables
## without also getting the enemies.
##
## Bump-destructible out of the box: its HitBox sits on the `hurtbox` layer, which
## is what the player's BumpCombatComponent scans, so running into one damages it
## through exactly the same path as an enemy. Set `max_hp` at or below the bump's
## minimum damage (5) and any bump from any angle kills it in one hit.
##
## Loot is not this class's business either — add a DropComponent for that.
##
## Bodies are `collision_layer = 0` like enemies, so the player runs THROUGH a
## breakable rather than into it. That is what makes a bump land cleanly. If you
## want one to physically block, give it a CollisionShape3D on the `environment`
## layer — but expect bumping it to feel different, because the player stops dead
## on contact instead of running past.


func _ready() -> void:
	add_to_group("breakable")
	super._ready()


func _label() -> String:
	return "Breakable:" + String(name)


func _death_message() -> String:
	return "Smashed!"
