extends SportMinigame

## Free throws: ten shots on a moving marker, and a rim that gets less
## forgiving every time.
##
## Same principle as the batting cage: the marker's sweep is visible and the
## result is a function of where it was when the key went down. What changes is
## the pressure - each shot the marker moves faster and the sweet spot narrows,
## so a session is a test of holding precision as it gets harder rather than of
## hitting one lucky window.

const TIROS := 10
const ANCHO_BARRA := 620.0
const CENTRO_TOLERANCIA := 46.0     ## half-width of a make, in pixels, shot 1
const CRECIMIENTO_VELOCIDAD := 0.08 ## +8% marker speed per shot
const REDUCCION_VENTANA := 0.045    ## -4.5% window per shot

var _barra: ColorRect
var _zona: ColorRect
var _marca: ColorRect
var _marcador: Label
var _tiro := 0
var _aciertos := 0
var _posicion := 0.0
var _direccion := 1.0
var _velocidad := 300.0
var _tolerancia := CENTRO_TOLERANCIA
var _activo := false

func _nombre_juego() -> String:
	return "tiros libres"

func _texto_instrucciones() -> String:
	return ("Diez tiros. Pulsa ESPACIO cuando el marcador esté sobre la zona verde. " +
		"Cada tiro el marcador va más rápido y la zona se encoge.")

func _preparar(area: Control) -> void:
	var fondo := ColorRect.new()
	fondo.color = Color(0.16, 0.11, 0.08)
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	area.add_child(fondo)

	_barra = ColorRect.new()
	_barra.color = Color(0.22, 0.24, 0.28)
	_barra.size = Vector2(ANCHO_BARRA, 46)
	_barra.position = Vector2(60, 150)
	area.add_child(_barra)

	_zona = ColorRect.new()
	_zona.color = Color(0.35, 0.75, 0.45)
	area.add_child(_zona)

	_marca = ColorRect.new()
	_marca.color = Color(0.98, 0.94, 0.75)
	_marca.size = Vector2(6, 62)
	area.add_child(_marca)

	_marcador = Label.new()
	_marcador.position = Vector2(60, 90)
	_marcador.add_theme_font_size_override("font_size", 20)
	area.add_child(_marcador)
	_posicion = _barra.position.x
	_actualizar_zona()
	_actualizar_marcador()

func _empezar() -> void:
	_siguiente_tiro()

func _siguiente_tiro() -> void:
	if _tiro >= TIROS:
		_cerrar_sesion()
		return
	_tiro += 1
	_velocidad = 300.0 * pow(1.0 + CRECIMIENTO_VELOCIDAD, float(_tiro - 1))
	_tolerancia = CENTRO_TOLERANCIA * pow(1.0 - REDUCCION_VENTANA, float(_tiro - 1))
	_actualizar_zona()
	_activo = true
	fijar_estado("Tiro %d de %d" % [_tiro, TIROS])

func _actualizar_zona() -> void:
	var centro: float = _barra.position.x + ANCHO_BARRA * 0.5
	_zona.size = Vector2(_tolerancia * 2.0, 46)
	_zona.position = Vector2(centro - _tolerancia, _barra.position.y)

func _process(delta: float) -> void:
	super(delta)
	if not esta_jugando() or not _activo:
		return
	_posicion += _direccion * _velocidad * delta
	if _posicion > _barra.position.x + ANCHO_BARRA:
		_posicion = _barra.position.x + ANCHO_BARRA
		_direccion = -1.0
	elif _posicion < _barra.position.x:
		_posicion = _barra.position.x
		_direccion = 1.0
	_marca.position = Vector2(_posicion - 3.0, _barra.position.y - 8.0)

func _unhandled_input(evento: InputEvent) -> void:
	if not esta_jugando() or not _activo:
		return
	if evento.is_action_pressed("jump") or (evento is InputEventKey and evento.pressed
			and not evento.echo and evento.keycode == KEY_SPACE):
		get_viewport().set_input_as_handled()
		_resolver()

func _resolver() -> void:
	_activo = false
	var centro: float = _barra.position.x + ANCHO_BARRA * 0.5
	var error: float = absf(_posicion - centro)
	var dentro: bool = error <= _tolerancia
	if dentro:
		_aciertos += 1
	_actualizar_marcador("¡Dentro!" if dentro else "Fuera por %d px" % int(error - _tolerancia))
	await get_tree().create_timer(0.4).timeout
	if esta_jugando():
		_siguiente_tiro()

func _actualizar_marcador(ultimo: String = "") -> void:
	_marcador.text = "%d de %d  ·  %d aciertos     %s" % [_tiro, TIROS, _aciertos, ultimo]

## Free-throw accuracy becomes scoring: a shooter who cannot miss from the line
## is the one who scores at will, and the curve is deliberately convex so the
## last few percent - the hard ones, with the window at its narrowest - are
## what separate a district scorer from a national one.
func _puntos_por_juego(porcentaje: float) -> float:
	return 4.0 + 26.0 * pow(clampf(porcentaje, 0.0, 1.0), 1.4)

func _cerrar_sesion() -> void:
	var porcentaje: float = float(_aciertos) / float(maxi(_tiro, 1))
	var puntos: float = _puntos_por_juego(porcentaje)
	var resumen: Array[String] = [
		"[b]%d de %d[/b] desde la línea (%.0f%%)." % [_aciertos, _tiro, porcentaje * 100.0],
		"Eso te pone en [b]%.1f puntos por juego[/b]." % puntos,
	]
	terminar_sesion({
		"estadisticas": {&"baloncesto_puntos_por_juego": puntos},
		"resumen": resumen,
	})

# --- For the verification harness --------------------------------------------

## Distance from the middle of the bar right now, and the window that would
## count as a make - the same two numbers the player is reading off the screen.
func error_actual() -> float:
	return absf(_posicion - (_barra.position.x + ANCHO_BARRA * 0.5))

func tolerancia_actual() -> float:
	return _tolerancia

func tiro_actual() -> int:
	return _tiro
