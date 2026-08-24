extends Resource
class_name SynergyRule

## One rule saying that having a lot of attribute A makes gains in attribute B
## worth more (or less). Rules live in data/synergies/ and the engine applies
## whatever it finds - it has no idea which attributes are involved.

@export var id: StringName = &""
@export var descripcion: String = ""

## The attribute whose CURRENT value decides whether this rule fires.
@export var atributo_origen: StringName = &""
## The attribute whose incoming GAINS get scaled.
@export var atributo_afectado: StringName = &""

## Origen must be at least this high (absolute value) for the rule to apply.
@export var umbral_activacion: float = 50.0

## Multiplier applied at FULL strength, i.e. when origen is at its maximum.
## 1.0 means no effect; 1.3 means +30%; below 1.0 models interference rather
## than synergy, which the engine supports without needing a separate concept.
@export var factor: float = 1.25

## Strength of this rule right now, in [0, 1]: 0 below the threshold, ramping
## to 1 as the origin attribute goes from the threshold to its maximum.
func intensidad(valor_origen: float, maximo_origen: float) -> float:
	if valor_origen < umbral_activacion:
		return 0.0
	var rango: float = maxf(maximo_origen - umbral_activacion, 0.0001)
	return clampf((valor_origen - umbral_activacion) / rango, 0.0, 1.0)

## The multiplier to actually use, interpolated by intensity so crossing the
## threshold ramps in smoothly instead of snapping.
func multiplicador(valor_origen: float, maximo_origen: float) -> float:
	return lerpf(1.0, factor, intensidad(valor_origen, maximo_origen))

func validar() -> PackedStringArray:
	var problemas := PackedStringArray()
	if id == &"":
		problemas.append("id vacio")
	if atributo_origen == &"":
		problemas.append("atributo_origen vacio")
	if atributo_afectado == &"":
		problemas.append("atributo_afectado vacio")
	if atributo_origen == atributo_afectado:
		problemas.append("atributo_origen y atributo_afectado son el mismo ('%s'), lo que crea una realimentacion" % atributo_origen)
	if factor < 0.0:
		problemas.append("factor negativo (%f)" % factor)
	return problemas
