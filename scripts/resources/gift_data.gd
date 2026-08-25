extends Resource
class_name GiftData

## One thing the player can buy at a gift shop.
##
## The tiers are data, not an enum: a fourth kind of present is a fourth file,
## and what separates them is only what they cost and what they are worth.

@export var id: StringName = &""
@export var nombre_display: String = ""
@export_multiline var descripcion: String = ""

## Price. No wallet exists yet, so this is reported rather than charged - the
## expense system reads it when it arrives.
@export var costo: float = 0.0

## Relationship points the gift is worth, before any occasion multiplier.
@export var puntos_relacion: float = 0.0

## Ordering hint for the UI, 1 = cheapest tier. Also what a shop uses to lay
## its shelves out without naming any gift.
@export_range(1, 9) var nivel: int = 1

func validar() -> PackedStringArray:
	var problemas := PackedStringArray()
	if id == &"":
		problemas.append("id vacio")
	if nombre_display.is_empty():
		problemas.append("nombre_display vacio")
	if costo < 0.0:
		problemas.append("costo negativo")
	if puntos_relacion <= 0.0:
		problemas.append("un regalo que no sube la relacion no es un regalo")
	return problemas
