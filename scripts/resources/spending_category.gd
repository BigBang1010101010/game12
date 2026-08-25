extends Resource
class_name SpendingCategory

## One kind of thing money gets spent on, and - the point of the class -
## whether FAMILY money is allowed to pay for it.
##
## The two-purse rule is a design statement: a family lends for things that
## look like an investment in the applicant, not for the player's life. Which
## side of that line a category falls on is data, so the day tutoring stops
## counting as an investment it is a flag in a file, not a branch in a script.

@export var id: StringName = &""
@export var nombre_display: String = ""
@export_multiline var descripcion: String = ""

## Whether the family purse may pay for this.
@export var permite_dinero_familia: bool = false

## Ordering hint for UI lists.
@export_range(1, 99) var orden: int = 50

func validar() -> PackedStringArray:
	var problemas := PackedStringArray()
	if id == &"":
		problemas.append("id vacio")
	if nombre_display.is_empty():
		problemas.append("nombre_display vacio")
	if descripcion.is_empty():
		problemas.append("descripcion vacia: el jugador no sabria por que le rechazan un pago")
	return problemas
