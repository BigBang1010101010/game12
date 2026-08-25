extends ResourceRegistry

## Autoload registry of every StatBenchmark in data/sport_benchmarks/.

func _init() -> void:
	directorio = "res://data/sport_benchmarks"
	clase_esperada = "StatBenchmark"

var _por_categoria: Dictionary = {}

func recargar() -> void:
	super()
	_por_categoria.clear()
	for benchmark_res in obtener_todos():
		var benchmark: StatBenchmark = benchmark_res
		if not SportStatRegistry.tiene(benchmark.categoria_id):
			_fallar("benchmark '%s': la estadistica '%s' no existe" % [benchmark.id, benchmark.categoria_id])
			continue
		if _por_categoria.has(benchmark.categoria_id):
			_fallar("dos benchmarks para la misma estadistica '%s'" % benchmark.categoria_id)
			continue
		_por_categoria[benchmark.categoria_id] = benchmark

## The bands that read one statistic, or null when it has none - a statistic
## may exist for flavour without driving recognition.
func para_categoria(categoria_id: StringName) -> StatBenchmark:
	return _por_categoria.get(categoria_id, null)
