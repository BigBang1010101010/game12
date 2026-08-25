extends Node

## Autoload turning money into an ESTIMATE of the player's own standing.
##
## Everything it reports is deliberately wrong by a bounded amount. Three rules
## shape the noise, and each one exists to stop a way of cheating it:
##
##   1. NEVER EXACT. A reported value is always displaced by at least a
##      fraction of the tier's margin, so no report ever coincides with the
##      real number - not even by luck.
##
##   2. STABLE WITHIN THE DAY. The noise is drawn from a seed built out of the
##      tier, the day and what is being asked. Consulting twice on the same day
##      returns the same estimate; if it did not, a player could ask ten times
##      and average the noise away, which would make the margin meaningless
##      and the expensive tiers pointless.
##
##   3. HONEST RANKING. After the noise, the schools are re-sorted so their
##      order matches the real one. An approximation may be off about how
##      likely Yale is, but it will never tell you Yale is easier than Cornell
##      when it is not. That is what makes a cheap report useful and not a lie.

const CATEGORIA_GASTO := &"asesoria"
## Minimum displacement, as a fraction of the tier's margin. Rule 1.
const RUIDO_MINIMO := 0.2

signal informe_emitido(informe: Dictionary)

## Reports the player has already paid for today, tier_id -> informe.
var _cache_del_dia: Dictionary = {}
var _dia_cache: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## What a tier would cost and whether it can be paid right now.
func puede_pagar(tier_id: StringName) -> bool:
	var tier: ConsultingTier = ConsultingRegistry.obtener(tier_id)
	return tier != null and Wallet.puede_pagar(tier.costo, CATEGORIA_GASTO)

## Buys a consultation. Returns {exito, motivo, mensaje} on refusal, or the
## report - see _construir_informe - on success.
func consultar(tier_id: StringName, carrera_id: StringName = &"", ensayo_id: StringName = &"", es_early: bool = false) -> Dictionary:
	var tier: ConsultingTier = ConsultingRegistry.obtener(tier_id)
	if not tier:
		return {"exito": false, "motivo": "tier_desconocido",
			"mensaje": "No existe la asesoria '%s'." % tier_id}

	_revisar_dia()
	# Already paid for today: same report, no second charge. Charging twice
	# for an identical answer would be a trap, not a mechanic.
	if _cache_del_dia.has(tier_id):
		var repetido: Dictionary = (_cache_del_dia[tier_id] as Dictionary).duplicate(true)
		repetido["ya_pagado_hoy"] = true
		return repetido

	if tier.costo > 0.0:
		var pago: Dictionary = Wallet.gastar(tier.costo, CATEGORIA_GASTO, tier.id, {"asesoria": tier.id})
		if not pago["exito"]:
			return {"exito": false, "motivo": pago["motivo"], "mensaje": pago["mensaje"]}

	var informe: Dictionary = _construir_informe(tier, carrera_id, ensayo_id, es_early)
	_cache_del_dia[tier_id] = informe.duplicate(true)
	informe_emitido.emit(informe)
	return informe

# --- The report -------------------------------------------------------------

## Report shape:
##   exito, tier, nombre, costo, margen_error, cobertura, dia
##   indice_estimado, indice_texto
##   atributos:      atributo_id -> {estimado, banda}          (cobertura >= atributos)
##   universidades:  [{id, nombre, probabilidad_estimada, texto, terminos}] (>= desglose)
func _construir_informe(tier: ConsultingTier, carrera_id: StringName, ensayo_id: StringName, es_early: bool) -> Dictionary:
	var valores: Dictionary = PlayerState.obtener_todos_los_valores()
	var informe: Dictionary = {
		"exito": true,
		"ya_pagado_hoy": false,
		"tier": tier.id,
		"nombre": tier.nombre_display,
		"costo": tier.costo,
		"margen_error": tier.margen_error,
		"cobertura": tier.cobertura,
		"dia": DayNightCycle.get_days_elapsed(),
	}

	var indice_real: float = AcademicIndex.valor()
	informe["indice_estimado"] = _con_ruido(indice_real, tier, "indice")
	informe["indice_texto"] = InfoPolicy.describir_estimacion(informe["indice_estimado"], tier.margen_error)

	if tier.cubre(&"atributos"):
		var estimados: Dictionary = {}
		for definicion_res in AttributeRegistry.get_all_definitions():
			var definicion: AttributeDefinition = definicion_res
			var real: float = float(valores.get(definicion.id, 0.0))
			var estimado: float = _con_ruido(real, tier, "atr_" + String(definicion.id))
			estimados[definicion.id] = {
				"nombre": definicion.nombre_display,
				"estimado": clampf(estimado, 0.0, definicion.valor_maximo),
				"banda": InfoPolicy.describir_atributo(estimado, definicion.valor_maximo),
			}
		informe["atributos"] = estimados

	if tier.cubre(&"desglose"):
		informe["universidades"] = _universidades_con_ruido(tier, carrera_id, ensayo_id, es_early)

	return informe

