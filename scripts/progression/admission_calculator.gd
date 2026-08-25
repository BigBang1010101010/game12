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
##   5. actividades = W_a2 * (Sigma (afinidad_i - 1) * peso_tier_i * continuidad_i)
##                                    / referencia
##      Only the activities that made it onto the application count, and each
##      one counts in proportion to how strongly it reads (tier) and how long
##      it was sustained (continuity). An activity unrelated to the career
##      applied to contributes nothing here - it already paid in attributes.
##
##   6. universal = W_u * (Sigma boost_i * peso_tier_i * continuidad_i) / ref
##      Some support does not point at a field. Paid work is the case the real
##      data shows: in Common Data Set C7 all eight Ivies mark work experience
##      as CONSIDERED, so it lands identically everywhere. It is therefore a
##      term of its own rather than an affinity, and any activity can join it
##      by declaring boost_universal in its own file.
##
##   7. atletico = B_a, but ONLY for an athlete who is actually recruitable:
##      recognition at or above the sport's own bar AND an Academic Index at
##      or above the sport's own floor. Both gates, always. A state champion
##      with a weak record is not recruited in the Ivy League, and neither is
##      a strong student who merely plays. When a gate fails, the term is zero
##      and the result says which gate, so the game can tell the player.
##
##   8. penalizacion_indice = P_i * (deficit_indice) ^ E_i
##      Distance below the floor that applies to THIS applicant - the athletic
##      floor when recruited, the competitive one otherwise - as a fraction of
##      the scale, raised to a power. Same convex shape as the attribute
##      thresholds, for the same reason.
##
##   9. S = fit + ensayo + carrera + actividades + universal + atletico
##          - umbrales - penalizacion_indice
##
##  10. odds = (base / (1 - base)) * exp(K * (S - S_ref))
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
const FORMULA_VERSION := 3

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
## `actividades` is the application's activity list, in the shape
## ApplicationBuilder produces. Left empty together with `valores`, the live
## player's own application is used; passing `valores` without `actividades`
## means a profile with no extracurriculars, NOT the real player's - mixing a
## hypothetical set of attributes with real activities would explain nothing.
func calcular_probabilidad(universidad_id: StringName, carrera_id: StringName, ensayo_id: StringName, es_early: bool, valores: Dictionary = {}, actividades: Array = []) -> AdmissionResult:
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

	var perfil_real: bool = valores.is_empty()
	if perfil_real:
		valores = PlayerState.obtener_todos_los_valores()
	var indice: float = AcademicIndex.calcular_desde(valores)
	resultado.academic_index = indice
	if actividades.is_empty() and perfil_real:
		actividades = ApplicationBuilder.obtener_seleccion(indice)

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

	# --- 5. Activities on the application -----------------------------------
	var afinidad_total := 0.0
	var aportes: Array[Dictionary] = []
	for entrada in actividades:
		var actividad: ActivityData = ActivityRegistry.obtener(entrada.get("actividad_id", &""))
		if not actividad:
			continue
		var afinidad_carrera: float = float(actividad.carreras_afinidad.get(carrera_id, 1.0))
		var tier: int = int(entrada.get("tier", 5))
		if tier > 4:
			continue
		# A tier 1 activity reads four times as loudly as a tier 4 one.
		var peso_tier: float = float(5 - tier) / 4.0
		var continuidad: float = float(entrada.get("continuidad", 1.0))
		var aporte: float = (afinidad_carrera - 1.0) * peso_tier * continuidad
		afinidad_total += aporte
		aportes.append({
			"actividad_id": actividad.id,
			"nombre": actividad.nombre_display,
			"tier": tier,
			"anios": float(entrada.get("anios", 0.0)),
			"continuidad": continuidad,
			"afinidad": afinidad_carrera,
			"aporte": aporte,
		})
	aportes.sort_custom(func(a, b): return a["aporte"] > b["aporte"])
	var normalizada: float = clampf(afinidad_total / maxf(_config.actividad_afinidad_referencia, 0.0001), 0.0, 1.5)
	resultado.afinidad_actividades = afinidad_total
	resultado.efecto_actividades = _config.peso_actividades * normalizada
	resultado.aportes_actividad = aportes

	# --- 6. Support that lands the same everywhere --------------------------
	var fuerza_universal := 0.0
	var universales: Array[Dictionary] = []
	for entrada in actividades:
		var actividad_u: ActivityData = ActivityRegistry.obtener(entrada.get("actividad_id", &""))
		if not actividad_u or is_zero_approx(actividad_u.boost_universal):
			continue
		var tier_u: int = int(entrada.get("tier", 5))
		if tier_u > 4:
			continue
		var aporte_u: float = (actividad_u.boost_universal * (float(5 - tier_u) / 4.0)
			* float(entrada.get("continuidad", 1.0)))
		fuerza_universal += aporte_u
		universales.append({
			"actividad_id": actividad_u.id,
			"nombre": actividad_u.nombre_display,
			"tier": tier_u,
			"boost": actividad_u.boost_universal,
			"aporte": aporte_u,
		})
	universales.sort_custom(func(a, b): return a["aporte"] > b["aporte"])
	resultado.fuerza_universal = fuerza_universal
	resultado.aportes_universales = universales
	resultado.efecto_universal = _config.peso_boost_universal * clampf(
		fuerza_universal / maxf(_config.boost_universal_referencia, 0.0001), 0.0, 1.5)

	# --- 7. The athletic route ----------------------------------------------
	var reclutado := false
	var fallidos: Array[Dictionary] = []
	for entrada in actividades:
		var deporte: ActivityData = ActivityRegistry.obtener(entrada.get("actividad_id", &""))
		if not deporte or not deporte.es_deporte:
			continue
		var reconocimiento: StringName = entrada.get("reconocimiento", &"ninguno")
		var alcance: int = ActivityScales.indice_reconocimiento(reconocimiento)
		if alcance >= deporte.umbral_reclutamiento and indice >= float(deporte.academic_index_minimo):
			reclutado = true
			continue
		# Say WHICH gate failed: "you are not being recruited" is not an
		# explanation, and this game promises explanations.
		fallidos.append({
			"actividad_id": deporte.id,
			"nombre": deporte.nombre_display,
			"motivo": "reconocimiento" if alcance < deporte.umbral_reclutamiento else "academic_index",
			"reconocimiento": reconocimiento,
			"umbral": ActivityScales.nombre_reconocimiento(deporte.umbral_reclutamiento),
			"indice": indice,
			"minimo": float(deporte.academic_index_minimo),
		})
	resultado.es_reclutado = reclutado
	resultado.efecto_atletico = _config.bonus_atletico if reclutado else 0.0
	resultado.deportes_no_reclutables = fallidos

	# --- 8. Academic Index floor --------------------------------------------
	var umbral_indice: float = _config.umbral_indice_atletico if reclutado else _config.umbral_indice_competitivo
	resultado.umbral_indice = umbral_indice
	var penalizacion_indice := 0.0
	if indice < umbral_indice:
		var rango: float = maxf(umbral_indice - AcademicIndex.MINIMO, 0.0001)
		var deficit: float = clampf((umbral_indice - indice) / rango, 0.0, 1.0)
		penalizacion_indice = _config.peso_indice * pow(deficit, _config.exponente_indice)
	resultado.penalizacion_indice = penalizacion_indice

	# --- 9. Combined score --------------------------------------------------
	var puntaje: float = (fit + efecto_ensayo + resultado.efecto_carrera + resultado.efecto_ajuste_carrera
		+ resultado.efecto_actividades + resultado.efecto_universal + resultado.efecto_atletico
		- penalizacion - penalizacion_indice)
	resultado.puntaje_final = puntaje

	# --- 10. Odds-ratio mapping onto the school's real published rate --------
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
func calcular_todas(carrera_id: StringName, ensayo_id: StringName, es_early: bool, valores: Dictionary = {}, actividades: Array = []) -> Array[AdmissionResult]:
	var salida: Array[AdmissionResult] = []
	for universidad in UniversityRegistry.obtener_todos():
		salida.append(calcular_probabilidad(
			(universidad as UniversityData).id, carrera_id, ensayo_id, es_early, valores, actividades))
	return salida
