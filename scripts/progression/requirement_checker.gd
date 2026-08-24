extends RefCounted
class_name RequirementChecker

## The one place that knows what a requirement DICTIONARY means.
##
## Essays already gated themselves with these; activities gate themselves with
## the same vocabulary, so the evaluation lives here instead of being copied.
## Content still declares its own conditions - this only reads them:
##   {"tipo": "atributo_minimo", "atributo": &"rigor_academico", "valor": 60.0}
##   {"tipo": "tiempo_minimo",   "actividad": &"robotica", "cantidad": 20.0}
##   {"tipo": "hito",            "hito": &"capitan_equipo"}
##
## An unknown type is REPORTED and fails closed. A typo in data must never
## quietly unlock everything, which is what returning true would do.

static func cumple(requisito: Dictionary, contexto: Dictionary = {}) -> bool:
	var tiempo_por_actividad: Dictionary = contexto.get("tiempo_por_actividad", {})
	var hitos: Array = contexto.get("hitos", [])
	var valores: Dictionary = contexto.get("valores", {})

	match String(requisito.get("tipo", "")):
		"atributo_minimo":
			var atributo: StringName = requisito.get("atributo", &"")
			# Hypothetical profiles (the calibration lab, the test suite) pass
			# their own values; live gameplay falls through to PlayerState.
			var valor: float = float(valores[atributo]) if valores.has(atributo) else PlayerState.obtener_valor(atributo)
			return valor >= float(requisito.get("valor", 0.0))
		"tiempo_minimo":
			return float(tiempo_por_actividad.get(requisito.get("actividad", &""), 0.0)) >= float(requisito.get("cantidad", 0.0))
		"hito":
			return hitos.has(requisito.get("hito", &""))
		_:
			push_error("RequirementChecker: tipo de requisito desconocido '%s'" % requisito.get("tipo", ""))
			return false

## Every condition must hold. An empty list means "always available".
static func cumple_todos(requisitos: Array, contexto: Dictionary = {}) -> bool:
	for requisito in requisitos:
		if not cumple(requisito, contexto):
			return false
	return true

## The subset that does NOT hold, so the UI can explain a lock instead of just
## showing one.
static func faltantes(requisitos: Array, contexto: Dictionary = {}) -> Array[Dictionary]:
	var salida: Array[Dictionary] = []
	for requisito in requisitos:
		if not cumple(requisito, contexto):
			salida.append(requisito)
	return salida
