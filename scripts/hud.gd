extends CanvasLayer

## Always-on screen readout, top-left: the in-game clock and how long the
## player has been awake. Built in code like the other UI autoloads so it
## needs no scene wiring and shows up in whatever scene is running.

var panel: PanelContainer
var clock_label: Label
var awake_label: Label

func _ready() -> void:
	layer = 15
	# Keeps drawing (and updating) while the inventory pauses the tree, since
	# the clock and awake counter both keep advancing during a pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	PlayerStats.awake_changed.connect(_on_awake_changed)
	_refresh()

func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.position = Vector2(16, 16)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.45)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)

	clock_label = Label.new()
	column.add_child(clock_label)

	awake_label = Label.new()
	column.add_child(awake_label)

func _process(_delta: float) -> void:
	_refresh()

func _on_awake_changed(_hours: float) -> void:
	_refresh()

func _refresh() -> void:
	if not clock_label:
		return
	clock_label.text = "Hora: %s%s" % [
		DayNightCycle.get_clock_string(),
		"  (noche)" if DayNightCycle.is_night() else "",
	]
	awake_label.text = "Despierto: %s" % PlayerStats.get_awake_string()
