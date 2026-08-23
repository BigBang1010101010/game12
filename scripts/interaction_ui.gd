extends CanvasLayer

## Shared on-screen UI for proximity interactions: a persistent "press E"
## prompt any Interactable can show/hide, and a short-lived feedback message
## for the actual interaction result. Built in code so any Interactable
## (attached to any object, anywhere) can use it without wiring a UI scene.

var prompt_label: Label
var message_label: Label
var message_timer: Timer

func _ready() -> void:
	layer = 10

	prompt_label = Label.new()
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.offset_left = -160
	prompt_label.offset_right = 160
	prompt_label.offset_top = -90
	prompt_label.offset_bottom = -55
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 22)
	prompt_label.add_theme_color_override("font_color", Color.WHITE)
	prompt_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	prompt_label.add_theme_constant_override("shadow_offset_x", 1)
	prompt_label.add_theme_constant_override("shadow_offset_y", 1)
	prompt_label.visible = false
	add_child(prompt_label)

	message_label = Label.new()
	message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	message_label.offset_left = -200
	message_label.offset_right = 200
	message_label.offset_top = 60
	message_label.offset_bottom = 100
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 26)
	message_label.add_theme_color_override("font_color", Color.YELLOW)
	message_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	message_label.add_theme_constant_override("shadow_offset_x", 1)
	message_label.add_theme_constant_override("shadow_offset_y", 1)
	message_label.visible = false
	add_child(message_label)

	message_timer = Timer.new()
	message_timer.one_shot = true
	message_timer.timeout.connect(func(): message_label.visible = false)
	add_child(message_timer)

func show_prompt(text: String) -> void:
	prompt_label.text = text
	prompt_label.visible = true

func hide_prompt() -> void:
	prompt_label.visible = false

func show_message(text: String, duration: float = 2.0) -> void:
	message_label.text = text
	message_label.visible = true
	message_timer.start(duration)
