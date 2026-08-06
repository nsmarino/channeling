extends PlayerAbility
class_name HealAbility

## Convert a full bank of power into health.
##
## The exchange rate is the point: power is only earned by fighting, so healing is
## paid for by the encounter you are currently in. Costing the ENTIRE bank (10 of
## 10 by default) makes it a real decision rather than a tax — the same power buys
## two Power Dives, so topping up is always giving something else up.
##
## Refuses at full health instead of firing and wasting the bank. That is a guard
## against the player, not against the code: nothing breaks if it heals for zero,
## but silently eating ten power for nothing is indistinguishable from a bug.

## Health restored per use.
@export_range(0, 20, 1) var heal_amount: int = 3
## Refuse when it would heal for nothing. Off = you may burn the bank at full HP.
@export var block_at_full_health: bool = true


func _can_activate() -> bool:
	if body == null:
		return false
	if block_at_full_health and body.has_method("is_at_full_health") \
			and bool(body.call("is_at_full_health")):
		return false
	return true


func _activate() -> void:
	if body == null or not body.has_method("heal"):
		return
	var restored: int = int(body.call("heal", heal_amount))
	if debug_log:
		print("[%s] Healed %d" % [String(name), restored])
