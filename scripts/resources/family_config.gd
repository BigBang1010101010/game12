extends Resource
class_name FamilyConfig

## Every number behind the family relationship, in one file. Same rule as the
## admission config: family_relationship.gd holds no constants.

## Ceiling of a relationship. Not 100 by accident - the scale is a percentage
## and the UI says so.
@export var nivel_maximo: float = 100.0

## --- Dinners ---------------------------------------------------------------
## Points one family dinner is worth on its own. Small: the mechanic is the
## repetition, not the event.
@export var puntos_cena: float = 2.0
## Each dinner in an unbroken run multiplies the next one by this much more,
## up to the cap. Same shape as an activity's continuity, for the same reason:
## showing up again matters more than showing up once.
@export var cena_bonus_continuidad: float = 0.15
@export var cena_tope_continuidad: float = 8.0
## Days without a dinner before the streak resets.
@export var cena_dias_para_romper_racha: float = 10.0

## --- Birthdays -------------------------------------------------------------
## Celebrating ON the day. The largest single move available.
@export var cumpleanos_bonus_exacto: float = 18.0
## Celebrating on any other day. Still worth something - it is a celebration -
## but a fraction, which is what makes remembering the date matter.
@export var cumpleanos_fuera_de_fecha: float = 4.0
## Charged once when a birthday goes by uncelebrated.
@export var cumpleanos_penalizacion_olvido: float = 12.0
## A gift given on the birthday is worth this much more.
@export var regalo_multiplicador_cumpleanos: float = 1.5

func validar() -> PackedStringArray:
	var problemas := PackedStringArray()
	if nivel_maximo <= 0.0:
		problemas.append("nivel_maximo debe ser > 0")
	if cumpleanos_bonus_exacto <= cumpleanos_fuera_de_fecha:
		problemas.append("celebrar en la fecha exacta debe valer mas que fuera de fecha")
	if cumpleanos_penalizacion_olvido < 0.0:
		problemas.append("cumpleanos_penalizacion_olvido no puede ser negativa")
	if puntos_cena <= 0.0:
		problemas.append("puntos_cena debe ser > 0")
	return problemas
