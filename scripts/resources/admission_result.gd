extends Resource
class_name AdmissionResult

## The full explanation behind one admission probability. The game promises to
## justify every result with real numbers, so the calculator returns this whole
## breakdown rather than a bare float.

@export var universidad_id: StringName = &""
@export var carrera_id: StringName = &""
@export var ensayo_id: StringName = &""
@export var es_early: bool = false
@export var version_formula: int = 0

## Final probability, already clamped.
@export var probabilidad: float = 0.0
## The published rate used as the starting point (base or early).
@export var tasa_base: float = 0.0

## Weighted, normalised match against this school's weights, in [0,1].
@export var fit_score: float = 0.0
## atributo_id -> {valor, peso, aporte} where aporte is that attribute's share
## of fit_score. This is the "which of my stats got me here" table.
@export var contribuciones_atributo: Dictionary = {}

## Essay and career terms, already multiplied by their school-specific factors.
@export var efecto_ensayo: float = 0.0
@export var afinidad_ensayo: float = 1.0
@export var efecto_carrera: float = 0.0
@export var fortaleza_carrera: float = 0.0
@export var efecto_ajuste_carrera: float = 0.0
@export var ajuste_carrera: float = 0.0

## Total threshold penalty, and the per-attribute detail behind it.
@export var penalizacion_umbrales: float = 0.0
## [{atributo, valor, umbral, deficit, penalizacion}]
@export var umbrales_incumplidos: Array[Dictionary] = []

## fit + essay + career - penalty, i.e. what actually drives the odds.
@export var puntaje_final: float = 0.0
## Multiplicative effect on the odds versus the published rate. 1.0 means the
## player lands exactly at the base rate; 3.0 means three times the odds.
@export var multiplicador_odds: float = 1.0
## Early's contribution, expressed as the ratio between the early and regular
## published rates, so the UI can say what applying early was worth.
@export var bonus_early: float = 1.0

## Randomness the real decision roll may apply. Reported, never applied here.
@export var factor_aleatoriedad: float = 0.0

## One-line human summary for logs and tooltips.
func resumen() -> String:
	return "%s%s: %.1f%% (base %.1f%%, fit %.3f, ensayo %+.3f, carrera %+.3f, umbrales %-.3f)" % [
		universidad_id, " [early]" if es_early else "", probabilidad * 100.0,
		tasa_base * 100.0, fit_score, efecto_ensayo,
		efecto_carrera + efecto_ajuste_carrera, penalizacion_umbrales]
