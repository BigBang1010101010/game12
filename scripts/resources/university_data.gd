extends Resource
class_name UniversityData

## One university's admissions profile. Lives in data/universities/.
## Adding school #9 is adding a .tres there; nothing enumerates schools.

@export var id: StringName = &""
## Kept separate from id so display names can change (licensing, rebrands)
## without breaking a single reference anywhere in saves or other data.
@export var nombre_display: String = ""
@export var color_primario: Color = Color.WHITE
@export var color_secundario: Color = Color.BLACK

## Real overall acceptance rate, e.g. 0.032.
@export var tasa_admision_base: float = 0.05
## Early decision/action rate, which in reality is substantially higher.
@export var tasa_admision_early: float = 0.10

## atributo_id -> weight. Attributes absent from this dictionary count as 0,
## so a school simply does not mention what it does not care about.
@export var pesos_atributos: Dictionary = {}

## atributo_id -> minimum. Falling below one of these hurts far more than the
## weighted score alone would suggest - modelling that no Ivy takes you with
## weak academic rigour however brilliant you are elsewhere.
@export var umbrales_minimos: Dictionary = {}

## narrativa_tipo -> multiplier on that essay's effect. This is what makes the
## SAME essay strong at one school and weak at another.
@export var afinidad_narrativas: Dictionary = {}

## carrera_id -> how strong this school is in that field, and therefore how
## much applying there in it helps.
@export var fortalezas_carrera: Dictionary = {}

@export_multiline var descripcion_cultura: String = ""

func validar() -> PackedStringArray:
	var problemas := PackedStringArray()
	if id == &"":
		problemas.append("id vacio")
	if nombre_display.is_empty():
		problemas.append("nombre_display vacio")
	if tasa_admision_base <= 0.0 or tasa_admision_base >= 1.0:
		problemas.append("tasa_admision_base fuera de (0,1): %f" % tasa_admision_base)
	if tasa_admision_early <= 0.0 or tasa_admision_early >= 1.0:
		problemas.append("tasa_admision_early fuera de (0,1): %f" % tasa_admision_early)
	if pesos_atributos.is_empty():
		problemas.append("pesos_atributos vacio: la universidad no valoraria nada")
	var suma := 0.0
	for clave in pesos_atributos:
		var peso: float = pesos_atributos[clave]
		if peso < 0.0:
			problemas.append("peso negativo en '%s'" % clave)
		suma += peso
	if suma <= 0.0:
		problemas.append("los pesos suman 0")
	return problemas

## Total weight, used to normalise the fit score so schools that list more
## attributes are not automatically easier or harder.
func peso_total() -> float:
	var suma := 0.0
	for clave in pesos_atributos:
		suma += pesos_atributos[clave]
	return suma
