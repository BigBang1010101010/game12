extends Control

const MAIN_SCENE := "res://scenes/main.tscn"

func _on_character_button_pressed(skin_path: String) -> void:
	GameState.selected_character = skin_path
	get_tree().change_scene_to_file(MAIN_SCENE)
