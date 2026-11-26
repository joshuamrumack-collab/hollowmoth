extends RefCounted
## Party brains: one Beehave behaviour tree per hero, built in code.
##
## hero.gd keeps the reflexes (dodging, parrying, regrouping, drinking when nearly dead)
## and picks a sensible target; the tree on top decides what this particular person
## does with the fight. Root is a reactive selector: every tick the first branch whose
## condition holds wins, so a hero drops whatever they were doing when something they
## care about more comes up.
##
##   Average  - show-off: charges the biggest thing in the fight, bellows LOOK AT ME
##              when a friend is in trouble, poses after kills.
##   Brokk    - grudge-keeper: hunts whatever is in his book, shoots casters first,
##              keeps his distance, curses anyone who gets close.
##   Eowilas  - protector: heals the worst-off first, breaks chains, steps between
##              brutes and the soft members of the party.
##   Puck     - opportunist: herb smoke on crowds, stabs whatever isn't looking.

const DO := preload("res://scripts/ai/bt_do.gd")
const IF := preload("res://scripts/ai/bt_if.gd")


static func build(h: Node) -> BeehaveTree:
	var root: Node
	match h.hero_id:
		"average": root = _average()
		"brokk": root = _brokk()
		"sael": root = _eowilas()
		"puck": root = _puck()
	var tree := BeehaveTree.new()
	tree.name = "Brain"
	tree.process_thread = BeehaveTree.ProcessThread.MANUAL
	tree.add_child(root)
	tree.actor = h
	return tree


# ------------------------------------------------------------------ builders

static func sel(n: String, kids: Array) -> Node:
	var s := SelectorReactiveComposite.new()
	s.name = n
	for k in kids:
		s.add_child(k)
	return s


static func seq(n: String, kids: Array) -> Node:
	var s := SequenceComposite.new()
	s.name = n
	for k in kids:
		s.add_child(k)
	return s


static func act(n: String, fn: Callable) -> Node:
	var a := DO.new()
	a.name = n
	a.fn = fn
	return a


static func cond(n: String, fn: Callable) -> Node:
	var c := IF.new()
	c.name = n
	c.fn = fn
	return c


static func cooldown(secs: float, child: Node) -> Node:
	var d := CooldownDecorator.new()
	d.name = "every %ds" % int(secs)
	d.wait_time = secs
	d.add_child(child)
	return d


# A branch: "when <test>, do <fn>".
static func when(n: String, test: Callable, fn: Callable) -> Node:
	return seq(n, [cond(n + "?", test), act(n, fn)])


# ------------------------------------------------------------------ shared helpers

static func _aware_enemies(h: Node, r: float) -> Array:
	return h.main.enemies.filter(func(e): return not e.is_dead() and e.aware and e.global_position.distance_to(h.global_position) < r)


static func _go_hit(h: Node, reach: float) -> int:
	h._approach_and_hit(reach)
	return BeehaveTree.SUCCESS


static func _target(h: Node, e: Node) -> void:
	h.ai_target = e
	h.think_t = 0.6   # keep this choice for a moment instead of re-picking


# ================================================================== AVERAGE

