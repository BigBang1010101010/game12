extends Node

## Autoload holding the player's relationship with each member of their
## family, and the only thing allowed to move it.
##
## It names no parent: the levels are built from ParentRegistry, the gifts
## come from GiftRegistry, and every number lives in family_config.tres. A
## grandmother is a file in data/parents/.
##
## Every change goes through PlayerState's ledger with fuente_tipo &"familia",
## so "why is my relationship with my father at 41?" is answerable event by
## event, exactly like an attribute.

signal relacion_cambiada(padre_id: StringName, nivel: float)
signal cumpleanos_olvidado(padre_id: StringName)

const FUENTE := &"familia"
const RUTA_CONFIG := "res://data/config/family_config.tres"

## Ledger key for a parent: relacion_<id>. Kept as a prefix so a query can ask
## for one parent or, with the ledger's own filters, for the whole family.
const PREFIJO_CLAVE := "relacion_"

var _config: FamilyConfig = null
## padre_id -> nivel actual
var _niveles: Dictionary = {}
## padre_id -> day of the run of the last interaction of any kind
var _ultimo_contacto: Dictionary = {}
## padre_id -> {racha: int, ultimo_dia: float}
var _cenas: Dictionary = {}
## padre_id -> day of year of the last birthday already resolved, so one
## birthday can neither be celebrated twice nor forgotten twice.
var _cumpleanos_resueltos: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	recargar_config()
	reiniciar()
	DayNightCycle.day_passed.connect(_on_dia_pasado)

func recargar_config() -> void:
	_config = load(RUTA_CONFIG) as FamilyConfig
	if not _config:
		push_error("FamilyRelationship: no se pudo cargar %s" % RUTA_CONFIG)
		return
	var problemas: PackedStringArray = _config.validar()
	if not problemas.is_empty():
		push_error("FamilyConfig invalido: %s" % ", ".join(problemas))

func obtener_config() -> FamilyConfig:
	return _config

## Rebuilds every relationship at its declared starting level. Called at
## startup, when a new run begins and after loading a save.
func reiniciar() -> void:
	_niveles.clear()
	_ultimo_contacto.clear()
	_cenas.clear()
	_cumpleanos_resueltos.clear()
	for padre_res in ParentRegistry.obtener_todos():
		var padre: ParentData = padre_res
		_niveles[padre.id] = padre.nivel_relacion_inicial
		_ultimo_contacto[padre.id] = _dia()
		_cenas[padre.id] = {"racha": 0, "ultimo_dia": -999.0}

# --- What other systems read ------------------------------------------------

## THE read method. Family credit, dialogue and anything else asks here.
## Returns 0.0 for an unknown parent rather than failing, so a system reading
## a family member that was removed from the data degrades instead of crashing.
func obtener_nivel_relacion(padre_id: StringName) -> float:
	return float(_niveles.get(padre_id, 0.0))

func obtener_niveles() -> Dictionary:
	return _niveles.duplicate()

## Average across the whole family, for systems that care about "the family"
## rather than about one person - family credit being the first of them.
func nivel_promedio() -> float:
	if _niveles.is_empty():
		return 0.0
	var suma := 0.0
	for id in _niveles:
		suma += _niveles[id]
	return suma / float(_niveles.size())

## Ledger key for one parent, so callers can query the breakdown themselves.
func clave_ledger(padre_id: StringName) -> StringName:
	return StringName(PREFIJO_CLAVE + String(padre_id))

## Where this relationship's points came from, spanning every source.
func obtener_desglose(padre_id: StringName) -> Dictionary:
	var entradas: Array[Dictionary] = PlayerState.consultar_ledger({"atributo": clave_ledger(padre_id)})
	var por_fuente: Dictionary = {}
	var ganado := 0.0
	var perdido := 0.0
	for entrada in entradas:
		var delta: float = entrada["delta_aplicado"]
		if delta >= 0.0:
			ganado += delta
		else:
			perdido += delta
		por_fuente[entrada["fuente_id"]] = por_fuente.get(entrada["fuente_id"], 0.0) + delta
	return {
		"padre": padre_id,
		"nivel_actual": obtener_nivel_relacion(padre_id),
		"total_ganado": ganado,
		"total_perdido": perdido,
		"por_fuente": por_fuente,
		"eventos": entradas.size(),
	}

# --- The three ways up ------------------------------------------------------

