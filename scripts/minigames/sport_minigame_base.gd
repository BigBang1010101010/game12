extends Control
class_name SportMinigame

## Base class for every sports minigame.
##
## It owns everything that is the same in all of them - the full-screen panel,
## the countdown, the play area, the result screen and, above all, the way a
## session turns into real statistics - so a new sport is a subclass that
## implements three methods and knows nothing about the progression systems.
##
## THE CONTRACT WITH THE REST OF THE GAME lives in finalizar(): a subclass
## hands over what it measured, in the sport's own categories, and this class
## posts it through SportStatsTracker. That is the only door, so no minigame
## can invent recognition for itself - it can only report numbers, and the
## benchmarks decide what they are worth.
##
## Subclasses implement:
##   _preparar(area)  build the play area (a Control the base sizes and clears)
##   _empezar()       start playing; the countdown has just finished
##   _terminar()      optional cleanup before the result screen
## and call terminar_sesion(resultado) when the session is over, with
##   {"estadisticas": {categoria_id: valor}, "resumen": [String, ...]}

signal sesion_terminada(resultado: Dictionary)

const SEGUNDOS_CUENTA := 3

var deporte_id: StringName = &""
var _fase: String = "cuenta"          # cuenta -> jugando -> resultado
var _restante: float = 0.0

var _titulo: Label
var _instrucciones: Label
var _estado: Label
var _area: Control
var _resultado: RichTextLabel
var _salir: Button

## Opens a minigame full screen, paused over the world. Static so a world node
## only needs the script and the sport id.
static func lanzar(guion: Script, id_deporte: StringName) -> SportMinigame:
	var capa := CanvasLayer.new()
	capa.layer = 46
	capa.process_mode = Node.PROCESS_MODE_ALWAYS
	# guion.new() builds the node already wearing the script: creating a plain
	# Control and setting the script afterwards leaves the typed assignment
	# looking at a bare Control and fails.
	var juego: SportMinigame = (guion as GDScript).new()
	capa.add_child(juego)
	(Engine.get_main_loop() as SceneTree).root.add_child(capa)
	juego.iniciar(id_deporte)
	return juego

# --- Life cycle --------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	_construir()

## Entry point: sets the sport and starts the countdown.
func iniciar(id_deporte: StringName) -> void:
	deporte_id = id_deporte
	var actividad: ActivityData = ActivityRegistry.obtener(deporte_id)
	_titulo.text = "%s — %s" % [actividad.nombre_display if actividad else String(deporte_id), _nombre_juego()]
	_instrucciones.text = _texto_instrucciones()
	_preparar(_area)
	_fase = "cuenta"
	_restante = float(SEGUNDOS_CUENTA)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	HUD.ocultar()
	InteractionUI.hide_prompt()

func _process(delta: float) -> void:
	if _fase != "cuenta":
		return
	_restante -= delta
	if _restante > 0.0:
		_estado.text = "Empieza en %d…" % int(ceil(_restante))
		return
	_estado.text = "¡YA!"
	_fase = "jugando"
	_empezar()

## Ends the session: posts every statistic it produced and shows what those
## numbers turned out to be worth.
func terminar_sesion(resultado: Dictionary) -> void:
	if _fase == "resultado":
		return
	_fase = "resultado"
	_terminar()
	_estado.text = "Sesión terminada"
	_resultado.text = _formatear_resultado(resultado)
	_resultado.visible = true
	_salir.visible = true
	sesion_terminada.emit(resultado)

