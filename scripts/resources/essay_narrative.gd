extends Resource
class_name EssayNarrative

## One essay narrative the player can choose. Lives in data/essays/.
##
## The same narrative should help a lot at some schools and little at others;
## that comes from the school's afinidad_narrativas matching narrativa_tipo,
## not from anything written here.

@export var id: StringName = &""
@export var titulo: String = ""
## The summary the player reads when choosing.
@export_multiline var texto_preview: String = ""

## atributo_id -> how strongly this narrative presents that attribute to
## admissions. Not a change to the attribute itself: it is framing.
@export var modificadores_atributo: Dictionary = {}

## One short line saying what kind of strength this essay puts forward, in the
## player's language. It exists so the UI never has to print the raw numbers
## below: the game hides exact attribute values everywhere else, and an essay
## card leaking "liderazgo +20" would be the one place it did not.
##
## Written per essay because it IS content - deriving it from narrativa_tipo
## would mean a table of narrative types inside a script, which is exactly
## what this project does not do. Left empty, the UI falls back to naming the
## attributes it moves most, still without the numbers.
@export var resalta: String = ""

## Archetype key that universities reference in afinidad_narrativas.
@export var narrativa_tipo: StringName = &""

## Conditions, AS DATA, that gate this narrative. Each entry is a Dictionary:
##   {"tipo": "atributo_minimo", "atributo": &"logro_atletico", "valor": 40.0}
##   {"tipo": "tiempo_minimo",   "actividad": &"deporte", "cantidad": 20.0}
##   {"tipo": "hito",            "hito": &"capitan_equipo"}
## Unknown condition types are reported rather than silently passing, so a
## typo in data cannot quietly unlock everything.
@export var requisitos_desbloqueo: Array[Dictionary] = []

func validar() -> PackedStringArray:
	var problemas := PackedStringArray()
	if id == &"":
		problemas.append("id vacio")
	if titulo.is_empty():
		problemas.append("titulo vacio")
	if narrativa_tipo == &"":
		problemas.append("narrativa_tipo vacio (ninguna universidad podria tener afinidad)")
	for requisito in requisitos_desbloqueo:
		if not requisito.has("tipo"):
			problemas.append("un requisito no declara 'tipo'")
	return problemas
