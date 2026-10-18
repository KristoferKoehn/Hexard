class_name PausePanel
extends CanvasLayer

## The pause screen: a scrim over the board and the four things worth doing mid-run.
##
## Deliberately a plain overlay rather than a tree pause: Main stops advancing the game
## clock and stops routing gameplay input while the screen is PAUSED, and the board is
## allowed to finish settling underneath. Freezing an animation mid-fall under a menu
## looks like a bug, and the rules core is already final by the time it plays.

signal resume_pressed
signal settings_pressed
signal restart_pressed
signal menu_pressed

var _root: Control


func _ready() -> void:
	layer = 1
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Swallows clicks so the board underneath cannot be played through the scrim.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.02, 0.035, 0.06, 0.72)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(centre)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", NeonStyle.panel_box(26))
	centre.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var title := NeonStyle.label("PAUSED", 40, NeonStyle.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	column.add_child(_button("Resume  (Esc)", func() -> void: resume_pressed.emit()))
	column.add_child(_button("Settings", func() -> void: settings_pressed.emit()))
	column.add_child(_button("Restart  (R)", func() -> void: restart_pressed.emit()))
	column.add_child(_button("Main menu  (M)", func() -> void: menu_pressed.emit()))

	visible = false


func open() -> void:
	visible = true


func close() -> void:
	visible = false


func _button(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(260, 40)
	NeonStyle.style_button(button, 18)
	button.pressed.connect(action)
	return button
