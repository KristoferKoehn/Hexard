extends "res://tests/test_case.gd"

## Every clip must produce the thing its own text claims, from its own rig, with its own
## move. This is the check that was missing when four of five clips were wrong and the suite
## was green.

const Library := preload("res://src/core/tutorial_library.gd")


func test_each_clip_demonstrates_what_it_claims() -> void:
	# The check that was missing when four of five clips were wrong: every clip must
	# actually produce the thing its text says, from its own rig, with its own move.
	var expected := {
		"clear": "cleared", "stars": "bonus_star_cluster",
		"flower": "starflower", "pearl": "pearl", "turn": "turn", "bombs": "defused",
		"pearl_bloom": "pearl", "colour_wipe": "wipe", "flower_cluster": "windfall",
		"pearl_finish": "finished",
	}
	for id: String in Library.ids():
		var game = Library.make_game(id)
		var result = Library.play(game, id)
		assert_true(result.committed, "%s: the demonstration move is committed" % id)
		match str(expected[id]):
			"cleared":
				assert_ge(result.cleared_count, 3, "%s: clears gems" % id)
			"bonus_star_cluster":
				var found := false
				for group in result.clear_groups:
					if group.has_formation("bonus_star_cluster"):
						found = true
				assert_true(found, "%s: forms a star cluster" % id)
			"starflower":
				var promoted := false
				for promotion: Dictionary in result.promotions:
					if str(promotion.get("kind", "")) == "starflower":
						promoted = true
				assert_true(promoted, "%s: blooms a starflower" % id)
			"pearl":
				var pearl := false
				for promotion: Dictionary in result.promotions:
					if str(promotion.get("kind", "")) == "pearl":
						pearl = true
				assert_true(pearl, "%s: makes a pearl" % id)
			"turn":
				assert_eq(result.piece_cell, Vector2i(4, 4), "%s: turns the starflower" % id)
			"defused":
				assert_gt(result.bombs_defused, 0, "%s: defuses the bomb" % id)
			"windfall":
				var windfall := false
				for group in result.clear_groups:
					if group.has_formation("starflower_cluster"):
						windfall = true
				assert_true(windfall, "%s: pays the starflower windfall" % id)
			"wipe":
				var wiped := false
				for group in result.clear_groups:
					if group.has_formation("bomb_colour_wipe"):
						wiped = true
				assert_true(wiped, "%s: wipes the colour" % id)
			"finished":
				assert_true(result.finished, "%s: ends the run" % id)
