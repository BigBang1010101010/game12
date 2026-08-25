extends ResourceRegistry

## Autoload registry of every SpendingCategory in data/spending/.

func _init() -> void:
	directorio = "res://data/spending"
	clase_esperada = "SpendingCategory"

## Categories the family purse may pay for, in display order.
func obtener_permitidas() -> Array[Resource]:
	return _filtrar(true)

func obtener_no_permitidas() -> Array[Resource]:
	return _filtrar(false)

func permite_dinero_familia(categoria_id: StringName) -> bool:
	var categoria: SpendingCategory = obtener(categoria_id)
	# An unknown category is NOT allowed to touch family money. Failing closed
	# matters here: a typo in a category id must never open the family purse.
	return categoria.permite_dinero_familia if categoria else false

func _filtrar(permite: bool) -> Array[Resource]:
	var salida: Array[Resource] = []
	for categoria_res in obtener_todos():
		if (categoria_res as SpendingCategory).permite_dinero_familia == permite:
			salida.append(categoria_res)
	salida.sort_custom(func(a, b): return (a as SpendingCategory).orden < (b as SpendingCategory).orden)
	return salida
