extends "res://tests/test_case.gd"

## Every view script must at least compile.
##
## This exists because a view compile error once reached a playtest with the suite fully
## green: ClipPlayer had an undefined identifier, nothing under test instantiated it, and
## the only symptom was the game failing to start. Preloading each script at const time
## makes a compile error a load failure of this test file, which the runner reports.

const Scripts := {
	"audio_service": preload("res://src/view/audio_service.gd"),
	"board_view": preload("res://src/view/board_view.gd"),
	"clip_player": preload("res://src/view/clip_player.gd"),
	"cursor_painter": preload("res://src/view/cursor_painter.gd"),
	"gem_glyphs": preload("res://src/view/gem_glyphs.gd"),
	"gem_painter": preload("res://src/view/gem_painter.gd"),
	"hud": preload("res://src/view/hud.gd"),
	"hud_model": preload("res://src/view/hud_model.gd"),
	"leaderboard_panel": preload("res://src/view/leaderboard_panel.gd"),
	"achievements_panel": preload("res://src/view/achievements_panel.gd"),
	"achievement_toast": preload("res://src/view/achievement_toast.gd"),
	"menu_flourish": preload("res://src/view/menu_flourish.gd"),
	"move_timeline": preload("res://src/view/move_timeline.gd"),
	"neon_style": preload("res://src/view/neon_style.gd"),
	"pause_panel": preload("res://src/view/pause_panel.gd"),
	"settings_panel": preload("res://src/view/settings_panel.gd"),
	"tutorial_view": preload("res://src/view/tutorial_view.gd"),
}


func test_every_view_script_compiles() -> void:
	for name: String in Scripts:
		assert_ne(Scripts[name], null, "%s compiles" % name)
	assert_eq(Scripts.size(), 17, "every view script is listed, so a new one gets this check")


func test_the_clip_player_can_actually_be_built() -> void:
	# Compiling is not the same as constructing: this is the class whose failure reached a
	# playtest, and instantiating it is what would have caught it.
	var player = Scripts["clip_player"].new()
	assert_ne(player, null, "a clip player can be instantiated")
	player.free() if player is Node else null


func test_the_tutorial_library_describes_every_clip_it_offers() -> void:
	for id: String in TutorialLibrary.ids():
		var clip := TutorialLibrary.clip(id)
		assert_false(clip.is_empty(), "%s has a definition" % id)
		assert_ne(str(clip.get("title", "")), "", "%s has a title" % id)
		assert_ne(str(clip.get("text", "")), "", "%s has text to show under it" % id)
		assert_gt(TutorialLibrary.zoom_for(id), 0.0, "%s has a usable zoom" % id)
		assert_ne(TutorialLibrary.slot_cell(id), Vector2i(-1, -2), "%s names a slot" % id)
