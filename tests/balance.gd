extends SceneTree
## Balance sweep. For each level: AutoBuilder layout + {passive, human, active} AutoPlayer x N seeds.
##   godot --headless --path . --script res://tests/balance.gd -- [--levels=med_1,arctic_3] [--seeds=5] [--base=1000]
##        [--csv=res://tests/out/balance.csv] [--knobs=mess:1.5,health:0.7,decay:1.2] [--modes=passive,human,active]
## Prints compact tables and writes tests/out/balance.csv (one row per run).

const CSV_HEADER: String = "level,mode,seed,rating,stars,g1,g2,g3,profit,lost,served,avg_queue,peak_queue,avg_problems,peak_problems,messes,mess_spread,cleaned,breakdowns,repairs,sick,ghosts,banished,patience_outs,slips,mutiny,time"
const KEYS: Array[String] = ["rate", "stars", "profit", "lost", "avgq", "peakq", "prob", "peakp", "msg", "brk", "sick", "gh"]


func _init() -> void:
	var seeds: int = 5
	var only: PackedStringArray = []
	var csv_path: String = "res://tests/out/balance.csv"
	var knobs: Dictionary = {}
	var base_seed: int = 1000
	var modes: Array[StringName] = [&"passive", &"human", &"active"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--levels="):
			only = a.substr(9).split(",")
		elif a.begins_with("--csv="):
			csv_path = a.substr(6)
		elif a.begins_with("--sat="):
			# experiment: --sat=good:0.3,ok:0.05,low:0.5,crit:0.35,use:5,fav:9
			for kv in a.substr(6).split(","):
				var q: PackedStringArray = kv.split(":")
				match q[0]:
					"good": SimConst.SAT_GOOD_RATE = float(q[1])
					"ok": SimConst.SAT_OK_RATE = float(q[1])
					"low": SimConst.SAT_LOW_RATE = float(q[1])
					"crit": SimConst.SAT_CRIT_RATE = float(q[1])
					"use": SimConst.SAT_USE_GAIN = float(q[1])
					"fav": SimConst.SAT_USE_GAIN_FAV = float(q[1])
		elif a.begins_with("--needs="):
			var nr: PackedStringArray = a.substr(8).split(":")
			SimConst.INITIAL_NEED_MIN = float(nr[0])
			SimConst.INITIAL_NEED_MAX = float(nr[1])
		elif a.begins_with("--base="):
			base_seed = int(a.substr(7))
		elif a.begins_with("--modes="):
			modes = []
			for m in a.substr(8).split(","):
				modes.append(StringName(m))
		elif a.begins_with("--knobs="):
			for kv in a.substr(8).split(","):
				var p: PackedStringArray = kv.split(":")
				if p.size() == 2:
					knobs[p[0]] = float(p[1])
	ContentStore.reload()
	var rows: PackedStringArray = [CSV_HEADER]
	var tot: Dictionary = {}
	var lvls: int = 0
	var lines_a: PackedStringArray = []
	var lines_b: PackedStringArray = []
	for lvl in ContentStore.campaign():
		if not only.is_empty() and not only.has(String(lvl.id)):
			continue
		if not knobs.is_empty():
			lvl = lvl.duplicate(true)
			for k in knobs:
				match k:
					"mess": lvl.mess_mult = knobs[k]
					"health": lvl.health_mult = knobs[k]
					"decay": lvl.decay_mult = knobs[k]
					"patience": lvl.patience_mult = knobs[k]
					"ghost": lvl.ghost_interval_mult = knobs[k]
		var port := AutoBuilder.build(lvl)
		var st: Dictionary = {}
		for mode in modes:
			var acc: Dictionary = {}
			for k in KEYS:
				acc[k] = []
			var mut: int = 0
			var zero_star: int = 0
			for s in seeds:
				var r: Dictionary = SimRunner.run(lvl, port, base_seed + s * 17, mode)
				var m: Dictionary = r["metrics"]
				acc["rate"].append(float(r["rating"]))
				acc["stars"].append(float(r["stars"]))
				acc["profit"].append(float(r["profit"]))
				acc["lost"].append(float(r["guests_lost"]))
				acc["avgq"].append(float(r["avg_queue"]))
				acc["peakq"].append(float(r["peak_queue"]))
				acc["prob"].append(float(r["avg_problems"]))
				acc["peakp"].append(float(r["peak_problems"]))
				acc["msg"].append(float(m["messes"]))
				acc["brk"].append(float(m["breakdowns"]))
				acc["sick"].append(float(m["sick"]))
				acc["gh"].append(float(m["ghosts"]))
				if r["mutiny"]:
					mut += 1
				if int(r["stars"]) == 0:
					zero_star += 1
				var g: Array = r["goals"]
				rows.append("%s,%s,%d,%.2f,%d,%d,%d,%d,%d,%d,%d,%.2f,%d,%.2f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.1f" % [
					lvl.id, mode, s, r["rating"], r["stars"],
					1 if g.size() > 0 and g[0]["met"] else 0, 1 if g.size() > 1 and g[1]["met"] else 0, 1 if g.size() > 2 and g[2]["met"] else 0,
					r["profit"], r["guests_lost"], r["served"], r["avg_queue"], r["peak_queue"], r["avg_problems"], r["peak_problems"],
					m["messes"], m["mess_spread"], m["cleaned"], m["breakdowns"], m["repairs"], m["sick"], m["ghosts"],
					m["banished"], m["patience_outs"], m["slips"], 1 if r["mutiny"] else 0, r["time"]])
			var mean: Dictionary = {}
			for k in KEYS:
				mean[k] = _mean(acc[k])
			mean["mut"] = mut
			mean["zero"] = zero_star
			mean["min_stars"] = _min(acc["stars"])
			st[mode] = mean
			for k in KEYS:
				tot["%s_%s" % [mode, k]] = float(tot.get("%s_%s" % [mode, k], 0.0)) + float(mean[k])
		lvls += 1
		var l1: String = "%-13s %3d %5d |" % [lvl.id, lvl.total_guests(), port.budget]
		var l2: String = "%-13s |" % lvl.id
		for mode in modes:
			var d: Dictionary = st[mode]
			l1 += " %5.1f %3.1f* (<%d:%d%s) |" % [d["rate"], d["stars"], int(d["min_stars"]), int(d["zero"]), "M%d" % int(d["mut"]) if int(d["mut"]) > 0 else ""]
			l2 += " q %4.1f/%-3d pr %3.1f/%-3d |" % [d["avgq"], int(d["peakq"]), d["prob"], int(d["peakp"])]
		var h: Dictionary = st[modes[modes.size() - 1]]
		l2 += " msg %3.0f brk %3.0f sick %2.0f gh %2.0f" % [h["msg"], h["brk"], h["sick"], h["gh"]]
		lines_a.append(l1)
		lines_b.append(l2)
		print(l1)
	print("")
	print("queue avg/peak (summed over rooms) and open problems avg/peak; spawn counts per voyage for the last mode")
	for l in lines_b:
		print(l)
	if lvls > 0:
		var summary: String = "mean rating:"
		for mode in modes:
			summary += " %s %.1f (%.2f stars)" % [mode, float(tot["%s_rate" % mode]) / lvls, float(tot["%s_stars" % mode]) / lvls]
		print(summary)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/out"))
	var f := FileAccess.open(csv_path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(rows) + "\n")
		f.close()
		print("wrote ", csv_path)
	quit()


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s: float = 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


func _min(a: Array) -> float:
	var m: float = 1.0e9
	for v in a:
		m = minf(m, float(v))
	return m
