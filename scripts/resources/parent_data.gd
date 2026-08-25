extends Resource
class_name ParentData

## One member of the player's family they have a relationship with.
##
## Two files ship with the game, but nothing anywhere says "two": a
## grandmother is a third file, and every system that iterates the registry
## picks her up.

@export var id: StringName = &""
@export var nombre_display: String = ""
@export_multiline var descripcion: String = ""

## Birthday as "MM-DD" on the game's fixed 365-day calendar. Written as a date
## rather than a day number so the file reads like what it means.
@export var fecha_cumpleanos: String = "01-01"

## Where the relationship starts, 0-100. Family is not a stranger: this is
## normally well above zero, and how far above is characterisation.
@export_range(0.0, 100.0) var nivel_relacion_inicial: float = 60.0

## Days without any interaction before the relationship starts to fade, and
## how much it fades per day after that. Per parent, because not everyone
## needs the same amount of attention.
@export var dias_gracia_decaimiento: float = 7.0
@export var decaimiento_diario: float = 0.35

const DIAS_POR_MES: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

func validar() -> PackedStringArray:
	var problemas := PackedStringArray()
	if id == &"":
		problemas.append("id vacio")
	if nombre_display.is_empty():
		problemas.append("nombre_display vacio")
	if dia_del_anio() < 0:
		problemas.append("fecha_cumpleanos '%s' no tiene el formato MM-DD o no existe" % fecha_cumpleanos)
	if nivel_relacion_inicial < 0.0 or nivel_relacion_inicial > 100.0:
		problemas.append("nivel_relacion_inicial fuera de 0-100")
	if decaimiento_diario < 0.0:
		problemas.append("decaimiento_diario no puede ser negativo")
	return problemas

## Birthday as a day of the year, 1-365, or -1 when the date is malformed.
## Kept as a method rather than a stored number so the file never has to hold
## two representations that could disagree.
func dia_del_anio() -> int:
	var partes: PackedStringArray = fecha_cumpleanos.split("-")
	if partes.size() != 2:
		return -1
	if not (partes[0].is_valid_int() and partes[1].is_valid_int()):
		return -1
	var mes: int = int(partes[0])
	var dia: int = int(partes[1])
	if mes < 1 or mes > 12 or dia < 1 or dia > DIAS_POR_MES[mes - 1]:
		return -1
	var acumulado := 0
	for i in range(mes - 1):
		acumulado += DIAS_POR_MES[i]
	return acumulado + dia
