extends ResourceRegistry

## Autoload registry of every CareerData in data/careers/.
## Same directory scan as every other registry: adding content is adding a
## .tres, never editing this file.

func _init() -> void:
	directorio = "res://data/careers"
	clase_esperada = "CareerData"