## Buys a gift. Refuses, with a reason, when the player is not standing in a
## gift shop or when either id is unknown - the caller gets something it can
## show, never a silent no-op.
##
## The cost is REPORTED, not charged: there is no wallet yet. When the expense
## system lands it charges `costo` from this same result.
func comprar_regalo(padre_id: StringName, regalo_id: StringName) -> Dictionary:
	var regalo: GiftData = GiftRegistry.obtener(regalo_id)
	if not _niveles.has(padre_id):
		return _fallo("padre_desconocido", "No existe '%s' en data/parents/" % padre_id)
	if not regalo:
		return _fallo("regalo_desconocido", "No existe el regalo '%s'" % regalo_id)
	if not GiftShop.hay_tienda_cerca():
		return _fallo("sin_tienda", "Los regalos se compran en una tienda de regalos.")

	var es_cumpleanos: bool = es_su_cumpleanos(padre_id)
	var puntos: float = regalo.puntos_relacion
	if es_cumpleanos:
		puntos *= _config.regalo_multiplicador_cumpleanos
	var aplicado: float = _mover(padre_id, puntos, &"regalo", {
		"regalo": regalo.id, "costo": regalo.costo, "nivel_regalo": regalo.nivel,
		"en_su_cumpleanos": es_cumpleanos,
	})
	if es_cumpleanos:
		_cumpleanos_resueltos[padre_id] = DayNightCycle.get_day_of_year()
	return {
		"exito": true, "puntos": aplicado, "costo": regalo.costo,
		"en_su_cumpleanos": es_cumpleanos, "nivel": obtener_nivel_relacion(padre_id),
	}

## Celebrates a birthday. Worth several times more on the actual day, which is
## the entire point of the parents carrying a date.
func celebrar_cumpleanos(padre_id: StringName) -> Dictionary:
	if not _niveles.has(padre_id):
		return _fallo("padre_desconocido", "No existe '%s' en data/parents/" % padre_id)
	var exacto: bool = es_su_cumpleanos(padre_id)
	var puntos: float = _config.cumpleanos_bonus_exacto if exacto else _config.cumpleanos_fuera_de_fecha
	var aplicado: float = _mover(padre_id, puntos, &"cumpleanos", {
		"en_fecha": exacto,
		"dia_del_anio": DayNightCycle.get_day_of_year(),
		"su_dia": _dia_de_cumpleanos(padre_id),
	})
	if exacto:
		_cumpleanos_resueltos[padre_id] = DayNightCycle.get_day_of_year()
	return {"exito": true, "puntos": aplicado, "en_fecha": exacto,
		"nivel": obtener_nivel_relacion(padre_id)}

## A family dinner: small on its own, and worth more the longer the streak of
## them runs. Same continuity idea as an activity, and for the same reason.
func cenar_en_familia(padre_id: StringName) -> Dictionary:
	if not _niveles.has(padre_id):
		return _fallo("padre_desconocido", "No existe '%s' en data/parents/" % padre_id)
	var estado: Dictionary = _cenas[padre_id]
	var hoy: float = _dia()
	if hoy - float(estado["ultimo_dia"]) > _config.cena_dias_para_romper_racha:
		estado["racha"] = 0
	estado["racha"] = int(estado["racha"]) + 1
	estado["ultimo_dia"] = hoy
	var contadas: float = minf(float(estado["racha"] - 1), _config.cena_tope_continuidad)
	var multiplicador: float = 1.0 + _config.cena_bonus_continuidad * contadas
	var aplicado: float = _mover(padre_id, _config.puntos_cena * multiplicador, &"cena", {
		"racha": estado["racha"], "continuidad": multiplicador,
	})
	return {"exito": true, "puntos": aplicado, "racha": estado["racha"],
		"continuidad": multiplicador, "nivel": obtener_nivel_relacion(padre_id)}

# --- Time passing -----------------------------------------------------------

func es_su_cumpleanos(padre_id: StringName) -> bool:
	return _dia_de_cumpleanos(padre_id) == DayNightCycle.get_day_of_year()

## Days until this parent's birthday, for the UI that has to remind the player.
func dias_para_cumpleanos(padre_id: StringName) -> int:
	var dia: int = _dia_de_cumpleanos(padre_id)
	return DayNightCycle.days_until(dia) if dia > 0 else -1

func _on_dia_pasado() -> void:
	_cobrar_olvidos()
	_aplicar_decaimiento()

