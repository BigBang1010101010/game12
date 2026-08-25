extends Resource
class_name LoanResult

## The full explanation behind one loan decision. Same contract as
## AdmissionResult: the game promises to justify a number, so the calculator
## returns the whole breakdown and never a bare yes/no.

@export var version_formula: int = 0
@export var aprobado: bool = false
## Why a request never reached a roll at all: "sin_ubicacion",
## "monto_invalido", "sin_familia". Empty when it was actually decided.
@export var motivo: StringName = &""
@export var mensaje: String = ""

@export var monto_solicitado: float = 0.0
## What was actually put on the table. Equal to the request unless it was
## above the ceiling, in which case the family offers the ceiling instead of
## saying no - which is what families do.
@export var monto_evaluado: float = 0.0
@export var monto_aprobado: float = 0.0
@export var monto_maximo: float = 0.0
@export var recortado: bool = false

@export var probabilidad: float = 0.0
## The location's own disposition, before anything the player did.
@export var ubicacion_id: StringName = &""
@export var base_ubicacion: float = 0.0

## Weighted match against the attributes that read as "responsible", in [0,1],
## and the per-attribute detail behind it.
@export var fit_responsabilidad: float = 0.0
@export var contribuciones_atributo: Dictionary = {}

## Who was asked, how the relationship stands and what that was worth.
@export var padre_id: StringName = &""
@export var nivel_relacion: float = 0.0
@export var efecto_relacion: float = 0.0

## Asking for a lot is harder than asking for a little.
@export var efecto_monto: float = 0.0
## Recent refusals still hanging in the air, and their cost.
@export var rechazos_recientes: int = 0
@export var penalizacion_rechazos: float = 0.0

@export var puntaje_final: float = 0.0
@export var multiplicador_odds: float = 1.0
## The roll that decided it, so a result can be replayed and explained.
@export var tirada: float = 0.0

func resumen() -> String:
	if motivo != &"":
		return "prestamo no evaluado (%s): %s" % [motivo, mensaje]
	return "%s %.0f de %.0f (max %.0f): p=%.1f%% [base %.2f, fit %.3f, relacion %+.3f, monto %+.3f, rechazos %+.3f] tirada %.3f" % [
		"APROBADO" if aprobado else "RECHAZADO", monto_aprobado, monto_solicitado, monto_maximo,
		probabilidad * 100.0, base_ubicacion, fit_responsabilidad, efecto_relacion,
		efecto_monto, -penalizacion_rechazos, tirada]
