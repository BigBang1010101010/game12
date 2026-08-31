extends Control

## The gift shop counter.
##
## Generated from the two registries it needs - ParentRegistry for who you can
## buy for, GiftRegistry for what is on the shelf - so a third family member or
## a fourth tier appears here by existing.
##
## It applies no rules of its own: FamilyRelationship.comprar_regalo() checks
## the shop, charges the wallet against the &"regalos" category and moves the
## relationship. This screen only shows what that call answered.

const COLOR_OK := Color(0.55, 0.85, 0.6)
const COLOR_TENUE := Color(0.62, 0.65, 0.72)
const COLOR_MAL := Color(1.0, 0.55, 0.55)

var _padre_actual: StringName = &""
var _saldo: Label
var _mensaje: RichTextLabel
var _lista: VBoxContainer
var _botones_padre: Dictionary = {}   # padre_id -> Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	get_viewport().size_changed.connect(func(): size = get_viewport_rect().size)
	var padres: Array[Resource] = ParentRegistry.obtener_todos()
	if not padres.is_empty():
		_padre_actual = (padres[0] as ParentData).id
	_construir()
	_refrescar()

func _construir() -> void:
	var fondo := ColorRect.new()
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.color = Color(0.07, 0.06, 0.09, 0.97)
	add_child(fondo)

	var margen := MarginContainer.new()
	margen.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right", "top", "bottom"]:
		margen.add_theme_constant_override("margin_" + lado, 30)
	add_child(margen)

	var centro := CenterContainer.new()
	margen.add_child(centro)

	var columna := VBoxContainer.new()
	columna.custom_minimum_size = Vector2(720, 0)
	columna.add_theme_constant_override("separation", 12)
	centro.add_child(columna)

	var titulo := Label.new()
	titulo.text = "Tienda de regalos"
	titulo.add_theme_font_size_override("font_size", 26)
	columna.add_child(titulo)

	_saldo = Label.new()
	columna.add_child(_saldo)

	var eleccion := HBoxContainer.new()
	eleccion.add_theme_constant_override("separation", 10)
	columna.add_child(eleccion)
	var para := Label.new()
	para.text = "¿Para quién?"
	para.add_theme_color_override("font_color", COLOR_TENUE)
	eleccion.add_child(para)
	for padre_res in ParentRegistry.obtener_todos():
		var padre: ParentData = padre_res
		var boton := Button.new()
		boton.toggle_mode = true
		boton.pressed.connect(func():
			_padre_actual = padre.id
			_refrescar())
		eleccion.add_child(boton)
		_botones_padre[padre.id] = boton

	_lista = VBoxContainer.new()
	_lista.add_theme_constant_override("separation", 8)
	columna.add_child(_lista)

	_mensaje = RichTextLabel.new()
	_mensaje.bbcode_enabled = true
	_mensaje.fit_content = true
	_mensaje.custom_minimum_size = Vector2(0, 54)
	columna.add_child(_mensaje)

	var cerrar := Button.new()
	cerrar.text = "Salir (E o Esc)"
	cerrar.pressed.connect(func(): GiftShopScreen.cerrar())
	columna.add_child(cerrar)

func _refrescar() -> void:
	_saldo.text = "Tu dinero: %d propio   ·   %d de familia (no sirve para regalos)" % [
		int(Wallet.dinero_personal()), int(Wallet.dinero_familia())]

	for padre_res in ParentRegistry.obtener_todos():
		var padre: ParentData = padre_res
		var boton: Button = _botones_padre[padre.id]
		boton.button_pressed = padre.id == _padre_actual
		var dias: int = FamilyRelationship.dias_para_cumpleanos(padre.id)
		var cumple: String = "  ¡HOY CUMPLE!" if dias == 0 else "  (cumple en %d días)" % dias
		# The relationship shows as a band, not a number: the player knows how
		# things are with their mother, they do not know a score.
		boton.text = "%s — %s%s" % [padre.nombre_display,
			InfoPolicy.describir_atributo(FamilyRelationship.obtener_nivel_relacion(padre.id)), cumple]

	for hijo in _lista.get_children():
		hijo.queue_free()
	for regalo_res in GiftRegistry.obtener_por_nivel():
		_lista.add_child(_fila(regalo_res as GiftData))

