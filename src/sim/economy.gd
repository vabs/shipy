class_name Economy
extends RefCounted
## Voyage money and ledger. Categories: tickets, spending (income); upkeep, wages, hires (expenses).
## `ledger` holds absolute totals per category.

var money: int = 0
var money_start: int = 0
var ledger: Dictionary = {&"tickets": 0, &"spending": 0, &"upkeep": 0, &"wages": 0, &"hires": 0}
var _upkeep_acc: float = 0.0
var _upkeep_pending: int = 0
var upkeep_per_minute: float = 0.0


func _init(start: int = 0) -> void:
	money = start
	money_start = start


func profit() -> int:
	return money - money_start


## Records income (positive amount) in a category and returns the signed delta.
func earn(category: StringName, amount: int) -> int:
	money += amount
	ledger[category] = int(ledger.get(category, 0)) + amount
	return amount


## Records an expense (positive amount) in a category and returns the signed delta (negative).
func spend(category: StringName, amount: int) -> int:
	money -= amount
	ledger[category] = int(ledger.get(category, 0)) + amount
	return -amount


## Accumulates upkeep; returns whole coins charged this call (0 until a few coins have built up).
func tick_upkeep(dt: float) -> int:
	_upkeep_acc += upkeep_per_minute * dt / 60.0
	var whole: int = int(_upkeep_acc)
	if whole >= 3:
		_upkeep_acc -= float(whole)
		spend(&"upkeep", whole)
		return whole
	return 0
