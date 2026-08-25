extends Control

## The consulting firm's counter: pick a tier, pay, read an approximation.
##
## Generated from ConsultingRegistry, so a fourth tier appears by existing.
## Nothing here formats a raw attribute or a raw probability - every number on
## screen comes from ConsultingService already carrying its margin of error,
## which is the whole point of the screen.

const CARRERA_POR_DEFECTO := &"economia"

var _informe: RichTextLabel
var _saldo: Label
var _tarjetas: Dictionary = {}   # tier_id -> Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Anchors AND offsets: this Control hangs off a CanvasLayer, not off
	# another Control, and setting only the anchors left it at the size of its
	# contents - a 700px panel with the world showing around it.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	get_viewport().size_changed.connect(func(): size = get_viewport_rect().size)
	_construir()
	_refrescar_saldo()
	Wallet.balance_cambiado.connect(func(_p, _f): _refrescar_saldo())

func _construir() -> void:
	var fondo := ColorRect.new()
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.color = Color(0.06, 0.07, 0.10, 0.97)
	add_child(fondo)

	var margen := MarginContainer.new()
	margen.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right", "top", "bottom"]:
		margen.add_theme_constant_override("margin_" + lado, 28)
	add_child(margen)

	var columnas := HBoxContainer.new()
	columnas.add_theme_constant_override("separation", 20)
	margen.add_child(columnas)

	var izquierda := VBoxContainer.new()
	izquierda.custom_minimum_size = Vector2(430, 0)
	izquierda.add_theme_constant_override("separation", 12)
	columnas.add_child(izquierda)

	var titulo := Label.new()
	titulo.text = "Asesoría de admisiones"
	titulo.add_theme_font_size_override("font_size", 26)
	izquierda.add_child(titulo)

	var aviso := Label.new()
	aviso.text = "Nadie puede decirte tus números exactos. Lo que compras aquí es cuánto se equivocan."
	aviso.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	aviso.add_theme_color_override("font_color", Color(0.72, 0.76, 0.85))
	izquierda.add_child(aviso)

	_saldo = Label.new()
	izquierda.add_child(_saldo)

	for tier_res in ConsultingRegistry.obtener_por_nivel():
		izquierda.add_child(_tarjeta(tier_res as ConsultingTier))

	var cerrar := Button.new()
	cerrar.text = "Salir (E o Esc)"
	cerrar.pressed.connect(_cerrar)
	izquierda.add_child(cerrar)

	var derecha := VBoxContainer.new()
	derecha.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columnas.add_child(derecha)
	_informe = RichTextLabel.new()
	_informe.bbcode_enabled = true
	_informe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var caja := StyleBoxFlat.new()
	caja.bg_color = Color(0.11, 0.12, 0.15)
	caja.set_content_margin_all(14)
	caja.set_corner_radius_all(4)
	_informe.add_theme_stylebox_override("normal", caja)
	_informe.text = "[i]Elige una asesoría para ver un informe.[/i]"
	derecha.add_child(_informe)

func _tarjeta(tier: ConsultingTier) -> Control:
	var panel := PanelContainer.new()
	var caja := StyleBoxFlat.new()
	caja.bg_color = Color(0.11, 0.13, 0.17)
	caja.set_content_margin_all(12)
	caja.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", caja)

	var columna := VBoxContainer.new()
	panel.add_child(columna)

	var nombre := Label.new()
	nombre.text = "%s   ·   %s" % [tier.nombre_display,
		"gratis" if tier.costo <= 0.0 else "%d" % int(tier.costo)]
	nombre.add_theme_font_size_override("font_size", 19)
	columna.add_child(nombre)

	var descripcion := Label.new()
	descripcion.text = tier.descripcion
	descripcion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	descripcion.add_theme_color_override("font_color", Color(0.75, 0.79, 0.86))
	columna.add_child(descripcion)

	var detalle := Label.new()
	detalle.text = "Margen de error ±%d%%   ·   revela: %s" % [
		int(round(tier.margen_error * 100.0)), _texto_cobertura(tier)]
	detalle.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	columna.add_child(detalle)

	var boton := Button.new()
	boton.text = "Consultar"
	boton.pressed.connect(_consultar.bind(tier.id))
	columna.add_child(boton)
	_tarjetas[tier.id] = boton
	return panel

func _texto_cobertura(tier: ConsultingTier) -> String:
	if tier.cubre(&"desglose"):
		return "índice, atributos y probabilidades por universidad"
	if tier.cubre(&"atributos"):
		return "índice y atributos"
	return "solo el índice académico"

func _refrescar_saldo() -> void:
	_saldo.text = "Tu dinero: %d propio   ·   %d de familia" % [
		int(Wallet.dinero_personal()), int(Wallet.dinero_familia())]

func _consultar(tier_id: StringName) -> void:
	var informe: Dictionary = ConsultingService.consultar(tier_id, CARRERA_POR_DEFECTO)
	if not informe["exito"]:
		_informe.text = "[color=#ff9090]%s[/color]" % informe["mensaje"]
		return
	_informe.text = _formatear(informe)

func _formatear(informe: Dictionary) -> String:
	var t := PackedStringArray()
	t.append("[b]%s[/b]   (margen de error ±%d%%)" % [
		informe["nombre"], int(round(float(informe["margen_error"]) * 100.0))])
	if informe.get("ya_pagado_hoy", false):
		t.append("[i]Ya pagaste esta asesoría hoy: el informe es el mismo.[/i]")
	t.append("")
	t.append("[b]Índice académico[/b]: %s" % informe["indice_texto"])

	if informe.has("atributos"):
		t.append("")
		t.append("[b]Cómo te ven[/b]")
		for atributo_id in informe["atributos"]:
			var fila: Dictionary = informe["atributos"][atributo_id]
			t.append("  %-28s %s  (~%d)" % [fila["nombre"], fila["banda"], int(fila["estimado"])])

	if informe.has("universidades"):
		t.append("")
		t.append("[b]Tus posibilidades[/b]  (el orden es fiable; los números, aproximados)")
		for fila in informe["universidades"]:
			t.append("  %-24s %-14s %s" % [fila["nombre"], fila["texto"], fila["rango"]])

	t.append("")
	t.append("[i]Ninguna cifra de este informe es exacta. Nadie puede darte la exacta.[/i]")
	return "\n".join(t)

func _cerrar() -> void:
	if is_instance_valid(ConsultingOffice._abierta):
		ConsultingOffice.cerrar()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_cerrar()