static func _average() -> Node:
	return sel("Average", [
		# Showboat: just killed something and nothing is in his face -> flex for the crowd
		cooldown(9.0, when("Showboat",
			func(h): return h.since_kill < 1.5 and h.main.enemies_within(h.global_position, 30.0) == 0,
			func(h):
				h.emote("flex", 1.2)
				h.bark(["LOOK AT ME!", "Did you SEE that?", "Next!", "Too easy!"].pick_random())
				return BeehaveTree.SUCCESS)),
		# LOOK AT ME: something is going for a friend -> bellow and pull it onto himself
		cooldown(8.0, when("Look at me",
			func(h): return _bully_of_friend(h) != null,
			func(h):
				var e: Node = _bully_of_friend(h)
				e.target = h
				e.think_t = 2.5
				_target(h, e)
				h.bark("HEY! LOOK AT ME!")
				h.glory = min(100.0, h.glory + 5.0)
				Sfx.play("roar", h.global_position, -10.0, 0.2)
				h.main.float_text(e.global_position + Vector2(0, -e.sprite_h - 6), "!", Color(1.0, 0.6, 0.3), 0.8)
				return BeehaveTree.SUCCESS)),
		when("Rage",
			func(h): return h.main.tactics_rage and h.cd("rage") <= 0.0 and h.main.enemies_within(h.global_position, 50.0) >= 1,
			func(h):
				h.ability(1)
				return BeehaveTree.SUCCESS),
		when("Glory",
			func(h): return h.glory >= 100.0,
			func(h):
				h.ability(2)
				return BeehaveTree.SUCCESS),
		when("Slam",
			func(h): return h.main.enemies_within(h.global_position, 44.0) >= 2 and h.cd("slam") <= 0.0 and h.stamina > 30.0,
			func(h):
				h.use_cast()
				return BeehaveTree.SUCCESS),
		when("Execute",
			func(h): return h.ai_target is Enemy and h.ai_target.has("staggered") and h.stamina > 35.0 and h.global_position.distance_to(h.ai_target.global_position) < 28.0,
			func(h):
				h.aim = (h.ai_target.global_position - h.global_position).normalized()
				h.use_special()
				return BeehaveTree.SUCCESS),
		# Prove himself: the biggest thing in the fight is his
		when("Biggest one",
			func(h): return _biggest(h) != null,
			func(h):
				var e: Node = _biggest(h)
				if e != h.ai_target:
					_target(h, e)
					if h.claimed != e:
						h.claimed = e
						h.bark(["That big one's MINE!", "Out of the way, he's mine!", "Finally, a real one!"].pick_random())
				var d: float = h.global_position.distance_to(e.global_position)
				# close the gap with a running charge
				if d > 60.0 and d < 120.0 and h.cd("charge_ai") <= 0.0 and h.stamina > 40.0:
					h.cds["charge_ai"] = 4.0
					h.start_dash((e.global_position - h.global_position).normalized())
					return BeehaveTree.SUCCESS
				return _go_hit(h, 20.0)),
		act("Brawl", func(h): return _go_hit(h, 20.0)),
	])


## An aware enemy going for someone other than Average, near enough to matter.
static func _bully_of_friend(h: Node) -> Node:
	for e in _aware_enemies(h, 150.0):
		if e.target != null and e.target != h and e.target is Hero and e.global_position.distance_to(e.target.global_position) < 40.0:
			return e
	return null


## The biggest aware enemy within charging range (worth proving himself on).
static func _biggest(h: Node) -> Node:
	var best: Node = null
	for e in _aware_enemies(h, 200.0):
		if e.max_hp < 30 or e.kind in ["moth_swarm", "mirror_clone"]:
			continue
		if best == null or e.max_hp > best.max_hp:
			best = e
	return best


# ================================================================== BROKK

static func _brokk() -> Node:
	return sel("Brokk", [
		when("Back off",
			func(h): return h.main.nearest_enemy_dist(h.global_position) < 55.0 and not h.has("stand"),
			func(h):
				h.move_input = h.main.flee_vector(h)
				if h.main.nearest_enemy_dist(h.global_position) < 25.0 and h.dodge_cd <= 0.0:
					h.dodge_cd = 1.2
					h.start_dash(h.main._safe_dir(h.global_position, h.main.flee_vector(h)))
				if h.cd("curse_ai") <= 0.0:
					h.cds["curse_ai"] = 6.0
					h.bark(["Get OFF me!", "Personal space, you corpse!", "Oi! Too close!"].pick_random())
				return BeehaveTree.SUCCESS),
		# Grudges: anything in his book gets shot first
		when("Grudge",
			func(h): return _grudged(h) != null and _grudged(h) != h.ai_target,
			func(h):
				var e: Node = _grudged(h)
				_target(h, e)
				if h.cd("grudge_bark") <= 0.0:
					h.cds["grudge_bark"] = 10.0
					h.bark(["You're in the BOOK!", "I remember your kind.", "Page %d. You." % randi_range(12, 90)].pick_random())
				return BeehaveTree.SUCCESS),
		when("Casters first",
			func(h): return _caster(h) != null and _caster(h) != h.ai_target,
			func(h):
				_target(h, _caster(h))
				return BeehaveTree.SUCCESS),
		when("Get in range",
			func(h): return h.global_position.distance_to(h.ai_target.global_position) > 170.0,
			func(h):
				# anything already in range will do; only walk if nothing is
				var near: Array = _aware_enemies(h, 160.0)
				if not near.is_empty():
					near.sort_custom(func(a, b): return a.global_position.distance_to(h.global_position) < b.global_position.distance_to(h.global_position))
					_target(h, near[0])
					return BeehaveTree.SUCCESS
				h.move_input = (h.ai_target.global_position - h.global_position).normalized()
				return BeehaveTree.SUCCESS),
		when("Spell arrow",
			func(h): return h.arcane_pool > 0 and h.cd("spell_ai") <= 0.0 and (h.ai_target.max_hp > 30 or h.ai_target.kind == "cultist"),
			func(h):
				h.cds["spell_ai"] = 4.0
				h.aim = (h.ai_target.global_position - h.global_position).normalized()
				h.facing = h.aim
				h.spell_index = 0 if not h.ai_target.is_boss else 1
				h.use_cast()
				return BeehaveTree.SUCCESS),
		act("Shoot", func(h):
			h.aim = (h.ai_target.global_position - h.global_position).normalized()
			h.facing = h.aim
			if h.stamina > 12.0:
				h.use_attack()
			return BeehaveTree.SUCCESS),
	])


