extends Node

## Autoload deciding whether the family lends, and how much.
##
## THE SAME MATHEMATICS AS ADMISSIONS, on purpose. A weighted, normalised fit
## against what the decider cares about, plus a handful of separate terms, all
## mapped onto a published-looking base rate through an odds ratio:
##
##   1. base = facilidad_credito_familiar of the birthplace. The anchor, and
##      the reason a run in New Jersey is easier than one in New York.
##
##   2. fit = Sigma(peso_i * valor_i / max_i) / Sigma(peso_i)      in [0,1]
##      over the attributes the config calls "responsible". Identical shape to
##      the admission fit, and the attributes are listed in the config file,
##      never here.
##
##   3. relacion = W_r * (nivel - referencia) / 100
##      The family relationship system paying off. Symmetric: a cold
##      relationship subtracts as much as a warm one adds.
##
##   4. monto = -W_m * (monto / maximo) ^ E_m
##      Asking for a little is easy; asking for the whole ceiling is not.
##      Convex, so the difficulty is concentrated at the top of the range.
##
##   5. rechazos = -P_r * (refusals still in memory)
##      Asking again right after a no is the worst moment to ask.
##
##   6. S    = fit + relacion + monto - rechazos
##      odds = (base/(1-base)) * exp(K * (S - S_ref))
##      p    = odds / (1 + odds), clamped
##
## A player exactly at the reference fit, at a neutral relationship, asking for
## nothing, gets exactly the location's own disposition. Every term above then
## reads as "multiplies your odds by exp(K * its contribution)".

const FORMULA_VERSION := 1
const RUTA_CONFIG := "res://data/config/credit_config.tres"
const FUENTE := &"prestamo"

signal prestamo_resuelto(resultado: LoanResult)

var _config: CreditConfig = null
## In-game days on which a request was refused. Old ones fall out of memory.
var _rechazos: Array[float] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	recargar_config()

func recargar_config() -> void:
	_config = load(RUTA_CONFIG) as CreditConfig
	if not _config:
		push_error("FamilyCredit: no se pudo cargar %s" % RUTA_CONFIG)
		return
	var problemas: PackedStringArray = _config.validar()
	if not problemas.is_empty():
		push_error("CreditConfig invalido: %s" % ", ".join(problemas))
	for atributo_id in _config.pesos_responsabilidad:
		if not AttributeRegistry.tiene(atributo_id):
			push_error("CreditConfig: el atributo de responsabilidad '%s' no existe" % atributo_id)

func obtener_config() -> CreditConfig:
	return _config

# --- Reading before asking --------------------------------------------------

## Who the player would ask if they did not say: whoever likes them most,
## which is what people actually do.
func mejor_pariente() -> StringName:
	var mejor: StringName = &""
	var nivel_mejor := -1.0
	for padre_res in ParentRegistry.obtener_todos():
		var padre: ParentData = padre_res
		var nivel: float = FamilyRelationship.obtener_nivel_relacion(padre.id)
		if nivel > nivel_mejor:
			nivel_mejor = nivel
			mejor = padre.id
	return mejor

## The ceiling: what the family could put together at all, scaled by how well
## the player stands with the person they are asking. Zero without a
## birthplace, since the family's means come from where they live.
func monto_maximo(padre_id: StringName = &"") -> float:
	var ubicacion: LocationData = PlayerOrigin.obtener_ubicacion()
	if not ubicacion or not _config:
		return 0.0
	var quien: StringName = padre_id if padre_id != &"" else mejor_pariente()
	var nivel: float = FamilyRelationship.obtener_nivel_relacion(quien)
	var escala: float = _config.maximo_factor_base + _config.maximo_bonus_relacion * (nivel / 100.0)
	return ubicacion.dinero_familia_base_max * escala

## Refusals still weighing on the next request.
func rechazos_recientes() -> int:
	_olvidar_rechazos_viejos()
	return _rechazos.size()

## The whole decision WITHOUT making it: same breakdown, no roll, no money.
## This is what a UI shows before the player commits to asking.
func evaluar(monto: float, padre_id: StringName = &"") -> LoanResult:
	return _construir(monto, padre_id)

# --- Asking -----------------------------------------------------------------

## Asks for money. `rng` lets a test or a replay reproduce the roll; live play
## passes nothing and gets a fresh one.
func solicitar_prestamo(monto: float, padre_id: StringName = &"", rng: RandomNumberGenerator = null) -> LoanResult:
	var resultado: LoanResult = _construir(monto, padre_id)
	if resultado.motivo != &"":
		EventBus.prestamo_solicitado.emit(monto, false, resultado)
		prestamo_resuelto.emit(resultado)
		return resultado

	resultado.tirada = rng.randf() if rng else randf()
	resultado.aprobado = resultado.tirada < resultado.probabilidad
	if resultado.aprobado:
		resultado.monto_aprobado = resultado.monto_evaluado
		Wallet.ingresar(resultado.monto_aprobado, Wallet.CLAVE_FAMILIA, FUENTE, resultado.padre_id, {
			"probabilidad": resultado.probabilidad,
			"nivel_relacion": resultado.nivel_relacion,
			"solicitado": resultado.monto_solicitado,
			"maximo": resultado.monto_maximo,
		})
	else:
		# A refusal is remembered, and the memory is what makes asking again
		# immediately the worst possible move.
		_rechazos.append(PlayerState.dia_actual())
		PlayerState.registrar_cambio(
			Wallet.CLAVE_FAMILIA, 0.0, Wallet.dinero_familia(), Wallet.dinero_familia(),
			FUENTE, &"rechazado", {"solicitado": monto, "probabilidad": resultado.probabilidad})

	EventBus.prestamo_solicitado.emit(monto, resultado.aprobado, resultado)
	prestamo_resuelto.emit(resultado)
	return resultado

