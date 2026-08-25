extends Resource
class_name SportStatCategory

## One statistic a sport is actually measured by.
##
## These are the real box-score categories of each sport, not invented ones:
## a football player is read by yards and touchdowns, a pitcher by ERA, a
## rower by a 2000m time. That matters because the whole point of the system
## is that a player's recognition is JUSTIFIED by numbers a real coach would
## recognise, rather than by a value someone typed in.
##
## Ids are prefixed with the sport - beisbol_asistencias and
## baloncesto_asistencias are different statistics that share a name - because
## the registry demands unique ids across all sports.

@export var id: StringName = &""

## The activity this belongs to. Must be an ActivityData with es_deporte.
@export var deporte_id: StringName = &""

@export var nombre_display: String = ""

## Unit shown next to the number: "yardas", "por juego", "segundos", "puesto".
@export var unidad: String = ""

## Whether a HIGHER number is better. False for the ones where it is not -
## ERA, a 2000m time, a national ranking - and the difference is not cosmetic:
## it flips how the benchmark bands are read.
@export var es_mejor_mayor: bool = true

## Ordering hint inside its sport.
@export_range(1, 99) var orden: int = 50

func validar() -> PackedStringArray:
	var problemas := PackedStringArray()
	if id == &"":
		problemas.append("id vacio")
	if deporte_id == &"":
		problemas.append("deporte_id vacio")
	if nombre_display.is_empty():
		problemas.append("nombre_display vacio")
	if unidad.is_empty():
		problemas.append("unidad vacia: un numero sin unidad no se puede leer")
	return problemas

## Formats a value the way its sport writes it. Batting averages are written
## .347, times as 6:23, everything else as a plain number.
func formatear(valor: float) -> String:
	if unidad == "promedio":
		return ("%.3f" % valor).trim_prefix("0")
	if unidad == "segundos":
		return "%d:%04.1f" % [int(valor) / 60, fmod(valor, 60.0)]
	if unidad == "puesto":
		return "#%d" % int(round(valor))
	if absf(valor - round(valor)) < 0.01:
		return "%d %s" % [int(round(valor)), unidad]
	return "%.2f %s" % [valor, unidad]
