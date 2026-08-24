extends Node

## Turns a RAW delta requested by some system into the change actually applied
## to an attribute. Everything it needs comes from data: the attribute's own
## curve, whatever synergy rules happen to exist, and the attribute's cap.
##
## It never names an attribute. Adding an attribute or a synergy rule changes
## nothing here.

## Result of evaluating one modification, kept as a dictionary so the ledger
## and the UI can show every intermediate step ("de dónde salió cada punto").
##  delta_crudo        what the caller asked for
##  mult_rendimiento   diminishing-returns multiplier from the attribute curve
##  mult_sinergia      combined multiplier from all matching synergy rules
##  sinergias          [{id, factor_aplicado}] for the breakdown UI
##  delta_efectivo     after curve and synergies, before caps
##  delta_aplicado     after clamping to [0, valor_maximo]
##  valor_antes / valor_despues
## `valores` lets a caller evaluate against a HYPOTHETICAL profile instead of
## the live player - the calibration lab and the test suite pass one. Empty
## means "use the real player", which is what gameplay does.
func evaluar(atributo_id: StringName, delta_crudo: float, valor_actual: float, valores: Dictionary = {}) -> Dictionary:
	var definicion: AttributeDefinition = AttributeRegistry.get_definition(atributo_id)
	if not definicion:
		push_error("ModifierEngine: atributo desconocido '%s'" % atributo_id)
		return {}

	# Diminishing returns only make sense for GAINS. A loss (decay, a penalty)
	# is applied at face value: otherwise high attributes would also be
	# near-immune to going down, which is the opposite of what the curve means.
	var mult_rendimiento := 1.0
	var mult_sinergia := 1.0
	var sinergias: Array[Dictionary] = []
	if delta_crudo > 0.0:
		mult_rendimiento = definicion.multiplicador_rendimiento(valor_actual)
		for regla_res in SynergyRegistry.reglas_que_afectan(atributo_id):
			var regla: SynergyRule = regla_res
			var origen: AttributeDefinition = AttributeRegistry.get_definition(regla.atributo_origen)
			if not origen:
				# A rule pointing at an attribute that no longer exists is a
				# content error, not a crash: skip it and say so.
				push_warning("SynergyRule '%s' referencia el atributo inexistente '%s'" % [regla.id, regla.atributo_origen])
				continue
			var valor_origen: float = (float(valores[regla.atributo_origen])
				if valores.has(regla.atributo_origen)
				else PlayerState.obtener_valor(regla.atributo_origen))
			var m: float = regla.multiplicador(valor_origen, origen.valor_maximo)
			if not is_equal_approx(m, 1.0):
				mult_sinergia *= m
				sinergias.append({"id": regla.id, "factor_aplicado": m})

	var delta_efectivo: float = delta_crudo * mult_rendimiento * mult_sinergia
	var valor_despues: float = clampf(valor_actual + delta_efectivo, 0.0, definicion.valor_maximo)
	return {
		"delta_crudo": delta_crudo,
		"mult_rendimiento": mult_rendimiento,
		"mult_sinergia": mult_sinergia,
		"sinergias": sinergias,
		"delta_efectivo": delta_efectivo,
		"delta_aplicado": valor_despues - valor_actual,
		"valor_antes": valor_actual,
		"valor_despues": valor_despues,
	}

## Applies one in-game day of decay to every attribute that declares a decay
## rate. Driven by whoever owns the calendar (see _on_dia_pasado wiring in
## PlayerState) rather than by a timer here, so decay stays locked to the same
## clock as everything else.
func aplicar_decaimiento_diario(dias: float = 1.0) -> void:
	if dias <= 0.0:
		return
	for definicion_res in AttributeRegistry.get_all_definitions():
		var definicion: AttributeDefinition = definicion_res
		if definicion.tasa_decaimiento <= 0.0:
			continue
		var perdida: float = definicion.tasa_decaimiento * dias
		if PlayerState.obtener_valor(definicion.id) <= 0.0:
			continue
		PlayerState.aplicar_modificador(
			definicion.id, -perdida, &"decaimiento", definicion.id,
			{"dias": dias, "tasa": definicion.tasa_decaimiento})
