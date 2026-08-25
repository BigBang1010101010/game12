extends Node

## Autoload message bus. Minigames, hobbies, events and any future system talk
## to progression ONLY through here - they never call PlayerState directly.
## That is what lets a new system be added without touching an existing one:
## it emits on the bus, and whoever cares is already listening.
##
## The signals are deliberately generic (ids and dictionaries, not typed
## per-feature payloads) so adding a new kind of source never means adding a
## new signal.

## Something wants to change an attribute. PlayerState listens and applies it.
signal solicitar_modificador(atributo_id: StringName, delta: float, fuente_tipo: StringName, fuente_id: StringName, contexto: Dictionary)

## An attribute actually changed, after curves, synergies and caps. UI listens.
signal atributo_modificado(atributo_id: StringName, delta: float, fuente_tipo: StringName, fuente_id: StringName)

## A milestone was reached. Unlock conditions and UI listen.
signal hito_desbloqueado(hito_id: StringName)

## The player spent time on something. Essay unlock conditions read this.
signal tiempo_invertido(actividad_id: StringName, cantidad: float)

## Admission odds were recomputed and any showing UI should refresh.
signal probabilidades_recalculadas()

## --- Money ------------------------------------------------------------------
## Money came in. `bolsillo` is which purse grew, so a listener can tell
## personal earnings from family money without knowing what either is for.
signal dinero_ganado(monto: float, bolsillo: StringName, fuente_tipo: StringName, fuente_id: StringName)

## Money went out, against a spending category.
signal dinero_gastado(monto: float, categoria_id: StringName, desde_familia: float, desde_personal: float)

## A loan was asked for, whatever the answer. `resultado` carries the full
## LoanResult breakdown, so UI and analytics read the same object.
signal prestamo_solicitado(monto: float, aprobado: bool, resultado: Resource)

## Convenience wrappers so callers do not have to remember argument order.
func pedir_modificador(atributo_id: StringName, delta: float, fuente_tipo: StringName, fuente_id: StringName, contexto: Dictionary = {}) -> void:
	solicitar_modificador.emit(atributo_id, delta, fuente_tipo, fuente_id, contexto)

func avisar_tiempo(actividad_id: StringName, cantidad: float) -> void:
	tiempo_invertido.emit(actividad_id, cantidad)

func avisar_hito(hito_id: StringName) -> void:
	hito_desbloqueado.emit(hito_id)

func avisar_ingreso(monto: float, bolsillo: StringName, fuente_tipo: StringName, fuente_id: StringName) -> void:
	dinero_ganado.emit(monto, bolsillo, fuente_tipo, fuente_id)

func avisar_gasto(monto: float, categoria_id: StringName, desde_familia: float, desde_personal: float) -> void:
	dinero_gastado.emit(monto, categoria_id, desde_familia, desde_personal)
