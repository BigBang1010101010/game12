extends Control

## Birthplace selection, shown once at the start of a run.
##
## The whole screen is generated from LocationRegistry: the cards, their
## order, the numbers on them and the text under them all come from the
## LocationData files. A fourth city appears here by existing.

## Scene loaded once a birthplace is chosen.
@export_file("*.tscn") var escena_juego: String = "res://scenes/main.tscn"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_construir()

func _construir() -> void:
	var fondo := ColorRect.new()
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.color = Color(0.06, 0.07, 0.10)
	add_child(fondo)

	var margen := MarginContainer.new()
	margen.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right", "top", "bottom"]:
		margen.add_theme_constant_override("margin_" + lado, 40)
	add_child(margen)

	var columna := VBoxContainer.new()
	columna.add_theme_constant_override("separation", 18)
	margen.add_child(columna)

	var titulo := Label.new()
	titulo.text = "¿Dónde naciste?"
	titulo.add_theme_font_size_override("font_size", 34)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	columna.add_child(titulo)

	var subtitulo := Label.new()
	subtitulo.text = "Esta elección fija el costo de tu vida, el dinero con el que empiezas y lo fácil que será que tu familia te preste. No se puede cambiar después."
	subtitulo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitulo.add_theme_color_override("font_color", Color(0.72, 0.76, 0.85))
	columna.add_child(subtitulo)

	var tarjetas := HBoxContainer.new()
	tarjetas.alignment = BoxContainer.ALIGNMENT_CENTER
	tarjetas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tarjetas.add_theme_constant_override("separation", 18)
	columna.add_child(tarjetas)

	# Cheapest first, i.e. easiest first, straight from the data.
	for ubicacion_res in LocationRegistry.obtener_por_dificultad():
		tarjetas.add_child(_tarjeta(ubicacion_res as LocationData))

	if LocationRegistry.contar() == 0:
		var vacio := Label.new()
		vacio.text = "No hay ninguna ubicación en data/locations/."
		vacio.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
		columna.add_child(vacio)

func _tarjeta(ubicacion: LocationData) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(330, 0)
	var caja := StyleBoxFlat.new()
	caja.bg_color = Color(0.11, 0.13, 0.17)
	caja.set_content_margin_all(16)
	caja.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", caja)

	var columna := VBoxContainer.new()
	columna.add_theme_constant_override("separation", 10)
	panel.add_child(columna)

	var nombre := Label.new()
	nombre.text = ubicacion.nombre_display
	nombre.add_theme_font_size_override("font_size", 24)
	columna.add_child(nombre)

	var descripcion := Label.new()
	descripcion.text = ubicacion.descripcion
	descripcion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	descripcion.add_theme_color_override("font_color", Color(0.75, 0.79, 0.86))
	columna.add_child(descripcion)

	var datos := VBoxContainer.new()
	columna.add_child(datos)
	for fila in [
		["Costo de vida", "%d  (Nueva York = 100)" % int(ubicacion.indice_costo_vida)],
		["Gasto semanal", "x%.2f" % ubicacion.gasto_semanal()],
		["Dinero inicial", "%d - %d" % [int(ubicacion.dinero_familia_base_min), int(ubicacion.dinero_familia_base_max)]],
		["Crédito familiar", "%d%% de disposición" % int(round(ubicacion.facilidad_credito_familiar * 100.0))],
	]:
		var linea := HBoxContainer.new()
		datos.add_child(linea)
		var etiqueta := Label.new()
		etiqueta.text = fila[0]
		etiqueta.custom_minimum_size = Vector2(140, 0)
		etiqueta.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
		linea.add_child(etiqueta)
		var valor := Label.new()
		valor.text = fila[1]
		linea.add_child(valor)

	var dificultad := Label.new()
	dificultad.text = ubicacion.descripcion_dificultad
	dificultad.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dificultad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columna.add_child(dificultad)

	var boton := Button.new()
	boton.text = "Nacer en %s" % ubicacion.nombre_display
	boton.pressed.connect(_elegir.bind(ubicacion.id))
	columna.add_child(boton)
	return panel

func _elegir(ubicacion_id: StringName) -> void:
	if not PlayerOrigin.fijar_ubicacion(ubicacion_id):
		return
	get_tree().change_scene_to_file(escena_juego)
