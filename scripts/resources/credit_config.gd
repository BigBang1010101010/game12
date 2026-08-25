extends Resource
class_name CreditConfig

## Every number behind a family loan. Same rule as the admission config:
## family_credit.gd holds no constants, and the attributes that count as
## "responsible" are listed HERE, not in code.

## atributo_id -> weight in the responsibility fit. Data, so the day character
## stops mattering or grades start mattering more, it is this file.
@export var pesos_responsabilidad: Dictionary = {}

## The responsibility fit of someone a family would lend to without thinking
## about it. A player exactly here gets exactly the location's own
## disposition; everything else is movement away from that point.
@export var fit_referencia: float = 0.55
## How sharply the odds respond to that movement.
@export var sensibilidad: float = 3.2

## --- Relationship ----------------------------------------------------------
## Relationship level that counts as neutral, and how much the distance from
## it is worth. This is where the family relationship system pays off.
@export var relacion_referencia: float = 60.0
@export var peso_relacion: float = 0.45

## --- Amount ----------------------------------------------------------------
## Asking for the whole ceiling costs this much score; asking for a fraction
## costs a convex fraction of it.
@export var peso_monto: float = 0.5
@export var exponente_monto: float = 1.6

## Ceiling: the location's top family balance times this, plus a bonus that
## scales with the relationship. A loved child can ask for more.
@export var maximo_factor_base: float = 0.8
@export var maximo_bonus_relacion: float = 0.9

## --- Recent refusals -------------------------------------------------------
## Each refusal still in memory costs this much score, and refusals fade after
## this many in-game days. Asking again immediately after a no is the worst
## time to ask, which is true of families and of banks.
@export var penalizacion_por_rechazo: float = 0.25
@export var rechazo_dias_memoria: float = 14.0

## --- Output ----------------------------------------------------------------
@export var probabilidad_maxima: float = 0.95
@export var probabilidad_minima: float = 0.02

func validar() -> PackedStringArray:
	var problemas := PackedStringArray()
	if pesos_responsabilidad.is_empty():
		problemas.append("pesos_responsabilidad vacio: el fit de responsabilidad no mediria nada")
	if fit_referencia <= 0.0 or fit_referencia >= 1.0:
		problemas.append("fit_referencia fuera de (0,1)")
	if sensibilidad <= 0.0:
		problemas.append("sensibilidad debe ser > 0")
	if probabilidad_maxima >= 1.0:
		problemas.append("probabilidad_maxima debe ser < 1.0: un prestamo nunca es seguro")
	if probabilidad_minima < 0.0 or probabilidad_minima >= probabilidad_maxima:
		problemas.append("probabilidad_minima fuera de rango")
	if maximo_factor_base <= 0.0:
		problemas.append("maximo_factor_base debe ser > 0")
	return problemas

func peso_total() -> float:
	var total := 0.0
	for atributo_id in pesos_responsabilidad:
		total += float(pesos_responsabilidad[atributo_id])
	return total
