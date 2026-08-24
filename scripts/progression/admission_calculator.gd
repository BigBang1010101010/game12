extends Node

## Turns a player profile plus their choices into an admission probability AND
## the full explanation behind it.
##
## No school, career, attribute or narrative is named anywhere in this file:
## every term is built by iterating whatever the registries loaded. Adding
## school #9 changes nothing here.
##
## THE FORMULA (see FORMULA_VERSION):
##
##   1. fit = Σ(peso_i * valor_i / max_i) / Σ(peso_i)              in [0,1]
##      A weighted, normalised match against this school's stated priorities.
##      Normalising by total weight means a school that lists more attributes
##      is not automatically harder or easier than one that lists fewer.
##
##   2. penalizacion = P * Σ( (deficit_i / umbral_i) ^ E )
##      For each unmet minimum only. Convex in the shortfall (E > 1), so just
##      missing a threshold is cheap and missing it badly is ruinous. This is
##      what models "no Ivy takes you with weak academic rigour, however
##      brilliant you are elsewhere" - it is subtracted from the score rather
##      than scaled into it, so a high fit cannot buy it back.
##
##   3. ensayo = W_e * (Σ modificadores / referencia) * afinidad_escuela
##      The same essay is worth different amounts at different schools,
##      because the affinity multiplier comes from the school's own data.
##
##   4. carrera = W_c * fortaleza_escuela_en_carrera
##             + W_a * ajuste_del_perfil_a_la_carrera
##      Two separate ideas kept separate on purpose: applying to a programme
##      the school is strong in, and actually looking like someone who belongs
##      in that field.
##
##   5. S = fit + ensayo + carrera - penalizacion
##
##   6. odds = (base / (1 - base)) * exp(K * (S - S_ref))
##      p    = odds / (1 + odds)
##      An odds-ratio (logistic) model on top of the school's REAL published
##      rate. A player exactly at S_ref gets exactly the published rate, which
##      keeps the numbers anchored to reality. Every term above therefore has
##      a clean reading: it multiplies your odds by exp(K * its contribution).
##      Probability approaches but never reaches 1, both mathematically and
##      through an explicit cap.
##
##   Early decision is handled by starting from the school's own published
##   early rate rather than by inventing a bonus, so the advantage matches the
##   real difference between the two rates at that specific school.

## Bump when the formula changes shape, so past calibrations stay comparable.
const FORMULA_VERSION := 1

var _config: AdmissionConfig = null

func _ready() -> void:
	recargar_config()

func recargar_config() -> void:
	_config = load("res://data/config/admission_config.tres") as AdmissionConfig
	if not _config:
		push_error("AdmissionCalculator: no se pudo cargar data/config/admission_config.tres")
		return
	var problemas: PackedStringArray = _config.validar()
	if not problemas.is_empty():
		push_error("AdmissionConfig invalido: %s" % ", ".join(problemas))

func obtener_config() -> AdmissionConfig:
	return _config

