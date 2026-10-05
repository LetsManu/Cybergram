class_name HeroPool
extends RefCounted
## The pickable hero ids, read from ContentDB (read only). Kept separate so
## pick sessions can be tested with a fixture list.


## Every hero id in `db` (default: the project's content), sorted.
static func from_content_db(db: ContentDB = null) -> Array[StringName]:
	var d := db if db != null else ContentDB.shared()
	var out: Array[StringName] = []
	for i in range(1, d.count(ContentDB.HERO) + 1):
		out.append(d.id_at(ContentDB.HERO, i))
	return out