# --- The formula ------------------------------------------------------------

func _construir(monto: float, padre_id: StringName) -> LoanResult:
	var resultado := LoanResult.new()
	resultado.version_formula = FORMULA_VERSION
	resultado.monto_solicitado = monto

	if not _config:
		return _sin_evaluar(resultado, &"sin_config", "No hay configuracion de credito cargada.")
	if monto <= 0.0:
		return _sin_evaluar(resultado, &"monto_invalido", "Hay que pedir una cantidad positiva.")
	var ubicacion: LocationData = PlayerOrigin.obtener_ubicacion()
	if not ubicacion:
		return _sin_evaluar(resultado, &"sin_ubicacion",
			"Todavia no se ha elegido lugar de nacimiento, asi que no hay familia que pueda prestar.")
	var quien: StringName = padre_id if padre_id != &"" else mejor_pariente()
	if quien == &"":
		return _sin_evaluar(resultado, &"sin_familia", "No hay nadie a quien pedirle.")

	resultado.ubicacion_id = ubicacion.id
	resultado.base_ubicacion = ubicacion.facilidad_credito_familiar
	resultado.padre_id = quien
	resultado.nivel_relacion = FamilyRelationship.obtener_nivel_relacion(quien)
	resultado.monto_maximo = monto_maximo(quien)

	# Over the ceiling the family does not say no - it offers what it has.
	resultado.monto_evaluado = minf(monto, resultado.monto_maximo)
	resultado.recortado = resultado.monto_evaluado < monto - 0.0001
	if resultado.monto_maximo <= 0.0:
		return _sin_evaluar(resultado, &"sin_margen",
			"Tu familia no tiene nada que prestar ahora mismo.")

	# 2. Responsibility fit, exactly the shape of the admission fit.
	var valores: Dictionary = PlayerState.obtener_todos_los_valores()
	var peso_total: float = _config.peso_total()
	var fit := 0.0
	var contribuciones: Dictionary = {}
	for atributo_id in _config.pesos_responsabilidad:
		var definicion: AttributeDefinition = AttributeRegistry.get_definition(atributo_id)
		if not definicion:
			continue
		var peso: float = float(_config.pesos_responsabilidad[atributo_id])
		var valor: float = float(valores.get(atributo_id, 0.0))
		var normalizado: float = clampf(valor / maxf(definicion.valor_maximo, 0.0001), 0.0, 1.0)
		var aporte: float = peso * normalizado / maxf(peso_total, 0.0001)
		fit += aporte
		contribuciones[atributo_id] = {"valor": valor, "peso": peso, "aporte": aporte}
	resultado.fit_responsabilidad = fit
	resultado.contribuciones_atributo = contribuciones

	# 3. Where the relationship stands.
	resultado.efecto_relacion = _config.peso_relacion * (
		(resultado.nivel_relacion - _config.relacion_referencia) / 100.0)

	# 4. How much is being asked for, as a fraction of what there is.
	var fraccion: float = clampf(resultado.monto_evaluado / maxf(resultado.monto_maximo, 0.0001), 0.0, 1.0)
	resultado.efecto_monto = -_config.peso_monto * pow(fraccion, _config.exponente_monto)

	# 5. Recent noes.
	resultado.rechazos_recientes = rechazos_recientes()
	resultado.penalizacion_rechazos = _config.penalizacion_por_rechazo * float(resultado.rechazos_recientes)

	# 6. Score and odds.
	var puntaje: float = (fit + resultado.efecto_relacion + resultado.efecto_monto
		- resultado.penalizacion_rechazos)
	resultado.puntaje_final = puntaje

	var base: float = clampf(resultado.base_ubicacion, 0.0001, 0.9999)
	var odds_base: float = base / (1.0 - base)
	resultado.multiplicador_odds = exp(_config.sensibilidad * (puntaje - _config.fit_referencia))
	var odds: float = odds_base * resultado.multiplicador_odds
	resultado.probabilidad = clampf(odds / (1.0 + odds),
		_config.probabilidad_minima, _config.probabilidad_maxima)
	return resultado

func _sin_evaluar(resultado: LoanResult, motivo: StringName, mensaje: String) -> LoanResult:
	resultado.motivo = motivo
	resultado.mensaje = mensaje
	resultado.aprobado = false
	resultado.monto_aprobado = 0.0
	return resultado

func _olvidar_rechazos_viejos() -> void:
	if not _config:
		return
	var corte: float = PlayerState.dia_actual() - _config.rechazo_dias_memoria
	var vigentes: Array[float] = []
	for dia in _rechazos:
		if dia >= corte:
			vigentes.append(dia)
	_rechazos = vigentes

# --- Persistence ------------------------------------------------------------

func obtener_estado() -> Dictionary:
	return {"rechazos": _rechazos.duplicate()}

func cargar_estado(datos: Dictionary) -> void:
	_rechazos.clear()
	for dia in datos.get("rechazos", []):
		_rechazos.append(float(dia))

func reiniciar() -> void:
	_rechazos.clear()
