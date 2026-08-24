extends ResourceRegistry

## Autoload registry of every UniversityData in data/universities/.
## Same directory scan as every other registry: adding content is adding a
## .tres, never editing this file.

func _init() -> void:
	directorio = "res://data/universities"
	clase_esperada = "UniversityData"
