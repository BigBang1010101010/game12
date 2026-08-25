extends Node

## Autoload holding the player's two purses, and the only thing allowed to
## move money.
##
## TWO PURSES, ON PURPOSE:
##   dinero_personal  earned - a paid job, a prize, a gift of cash. Spends on
##                    anything.
##   dinero_familia   never earned, only borrowed (see FamilyCredit) or given
##                    at the start by the family the player was born into.
##                    Spends only on categories whose file says so.
##
## The asymmetry is the whole design: the family funds what looks like an
## investment in the applicant, and the player's own life comes out of their
## own pocket. Which categories fall on which side is data.
##
## Every movement goes through EventBus and lands in PlayerState's ledger under
## the keys below, so money is as auditable as any attribute.

const CLAVE_PERSONAL := &"dinero_personal"
const CLAVE_FAMILIA := &"dinero_familia"

signal balance_cambiado(personal: float, familia: float)

var _personal: float = 0.0
var _familia: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The family purse is seeded by where the player was born: the location's
	# range is what the family can actually put in front of them.
	PlayerOrigin.ubicacion_fijada.connect(_on_ubicacion_fijada)

func _on_ubicacion_fijada(_ubicacion: LocationData) -> void:
	reiniciar_desde_origen()

## Starts the run's money from the chosen birthplace. Safe to call again after
## loading a save - the save overwrites the balances afterwards.
func reiniciar_desde_origen() -> void:
	_personal = 0.0
	_familia = 0.0
	var inicial: float = PlayerOrigin.dinero_inicial()
	if inicial > 0.0:
		ingresar(inicial, CLAVE_FAMILIA, &"origen", PlayerOrigin.obtener_ubicacion_id(), {
			"motivo": "dinero de familia inicial",
		})
	balance_cambiado.emit(_personal, _familia)

# --- Reading ----------------------------------------------------------------

func dinero_personal() -> float:
	return _personal

func dinero_familia() -> float:
	return _familia

func total() -> float:
	return _personal + _familia

## What is actually available for one category: family money only counts when
## the category allows it.
func disponible_para(categoria_id: StringName) -> float:
	if SpendingRegistry.permite_dinero_familia(categoria_id):
		return _personal + _familia
	return _personal

func puede_pagar(monto: float, categoria_id: StringName) -> bool:
	return monto <= disponible_para(categoria_id) + 0.0001

# --- Money in ---------------------------------------------------------------

## Income. Defaults to the personal purse, which is the only one that can be
## EARNED; FamilyCredit is what puts money in the other one.
func ingresar(monto: float, bolsillo: StringName, fuente_tipo: StringName, fuente_id: StringName, contexto: Dictionary = {}) -> float:
	if monto <= 0.0:
		return 0.0
	var antes: float = _leer(bolsillo)
	if bolsillo == CLAVE_FAMILIA:
		_familia += monto
	else:
		bolsillo = CLAVE_PERSONAL
		_personal += monto
	_anotar(bolsillo, monto, antes, _leer(bolsillo), fuente_tipo, fuente_id, contexto)
	EventBus.avisar_ingreso(monto, bolsillo, fuente_tipo, fuente_id)
	balance_cambiado.emit(_personal, _familia)
	return monto

# --- Money out --------------------------------------------------------------

## Spends against a category. Returns a result the caller can show:
##   {exito, motivo, mensaje, desde_familia, desde_personal}
##
## Family money is spent FIRST where it is allowed. That is deliberate: it is
## the money that cannot be used for anything else, so holding on to it while
## burning wages would be strictly worse for the player, and a rule that
## punishes the obvious move is a bad rule.
func gastar(monto: float, categoria_id: StringName, fuente_id: StringName = &"", contexto: Dictionary = {}) -> Dictionary:
	if monto <= 0.0:
		return _fallo("monto_invalido", "El gasto tiene que ser positivo.")
	if not SpendingRegistry.tiene(categoria_id):
		return _fallo("categoria_desconocida",
			"No existe la categoria de gasto '%s'." % categoria_id)

	var permite: bool = SpendingRegistry.permite_dinero_familia(categoria_id)
	var categoria: SpendingCategory = SpendingRegistry.obtener(categoria_id)
	if not puede_pagar(monto, categoria_id):
		if not permite and monto <= _personal + _familia:
			# The distinction the player needs: they HAVE the money, it just
			# is not money that can pay for this.
			return _fallo("categoria_no_permite_familia",
				"El dinero de la familia no cubre '%s'. Eso sale de tu bolsillo." % categoria.nombre_display)
		return _fallo("fondos_insuficientes",
			"Te faltan %.2f para '%s'." % [monto - disponible_para(categoria_id), categoria.nombre_display])

	var desde_familia: float = minf(_familia, monto) if permite else 0.0
	var desde_personal: float = monto - desde_familia

	if desde_familia > 0.0:
		var antes_f: float = _familia
		_familia -= desde_familia
		_anotar(CLAVE_FAMILIA, -desde_familia, antes_f, _familia, &"gasto", categoria_id,
			_contexto_gasto(contexto, fuente_id, monto))
	if desde_personal > 0.0:
		var antes_p: float = _personal
		_personal -= desde_personal
		_anotar(CLAVE_PERSONAL, -desde_personal, antes_p, _personal, &"gasto", categoria_id,
			_contexto_gasto(contexto, fuente_id, monto))

	EventBus.avisar_gasto(monto, categoria_id, desde_familia, desde_personal)
	balance_cambiado.emit(_personal, _familia)
	return {
		"exito": true, "motivo": "", "mensaje": "",
		"desde_familia": desde_familia, "desde_personal": desde_personal,
	}

# --- Internals --------------------------------------------------------------

func _leer(bolsillo: StringName) -> float:
	return _familia if bolsillo == CLAVE_FAMILIA else _personal

func _contexto_gasto(contexto: Dictionary, fuente_id: StringName, monto: float) -> Dictionary:
	var salida: Dictionary = contexto.duplicate(true)
	salida["monto_total"] = monto
	if fuente_id != &"":
		salida["concepto"] = fuente_id
	return salida

func _anotar(clave: StringName, delta: float, antes: float, despues: float, fuente_tipo: StringName, fuente_id: StringName, contexto: Dictionary) -> void:
	PlayerState.registrar_cambio(clave, delta, antes, despues, fuente_tipo, fuente_id, contexto)

func _fallo(motivo: String, mensaje: String) -> Dictionary:
	return {"exito": false, "motivo": motivo, "mensaje": mensaje,
		"desde_familia": 0.0, "desde_personal": 0.0}

# --- Persistence ------------------------------------------------------------

func obtener_estado() -> Dictionary:
	return {"personal": _personal, "familia": _familia}

func cargar_estado(datos: Dictionary) -> void:
	_personal = float(datos.get("personal", 0.0))
	_familia = float(datos.get("familia", 0.0))
	balance_cambiado.emit(_personal, _familia)
