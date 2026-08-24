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

## --- Activities ------------------------------------------------------------
## Weeks of the school year an activity is actually practised. Turns hours
## into years of continuity without any activity having to state its own
## calendar.
@export var semanas_por_anio_escolar: float = 36.0

## Sticking with something pays. Each sustained year multiplies what that
## activity is worth by this much more, up to the cap below - the shape of
## "four years of the same thing beats four different things", which is what
## admissions offices say they read for.
@export var continuidad_bonus_por_anio: float = 0.18
@export var continuidad_anios_tope: float = 4.0

## Total hours a week the player has to spend on everything.
@export var horas_semana_totales: int = 35

## atributo_id -> points lost per week, per hour of overcommitment. This is
## burnout: taking on more than the week holds costs something real. Kept as
## data so which attributes suffer is a content decision, not a code one.
@export var penalizacion_sobrecompromiso: Dictionary = {}

## How many activities reach the application at all. The real Common App has
## ten slots; everything else the player did still happened, it just never
## gets read.
@export var slots_common_app: int = 10

## Impact figure that counts as "a lot" when ranking activities for those
## slots (people reached, dollars raised, papers published...).
@export var impacto_referencia: float = 500.0

## Maximum fit contribution from the activities on the application matching
## the career applied to, and the summed affinity that counts as full
## strength.
@export var peso_actividades: float = 0.14
@export var actividad_afinidad_referencia: float = 4.0

## What being a recruitable athlete is worth, as a fit term of its own. Large
## on purpose: recruitment is the single biggest lever in Ivy admissions, and
## it is also the most gated - see academic_index_minimo on each sport.
@export var bonus_atletico: float = 0.55

## --- Academic Index --------------------------------------------------------
## Which attribute category the Academic Index is built from. A pointer into
## data, so an academic attribute added later is picked up automatically.
@export var categoria_academica: StringName = &"academico"

## Floor a recruited athlete must clear for the athletic route to open, and
## the floor below which a regular applicant is at a severe disadvantage.
## Both on the real 60-240 scale (see academic_index.gd).
@export var umbral_indice_atletico: float = 176.0
@export var umbral_indice_competitivo: float = 210.0

## Weight and shape of the penalty for falling under the relevant threshold.
## Convex like the attribute thresholds: just under is survivable, far under
## is not.
@export var peso_indice: float = 0.45
@export var exponente_indice: float = 1.6

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
	if semanas_por_anio_escolar <= 0.0:
		problemas.append("semanas_por_anio_escolar debe ser > 0")
	if horas_semana_totales <= 0:
		problemas.append("horas_semana_totales debe ser > 0")
	if slots_common_app <= 0:
		problemas.append("slots_common_app debe ser > 0")
	if umbral_indice_atletico > umbral_indice_competitivo:
		problemas.append("umbral_indice_atletico deberia ser menor que umbral_indice_competitivo")
	return problemas
