class_name PausePanel
extends CanvasLayer

## The pause screen: a scrim over the board and the four things worth doing mid-run.
##
## Deliberately a plain overlay rather than a tree pause: Main stops advancing the game
## clock and stops routing gameplay input while the screen is PAUSED, and the board is
## allowed to finish settling underneath. Freezing an animation mid-fall under a menu
## looks like a bug, and the rules core is already final by the time it plays.
##
## Both destructive choices ask first. Main menu and Restart each throw away the board,
## the score and the clock, and both sat one click from Resume.

signal resume_pressed
signal settings_pressed
signal restart_pressed
signal menu_pressed

const PENDING_MENU := "menu"
const PENDING_RESTART := "restart"

var _root: Control
var _list: VBoxContainer
var _confirm: VBoxContainer
var _question: Label
var _warning: Label
var _pending := ""


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

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	column.add_child(_list)
	_list.add_child(_button("Resume  (Esc)", func() -> void: resume_pressed.emit()))
	_list.add_child(_button("Settings", func() -> void: settings_pressed.emit()))
	_list.add_child(_button("Restart  (R)", request_restart))
	_list.add_child(_button("Main menu  (M)", request_quit))

	# One question box for both destructive choices: the answer decides which signal
	# leaves, so there is a single place that can bypass a confirmation, and it does not.
	_confirm = VBoxContainer.new()
	_confirm.add_theme_constant_override("separation", 10)
	column.add_child(_confirm)
	_question = NeonStyle.label("", 24, NeonStyle.AMBER)
	_question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm.add_child(_question)
	_warning = NeonStyle.label("", 17, NeonStyle.DIM)
	_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm.add_child(_warning)
	_confirm.add_child(_button("Yes  (Y)", confirm))
	_confirm.add_child(_button("Keep playing  (N)", cancel_confirm))
	_confirm.visible = false

	visible = false


func open() -> void:
	_show_list()
	visible = true


func close() -> void:
	_show_list()
	visible = false


## Asks before abandoning the run for the menu.
func request_quit() -> void:
	_ask(PENDING_MENU, "Quit to the main menu?", "This run will be lost.")


## Asks before replacing the board with a fresh run.
func request_restart() -> void:
	_ask(PENDING_RESTART, "Restart this run?", "The current board will be replaced.")


func confirm() -> void:
	var pending := _pending
	_show_list()
	if pending == PENDING_MENU:
		menu_pressed.emit()
	elif pending == PENDING_RESTART:
		restart_pressed.emit()


func cancel_confirm() -> void:
	_show_list()


func is_confirming() -> bool:
	return _confirm != null and _confirm.visible


func pending() -> String:
	return _pending if is_confirming() else ""


func _ask(kind: String, question: String, warning: String) -> void:
	_pending = kind
	_question.text = question
	_warning.text = warning
	_list.visible = false
	_confirm.visible = true


func _show_list() -> void:
	_pending = ""
	if _list != null:
		_list.visible = true
	if _confirm != null:
		_confirm.visible = false


func _button(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(260, 40)
	NeonStyle.style_button(button, 18)
	button.pressed.connect(action)
	return button
