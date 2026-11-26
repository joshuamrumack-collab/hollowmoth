extends Node
## PF1e-style dice and attack resolution, used by every combatant.
## The hitbox decides IF a blow connects; this decides HOW WELL.

signal logged(text: String)

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()


func d(sides: int) -> int:
	return rng.randi_range(1, sides)


## Roll NdS + bonus.
func roll(n: int, sides: int, bonus: int = 0) -> int:
	var total := bonus
	for i in n:
		total += d(sides)
	return total


func mod(score: int) -> int:
	return floori((score - 10) / 2.0)


## Resolves one attack. Returns a Dictionary:
## {result: "hit"|"graze"|"crit", damage: int, roll: int, total: int, ac: int}
## attack = {bonus, dice_n, dice_s, dmg_bonus, threat, mult, extra_n, extra_s (precision dice, not multiplied), name}
func resolve_attack(attacker, target, attack: Dictionary) -> Dictionary:
	var flat: bool = target.is_flat_footed() or attack.get("force_flat", false)
	var ac: int = target.get_ac(flat)
	var bonus: int = attack.get("bonus", 0)
	var nat := d(20)
	var total := nat + bonus
	var threat: int = attack.get("threat", 20)
	var hit := (nat == 20) or (nat != 1 and total >= ac)
	var crit := false
	if hit and (nat >= threat or attack.get("auto_threat", false)):
		var confirm := d(20) + bonus
		crit = confirm >= ac
	var base := roll(attack.get("dice_n", 1), attack.get("dice_s", 6), attack.get("dmg_bonus", 0))
	base = max(base, 1)
	var dmg := base
	if crit:
		dmg = 0
		for i in int(attack.get("mult", 2)):
			dmg += max(roll(attack.get("dice_n", 1), attack.get("dice_s", 6), attack.get("dmg_bonus", 0)), 1)
	var extra := 0
	if attack.get("extra_n", 0) > 0:
		extra = roll(attack.get("extra_n", 0), attack.get("extra_s", 6))
	dmg += extra
	var result := "crit" if crit else ("hit" if hit else "graze")
	if not hit:
		dmg = max(1, int(round(dmg * 0.25)))
	var line := "%s %s: d20 %d%+d=%d vs AC %d%s -> %s %d" % [
		attacker.display_name, attack.get("name", "attack"), nat, bonus, total, ac,
		" (flat-footed)" if flat else "", result.to_upper(), dmg]
	logged.emit(line)
	return {"result": result, "damage": dmg, "roll": nat, "total": total, "ac": ac, "flat": flat}


## Saving throw. Returns true if the save SUCCEEDS.
func save(target, kind: String, dc: int, label: String) -> bool:
	var bonus: int = target.get_save(kind)
	var nat := d(20)
	var ok := nat == 20 or (nat != 1 and nat + bonus >= dc)
	logged.emit("%s %s save vs %s: d20 %d%+d vs DC %d -> %s" % [
		target.display_name, kind, label, nat, bonus, dc, "SAVED" if ok else "FAILED"])
	return ok
