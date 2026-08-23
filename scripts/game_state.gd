extends Node

## Skin texture path for the character chosen on the character-select screen.
## The four characters share one rigged model (assets/characters/character_model.glb);
## this path selects which skin texture (assets/characters/skins/character_0N.png)
## gets applied to it. Persists across scene changes since this is an autoload.
var selected_character: String = "res://assets/characters/skins/character_01.png"
