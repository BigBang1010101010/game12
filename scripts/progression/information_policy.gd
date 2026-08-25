extends Node

## Autoload holding ONE design rule: the player does not get to see their own
## numbers.
##
## This is a deliberate change of stance. Attributes, the Academic Index and
## admission probabilities are all computed exactly, audited exactly and stored
## exactly - and shown to the player only as bands, or as a paid estimate with
## a margin of error attached. Nobody applying to university knows their real
## odds; the game is about deciding under that uncertainty, and a UI printing
## "Harvard: 18.4%" would delete the entire question.
##
## Two sanctioned exceptions, both explicit:
##   - ConsultingService, which returns approximations and always says by how
##     much it might be wrong.
##   - the F1 calibration lab, which is a development tool and says so.
##
## Any normal UI asks here for its wording instead of formatting a float.

## Flipping this to true turns the game into a spreadsheet. It exists so a
## debug tool can ask rather than assume.
const VALORES_EXACTOS_VISIBLES := false

## Qualitative bands, as fractions of an attribute's own maximum. A mechanic,
## not content: the words a UI is allowed to use.
const BANDAS: Array[Dictionary] = [
	{"hasta": 0.15, "etiqueta": "casi nulo"},
	{"hasta": 0.35, "etiqueta": "bajo"},
	{"hasta": 0.55, "etiqueta": "medio"},
	{"hasta": 0.75, "etiqueta": "bueno"},
	{"hasta": 0.90, "etiqueta": "muy bueno"},
	{"hasta": 1.01, "etiqueta": "excepcional"},
]

## How an admission probability may be described without stating it.
const BANDAS_PROBABILIDAD: Array[Dictionary] = [
	{"hasta": 0.03, "etiqueta": "remota"},
	{"hasta": 0.10, "etiqueta": "difícil"},
	{"hasta": 0.25, "etiqueta": "posible"},
	{"hasta": 0.45, "etiqueta": "razonable"},
	{"hasta": 0.70, "etiqueta": "sólida"},
	{"hasta": 1.01, "etiqueta": "muy probable"},
]

func puede_ver_valores_exactos() -> bool:
	return VALORES_EXACTOS_VISIBLES

## How a normal UI names an attribute value.
func describir_atributo(valor: float, maximo: float = 100.0) -> String:
	return _banda(BANDAS, valor / maxf(maximo, 0.0001))

## How a normal UI names a probability.
func describir_probabilidad(probabilidad: float) -> String:
	return _banda(BANDAS_PROBABILIDAD, probabilidad)

## An estimate with its margin attached, e.g. "entre 12% y 24%". This is the
## ONLY numeric shape the player ever sees, and it always carries the error.
func describir_estimacion(valor: float, margen: float, sufijo: String = "") -> String:
	var bajo: float = valor * (1.0 - margen)
	var alto: float = valor * (1.0 + margen)
	return "entre %.0f%s y %.0f%s" % [bajo, sufijo, alto, sufijo]

func _banda(bandas: Array[Dictionary], fraccion: float) -> String:
	var f: float = clampf(fraccion, 0.0, 1.0)
	for banda in bandas:
		if f <= float(banda["hasta"]):
			return String(banda["etiqueta"])
	return String(bandas[bandas.size() - 1]["etiqueta"])
