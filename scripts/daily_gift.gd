extends RefCounted
## Regalo cada 24 h reales. Si el reloj del teléfono retrocede, no da nada.
## Fallar un día no quita monedas ni rompe la racha.

const TABLE := [50, 50, 75, 75, 100, 100, 200]
const DAY := 86400


static func ready(now: int, last: int) -> bool:
	if last <= 0:
		return true
	if now < last:
		return false
	return now - last >= DAY


static func reward_for(streak: int) -> int:
	var i := clampi(streak, 0, TABLE.size() - 1)
	return int(TABLE[i])


## streak es el índice del próximo premio (0..6). Tras el 7.º vuelve a 50.
static func claim(now: int, last: int, streak: int) -> Dictionary:
	var idx := clampi(streak, 0, TABLE.size() - 1)
	if last > 0 and now < last:
		return {"ok": false, "coins": 0, "last": last, "streak": idx, "reason": "clock"}
	if not ready(now, last):
		return {"ok": false, "coins": 0, "last": last, "streak": idx, "reason": "wait"}
	var nxt := (idx + 1) % TABLE.size()
	return {"ok": true, "coins": int(TABLE[idx]), "last": now, "streak": nxt, "reason": "ok"}