static func _grudged(h: Node) -> Node:
	var best: Node = null
	for e in _aware_enemies(h, 165.0):
		if h.grudges.has(e.kind) and (best == null or e.hp < best.hp):
			best = e
	return best


static func _caster(h: Node) -> Node:
	for e in _aware_enemies(h, 165.0):
		if e.kind in ["cultist", "mirror_clone"] or (e.state == Combatant.State.WINDUP and e.action.get("is_spell", false)):
			return e
	return null


# ================================================================== EOWILAS

static func _eowilas() -> Node:
	return sel("Eowilas", [
		# Mend: worst-off friend first
		when("Mend",
			func(h): return _most_hurt(h) != null and h.slots > 0,
			func(h):
				var f: Node = _most_hurt(h)
				if f.global_position.distance_to(h.global_position) > 50.0:
					h.move_input = (f.global_position - h.global_position).normalized()
					return BeehaveTree.SUCCESS
				h.use_cast()
				return BeehaveTree.SUCCESS),
		when("Raise",
			func(h): return h.slots > 0 and _fallen(h) != null,
			func(h):
				var f: Node = _fallen(h)
				if h.global_position.distance_to(f.global_position) > 60.0:
					h.move_input = (f.global_position - h.global_position).normalized()
				else:
					h.ability(3)
				return BeehaveTree.SUCCESS),
		# Freedom: nobody in this party stays bound
		when("Break chains",
			func(h): return h.cd("chains") <= 0.0 and _bound_friend(h) != null,
			func(h):
				h.ability(2)
				h.bark(["Be free!", "No chains. Not on my watch.", "Up! You're nobody's prisoner."].pick_random())
				return BeehaveTree.SUCCESS),
		when("Hush the caster",
			func(h): return h.cd("silence") <= 0.0 and h.main.casting_enemy(h.global_position, 120.0) != null,
			func(h):
				h.ai_target = h.main.casting_enemy(h.global_position, 120.0)
				h.ability(1)
				return BeehaveTree.SUCCESS),
		# Shield the soft ones: step between a brute and Puck or Brokk
		cooldown(1.5, when("Shield",
			func(h): return _threat_to_soft(h) != null,
			func(h):
				var e: Node = _threat_to_soft(h)
				var f: Node = e.target
				var guard: Vector2 = f.global_position.lerp(e.global_position, 0.45)
				if h.global_position.distance_to(guard) > 8.0:
					h.move_input = (guard - h.global_position).normalized()
				if h.cd("shield_bark") <= 0.0:
					h.cds["shield_bark"] = 12.0
					h.bark(["Not them. Me.", "Step back, %s." % f.display_name, "You'll go through me first."].pick_random())
				if h.global_position.distance_to(e.global_position) < 20.0 + e.radius:
					h.aim = (e.global_position - h.global_position).normalized()
					h.use_attack()
				return BeehaveTree.SUCCESS)),
		act("Stay behind and poke", func(h):
			var leader: Node = h.main.leader
			var behind: Vector2 = leader.global_position - leader.facing * 26.0
			if leader != h and h.global_position.distance_to(behind) > 14.0:
				h.move_input = (behind - h.global_position).normalized()
			if h.global_position.distance_to(h.ai_target.global_position) < 20.0 + h.ai_target.radius:
				h.aim = (h.ai_target.global_position - h.global_position).normalized()
				h.use_attack()
			elif h.stamina > 30.0 and h.global_position.distance_to(h.ai_target.global_position) < 120.0 and h.cd("throw_ai") <= 0.0:
				h.cds["throw_ai"] = 3.0
				h.aim = (h.ai_target.global_position - h.global_position).normalized()
				h.use_special()
			return BeehaveTree.SUCCESS),
	])


