extends SceneTree
## Payout calibration (dev tool). For each level: AutoBuilder layout + {passive, human, active} AutoPlayer x N seeds,
## printing money_start / money_end / payout and the running campaign totals, so Shipyard perk prices can be checked
## against what players actually earn (docs/SPEC.md §13.1).
##   godot --headless --path . --script res://tests/payout.gd -- [--levels=med_1,med_2] [--seeds=4] [--modes=human,active]

func _init() -> void:
	var seeds: int = 4
	var only: PackedStringArray = []
	var modes: Array[StringName] = [&"passive", &"human", &"active"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--levels="):
			only = a.substr(9).split(",")
		elif a.begins_with("--modes="):
			modes = []
			for m in a.substr(8).split(","):
				modes.append(StringName(m))
	ContentStore.reload()
	var totals: Dictionary = {}
	print("%-12s %-8s %7s %7s %7s %6s %6s %s" % ["level", "mode", "start", "end", "payout", "stars", "rate", "mutiny"])
	for lvl in ContentStore.campaign():
		if not only.is_empty() and not only.has(String(lvl.id)):
			continue
		var port := AutoBuilder.build(lvl)
		for mode in modes:
			var start: float = 0.0
			var end: float = 0.0
			var pay: float = 0.0
			var stars: float = 0.0
			var rate: float = 0.0
			var mut: int = 0
			for s in seeds:
				var r: Dictionary = SimRunner.run(lvl, port, 1000 + s * 17, mode)
				start += float(r["money_start"])
				end += float(r["money_end"])
				pay += float(r["payout"])
				stars += float(r["stars"])
				rate += float(r["rating"])
				mut += 1 if bool(r["mutiny"]) else 0
			var n: float = float(seeds)
			print("%-12s %-8s %7.0f %7.0f %7.0f %6.1f %6.1f %d/%d" % [lvl.id, mode, start / n, end / n, pay / n, stars / n, rate / n, mut, seeds])
			totals[mode] = float(totals.get(mode, 0.0)) + pay / n
	for mode in totals:
		print("TOTAL payout over the listed levels (%s): %.0f" % [mode, totals[mode]])
	quit()
