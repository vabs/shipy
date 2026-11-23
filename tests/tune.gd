extends SceneTree
## Difficulty tuner (dev tool). Searches each level's difficulty knobs so that
##   * the ACTIVE bot's average queue length hits a campaign curve (controlled by guest hunger/decay), and
##   * the HUMAN-mode player faces a target number of open problems (controlled by mess rate / fragility).
## Ratings are whatever results; tests/goals.py then derives star goals from the per-mode distributions.
##   godot --headless --path . --script res://tests/tune.gd -- --levels=med_2,med_3 [--seeds=6] [--iters=8]
## Prints `RESULT level mess health decay` lines to paste into tools/gen_content.gd (KNOBS table).

const M0: float = 1.0
const H0: float = 1.0


## Target average total queue length for the active bot at campaign level c (1..18).
static func queue_target(c: int) -> float:
	var table: Array[float] = [0.0, 0.3, 0.5, 0.9, 1.1, 1.3, 1.1, 1.3, 1.5, 1.7, 1.9, 2.1, 1.5, 1.7, 1.9, 2.1, 2.3, 2.5]
	return table[c - 1]


## Target average open problems (messes + broken rooms + ghosts) for the human player.
static func problem_target(c: int) -> float:
	var table: Array[float] = [0.4, 0.9, 1.1, 1.4, 1.6, 1.8, 1.7, 1.9, 2.1, 2.3, 2.5, 2.7, 2.4, 2.7, 3.0, 3.3, 3.7, 4.0]
	return table[c - 1]


func _init() -> void:
	var seeds: int = 6
	var iters: int = 8
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--iters="):
			iters = int(a.substr(8))
		elif a.begins_with("--levels="):
			only = a.substr(9).split(",")
	ContentStore.reload()
	for base in ContentStore.campaign():
		if not only.is_empty() and not only.has(String(base.id)):
			continue
		var c: int = base.campaign_index
		var tq: float = queue_target(c)
		var tp: float = problem_target(c)
		var d: float = 1.0
		var p: float = 1.0
		var best: Dictionary = {}
		var best_err: float = 1.0e9
		for it in iters:
			var lvl: LevelDef = base.duplicate(true)
			lvl.mess_mult = M0 * p
			lvl.health_mult = H0 / p
			lvl.decay_mult = d
			var port := AutoBuilder.build(lvl)
			var q_sum: float = 0.0
			var pr_sum: float = 0.0
			var ra_sum: float = 0.0
			var rh_sum: float = 0.0
			for s in seeds:
				var ra: Dictionary = SimRunner.run(lvl, port, 500 + s * 13, &"active")
				var rh: Dictionary = SimRunner.run(lvl, port, 500 + s * 13, &"human")
				q_sum += float(ra["avg_queue"])
				pr_sum += float(rh["avg_problems"])
				ra_sum += float(ra["rating"])
				rh_sum += float(rh["rating"])
			var q: float = q_sum / seeds
			var pr: float = pr_sum / seeds
			var eq: float = q - tq
			var ep: float = pr - tp
			var floor_a: float = lerpf(76.0, 68.0, float(c - 1) / 17.0)
			var err: float = absf(eq) / maxf(tq, 0.5) + absf(ep) / maxf(tp, 0.5) + maxf(floor_a - ra_sum / seeds, 0.0) / 6.0
			print("  %s it%d d=%.2f p=%.2f -> active queue %.2f (target %.2f) human problems %.2f (target %.2f) ratings A %.1f H %.1f" % [base.id, it, d, p, q, tq, pr, tp, ra_sum / seeds, rh_sum / seeds])
			if err < best_err:
				best_err = err
				best = {"mess": M0 * p, "health": H0 / p, "decay": d, "q": q, "pr": pr, "a": ra_sum / seeds, "h": rh_sum / seeds}
			if absf(eq) < 0.12 + 0.08 * tq and absf(ep) < 0.2 + 0.08 * tp:
				break
			if tq > 0.05:
				d *= clampf(pow(tq / maxf(q, 0.05), 0.3), 0.85, 1.2)
			p *= clampf(pow(tp / maxf(pr, 0.1), 0.6), 0.7, 1.5)
			# Guard: never let the expert bot's rating sink below a floor (the ship must stay playable).
			if ra_sum / seeds < floor_a:
				d *= 0.93
				p *= 0.95
			d = clampf(d, 0.8, 1.7)
			p = clampf(p, 0.5, 3.0)
		print("RESULT %s mess %.2f health %.2f decay %.2f  (queue %.2f problems %.2f active %.1f human %.1f)" % [base.id, best["mess"], best["health"], best["decay"], best["q"], best["pr"], best["a"], best["h"]])
	quit()
