extends Node

## Autoload holding what the player has actually DONE in each activity, and
## the only thing allowed to promote them up an activity's ladder.
##
## It names no activity: every ladder, every payout and every gate is read
## from the ActivityData it is handed. Reaching a level pays out through
## PlayerState.aplicar_modificador with fuente_tipo &"actividad", so the audit
## ledger can answer "where did these 12 points of leadership come from?" with
## the activity, the level and the year that produced them.

signal actividad_iniciada(actividad_id: StringName)
signal nivel_alcanzado(actividad_id: StringName, nivel_indice: int, nivel: ActivityLevel)

const FUENTE := &"actividad"

## actividad_id -> {nivel_indice, anios_invertidos, horas_totales,
##                  reconocimiento, rol, impacto}
## nivel_indice is -1 for an activity joined but not yet credited with its
## first rung.
var _estado: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

# --- Enrolment ---------------------------------------------------------------

func esta_activa(actividad_id: StringName) -> bool:
	return _estado.has(actividad_id)

func actividades_activas() -> Array[StringName]:
	var salida: Array[StringName] = []
	for id in _estado:
		salida.append(id)
	# Compared as Strings: StringName sorts by pointer in Godot 4.
	salida.sort_custom(func(a, b): return String(a) < String(b))
	return salida

## Joins an activity. Returns false when it does not exist or its unlock
## conditions are not met, so the caller can explain the refusal.
func inscribir(actividad_id: StringName, contexto: Dictionary = {}) -> bool:
	if esta_activa(actividad_id):
		return true
	var actividad: ActivityData = ActivityRegistry.obtener(actividad_id)
	if not actividad:
		push_error("ActivityTracker: actividad desconocida '%s'" % actividad_id)
		return false
	if not RequirementChecker.cumple_todos(actividad.requisitos_desbloqueo, contexto):
		return false
	_estado[actividad_id] = _estado_inicial()
	actividad_iniciada.emit(actividad_id)
	# The first rung usually asks for nothing, so joining credits it at once.
	_revisar_ascensos(actividad)
	return true

func abandonar(actividad_id: StringName) -> void:
	_estado.erase(actividad_id)

func _estado_inicial() -> Dictionary:
	return {
		"nivel_indice": -1,
		"anios_invertidos": 0.0,
		"horas_totales": 0.0,
		"reconocimiento": &"ninguno",
		# Being enrolled IS being a member: a level that asks for the
		# &"miembro" role is asking for participation, not for a promotion.
		"rol": &"miembro",
		"impacto": 0.0,
	}

func obtener_estado(actividad_id: StringName) -> Dictionary:
	return (_estado.get(actividad_id, _estado_inicial()) as Dictionary).duplicate()

func obtener_todos_los_estados() -> Dictionary:
	return _estado.duplicate(true)

# --- The four levers ---------------------------------------------------------

## THE entry point for spending time on an activity. Hours become years of
## continuity through the activity's own weekly cost, so an activity that eats
## 12 hours a week reaches "a year of it" four times faster than one that eats
## 3 - which is the whole point of the time budget.
func invertir_tiempo(actividad_id: StringName, horas: float, contexto: Dictionary = {}) -> int:
	if horas <= 0.0:
		return 0
	if not esta_activa(actividad_id) and not inscribir(actividad_id, contexto):
		return 0
	var actividad: ActivityData = ActivityRegistry.obtener(actividad_id)
	var estado: Dictionary = _estado[actividad_id]
	estado["horas_totales"] += horas
	estado["anios_invertidos"] = anios_desde_horas(actividad, estado["horas_totales"])
	EventBus.avisar_tiempo(actividad_id, horas)
	return _revisar_ascensos(actividad)

## Records recognition earned outside the activity's own clock - a regional
## final, a state title. Only ever moves up: losing a title you already won is
## not a thing.
func fijar_reconocimiento(actividad_id: StringName, reconocimiento: StringName) -> int:
	return _subir_escala(actividad_id, "reconocimiento", reconocimiento,
		ActivityScales.indice_reconocimiento(reconocimiento), "reconocimiento")

func fijar_rol(actividad_id: StringName, rol: StringName) -> int:
	return _subir_escala(actividad_id, "rol", rol, ActivityScales.indice_rol(rol), "rol")

func _subir_escala(actividad_id: StringName, clave: String, valor: StringName, indice_nuevo: int, etiqueta: String) -> int:
	if not esta_activa(actividad_id):
		return 0
	if indice_nuevo < 0:
		push_error("ActivityTracker: %s desconocido '%s'" % [etiqueta, valor])
		return 0
	var estado: Dictionary = _estado[actividad_id]
	var indice_actual: int = (ActivityScales.indice_reconocimiento(estado[clave])
		if clave == "reconocimiento" else ActivityScales.indice_rol(estado[clave]))
	if indice_nuevo <= indice_actual:
		return 0
	estado[clave] = valor
	return _revisar_ascensos(ActivityRegistry.obtener(actividad_id))

