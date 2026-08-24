extends ResourceRegistry

## Autoload registry of every SynergyRule in data/synergies/.

func _init() -> void:
	directorio = "res://data/synergies"
	clase_esperada = "SynergyRule"

## Rules that scale gains for `atributo_id`. Built on demand rather than
## cached per attribute so newly reloaded content is picked up immediately.
func reglas_que_afectan(atributo_id: StringName) -> Array[Resource]:
	var salida: Array[Resource] = []
	for regla in obtener_todos():
		if (regla as SynergyRule).atributo_afectado == atributo_id:
			salida.append(regla)
	return salida
