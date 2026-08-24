extends Node

## Autoload computing the player's Academic Index: the 60-240 number the Ivy
## League itself uses to talk about academic strength.
##
## CONCEPTUAL SOURCE. The Academic Index comes from the Ivy Group Agreement,
## where it exists to keep recruited athletes academically within range of the
## rest of the class. Classically it is the SUM OF THREE COMPONENTS, each on a
## 20-80 scale - a converted rank/GPA score and two standardised test scores -
## which is where the 60 floor and 240 ceiling come from. Two figures from that
## world are quoted constantly and both live in the config resource, not here:
## roughly 176 as the floor a recruited athlete has to clear, and roughly 210
## as the point below which an unhooked applicant is fighting uphill.
##
## WHAT THIS DOES WITH IT. The game has no SATs, so the three components are
## generalised to "every attribute in the academic category", each mapped onto
## the same 20-80 band and averaged. With three equally weighted academic
## attributes the result is numerically identical to the real formula; with
## five it still spans exactly 60-240. Which category is academic, and how much
## each attribute weighs, are data - so an academic attribute added in two
## years is picked up here with no code change.
##
## It is READ-ONLY by construction: there is no setter. The index is a view of
## the attributes, and the only way to move it is to move them.

signal indice_cambiado(valor: float)

## The real scale. Not configurable: these are what the numbers MEAN.
const MINIMO := 60.0
const MAXIMO := 240.0

var _cache: float = -1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	PlayerState.valor_cambiado.connect(_on_valor_cambiado)

## Current index for the live player.
func valor() -> float:
	if _cache < 0.0:
		_cache = calcular_desde(PlayerState.obtener_todos_los_valores())
	return _cache

## Index for any hypothetical set of attribute values, so the calibration lab
## and the test suite can ask about a profile the player does not have.
func calcular_desde(valores: Dictionary) -> float:
	var total_peso := 0.0
	var acumulado := 0.0
	for definicion in _academicos():
		var peso: float = maxf(definicion.peso_indice_academico, 0.0)
		if is_zero_approx(peso):
			continue
		var normalizado: float = clampf(
			float(valores.get(definicion.id, 0.0)) / maxf(definicion.valor_maximo, 0.0001), 0.0, 1.0)
		acumulado += peso * normalizado
		total_peso += peso
	if total_peso <= 0.0:
		return MINIMO
	# Each component spans 20-80; N of them span 60-240 whatever N is.
	return MINIMO + (MAXIMO - MINIMO) * (acumulado / total_peso)

## Per-attribute detail, for the UI that has to explain the number.
## [{atributo, nombre, valor, peso, componente}] where componente is that
## attribute's own 20-80 score.
func componentes(valores: Dictionary = {}) -> Array[Dictionary]:
	if valores.is_empty():
		valores = PlayerState.obtener_todos_los_valores()
	var salida: Array[Dictionary] = []
	for definicion in _academicos():
		var normalizado: float = clampf(
			float(valores.get(definicion.id, 0.0)) / maxf(definicion.valor_maximo, 0.0001), 0.0, 1.0)
		salida.append({
			"atributo": definicion.id,
			"nombre": definicion.nombre_display,
			"valor": float(valores.get(definicion.id, 0.0)),
			"peso": definicion.peso_indice_academico,
			"componente": 20.0 + 60.0 * normalizado,
		})
	return salida

## Which floor applies to this applicant: the athletic one if they are being
## recruited, the competitive one otherwise.
func umbral_relevante(es_reclutado: bool) -> float:
	var config: AdmissionConfig = AdmissionCalculator.obtener_config()
	if not config:
		return 0.0
	return config.umbral_indice_atletico if es_reclutado else config.umbral_indice_competitivo

func _academicos() -> Array[AttributeDefinition]:
	var config: AdmissionConfig = AdmissionCalculator.obtener_config()
	var categoria: StringName = config.categoria_academica if config else &""
	var salida: Array[AttributeDefinition] = []
	if categoria == &"":
		push_error("AcademicIndex: la configuracion no declara categoria_academica")
		return salida
	for definicion_res in AttributeRegistry.get_by_category(categoria):
		salida.append(definicion_res as AttributeDefinition)
	if salida.is_empty():
		push_error("AcademicIndex: ningun atributo pertenece a la categoria '%s'" % categoria)
	return salida

func _on_valor_cambiado(_atributo_id: StringName, _valor: float) -> void:
	# Any attribute can be in the academic category tomorrow, so the cache is
	# dropped on any change rather than filtered by a hardcoded list.
	_cache = -1.0
	indice_cambiado.emit(valor())