## Adds measurable impact: people reached, dollars raised, papers published.
## What the number means is the activity's business, not this file's.
func sumar_impacto(actividad_id: StringName, cantidad: float) -> int:
	if not esta_activa(actividad_id) or cantidad <= 0.0:
		return 0
	_estado[actividad_id]["impacto"] += cantidad
	return _revisar_ascensos(ActivityRegistry.obtener(actividad_id))

# --- Climbing the ladder -----------------------------------------------------

## Promotes as far as the current state allows, paying out each level passed.
## Returns how many levels were gained.
func _revisar_ascensos(actividad: ActivityData) -> int:
	if not actividad:
		return 0
	var estado: Dictionary = _estado[actividad.id]
	var niveles: Array[ActivityLevel] = actividad.obtener_niveles()
	var ganados := 0
	while estado["nivel_indice"] + 1 < niveles.size():
		var siguiente: ActivityLevel = niveles[estado["nivel_indice"] + 1]
		if not cumple_ascenso(siguiente, estado):
			break
		estado["nivel_indice"] += 1
		ganados += 1
		_pagar_nivel(actividad, siguiente, estado)
		nivel_alcanzado.emit(actividad.id, estado["nivel_indice"], siguiente)
	return ganados

## Applies a level's payout THROUGH PlayerState, so every point is auditable
## and still subject to diminishing returns, synergies and caps.
func _pagar_nivel(actividad: ActivityData, nivel: ActivityLevel, estado: Dictionary) -> void:
	var multiplicador: float = multiplicador_continuidad(estado["anios_invertidos"])
	for atributo_id in nivel.modificadores_atributo:
		var puntos: float = float(nivel.modificadores_atributo[atributo_id]) * multiplicador
		PlayerState.aplicar_modificador(atributo_id, puntos, FUENTE, actividad.id, {
			"nivel": nivel.nombre,
			"tier": nivel.tier,
			"anios": estado["anios_invertidos"],
			"continuidad": multiplicador,
			"base": float(nivel.modificadores_atributo[atributo_id]),
		})

## True when every lever a level asks for has been pulled far enough.
func cumple_ascenso(nivel: ActivityLevel, estado: Dictionary) -> bool:
	for condicion in nivel.condiciones_ascenso:
		if not _cumple_palanca(condicion, estado):
			return false
	return true

func _cumple_palanca(condicion: Dictionary, estado: Dictionary) -> bool:
	match String(condicion.get("palanca", "")):
		"reconocimiento_externo":
			var pedido: int = ActivityScales.indice_reconocimiento(StringName(condicion.get("valor", &"")))
			return pedido >= 0 and ActivityScales.indice_reconocimiento(estado["reconocimiento"]) >= pedido
		"rol_liderazgo":
			var pedido_rol: int = ActivityScales.indice_rol(StringName(condicion.get("valor", &"")))
			return pedido_rol >= 0 and ActivityScales.indice_rol(estado["rol"]) >= pedido_rol
		"impacto_medible":
			return float(estado["impacto"]) >= float(condicion.get("valor", 0.0))
		"anios_continuidad":
			return float(estado["anios_invertidos"]) >= float(condicion.get("valor", 0.0))
		_:
			push_error("ActivityTracker: palanca desconocida '%s'" % condicion.get("palanca", ""))
			return false

# --- Derived numbers ---------------------------------------------------------

func anios_desde_horas(actividad: ActivityData, horas: float) -> float:
	var config: AdmissionConfig = AdmissionCalculator.obtener_config()
	var semanas: float = config.semanas_por_anio_escolar if config else 36.0
	return horas / maxf(float(actividad.costo_horas_semana) * semanas, 0.0001)

## Sticking with something multiplies what it pays. Curve lives in the config
## resource, never here.
func multiplicador_continuidad(anios: float) -> float:
	var config: AdmissionConfig = AdmissionCalculator.obtener_config()
	if not config:
		return 1.0
	var contados: float = clampf(anios, 0.0, config.continuidad_anios_tope)
	return 1.0 + config.continuidad_bonus_por_anio * contados

## Tier currently held in an activity, or 5 ("nothing yet") before the first
## rung is credited.
func tier_actual(actividad_id: StringName, estado: Dictionary = {}) -> int:
	var actividad: ActivityData = ActivityRegistry.obtener(actividad_id)
	if not actividad:
		return 5
	var e: Dictionary = estado if not estado.is_empty() else obtener_estado(actividad_id)
	var indice: int = int(e.get("nivel_indice", -1))
	var niveles: Array[ActivityLevel] = actividad.obtener_niveles()
	if indice < 0 or indice >= niveles.size():
		return 5
	return niveles[indice].tier

