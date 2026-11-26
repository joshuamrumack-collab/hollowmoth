extends ActionLeaf
## A Beehave action that runs a Callable(hero) -> SUCCESS / FAILURE / RUNNING.
## The party brains (brains.gd) are built from these so each behaviour reads as one small function.

var fn: Callable


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var st: int = fn.call(actor)
	# per-hero tally of which behaviours fire (the autotest prints it)
	var tally: Variant = actor.get("bt_stats")
	if tally is Dictionary and st != FAILURE:
		tally[String(name)] = int(tally.get(String(name), 0)) + 1
	return st