## Main entry point. `valores` defaults to the live player state, so the
## calibration lab can pass a hypothetical profile without touching it.
func calcular_probabilidad(universidad_id: StringName, carrera_id: StringName, ensayo_id: StringName, es_early: bool, valores: Dictionary = {}) -> AdmissionResult:
	var resultado := AdmissionResult.new()
	resultado.version_formula = FORMULA_VERSION
	resultado.universidad_id = universidad_id
	resultado.carrera_id = carrera_id
	resultado.ensayo_id = ensayo_id
	resultado.es_early = es_early

	var universidad: UniversityData = UniversityRegistry.obtener(universidad_id)
	if not universidad or not _config:
		push_error("AdmissionCalculator: universidad desconocida '%s'" % universidad_id)
		return resultado

	if valores.is_empty():
		valores = PlayerState.obtener_todos_los_valores()

	# --- 1. Weighted, normalised fit ---------------------------------------
	var peso_total: float = universidad.peso_total()
	var fit := 0.0
	var contribuciones: Dictionary = {}
	for atributo_id in universidad.pesos_atributos:
		var peso: float = universidad.pesos_atributos[atributo_id]
		var definicion: AttributeDefinition = AttributeRegistry.get_definition(atributo_id)
		if not definicion:
			push_warning("Universidad '%s' pondera el atributo inexistente '%s'" % [universidad_id, atributo_id])
			continue
		var valor: float = valores.get(atributo_id, 0.0)
		var normalizado: float = clampf(valor / maxf(definicion.valor_maximo, 0.0001), 0.0, 1.0)
		var aporte: float = peso * normalizado / maxf(peso_total, 0.0001)
		fit += aporte
		contribuciones[atributo_id] = {"valor": valor, "peso": peso, "aporte": aporte}
	resultado.fit_score = fit
	resultado.contribuciones_atributo = contribuciones

	# --- 2. Threshold penalties --------------------------------------------
	var penalizacion := 0.0
	var incumplidos: Array[Dictionary] = []
	for atributo_id in universidad.umbrales_minimos:
		var umbral: float = universidad.umbrales_minimos[atributo_id]
		if umbral <= 0.0:
			continue
		var valor: float = valores.get(atributo_id, 0.0)
		if valor >= umbral:
			continue
		var deficit_relativo: float = clampf((umbral - valor) / umbral, 0.0, 1.0)
		var castigo: float = _config.penalizacion_umbral * pow(deficit_relativo, _config.exponente_umbral)
		penalizacion += castigo
		incumplidos.append({
			"atributo": atributo_id, "valor": valor, "umbral": umbral,
			"deficit": umbral - valor, "penalizacion": castigo,
		})
	resultado.penalizacion_umbrales = penalizacion
	resultado.umbrales_incumplidos = incumplidos

	# --- 3. Essay -----------------------------------------------------------
	var efecto_ensayo := 0.0
	var afinidad := 1.0
	var ensayo: EssayNarrative = EssayRegistry.obtener(ensayo_id)
	if ensayo:
		var fuerza := 0.0
		for atributo_id in ensayo.modificadores_atributo:
			fuerza += float(ensayo.modificadores_atributo[atributo_id])
		var fuerza_normalizada: float = clampf(fuerza / maxf(_config.ensayo_modificador_referencia, 0.0001), 0.0, 1.5)
		afinidad = float(universidad.afinidad_narrativas.get(ensayo.narrativa_tipo, 1.0))
		efecto_ensayo = _config.peso_ensayo * fuerza_normalizada * afinidad
	resultado.efecto_ensayo = efecto_ensayo
	resultado.afinidad_ensayo = afinidad

	# --- 4. Career ----------------------------------------------------------
	var fortaleza := 0.0
	var ajuste := 0.0
	var carrera: CareerData = CareerRegistry.obtener(carrera_id)
	if carrera:
		fortaleza = float(universidad.fortalezas_carrera.get(carrera_id, 0.5))
		ajuste = carrera.calcular_ajuste(valores)
	resultado.fortaleza_carrera = fortaleza
	resultado.ajuste_carrera = ajuste
	resultado.efecto_carrera = _config.peso_carrera * fortaleza
	resultado.efecto_ajuste_carrera = _config.peso_ajuste_carrera * ajuste

	# --- 5. Combined score --------------------------------------------------
	var puntaje: float = fit + efecto_ensayo + resultado.efecto_carrera + resultado.efecto_ajuste_carrera - penalizacion
	resultado.puntaje_final = puntaje

	# --- 6. Odds-ratio mapping onto the school's real published rate --------
	var base: float = universidad.tasa_admision_early if es_early else universidad.tasa_admision_base
	base = clampf(base, 0.0001, 0.9999)
	resultado.tasa_base = base
	resultado.bonus_early = universidad.tasa_admision_early / maxf(universidad.tasa_admision_base, 0.0001)

	var odds_base: float = base / (1.0 - base)
	var multiplicador: float = exp(_config.sensibilidad * (puntaje - _config.fit_referencia))
	resultado.multiplicador_odds = multiplicador
	var odds: float = odds_base * multiplicador
	var probabilidad: float = odds / (1.0 + odds)
	resultado.probabilidad = clampf(probabilidad, _config.probabilidad_minima, _config.probabilidad_maxima)
	resultado.factor_aleatoriedad = _config.factor_aleatoriedad

	return resultado

## Every school at once, for the odds screen and the calibration lab.
func calcular_todas(carrera_id: StringName, ensayo_id: StringName, es_early: bool, valores: Dictionary = {}) -> Array[AdmissionResult]:
	var salida: Array[AdmissionResult] = []
	for universidad in UniversityRegistry.obtener_todos():
		salida.append(calcular_probabilidad((universidad as UniversityData).id, carrera_id, ensayo_id, es_early, valores))
	return salida
