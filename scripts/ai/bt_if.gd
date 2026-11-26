extends ConditionLeaf
## A Beehave condition from a Callable(hero) -> bool.

var fn: Callable


func tick(actor: Node, _blackboard: Blackboard) -> int:
	return SUCCESS if fn.call(actor) else FAILURE