## Posts the statistics and describes what happened to them.
func _formatear_resultado(resultado: Dictionary) -> String:
	var t := PackedStringArray()
	for linea in resultado.get("resumen", []):
		t.append(String(linea))
	t.append("")
	t.append("[b]Lo que queda en tu ficha[/b]")

	var antes_deporte: StringName = SportStatsTracker.reconocimiento_derivado(deporte_id)
	var estadisticas: Dictionary = resultado.get("estadisticas", {})
	for categoria_id in estadisticas:
		var categoria: SportStatCategory = SportStatRegistry.obtener(categoria_id)
		var registro: Dictionary = SportStatsTracker.registrar_resultado_minijuego(
			deporte_id, categoria_id, float(estadisticas[categoria_id]))
		if not registro.get("exito", false):
			t.append("  [color=#ff8f8f]%s: no se pudo registrar[/color]" % categoria_id)
			continue
		var valor_ficha: float = SportStatsTracker.obtener_valor(deporte_id, categoria_id)
		var linea := "  %s: %s" % [categoria.nombre_display, categoria.formatear(valor_ficha)]
		if categoria.acumulativa:
			linea += "  [color=#9aa0aa](sumaste %s esta sesión)[/color]" % categoria.formatear(
				float(estadisticas[categoria_id]))
		elif not registro["mejoro"]:
			linea += "  [color=#9aa0aa](tu mejor marca sigue siendo mejor)[/color]"
		else:
			linea += "  [color=#88ddaa](nueva mejor marca)[/color]"
		var reconocimiento: StringName = SportStatsTracker.reconocimiento_de_categoria(deporte_id, categoria_id)
		if reconocimiento != &"ninguno":
			linea += "  → %s" % reconocimiento
		t.append(linea)

	var despues: StringName = SportStatsTracker.reconocimiento_derivado(deporte_id)
	t.append("")
	if despues != antes_deporte:
		t.append("[color=#88ddaa][b]Tu reconocimiento subió a '%s'.[/b][/color]" % despues)
	else:
		t.append("Reconocimiento en este deporte: [b]%s[/b]" % despues)
		var siguiente: String = _que_falta()
		if not siguiente.is_empty():
			t.append("[color=#ffcc80]%s[/color]" % siguiente)
	return "\n".join(t)

## The nearest threshold the player has not reached yet, so the result screen
## says what to chase instead of just what happened.
func _que_falta() -> String:
	for fila in SportStatsTracker.desglose(deporte_id):
		var siguiente: Dictionary = fila["siguiente"]
		if siguiente.is_empty():
			continue
		var categoria: SportStatCategory = SportStatRegistry.obtener(fila["categoria"])
		return "Con %s en %s llegarías a '%s'." % [
			categoria.formatear(float(siguiente["valor"])), categoria.nombre_display,
			siguiente["reconocimiento"]]
	return ""

func cerrar() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	HUD.mostrar()
	var capa := get_parent()
	if capa is CanvasLayer:
		capa.queue_free()
	else:
		queue_free()

# --- Shared shell ------------------------------------------------------------

func _construir() -> void:
	var fondo := ColorRect.new()
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.color = Color(0.05, 0.06, 0.09, 0.98)
	add_child(fondo)

	var margen := MarginContainer.new()
	margen.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right", "top", "bottom"]:
		margen.add_theme_constant_override("margin_" + lado, 26)
	add_child(margen)

	var columna := VBoxContainer.new()
	columna.add_theme_constant_override("separation", 10)
	margen.add_child(columna)

	_titulo = Label.new()
	_titulo.add_theme_font_size_override("font_size", 26)
	columna.add_child(_titulo)

	_instrucciones = Label.new()
	_instrucciones.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_instrucciones.add_theme_color_override("font_color", Color(0.72, 0.76, 0.85))
	columna.add_child(_instrucciones)

	_estado = Label.new()
	_estado.add_theme_font_size_override("font_size", 22)
	_estado.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	columna.add_child(_estado)

	# The play area keeps a fixed height instead of expanding: a minigame draws
	# in pixel coordinates, so letting the box grow leaves the action stranded
	# in a band at the top of a mostly empty rectangle.
	_area = Control.new()
	_area.custom_minimum_size = Vector2(0, 330)
	_area.size_flags_vertical = Control.SIZE_FILL
	_area.clip_contents = true
	columna.add_child(_area)

	_resultado = RichTextLabel.new()
	_resultado.bbcode_enabled = true
	_resultado.fit_content = true
	_resultado.custom_minimum_size = Vector2(0, 220)
	_resultado.visible = false
	var caja := StyleBoxFlat.new()
	caja.bg_color = Color(0.11, 0.12, 0.15)
	caja.set_content_margin_all(14)
	caja.set_corner_radius_all(4)
	_resultado.add_theme_stylebox_override("normal", caja)
	columna.add_child(_resultado)

	_salir = Button.new()
	_salir.text = "Salir"
	_salir.visible = false
	_salir.pressed.connect(cerrar)
	columna.add_child(_salir)

	# Everything above keeps its natural height; the slack goes at the bottom so
	# the result panel appears right under the play area instead of at the foot
	# of the screen.
	var relleno := Control.new()
	relleno.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columna.add_child(relleno)

func fijar_estado(texto: String) -> void:
	_estado.text = texto

func esta_jugando() -> bool:
	return _fase == "jugando"

# --- To implement in a subclass ----------------------------------------------

func _nombre_juego() -> String:
	return "minijuego"

func _texto_instrucciones() -> String:
	return ""

func _preparar(_area_de_juego: Control) -> void:
	pass

func _empezar() -> void:
	pass

func _terminar() -> void:
	pass