static func _most_hurt(h: Node) -> Node:
	var best: Node = null
	var line: float = float(h.main.tactics_heal) / 100.0
	for f in h.main.heroes:
		if f.is_dead():
			continue
		var frac: float = float(f.hp) / f.max_hp
		if frac < line and (best == null or frac < float(best.hp) / best.max_hp):
			best = f
	return best


static func _fallen(h: Node) -> Node:
	var f: Node = h.main.nearest_fallen(h.global_position, 200.0)
	if f != null and h.main.nearest_enemy_dist(f.global_position) > 30.0:
		return f
	return null


static func _bound_friend(h: Node) -> Node:
	for f in h.main.heroes:
		if f != h and not f.is_dead() and (f.has("asleep") or f.has("confused") or f.has("prone")) and f.global_position.distance_to(h.global_position) < 60.0:
			return f
	return null


## A melee enemy closing on Puck or Brokk (the soft ones), that Eowilas can get to.
static func _threat_to_soft(h: Node) -> Node:
	for e in _aware_enemies(h, 140.0):
		var f: Node = e.target
		if f is Hero and f != h and f.hero_id in ["puck", "brokk"] and not f.is_dead() and e.kind in ["ghoul", "brute", "moth_swarm"]:
			if e.global_position.distance_to(f.global_position) < 60.0:
				return e
	return null


# ================================================================== PUCK

static func _puck() -> Node:
	return sel("Puck", [
		when("Herb smoke",
			func(h):
				if not h.main.tactics_herbs or h.herbs <= 1 or h.cd("herb_ai") > 0.0 or h.ai_target.has("asleep"):
					return false
				var cluster: int = h.main.enemies_within(h.ai_target.global_position, 40.0)
				var worth: bool = cluster >= 2 or h.ai_target.max_hp > 30 or h.ai_target.kind == "cultist"
				return worth and h.global_position.distance_to(h.ai_target.global_position) < 90.0,
			func(h):
				h.cds["herb_ai"] = 7.0
				h.herb_index = 0 if h.main.enemies_within(h.ai_target.global_position, 40.0) >= 2 else [0, 1, 2].pick_random()
				h.aim = (h.ai_target.global_position - h.global_position).normalized()
				h.use_cast()
				return BeehaveTree.SUCCESS),
		# Opportunist: anything asleep, staggered or not looking gets a rapier in the back
		when("Cheap shot",
			func(h): return _napping(h) != null,
			func(h):
				var e: Node = _napping(h)
				if e != h.ai_target:
					_target(h, e)
					if h.cd("cheap_bark") <= 0.0:
						h.cds["cheap_bark"] = 12.0
						h.bark(["Shh. Nap time.", "No offense, buddy.", "Nana, look away."].pick_random())
				return _go_hit(h, 18.0)),
		when("Flank",
			func(h):
				var leader: Node = h.main.leader
				return leader != h and leader.global_position.distance_to(h.ai_target.global_position) < 40.0,
			func(h):
				var leader: Node = h.main.leader
				var spot: Vector2 = h.ai_target.global_position + (h.ai_target.global_position - leader.global_position).normalized() * 16.0
				if h.global_position.distance_to(spot) > 10.0 and h.global_position.distance_to(h.ai_target.global_position) > 14.0:
					h.move_input = (spot - h.global_position).normalized()
					return BeehaveTree.SUCCESS
				return _go_hit(h, 18.0)),
		act("Stab", func(h): return _go_hit(h, 18.0)),
	])


static func _napping(h: Node) -> Node:
	var best: Node = null
	for e in h.main.enemies:
		if e.is_dead() or e.global_position.distance_to(h.global_position) > 110.0:
			continue
		# sleeping or staggered foes, or awake-but-busy ones; idle unnoticing ones only if the fight is already on
		var open: bool = e.has("asleep") or e.has("staggered") or e.has("prone") or (not e.aware and h.main.leader.ai_target == e)
		if open and (best == null or e.global_position.distance_to(h.global_position) < best.global_position.distance_to(h.global_position)):
			best = e
	return best
