extends Node2D
## Dev: micro-benchmarks of draw cost (prints once and quits).
var _done := false

func _draw() -> void:
	if _done:
		return
	_done = true
	var ids: Array[StringName] = [&"cabin", &"buffet", &"toilets", &"bar", &"pool", &"deck_chairs", &"cinema", &"gym", &"arcade", &"kids_club", &"restaurant", &"medbay", &"sauna", &"ice_rink", &"casino", &"crew_quarters", &"generator", &"water_tank", &"stairs", &"elevator"]
	var total := 0.0
	for id in ids:
		var wc := RoomArt.default_width(id)
		var h := 76.0 * (2.0 if id == &"stairs" else (4.0 if id == &"elevator" else 1.0))
		var rect := Rect2(0, 0, wc * 40.0, h)
		var st := {"t": 1.0, "busy_ratio": 0.5}
		RoomArt.draw_room(self, id, rect, 2, st)  # warm caches
		var t0 := Time.get_ticks_usec()
		for i in range(20):
			RoomArt.draw_room(self, id, rect, 2, st)
			RoomArt.draw_room_front(self, id, rect, 2, st)
		var dt := float(Time.get_ticks_usec() - t0) / 20.0 / 1000.0
		total += dt
		print("room %-12s %.3f ms" % [id, dt])
	print("room total (one of each) %.2f ms" % total)
	var t1 := Time.get_ticks_usec()
	for i in range(100):
		GuestArt.draw_guest(self, Vector2(50, 50), {"prop": &"sun_hat", "pose": &"walk", "t": 1.0, "walk_phase": 2.0})
	print("guest walk %.3f ms" % (float(Time.get_ticks_usec() - t1) / 100.0 / 1000.0))
	t1 = Time.get_ticks_usec()
	for i in range(100):
		GuestArt.draw_staff(self, Vector2(50, 50), {"role": &"janitor", "pose": &"work", "t": 1.0})
	print("staff %.3f ms" % (float(Time.get_ticks_usec() - t1) / 100.0 / 1000.0))
	t1 = Time.get_ticks_usec()
	for i in range(100):
		IconArt.draw_bubble(self, Vector2(50, 50), &"heart", 1.0, 1.0)
	print("bubble %.3f ms" % (float(Time.get_ticks_usec() - t1) / 100.0 / 1000.0))
	t1 = Time.get_ticks_usec()
	for i in range(20):
		ShipArt.draw_superstructure(self, 32, 5, 1.0)
	print("superstructure %.3f ms" % (float(Time.get_ticks_usec() - t1) / 20.0 / 1000.0))
	t1 = Time.get_ticks_usec()
	for i in range(1000):
		ArtUtil.circ(self, Vector2(5, 5), 4.0, Color.RED)
	print("1000 U.circ %.3f ms" % (float(Time.get_ticks_usec() - t1) / 1000.0))
	t1 = Time.get_ticks_usec()
	for i in range(1000):
		ArtUtil.rr(self, Rect2(0, 0, 10, 10), 3.0, Color.RED)
	print("1000 U.rr %.3f ms" % (float(Time.get_ticks_usec() - t1) / 1000.0))
	get_tree().quit()
