extends Resource
class_name StatBenchmark

## The table that turns a statistic into recognition.
##
## THIS is what makes an athlete's recognition earned rather than declared:
## instead of somebody choosing "estatal" for a player, the player posts a
## .400 batting average and the band says that IS state-level. Every band
## carries the reasoning for its threshold in the file that holds it.

@export var id: StringName = &""

## The statistic these bands read. Must exist in data/sport_stats/.
@export var categoria_id: StringName = &""

## Bands, weakest first: [{"valor": 0.300, "reconocimiento": &"escolar"}, ...]
## A band is met when the stat reaches its value - reading "reaches" in the
## direction the category declares, so a lower ERA and a higher home run count
## both climb.
@export var bandas: Array[Dictionary] = []

## Where the thresholds come from, in prose. Not decoration: these numbers are
## opinions about real sports and they have to be arguable.
@export_multiline var fuente: String = ""

func validar() -> PackedStringArray:
	var problemas := PackedStringArray()
	if id == &"":
		problemas.append("id vacio")
	if categoria_id == &"":
		problemas.append("categoria_id vacio")
	if bandas.is_empty():
		problemas.append("sin bandas: no derivaria ningun reconocimiento")
	if fuente.is_empty():
		problemas.append("fuente vacia: un umbral sin justificacion no es un dato, es un capricho")
	var anterior := -1
	for banda in bandas:
		if not banda.has("valor") or not banda.has("reconocimiento"):
			problemas.append("una banda no declara 'valor' y 'reconocimiento'")
			continue
		var indice: int = ActivityScales.indice_reconocimiento(StringName(banda["reconocimiento"]))
		if indice < 0:
			problemas.append("reconocimiento desconocido '%s'" % banda["reconocimiento"])
			continue
		# Bands have to climb: an out-of-order table would silently award the
		# wrong level for half its range.
		if indice <= anterior:
			problemas.append("las bandas no van de menor a mayor reconocimiento ('%s' tras el indice %d)" % [
				banda["reconocimiento"], anterior])
		anterior = indice
	return problemas

## The recognition a value earns, or &"ninguno" when it earns none.
## `es_mejor_mayor` comes from the statistic itself, so this method never has
## to know which sport it is reading.
func reconocimiento_para(valor: float, es_mejor_mayor: bool) -> StringName:
	var mejor: StringName = &"ninguno"
	for banda in bandas:
		var umbral: float = float(banda["valor"])
		var alcanzada: bool = valor >= umbral if es_mejor_mayor else valor <= umbral
		if alcanzada:
			mejor = StringName(banda["reconocimiento"])
	return mejor

## The threshold of the next band up, for the UI that tells the player what
## they are chasing. Returns {} when they are already at the top.
func siguiente_banda(valor: float, es_mejor_mayor: bool) -> Dictionary:
	for banda in bandas:
		var umbral: float = float(banda["valor"])
		var alcanzada: bool = valor >= umbral if es_mejor_mayor else valor <= umbral
		if not alcanzada:
			return banda
	return {}