## A birthday that went by without a celebration or a gift costs, once.
## Checked the day AFTER, because a birthday is not missed until it is over.
func _cobrar_olvidos() -> void:
	var ayer: int = posmod(DayNightCycle.get_day_of_year() - 2, DayNightCycle.DAYS_PER_YEAR) + 1
	for padre_res in ParentRegistry.obtener_todos():
		var padre: ParentData = padre_res
		if padre.dia_del_anio() != ayer:
			continue
		if int(_cumpleanos_resueltos.get(padre.id, -1)) == ayer:
			continue
		_cumpleanos_resueltos[padre.id] = ayer
		_mover(padre.id, -_config.cumpleanos_penalizacion_olvido, &"cumpleanos_olvidado", {
			"dia_del_anio": ayer,
		})
		cumpleanos_olvidado.emit(padre.id)

## Ignoring someone costs, but only after their own grace period: the decay is
## per parent because not everyone needs the same amount of attention.
func _aplicar_decaimiento() -> void:
	var hoy: float = _dia()
	for padre_res in ParentRegistry.obtener_todos():
		var padre: ParentData = padre_res
		if padre.decaimiento_diario <= 0.0:
			continue
		var dias_sin_contacto: float = hoy - float(_ultimo_contacto.get(padre.id, hoy))
		if dias_sin_contacto <= padre.dias_gracia_decaimiento:
			continue
		# The decay itself is not contact, so _ultimo_contacto is deliberately
		# left alone: it keeps falling until the player actually shows up.
		_mover(padre.id, -padre.decaimiento_diario, &"decaimiento", {
			"dias_sin_contacto": dias_sin_contacto,
			"gracia": padre.dias_gracia_decaimiento,
		}, false)

# --- Internals --------------------------------------------------------------

## Applies a change, clamps it to the scale, records it in the shared ledger
## and, when it was the player doing something, refreshes the contact clock.
func _mover(padre_id: StringName, delta: float, fuente_id: StringName, contexto: Dictionary, es_contacto: bool = true) -> float:
	var antes: float = obtener_nivel_relacion(padre_id)
	var despues: float = clampf(antes + delta, 0.0, _config.nivel_maximo)
	var aplicado: float = despues - antes
	_niveles[padre_id] = despues
	if es_contacto:
		_ultimo_contacto[padre_id] = _dia()
	PlayerState.registrar_cambio(
		clave_ledger(padre_id), aplicado, antes, despues, FUENTE, fuente_id, contexto)
	relacion_cambiada.emit(padre_id, despues)
	return aplicado

func _dia_de_cumpleanos(padre_id: StringName) -> int:
	var padre: ParentData = ParentRegistry.obtener(padre_id)
	return padre.dia_del_anio() if padre else -1

func _dia() -> float:
	return PlayerState.dia_actual()

func _fallo(motivo: String, mensaje: String) -> Dictionary:
	return {"exito": false, "motivo": motivo, "mensaje": mensaje, "puntos": 0.0}

# --- Persistence ------------------------------------------------------------

func obtener_estado() -> Dictionary:
	return {
		"niveles": _niveles.duplicate(),
		"ultimo_contacto": _ultimo_contacto.duplicate(),
		"cenas": _cenas.duplicate(true),
		"cumpleanos_resueltos": _cumpleanos_resueltos.duplicate(),
	}

## Restores a save, dropping family members who no longer exist and starting
## new ones at their declared level - the same discipline attributes get.
func cargar_estado(datos: Dictionary) -> void:
	reiniciar()
	var niveles: Dictionary = datos.get("niveles", {})
	for clave in niveles:
		var id := StringName(clave)
		if not _niveles.has(id):
			push_warning("FamilyRelationship: el guardado trae a '%s', que ya no existe" % clave)
			continue
		_niveles[id] = float(niveles[clave])
	for clave in datos.get("ultimo_contacto", {}):
		if _ultimo_contacto.has(StringName(clave)):
			_ultimo_contacto[StringName(clave)] = float(datos["ultimo_contacto"][clave])
	for clave in datos.get("cenas", {}):
		if _cenas.has(StringName(clave)):
			_cenas[StringName(clave)] = datos["cenas"][clave]
	for clave in datos.get("cumpleanos_resueltos", {}):
		_cumpleanos_resueltos[StringName(clave)] = int(datos["cumpleanos_resueltos"][clave])
