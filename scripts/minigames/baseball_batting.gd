extends SportMinigame

## Batting practice: ten pitches, one key, and a window that punishes being
## early as much as being late.
##
## Nothing here is rolled: the pitch varies (speed and height), but the OUTCOME
## is a pure function of how far the swing was from the moment the ball crossed
## the plate. A player who reads the pitch hits; one who mashes the key does
## not, and the batting average that reaches the ficha is literally hits over
## at-bats.

const LANZAMIENTOS := 10
const PLATO_X := 140.0          ## where the ball must be when the key is pressed
const ALTO_AREA := 300.0

## Swing tolerance, in pixels of ball travel. Tight on purpose: at 420 px/s a
## perfect window is about 55 ms, which is a real timing task and not a tap.
const VENTANA_PERFECTA := 12.0
const VENTANA_HIT := 30.0
const VENTANA_CONTACTO := 58.0

var _bola: ColorRect
var _plato: ColorRect
var _marcador: Label
var _lanzamiento := 0
var _hits := 0
var _jonrones := 0
var _turnos := 0
var _bola_activa := false
var _velocidad := 0.0
var _tolerancia := 1.0
var _rng := RandomNumberGenerator.new()

func _nombre_juego() -> String:
	return "práctica de bateo"

func _texto_instrucciones() -> String:
	return ("Diez lanzamientos. Pulsa ESPACIO justo cuando la bola cruce el plato (la línea " +
		"blanca). Los lanzamientos altos y bajos son más difíciles: la ventana se estrecha.")

func _preparar(area: Control) -> void:
	_rng.randomize()
	var fondo := ColorRect.new()
	fondo.color = Color(0.10, 0.16, 0.11)
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	area.add_child(fondo)

	_plato = ColorRect.new()
	_plato.color = Color(0.95, 0.95, 0.95)
	_plato.size = Vector2(3, ALTO_AREA)
	_plato.position = Vector2(PLATO_X, 0)
	area.add_child(_plato)

	_bola = ColorRect.new()
	_bola.color = Color(0.98, 0.94, 0.75)
	_bola.size = Vector2(20, 20)
	_bola.visible = false
	area.add_child(_bola)

	_marcador = Label.new()
	_marcador.position = Vector2(PLATO_X + 40, 10)
	_marcador.add_theme_font_size_override("font_size", 20)
	area.add_child(_marcador)
	_actualizar_marcador()

func _empezar() -> void:
	_siguiente_lanzamiento()

func _siguiente_lanzamiento() -> void:
	if _lanzamiento >= LANZAMIENTOS:
		_cerrar_sesion()
		return
	_lanzamiento += 1
	# Speed and height vary per pitch; height is not decoration - a pitch away
	# from the middle tightens the window.
	_velocidad = _rng.randf_range(330.0, 520.0)
	var altura: float = _rng.randf_range(40.0, ALTO_AREA - 60.0)
	var centro: float = ALTO_AREA * 0.5
	_tolerancia = lerpf(1.0, 0.72, clampf(absf(altura - centro) / centro, 0.0, 1.0))
	_bola.position = Vector2(_area.size.x - 40.0, altura)
	_bola.visible = true
	_bola_activa = true
	fijar_estado("Lanzamiento %d de %d" % [_lanzamiento, LANZAMIENTOS])

func _process(delta: float) -> void:
	super(delta)
	if not esta_jugando() or not _bola_activa:
		return
	_bola.position.x -= _velocidad * delta
	if _bola.position.x < PLATO_X - VENTANA_CONTACTO * _tolerancia - 20.0:
		# Let it go by: a called strike is still an at-bat.
		_resolver(9999.0)

func _unhandled_input(evento: InputEvent) -> void:
	if not esta_jugando() or not _bola_activa:
		return
	if evento.is_action_pressed("jump") or (evento is InputEventKey and evento.pressed
			and not evento.echo and evento.keycode == KEY_SPACE):
		get_viewport().set_input_as_handled()
		_resolver(absf(_bola.position.x - PLATO_X))

## Distance from the plate at the moment of the swing decides everything.
func _resolver(distancia: float) -> void:
	_bola_activa = false
	_bola.visible = false
	_turnos += 1
	var texto := ""
	if distancia <= VENTANA_PERFECTA * _tolerancia:
		_hits += 1
		_jonrones += 1
		texto = "¡JONRÓN!"
	elif distancia <= VENTANA_HIT * _tolerancia:
		_hits += 1
		texto = "¡Hit!"
	elif distancia <= VENTANA_CONTACTO * _tolerancia:
		texto = "Contacto, out."
	elif distancia > 1000.0:
		texto = "Strike cantado."
	else:
		texto = "Fallaste."
	_actualizar_marcador(texto)
	await get_tree().create_timer(0.45).timeout
	if esta_jugando():
		_siguiente_lanzamiento()

func _actualizar_marcador(ultimo: String = "") -> void:
	_marcador.text = "%d de %d  ·  %d hits  ·  %d jonrones     %s" % [
		_turnos, LANZAMIENTOS, _hits, _jonrones, ultimo]

func _cerrar_sesion() -> void:
	var promedio: float = float(_hits) / float(maxi(_turnos, 1))
	var resumen: Array[String] = [
		"[b]%d de %d[/b] con %d %s." % [_hits, _turnos, _jonrones,
			"jonrón" if _jonrones == 1 else "jonrones"],
		"Promedio de la sesión: [b]%s[/b]" % ("%.3f" % promedio).trim_prefix("0"),
	]
	var estadisticas: Dictionary = {&"beisbol_promedio_bateo": promedio}
	# Home runs only go on the record when there were any: posting a zero would
	# be a session, not a season, and the category adds up.
	if _jonrones > 0:
		estadisticas[&"beisbol_jonrones"] = float(_jonrones)
	terminar_sesion({"estadisticas": estadisticas, "resumen": resumen})

# --- For the verification harness --------------------------------------------

## Where the ball is relative to the plate, so an automated run can swing on
## the same information a player sees.
func distancia_al_plato() -> float:
	return _bola.position.x - PLATO_X if _bola_activa else INF

func lanzamiento_actual() -> int:
	return _lanzamiento
