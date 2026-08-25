extends Resource
class_name LocationData

## Where the player was born, and what that costs them.
##
## This resource IS the difficulty system. There is no separate "easy /
## normal / hard" switch anywhere in the project: a location is a cost of
## living, a starting family balance and a credit disposition, and those three
## numbers are what make one run harder than another. Adding a fourth city is
## adding a file here.

@export var id: StringName = &""
@export var nombre_display: String = ""
@export_multiline var descripcion: String = ""

## Cost of living index, 100 = New York City.
##
## SOURCE AND METHOD: the scale follows the shape of the published composite
## cost-of-living indices (C2ER/ACCRA-style, the family that Numbeo and the
## state-level tables also reproduce), where Manhattan sits at roughly twice
## the US average and is the most expensive metro in the country, Boston lands
## clearly below it but well above average, and northern New Jersey - the
## commuter belt - is cheaper than either while still being an expensive
## corner of the US. Rebased so New York is exactly 100, that gives the three
## values this catalogue ships with: NY 100, Boston 75, New Jersey 65. They
## are a defensible approximation, not a citation: if we later pull the real
## composite indices for specific counties, updating them is editing these
## three files and nothing else.
@export var indice_costo_vida: float = 100.0

## Weekly cost multiplier for the player's day-to-day living. Left at 0.0 it
## is DERIVED from the index (indice/100), which is the honest default:
## living somewhere 25% cheaper costs 25% less per week. A location may
## override it when its everyday costs and its housing costs pull apart.
@export var multiplicador_gasto_semanal: float = 0.0

## Family money available at the start of the run, as a range the game rolls
## within. Not income: this is what the family can actually put in front of
## the player.
@export var dinero_familia_base_min: float = 0.0
@export var dinero_familia_base_max: float = 0.0

## How readily the family says yes to a loan, 0 (never) to 1 (almost always).
##
## The counter-intuitive part is deliberate and is the whole point of the
## difficulty design: nominal income in New York is HIGHER and this number is
## LOWER. A family paying Manhattan rent has less slack at the end of the
## month than a family paying New Jersey rent on a smaller salary, and slack
## is what a loan comes out of. Cheaper to live, more margin, easier yes.
@export_range(0.0, 1.0) var facilidad_credito_familiar: float = 0.5

## How the game tells the player what they are choosing, in their terms.
@export_multiline var descripcion_dificultad: String = ""

func validar() -> PackedStringArray:
	var problemas := PackedStringArray()
	if id == &"":
		problemas.append("id vacio")
	if nombre_display.is_empty():
		problemas.append("nombre_display vacio")
	if indice_costo_vida <= 0.0:
		problemas.append("indice_costo_vida debe ser > 0")
	if multiplicador_gasto_semanal < 0.0:
		problemas.append("multiplicador_gasto_semanal no puede ser negativo")
	if dinero_familia_base_min < 0.0 or dinero_familia_base_max < dinero_familia_base_min:
		problemas.append("rango de dinero_familia_base invalido")
	if facilidad_credito_familiar < 0.0 or facilidad_credito_familiar > 1.0:
		problemas.append("facilidad_credito_familiar fuera de 0-1")
	if descripcion_dificultad.is_empty():
		problemas.append("descripcion_dificultad vacia: el jugador no sabria que esta eligiendo")
	return problemas

## The multiplier the weekly expense system will use. Derived from the index
## unless the file states otherwise.
func gasto_semanal() -> float:
	if multiplicador_gasto_semanal > 0.0:
		return multiplicador_gasto_semanal
	return indice_costo_vida / 100.0

## Starting family money. Deterministic when a seed is given, so a test or a
## calibration run can reproduce a specific start.
func dinero_inicial(rng: RandomNumberGenerator = null) -> float:
	if dinero_familia_base_max <= dinero_familia_base_min:
		return dinero_familia_base_min
	if rng:
		return rng.randf_range(dinero_familia_base_min, dinero_familia_base_max)
	return randf_range(dinero_familia_base_min, dinero_familia_base_max)

## Midpoint of the range, for UI that has to show one number.
func dinero_inicial_promedio() -> float:
	return (dinero_familia_base_min + dinero_familia_base_max) * 0.5
