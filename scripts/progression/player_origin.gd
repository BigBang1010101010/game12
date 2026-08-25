extends Node

## Autoload holding the ONE location choice of a run.
##
## Birthplace is fixed at the start and never changes: it is the run's
## difficulty, and a difficulty you can edit halfway through is not one. The
## setter refuses a second call unless explicitly told this is a new game, and
## says so rather than failing quietly.
##
## It names no city. Everything it knows comes from the LocationData the
## registry loaded.

signal ubicacion_fijada(ubicacion: LocationData)

## Key under which the choice is persisted, through the existing save system.
const CLAVE_GUARDADO := &"ubicacion_nacimiento"

var _ubicacion_id: StringName = &""
var _dinero_inicial: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func esta_fijada() -> bool:
	return _ubicacion_id != &""

## Fixes the birthplace. Returns false when it is already set (and logs why),
## so a UI cannot silently re-roll a run's difficulty.
func fijar_ubicacion(ubicacion_id: StringName, rng: RandomNumberGenerator = null) -> bool:
	if esta_fijada():
		push_warning("PlayerOrigin: la ubicacion ya es '%s' y no puede cambiar en la misma partida" % _ubicacion_id)
		return false
	if not LocationRegistry.tiene(ubicacion_id):
		push_error("PlayerOrigin: ubicacion desconocida '%s'" % ubicacion_id)
		return false
	_ubicacion_id = ubicacion_id
	var ubicacion: LocationData = obtener_ubicacion()
	_dinero_inicial = ubicacion.dinero_inicial(rng)
	SaveSystem.fijar_eleccion(CLAVE_GUARDADO, String(ubicacion_id))
	ubicacion_fijada.emit(ubicacion)
	return true

## Starts a new run, which is the only situation where the choice may change.
func reiniciar() -> void:
	_ubicacion_id = &""
	_dinero_inicial = 0.0

func obtener_ubicacion() -> LocationData:
	return LocationRegistry.obtener(_ubicacion_id) as LocationData

func obtener_ubicacion_id() -> StringName:
	return _ubicacion_id

# --- What other systems read ------------------------------------------------

## Multiplier the weekly expense system applies to living costs. 1.0 when no
## location is set, so a system asking early behaves as if in the reference
## city instead of dividing by zero.
func multiplicador_gasto_semanal() -> float:
	var ubicacion: LocationData = obtener_ubicacion()
	return ubicacion.gasto_semanal() if ubicacion else 1.0

## Disposition of the family toward lending, 0-1. Read by the family credit
## system.
func facilidad_credito_familiar() -> float:
	var ubicacion: LocationData = obtener_ubicacion()
	return ubicacion.facilidad_credito_familiar if ubicacion else 0.5

## Money the family put in front of the player at the start of this run, rolled
## once within the location's range and then fixed.
func dinero_inicial() -> float:
	return _dinero_inicial

## What the save system currently holds for this run, for UI and tests.
func obtener_eleccion_guardada() -> String:
	return String(SaveSystem.obtener_eleccion(CLAVE_GUARDADO, ""))

## Restores the choice from a loaded save.
func cargar_desde_guardado() -> void:
	var guardada: Variant = SaveSystem.obtener_eleccion(CLAVE_GUARDADO, "")
	var id := StringName(String(guardada))
	if id == &"":
		return
	if not LocationRegistry.tiene(id):
		push_warning("PlayerOrigin: el guardado trae la ubicacion desconocida '%s'" % id)
		return
	_ubicacion_id = id
	if is_zero_approx(_dinero_inicial):
		_dinero_inicial = obtener_ubicacion().dinero_inicial_promedio()
