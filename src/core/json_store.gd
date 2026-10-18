class_name JsonStore
extends RefCounted

## JSON persistence for the two services that keep state between sessions.
##
## Settings and ProfileService each carried their own copy of read/parse/write with
## slightly different failure messages. Reading is deliberately forgiving here: a
## missing or corrupt file yields an empty dictionary, because losing a leaderboard is
## bad but refusing to start is worse.

static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("JsonStore: %s is not a JSON object; ignoring it" % path)
		return {}
	return parsed


static func write(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("JsonStore: cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return true
