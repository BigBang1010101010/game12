extends Resource
class_name ConsultingTier

## One level of admissions consulting the player can pay for.
##
## What you buy is PRECISION, not truth: every tier reports an approximation,
## and the expensive ones are simply wrong by less. That is the honest model of
## the real industry, and it keeps the game's central uncertainty intact no
## matter how much money the player throws at it.

@export var id: StringName = &""
@export var nombre_display: String = ""
@export_multiline var descripcion: String = ""

## Price, always paid from the player's own pocket rules (see the spending
## category the service charges against).
@export var costo: float = 0.0

## Relative error of everything this tier reports, as a fraction. 0.30 means a
## real 20% may be shown as anything from 14% to 26%. Never 0: see validar().
@export_range(0.0, 1.0) var margen_error: float = 0.3

## How deep the report goes. Ordered scale, weakest first - a tier chooses
## where it sits, it does not invent a new kind of coverage.
##   indice    only the Academic Index band
##   atributos + the player's own attributes
##   desglose  + per-school odds and the terms behind them
const COBERTURAS: Array[StringName] = [&"indice", &"atributos", &"desglose"]
@export var cobertura: StringName = &"indice"

## Ordering hint for the UI.
@export_range(1, 9) var nivel: int = 1

func validar() -> PackedStringArray:
	var problemas := PackedStringArray()
	if id == &"":
		problemas.append("id vacio")
	if nombre_display.is_empty():
		problemas.append("nombre_display vacio")
	if costo < 0.0:
		problemas.append("costo negativo")
	if margen_error <= 0.0:
		problemas.append("margen_error debe ser > 0: ninguna asesoria puede prometer el numero exacto")
	if indice_cobertura() < 0:
		problemas.append("cobertura desconocida '%s'" % cobertura)
	return problemas

func indice_cobertura() -> int:
	return COBERTURAS.find(cobertura)

## Whether this tier reaches a given depth, compared by position on the scale.
func cubre(nivel_cobertura: StringName) -> bool:
	var pedido: int = COBERTURAS.find(nivel_cobertura)
	return pedido >= 0 and indice_cobertura() >= pedido
