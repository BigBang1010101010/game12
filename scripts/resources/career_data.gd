extends Resource
class_name CareerData

## One career path. Lives in data/careers/.

@export var id: StringName = &""
@export var nombre_display: String = ""
@export_multiline var descripcion: String = ""

## atributo_id -> the value that characterises someone who thrives here.
@export var perfil_ideal: Dictionary = {}

## atributo_id -> how forgiving deviation from the ideal is. Low numbers mean
## the attribute is critical (missing it hurts a lot); high numbers mean it is
## flexible. Attributes absent here use TOLERANCIA_POR_DEFECTO.
@export var tolerancia_desviacion: Dictionary = {}

## Free-form store for the real-world statistics the game will use to educate
## the player (satisfaction rates, common paths, salary distributions...).
## Deliberately empty for now; the structure exists so filling it later needs
## no schema change.
@export var datos_estadisticos: Dictionary = {}

const TOLERANCIA_POR_DEFECTO := 35.0

## How well a player's attribute values match this career, in [0, 1].
## 1 means sitting exactly on the ideal profile.
func calcular_ajuste(valores: Dictionary) -> float:
	if perfil_ideal.is_empty():
		return 0.5
	var suma := 0.0
	var cuenta := 0
	for atributo_id in perfil_ideal:
		var ideal: float = perfil_ideal[atributo_id]
		var actual: float = valores.get(atributo_id, 0.0)
		var tolerancia: float = tolerancia_desviacion.get(atributo_id, TOLERANCIA_POR_DEFECTO)
		tolerancia = maxf(tolerancia, 0.0001)
		# Only falling SHORT of the ideal counts against you. Exceeding it is
		# never a penalty: being better than the profile needs is not a flaw.
		var deficit: float = maxf(ideal - actual, 0.0)
		suma += clampf(1.0 - deficit / tolerancia, 0.0, 1.0)
		cuenta += 1
	return suma / float(maxi(cuenta, 1))

func validar() -> PackedStringArray:
	var problemas := PackedStringArray()
	if id == &"":
		problemas.append("id vacio")
	if nombre_display.is_empty():
		problemas.append("nombre_display vacio")
	if perfil_ideal.is_empty():
		problemas.append("perfil_ideal vacio")
	return problemas
