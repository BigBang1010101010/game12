extends Resource
class_name ActivityLevel

## One rung of an activity's internal ladder: "Miembro" -> "Oficial" ->
## "Capitán" -> "Campeón estatal".
##
## Reaching a level is what pays out: modificadores_atributo is applied once,
## through PlayerState, so it lands in the audit ledger like everything else.

## Shown to the player, e.g. "Capitán del equipo".
@export var nombre: String = ""

## Tier this level represents, 1 (national/exceptional) to 4 (participation).
## The lower the better, matching how admissions officers actually talk about
## extracurricular strength.
@export_range(1, 4) var tier: int = 4

## atributo_id -> points granted ONCE on reaching this level. Applied through
## the modifier engine, so diminishing returns and synergies still apply.
@export var modificadores_atributo: Dictionary = {}

## What it takes to climb here from the previous level, AS DATA. Each entry is
## a Dictionary naming one of the four universal levers:
##   {"palanca": "reconocimiento_externo", "valor": &"estatal"}
##   {"palanca": "rol_liderazgo",          "valor": &"presidente"}
##   {"palanca": "impacto_medible",        "valor": 500.0}
##   {"palanca": "anios_continuidad",      "valor": 3.0}
## All entries must hold at once. An unknown lever is reported rather than
## silently passing, so a typo cannot unlock a national title for free.
@export var condiciones_ascenso: Array[Dictionary] = []

func validar() -> PackedStringArray:
	var problemas := PackedStringArray()
	if nombre.is_empty():
		problemas.append("un nivel no tiene nombre")
	if tier < 1 or tier > 4:
		problemas.append("nivel '%s': tier %d fuera de 1-4" % [nombre, tier])
	for condicion in condiciones_ascenso:
		if not condicion.has("palanca"):
			problemas.append("nivel '%s': una condicion no declara 'palanca'" % nombre)
			continue
		var palanca := String(condicion["palanca"])
		match palanca:
			"reconocimiento_externo":
				if ActivityScales.indice_reconocimiento(StringName(condicion.get("valor", &""))) < 0:
					problemas.append("nivel '%s': reconocimiento desconocido '%s'" % [nombre, condicion.get("valor", "")])
			"rol_liderazgo":
				if ActivityScales.indice_rol(StringName(condicion.get("valor", &""))) < 0:
					problemas.append("nivel '%s': rol desconocido '%s'" % [nombre, condicion.get("valor", "")])
			"impacto_medible", "anios_continuidad":
				if not condicion.has("valor"):
					problemas.append("nivel '%s': la palanca '%s' no trae 'valor'" % [nombre, palanca])
			_:
				problemas.append("nivel '%s': palanca desconocida '%s'" % [nombre, palanca])
	return problemas
