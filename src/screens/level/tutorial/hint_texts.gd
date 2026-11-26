class_name HintTexts
extends RefCounted
## Copy of every contextual hint: id -> {icon, text} (`**word**` = sun-yellow bold). Pure data (no autoloads), so tests can read it
## headless; HintDirector decides when each one shows.

const HINTS: Dictionary = {
	&"sick": {"icon": &"sick", "text": "Sick guests need a **Medbay**. Build one in port to cure them."},
	&"sick_locked": {"icon": &"sick", "text": "Sick guests recover slowly. The **Medbay** unlocks soon!"},
	&"sick_have": {"icon": &"sick", "text": "A guest is sick! They will head to the **Medbay** to get cured."},
	&"ghost": {"icon": &"ghost", "text": "Click ghosts to **banish** them! They scare guests."},
	&"queue_anger": {"icon": &"angry", "text": "Guests leave long queues. **Add another room** or upgrade it!"},
	&"queue_anger_basic": {"icon": &"angry", "text": "Guests leave long queues. **Add another room** to share the load!"},
	&"mutiny": {"icon": &"warning", "text": "Guests are furious! **Fix problems fast** or they take over the ship."},
	&"elevator": {"icon": &"elevator", "text": "**Elevators** are unlocked! One shaft links every deck at once."},
	&"tier2": {"icon": &"star", "text": "**Upgrades** are open! Click a room, then Upgrade for more space and speed."},
	&"tier3": {"icon": &"star", "text": "**Tier III** upgrades are open! Your busiest rooms can go even faster."},
	&"dest_arctic": {"icon": &"ice_rink", "text": "Brr! Guests lose cheer on the **top deck** here. Keep the fun indoors."},
	&"dest_underworld": {"icon": &"ghost", "text": "Spooky! **Ghosts** drift through the decks. Click them before they scare guests."},
	&"event_lunch_rush": {"icon": &"buffet", "text": "Lunch rush! Everyone is hungry, so **food rooms** get busy."},
	&"event_power_surge": {"icon": &"breakdown", "text": "Power surge! Machines break. **Hold** on a broken room to repair it."},
	&"event_film_night": {"icon": &"cinema", "text": "Film night! The **cinema** is extra popular for a while."},
	&"event_pool_party": {"icon": &"pool", "text": "Pool party! The **pool** draws a crowd, and crowds make messes."},
	&"event_food_poisoning": {"icon": &"sick", "text": "Food poisoning! Sick guests need a **Medbay**."},
	&"event_food_poisoning_locked": {"icon": &"sick", "text": "Food poisoning! Sick guests recover slowly until the **Medbay** unlocks."},
	&"event_captains_dinner": {"icon": &"restaurant", "text": "Captain's dinner! The **restaurant** is packed and pays well."},
	&"event_heat_wave": {"icon": &"pool", "text": "Heat wave! Sweaty guests keep **toilets and the pool** busy."},
	&"event_northern_lights": {"icon": &"star", "text": "Northern lights! Guests rush to the **top deck** to watch."},
	&"event_haunting": {"icon": &"ghost", "text": "Haunting! Ghosts are aboard. **Click them** away!"},
	&"event_storm": {"icon": &"storm", "text": "Storm! The **top deck closes** and tummies turn. A **Medbay** or Medic settles seasick guests."},
	# --- v2: new crew roles (shown in port the first time the role can be hired) ---
	&"crew_medic": {"icon": &"medic", "text": "New crew: the **Medic**! Hire one to cure sick guests on the spot."},
	&"crew_entertainer": {"icon": &"entertainer", "text": "New crew: the **Entertainer**! They cheer up guests stuck in long queues."},
	&"crew_chef": {"icon": &"chef", "text": "New crew: the **Chef**! Station one at a food room to serve faster and spill less."},
	&"crew_warden": {"icon": &"warden", "text": "New crew: the **Warden**! They hunt ghosts so you do not have to."},
	# --- v2: VIPs, families, tired crew ---
	&"vip_plan": {"icon": &"vip", "text": "A **VIP** is on the guest list (gold star on the chart). Keep the ship tidy and the queues short!"},
	&"vip_critic": {"icon": &"critic", "text": "A **critic** came aboard! Serve them **two quick meals** and keep spills away from the food room."},
	&"vip_celebrity": {"icon": &"celebrity", "text": "A **celebrity** came aboard! They hate queues and love fun. Keep them **entertained**."},
	&"vip_inspector": {"icon": &"inspector", "text": "An **inspector** is touring every deck! **Clean spills** and **repair rooms** before they walk by."},
	&"families": {"icon": &"family", "text": "Couples and **families** are coming! Kids love the **Kids' Club**, and groups like to share a cabin."},
	&"fatigue": {"icon": &"zzz", "text": "Crew get **tired** from here on. Build **Crew Quarters** so they can rest."},
	&"tired": {"icon": &"zzz", "text": "A crew member is **tired** and slow. Pick them in the crew bar, then click the **Crew Quarters**."},
	&"tired_none": {"icon": &"zzz", "text": "A crew member is **tired** and slow. Build **Crew Quarters** in port so they can rest."},
	# --- v2: port stop + refit ---
	&"portstop_plan": {"icon": &"event", "text": "This voyage has a **port stop**. Keep some cash for a **quick refit** while guests go ashore!"},
	&"portstop": {"icon": &"event", "text": "We are docking! Guests go **ashore**, and their beds free up for the new arrivals."},
	&"refit": {"icon": &"star", "text": "**Quick refit!** Add or upgrade rooms with your voyage money, then press **Cast off!**"},
	# --- v2: first results ---
	&"funds": {"icon": &"coin", "text": "Your profit becomes **company funds**! Spend them on permanent perks in the **Shipyard** on the map."},
	&"report": {"icon": &"clock", "text": "Tap **Voyage report** or **Show heatmap** to see where guests got stuck and what to build next."},
}
