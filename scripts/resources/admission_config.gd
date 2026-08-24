extends Resource
class_name AdmissionConfig

## EVERY balancing constant of the admission formula. Nothing numeric lives in
## admission_calculator.gd, so the whole game can be recalibrated by editing
## data/config/admission_config.tres and reloading.

## --- Reference point -------------------------------------------------------
## The fit score of a "typical applicant to a school like this". A player
## sitting exactly here gets exactly the school's published acceptance rate;
## everything else is expressed as movement away from this point. Raising it
## makes the whole game harder without touching any school's data.
@export var fit_referencia: float = 0.55

## How sharply odds respond to being above or below the reference. This is the
## single biggest lever on how much player skill matters versus the base rate.
@export var sensibilidad: float = 4.2

## --- Thresholds ------------------------------------------------------------
## Multiplier on the summed shortfall across unmet minimums. Large on purpose:
## the point of thresholds is that being far below one is not something a
## strong score elsewhere can buy back.
@export var penalizacion_umbral: float = 2.6

## Shortfall is measured as a fraction of the threshold, then raised to this
## power. Above 1 it means just missing a threshold is cheap while missing it
## badly is catastrophic.
@export var exponente_umbral: float = 1.5

## --- Essay -----------------------------------------------------------------
## Maximum fit contribution an essay can add before the school's affinity
## multiplier is applied.
@export var peso_ensayo: float = 0.16
## Total attribute modifier that counts as a "full strength" essay. Essays
## weaker than this contribute proportionally less.
@export var ensayo_modificador_referencia: float = 45.0

## --- Career ----------------------------------------------------------------
## Maximum fit contribution from applying in a field the school is strong in.
@export var peso_carrera: float = 0.10
## Maximum fit contribution from the player's own profile matching the
## career's ideal profile.
@export var peso_ajuste_carrera: float = 0.08

## --- Output ----------------------------------------------------------------
## Hard ceiling on the returned probability. Never 1.0: admission is never
## certain, and a UI showing 100% would be lying.
@export var probabilidad_maxima: float = 0.94
## Floor, so a catastrophic profile still shows a non-zero sliver rather than
## an absolute 0 that reads as a bug.
@export var probabilidad_minima: float = 0.001

## Size of the per-applicant randomness the game may apply when a decision is
## actually rolled. The calculator reports it but does NOT apply it, so the
## displayed probability stays deterministic and explainable.
@export var factor_aleatoriedad: float = 0.08

func validar() -> PackedStringArray:
	var problemas := PackedStringArray()
	if fit_referencia <= 0.0 or fit_referencia >= 1.0:
		problemas.append("fit_referencia fuera de (0,1)")
	if sensibilidad <= 0.0:
		problemas.append("sensibilidad debe ser > 0")
	if probabilidad_maxima >= 1.0:
		problemas.append("probabilidad_maxima debe ser < 1.0: la admision nunca es segura")
	if probabilidad_minima < 0.0 or probabilidad_minima >= probabilidad_maxima:
		problemas.append("probabilidad_minima fuera de rango")
	return problemas
