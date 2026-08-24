extends Resource
class_name ActivityScales

## The four universal levers every activity advances on, and the only two of
## them that are ordinal scales.
##
## These are MECHANICS, not content: an activity does not get to invent a new
## kind of recognition, the same way a card game does not let a card invent a
## new suit. What each activity chooses is where on these scales its levels
## sit, which is data. Adding an activity never touches this file; the only
## reason to touch it would be deciding the game needs a new lever, which is a
## design change, not new content.
##
## Both scales are ordered from weakest to strongest and are compared by
## INDEX, so data writes &"estatal" and never a magic number.

## Reach of the recognition an activity has earned.
const RECONOCIMIENTO: Array[StringName] = [
	&"ninguno", &"escolar", &"regional", &"estatal", &"nacional", &"internacional",
]

## Position held inside the activity.
const ROL: Array[StringName] = [
	&"ninguno", &"miembro", &"oficial", &"presidente", &"fundador",
]

## Index of a recognition level, or -1 if the name is not one. Callers report
## the -1 rather than silently treating a typo as "ninguno".
static func indice_reconocimiento(nombre: StringName) -> int:
	return RECONOCIMIENTO.find(nombre)

static func indice_rol(nombre: StringName) -> int:
	return ROL.find(nombre)

static func nombre_reconocimiento(indice: int) -> StringName:
	return RECONOCIMIENTO[clampi(indice, 0, RECONOCIMIENTO.size() - 1)]

static func nombre_rol(indice: int) -> StringName:
	return ROL[clampi(indice, 0, ROL.size() - 1)]
