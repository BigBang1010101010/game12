extends Resource
class_name ActivityData

## One extracurricular the player can commit time to. Lives in
## data/activities/, one file each.
##
## Nothing about a specific activity is written in any script: the categories,
## the ladders, which careers it helps and whether it is a recruitable sport
## all come from here. Adding activity number 80 is adding a file.

@export var id: StringName = &""
@export var nombre_display: String = ""
@export_multiline var descripcion: String = ""

## Free-form grouping used by the UI, e.g. &"stem", &"medicina",
## &"derecho_politica", &"negocios", &"artes", &"transversal", &"deporte".
## Free-form on purpose: a new category is a new string in a new file, not a
## new enum case here.
@export var categoria: StringName = &""

## Best tier this activity can ever reach, 1 (national/exceptional) to 4.
## The ceiling exists because some activities simply cannot read as tier 1 to
## an admissions office however long you stay in them.
@export_range(1, 4) var tier_techo: int = 4

## Weekly cost against the player's finite time budget.
@export var costo_horas_semana: int = 2

## The internal ladder, weakest first. Array (not Array[ActivityLevel]) so a
## hand-authored .tres can list sub-resources without fighting the typed-array
## syntax; the class is checked in validar() instead.
@export var niveles: Array = []

## carrera_id -> multiplier on how much this activity supports that
## application. 1.0 is neutral; above it means the activity reads as evidence
## for that field.
@export var carreras_afinidad: Dictionary = {}

## --- The parallel athletic route -------------------------------------------
@export var es_deporte: bool = false
## Index into ActivityScales.RECONOCIMIENTO that the player must reach before
## a coach would ever put them on a recruitment list.
@export var umbral_reclutamiento: int = 3
## Academic Index floor a recruited athlete still has to clear. Below it the
## athletic route is closed no matter how good the athlete is - which is how
## the Ivy League actually works (see academic_index.gd).
@export var academic_index_minimo: int = 176

## Conditions gating availability, using the SAME vocabulary as essays
## (atributo_minimo / tiempo_minimo / hito), evaluated by RequirementChecker.
@export var requisitos_desbloqueo: Array[Dictionary] = []

func validar() -> PackedStringArray:
	var problemas := PackedStringArray()
	if id == &"":
		problemas.append("id vacio")
	if nombre_display.is_empty():
		problemas.append("nombre_display vacio")
	if categoria == &"":
		problemas.append("categoria vacia")
	if costo_horas_semana <= 0:
		problemas.append("costo_horas_semana debe ser > 0")
	if niveles.is_empty():
		problemas.append("sin niveles: la actividad no podria progresar")

	var tier_mejor := 5
	for nivel in niveles:
		if not (nivel is ActivityLevel):
			problemas.append("un elemento de 'niveles' no es un ActivityLevel")
			continue
		problemas.append_array((nivel as ActivityLevel).validar())
		tier_mejor = mini(tier_mejor, (nivel as ActivityLevel).tier)
	if not niveles.is_empty() and tier_mejor < tier_techo:
		problemas.append("un nivel otorga tier %d, mejor que el tier_techo %d declarado" % [
			tier_mejor, tier_techo])

	if es_deporte:
		if umbral_reclutamiento < 0 or umbral_reclutamiento >= ActivityScales.RECONOCIMIENTO.size():
			problemas.append("umbral_reclutamiento fuera de la escala de reconocimiento")
	for requisito in requisitos_desbloqueo:
		if not requisito.has("tipo"):
			problemas.append("un requisito de desbloqueo no declara 'tipo'")
	return problemas

## The ladder's rungs, typed, for callers that want to iterate them safely.
func obtener_niveles() -> Array[ActivityLevel]:
	var salida: Array[ActivityLevel] = []
	for nivel in niveles:
		if nivel is ActivityLevel:
			salida.append(nivel)
	return salida

## Best tier actually reachable, read from the ladder rather than trusted from
## tier_techo, so the two can be cross-checked.
func mejor_tier_de_niveles() -> int:
	var mejor := 4
	for nivel in obtener_niveles():
		mejor = mini(mejor, nivel.tier)
	return mejor
