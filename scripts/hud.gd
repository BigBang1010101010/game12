extends CanvasLayer

## Always-on screen readout, top-left: the in-game clock and how long the
## player has been awake. Built in code like the other UI autoloads so it
## needs no scene wiring and shows up in whatever scene is running.

var panel: PanelContainer
var clock_label: Label
var awake_label: Label
var hearts_row: HBoxContainer

func _ready() -> void:
	layer = 15
	# Keeps drawing (and updating) while the inventory pauses the tree, since
	# the clock and awake counter both keep advancing during a pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	PlayerStats.awake_changed.connect(_on_awake_changed)
	PlayerStats.health_changed.connect(_on_health_changed)
	_refresh_hearts()
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

	hearts_row = HBoxContainer.new()
	hearts_row.add_theme_constant_override("separation", 4)
	column.add_child(hearts_row)

func _process(_delta: float) -> void:
	_refresh()

func _on_awake_changed(_hours: float) -> void:
	_refresh()

func _on_health_changed(_half_hearts: int) -> void:
	_refresh_hearts()

## One icon per full heart, each drawn full, half or empty from the half-heart
## count, so 2 hearts read as 4 states rather than as a number.
func _refresh_hearts() -> void:
	if not hearts_row:
		return
	# remove_child before queue_free: queue_free alone leaves the old icons in
	# the tree until the end of the frame, so two health changes within one
	# frame would briefly show both sets of icons at once.
	for child in hearts_row.get_children():
		hearts_row.remove_child(child)
		child.queue_free()
	var full_hearts: int = PlayerStats.MAX_HALF_HEARTS / 2
	for i in range(full_hearts):
		var remaining: int = PlayerStats.health_half_hearts - i * 2
		var fill: int = clampi(remaining, 0, 2) # 2 full, 1 half, 0 empty
		hearts_row.add_child(_make_heart(fill))

const HEART_SIZE := 22
const HEART_FULL_COLOR := Color(0.90, 0.20, 0.26)
const HEART_EMPTY_COLOR := Color(0.24, 0.10, 0.12)

## Heart icons are drawn as a small pixel grid rather than loaded from an
## image, so the HUD needs no art assets. `fill` is 2 (full), 1 (left half) or
## 0 (empty).
func _make_heart(fill: int) -> TextureRect:
	var shape := [
		"0110110",
		"1111111",
		"1111111",
		"1111111",
		"0111110",
		"0011100",
		"0001000",
	]
	var size := shape.size()
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(size):
		for x in range(size):
			if shape[y][x] != "1":
				continue
			var is_filled: bool = fill == 2 or (fill == 1 and x < size / 2)
			image.set_pixel(x, y, HEART_FULL_COLOR if is_filled else HEART_EMPTY_COLOR)
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(image)
	rect.custom_minimum_size = Vector2(HEART_SIZE, HEART_SIZE)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return rect

func _refresh() -> void:
	if not clock_label:
		return
	clock_label.text = "Hora: %s%s" % [
		DayNightCycle.get_clock_string(),
		"  (noche)" if DayNightCycle.is_night() else "",
	]
	awake_label.text = "Despierto: %s" % PlayerStats.get_awake_string()
