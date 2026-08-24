extends Resource
class_name AttributeDefinition

## Definition of ONE trackable player attribute, loaded from data/attributes/.
##
## Attributes are deliberately NOT properties on a class. Adding a new one is
## creating a .tres in data/attributes/ - no script anywhere enumerates them,
## and every system that works with attributes iterates the registry instead.

## Unique key used by every other system to reference this attribute.
## Never shown to the player, so it can stay stable while names change.
@export var id: StringName = &""

## Player-facing name.
@export var nombre_display: String = ""

## What this attribute measures, shown in the UI so the player understands
## what they are building.
@export_multiline var descripcion: String = ""

## Grouping key, e.g. &"academico", &"holistico", &"vida". Free-form on
## purpose: adding a new category is just using a new string here, no enum to
## extend.
@export var categoria: StringName = &""

@export var valor_inicial: float = 0.0
@export var valor_maximo: float = 100.0

## How much of this attribute is lost per in-game DAY when it is not
## reinforced. Models skills that need sustained practice. 0 = never decays.
## Weight this attribute carries inside the Academic Index, for attributes in
## the academic category. 1.0 means "one full component of the index"; 0.0
## keeps an academic attribute out of it entirely. Ignored outside that
## category, so every other attribute can leave it alone.
@export var peso_indice_academico: float = 1.0

@export var tasa_decaimiento: float = 0.0

## Diminishing returns, applied by ModifierEngine.
##
## Two ways to express it, so designers can start simple and get precise later:
##  - curva_exponente: gains are multiplied by (1 - value/max) ^ exponente.
##    0.0 means no diminishing returns at all; 1.0 is linear falloff; higher
##    values make the last points much more expensive than the first.
##  - curva_rendimientos: an optional Curve sampled at the NORMALISED current
##    value (0..1) returning the multiplier directly. When set it wins over
##    the exponent, so an attribute can have a hand-authored curve without
##    the engine needing to know which attributes are special.
@export var curva_exponente: float = 1.0
@export var curva_rendimientos: Curve = null

## Multiplier for a raw delta at `valor_actual`, in [0, inf).
func multiplicador_rendimiento(valor_actual: float) -> float:
	var span: float = maxf(valor_maximo, 0.0001)
	var normalizado: float = clampf(valor_actual / span, 0.0, 1.0)
	if curva_rendimientos:
		return maxf(curva_rendimientos.sample_baked(normalizado), 0.0)
	if curva_exponente <= 0.0:
		return 1.0
	return pow(1.0 - normalizado, curva_exponente)

## Sanity check used by the registry and the test suite so malformed data
## fails loudly instead of silently misbehaving. Returns a list of problems.
func validar() -> PackedStringArray:
	var problemas := PackedStringArray()
	if id == &"":
		problemas.append("id vacio")
	if nombre_display.is_empty():
		problemas.append("nombre_display vacio")
	if categoria == &"":
		problemas.append("categoria vacia")
	if valor_maximo <= 0.0:
		problemas.append("valor_maximo debe ser > 0 (es %f)" % valor_maximo)
	if valor_inicial < 0.0 or valor_inicial > valor_maximo:
		problemas.append("valor_inicial %f fuera de [0, %f]" % [valor_inicial, valor_maximo])
	if tasa_decaimiento < 0.0:
		problemas.append("tasa_decaimiento negativa (%f)" % tasa_decaimiento)
	return problemas