func _fila(regalo: GiftData) -> Control:
	var panel := PanelContainer.new()
	var caja := StyleBoxFlat.new()
	caja.bg_color = Color(0.12, 0.11, 0.15)
	caja.set_content_margin_all(12)
	caja.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", caja)

	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 12)
	panel.add_child(fila)

	var texto := VBoxContainer.new()
	texto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(texto)

	var nombre := Label.new()
	nombre.text = regalo.nombre_display
	nombre.add_theme_font_size_override("font_size", 18)
	texto.add_child(nombre)

	var descripcion := Label.new()
	descripcion.text = regalo.descripcion
	descripcion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	descripcion.custom_minimum_size = Vector2(430, 0)
	descripcion.add_theme_color_override("font_color", COLOR_TENUE)
	texto.add_child(descripcion)

	var es_cumple: bool = FamilyRelationship.es_su_cumpleanos(_padre_actual)
	var puntos: float = regalo.puntos_relacion
	var extra := ""
	if es_cumple:
		puntos *= FamilyRelationship.obtener_config().regalo_multiplicador_cumpleanos
		extra = "  (x%.1f por su cumpleaños)" % FamilyRelationship.obtener_config().regalo_multiplicador_cumpleanos
	var efecto := Label.new()
	efecto.text = "Cuesta %d   ·   sube la relación +%.0f%s" % [int(regalo.costo), puntos, extra]
	efecto.add_theme_color_override("font_color", COLOR_OK if es_cumple else Color(0.55, 0.75, 1.0))
	texto.add_child(efecto)

	fila.add_child(_boton(regalo))
	return panel

func _boton(regalo: GiftData) -> Button:
	var padre: ParentData = ParentRegistry.obtener(_padre_actual)
	var boton := Button.new()
	boton.custom_minimum_size = Vector2(200, 0)
	# Same pattern as the activities screen: when the action cannot happen,
	# the button says why instead of failing after the click.
	if regalo.costo > Wallet.dinero_personal():
		boton.text = "Te faltan %d" % int(regalo.costo - Wallet.dinero_personal())
		boton.disabled = true
		boton.tooltip_text = ("Los regalos salen de tu bolsillo: el dinero de la familia no " +
			"cubre esta categoría.")
		return boton
	boton.text = "Regalar a %s" % (padre.nombre_display if padre else "?")
	boton.pressed.connect(_comprar.bind(regalo.id))
	return boton

func _comprar(regalo_id: StringName) -> void:
	var padre: ParentData = ParentRegistry.obtener(_padre_actual)
	var antes: float = FamilyRelationship.obtener_nivel_relacion(_padre_actual)
	var resultado: Dictionary = FamilyRelationship.comprar_regalo(_padre_actual, regalo_id)
	if not resultado["exito"]:
		_mensaje.text = "[color=#ff8f8f]%s[/color]" % resultado["mensaje"]
		_refrescar()
		return
	var subio: float = FamilyRelationship.obtener_nivel_relacion(_padre_actual) - antes
	var celebracion: String = "  Justo hoy es su cumpleaños." if resultado["en_su_cumpleanos"] else ""
	_mensaje.text = ("[color=#88ddaa][b]%s recibió tu regalo.[/b][/color]  Te costó %d y la relación " +
		"subió %+.1f.%s") % [padre.nombre_display, int(resultado["costo"]), subio, celebracion]
	_refrescar()

func _unhandled_input(evento: InputEvent) -> void:
	if evento.is_action_pressed("interact") or evento.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		GiftShopScreen.cerrar()
