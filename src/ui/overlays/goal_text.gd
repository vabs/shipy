class_name GoalText
extends RefCounted
## Text + icon for a LevelDef.star_goals entry.
##   GoalText.describe({"type": "rating", "value": 58}) -> "Rating 58% or more"
##   GoalText.icon(goal) -> StringName (IconArt id)


static func describe(goal: Dictionary) -> String:
	var v: int = int(goal.get("value", 0))
	match String(goal.get("type", "")):
		"rating": return "Rating %d%% or more" % v
		"profit": return "Profit of %s or more" % OvUtil.money(v)
		"no_lost_guests": return "No guests lost"
		"served": return "Serve %d room visits" % v
	return String(goal.get("text", "Goal"))


static func icon(goal: Dictionary) -> StringName:
	match String(goal.get("type", "")):
		"rating": return &"smile"
		"profit": return &"coin"
		"no_lost_guests": return &"heart"
		"served": return &"guest"
	return &"star"