## Whether a sport has actually turned into a recruitable one.
##
## BOTH gates must hold, and that is deliberate: a state champion with a weak
## academic record is not recruitable in the Ivy League, and a brilliant
## student who merely plays is not either. Passing `indice_academico` lets a
## hypothetical profile be tested without touching the live player.
func es_reclutable(actividad_id: StringName, indice_academico: float = -1.0, estado: Dictionary = {}) -> bool:
	var actividad: ActivityData = ActivityRegistry.obtener(actividad_id)
	if not actividad or not actividad.es_deporte:
		return false
	var e: Dictionary = estado if not estado.is_empty() else obtener_estado(actividad_id)
	if ActivityScales.indice_reconocimiento(e.get("reconocimiento", &"ninguno")) < actividad.umbral_reclutamiento:
		return false
	var indice: float = indice_academico if indice_academico >= 0.0 else AcademicIndex.valor()
	return indice >= float(actividad.academic_index_minimo)

# --- Hypothetical profiles ---------------------------------------------------

## Works out what a profile WOULD look like, without touching the player.
##
## `perfil` is actividad_id -> {anios, reconocimiento, rol, impacto}; missing
## keys take their neutral value. Used by the calibration lab and the tests,
## and it walks exactly the same ladder logic as real play, so the lab cannot
## drift away from the game.
##
## Returns:
##   actividades: actividad_id -> {nivel_indice, nivel, tier, anios,
##                                 continuidad, estado, modificadores}
##   modificadores: atributo_id -> total points the profile would have earned
##   valores:       valores_base with those points already applied
func simular_perfil(perfil: Dictionary, valores_base: Dictionary = {}) -> Dictionary:
	var actividades: Dictionary = {}
	var modificadores: Dictionary = {}
	# Worked on a copy: a simulation must never move the real player.
	var valores: Dictionary = valores_base.duplicate()
	for actividad_id in perfil:
		var actividad: ActivityData = ActivityRegistry.obtener(actividad_id)
		if not actividad:
			push_error("ActivityTracker.simular_perfil: actividad desconocida '%s'" % actividad_id)
			continue
		var entrada: Dictionary = perfil[actividad_id]
		var estado: Dictionary = _estado_inicial()
		estado["anios_invertidos"] = float(entrada.get("anios", 0.0))
		estado["horas_totales"] = estado["anios_invertidos"] * float(actividad.costo_horas_semana) * _semanas()
		estado["reconocimiento"] = entrada.get("reconocimiento", &"ninguno")
		estado["rol"] = entrada.get("rol", &"miembro")
		estado["impacto"] = float(entrada.get("impacto", 0.0))

		var multiplicador: float = multiplicador_continuidad(estado["anios_invertidos"])
		var propios: Dictionary = {}
		var niveles: Array[ActivityLevel] = actividad.obtener_niveles()
		var indice := -1
		while indice + 1 < niveles.size() and cumple_ascenso(niveles[indice + 1], estado):
			indice += 1
			for atributo_id in niveles[indice].modificadores_atributo:
				var puntos: float = float(niveles[indice].modificadores_atributo[atributo_id]) * multiplicador
				# Run it through the SAME engine real play uses, against the
				# running total, so a simulated profile feels diminishing
				# returns and caps exactly like a played one. Summing the raw
				# numbers instead would have the lab quoting totals the game
				# can never actually reach.
				var antes: float = float(valores.get(atributo_id, 0.0))
				var evaluacion: Dictionary = ModifierEngine.evaluar(atributo_id, puntos, antes, valores)
				if evaluacion.is_empty():
					continue
				var aplicado: float = evaluacion["delta_aplicado"]
				valores[atributo_id] = evaluacion["valor_despues"]
				propios[atributo_id] = propios.get(atributo_id, 0.0) + aplicado
				modificadores[atributo_id] = modificadores.get(atributo_id, 0.0) + aplicado
		estado["nivel_indice"] = indice
		actividades[actividad_id] = {
			"nivel_indice": indice,
			"nivel": niveles[indice].nombre if indice >= 0 else "sin nivel",
			"tier": niveles[indice].tier if indice >= 0 else 5,
			"anios": estado["anios_invertidos"],
			"continuidad": multiplicador,
			"estado": estado,
			"modificadores": propios,
		}
	return {
		"actividades": actividades,
		"modificadores": modificadores,
		"valores": valores,
	}

func _semanas() -> float:
	var config: AdmissionConfig = AdmissionCalculator.obtener_config()
	return config.semanas_por_anio_escolar if config else 36.0

## Wipes activity progress. Used by the lab and by loading a save.
func reiniciar() -> void:
	_estado.clear()

## Restores state saved by SaveSystem, dropping activities that no longer
## exist with a warning instead of failing to load the whole save.
func cargar_estado(datos: Dictionary) -> void:
	_estado.clear()
	for actividad_id in datos:
		if not ActivityRegistry.tiene(StringName(actividad_id)):
			push_warning("ActivityTracker: la partida guardada trae la actividad desconocida '%s'" % actividad_id)
			continue
		var entrada: Dictionary = _estado_inicial()
		entrada.merge(datos[actividad_id], true)
		_estado[StringName(actividad_id)] = entrada