## Per-school odds, noised and then re-ordered so the ranking stays true.
func _universidades_con_ruido(tier: ConsultingTier, carrera_id: StringName, ensayo_id: StringName, es_early: bool) -> Array:
	var reales: Array[AdmissionResult] = AdmissionCalculator.calcular_todas(carrera_id, ensayo_id, es_early)
	if reales.is_empty():
		return []

	# Real ranking, best first.
	var orden: Array = reales.duplicate()
	orden.sort_custom(func(a, b): return (a as AdmissionResult).probabilidad > (b as AdmissionResult).probabilidad)

	# Noisy values, sorted on their own.
	var ruidosas: Array[float] = []
	for r in orden:
		ruidosas.append(_con_ruido((r as AdmissionResult).probabilidad, tier,
			"uni_" + String((r as AdmissionResult).universidad_id)))
	ruidosas.sort()
	ruidosas.reverse()

	# Rule 3: the i-th best school gets the i-th highest estimate, so the order
	# the player reads is the real one even though the numbers are not.
	var salida: Array = []
	for i in range(orden.size()):
		var r: AdmissionResult = orden[i]
		var universidad: UniversityData = UniversityRegistry.obtener(r.universidad_id)
		var estimada: float = clampf(ruidosas[i], 0.001, 0.99)
		var fila: Dictionary = {
			"id": r.universidad_id,
			"nombre": universidad.nombre_display if universidad else String(r.universidad_id),
			"probabilidad_estimada": estimada,
			"texto": InfoPolicy.describir_probabilidad(estimada),
			"rango": InfoPolicy.describir_estimacion(estimada * 100.0, tier.margen_error, "%"),
		}
		# The elite tier also hands over which terms moved the number, itself
		# approximate.
		fila["terminos"] = {
			"fit": _con_ruido(r.fit_score, tier, "fit_" + String(r.universidad_id)),
			"actividades": _con_ruido(r.efecto_actividades, tier, "act_" + String(r.universidad_id)),
			"atletico": r.efecto_atletico,
			"umbrales": r.penalizacion_umbrales,
			"indice": r.penalizacion_indice,
		}
		salida.append(fila)
	return salida

# --- Noise ------------------------------------------------------------------

## Displaces a value by up to the tier's margin, never by less than
## RUIDO_MINIMO of it, deterministically for a given tier, day and key.
func _con_ruido(valor: float, tier: ConsultingTier, clave: String) -> float:
	if is_zero_approx(valor):
		return valor
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%s|%d|%s" % [tier.id, clave, DayNightCycle.get_days_elapsed(), tier.margen_error])
	var magnitud: float = rng.randf_range(RUIDO_MINIMO, 1.0) * tier.margen_error
	var signo: float = 1.0 if rng.randf() < 0.5 else -1.0
	return valor * (1.0 + signo * magnitud)

func _revisar_dia() -> void:
	var hoy: int = DayNightCycle.get_days_elapsed()
	if hoy != _dia_cache:
		_dia_cache = hoy
		_cache_del_dia.clear()

func reiniciar() -> void:
	_cache_del_dia.clear()
	_dia_cache = -1
