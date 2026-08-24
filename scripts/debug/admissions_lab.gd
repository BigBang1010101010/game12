extends Control

## Internal calibration tool (F1). Everything in it is generated from the
## registries: the sliders come from AttributeRegistry, the dropdowns from
## CareerRegistry and EssayRegistry, the table rows from UniversityRegistry.
## Adding content makes it appear here with no change to this file.

## Preset archetypes, expressed as attribute -> value. Only the attributes a
## preset cares about are listed; the rest fall back to VALOR_NEUTRO, so a
## preset keeps working when new attributes are added.
const VALOR_NEUTRO := 50.0
const PRESETS := {
	"Perfil equilibrado": {
		&"rigor_academico": 72, &"aptitud_cuantitativa": 68, &"aptitud_verbal": 70,
		&"aptitud_cientifica": 65, &"aptitud_investigacion": 60, &"liderazgo": 65,
		&"impacto_comunitario": 62, &"curiosidad_intelectual": 68, &"resiliencia": 65,
		&"logro_atletico": 45, &"profundidad_extracurricular": 62, &"habilidad_artistica": 45,
		&"red_social": 60, &"bienestar": 65, &"gestion_tiempo": 62,
	},
	"Genio academico sin vida social": {
		&"rigor_academico": 97, &"aptitud_cuantitativa": 96, &"aptitud_verbal": 88,
		&"aptitud_cientifica": 94, &"aptitud_investigacion": 92, &"liderazgo": 18,
		&"impacto_comunitario": 12, &"curiosidad_intelectual": 90, &"resiliencia": 55,
		&"logro_atletico": 8, &"profundidad_extracurricular": 35, &"habilidad_artistica": 15,
		&"red_social": 12, &"bienestar": 38, &"gestion_tiempo": 55,
	},
	"Lider carismatico, promedio academico": {
		&"rigor_academico": 62, &"aptitud_cuantitativa": 55, &"aptitud_verbal": 72,
		&"aptitud_cientifica": 48, &"aptitud_investigacion": 35, &"liderazgo": 94,
		&"impacto_comunitario": 88, &"curiosidad_intelectual": 55, &"resiliencia": 72,
		&"logro_atletico": 45, &"profundidad_extracurricular": 78, &"habilidad_artistica": 40,
		&"red_social": 92, &"bienestar": 70, &"gestion_tiempo": 75,
	},
	"Atleta estrella": {
		&"rigor_academico": 58, &"aptitud_cuantitativa": 50, &"aptitud_verbal": 52,
		&"aptitud_cientifica": 45, &"aptitud_investigacion": 25, &"liderazgo": 68,
		&"impacto_comunitario": 45, &"curiosidad_intelectual": 38, &"resiliencia": 92,
		&"logro_atletico": 96, &"profundidad_extracurricular": 90, &"habilidad_artistica": 20,
		&"red_social": 72, &"bienestar": 80, &"gestion_tiempo": 70,
	},
}

var _sliders: Dictionary = {}          # atributo_id -> HSlider
var _etiquetas_valor: Dictionary = {}  # atributo_id -> Label
var _filas: Dictionary = {}            # universidad_id -> Button
var _carrera: OptionButton
var _ensayo: OptionButton
var _early: CheckBox
var _desglose: RichTextLabel
var _seleccionada: StringName = &""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_construir()
	if not UniversityRegistry.obtener_ids().is_empty():
		_seleccionada = UniversityRegistry.obtener_ids()[0]
	_aplicar_preset(PRESETS.keys()[0])

func _construir() -> void:
	var fondo := ColorRect.new()
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.color = Color(0.07, 0.08, 0.10, 0.97)
	add_child(fondo)

	var margen := MarginContainer.new()
	margen.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right", "top", "bottom"]:
		margen.add_theme_constant_override("margin_" + lado, 14)
	add_child(margen)

	var columnas := HBoxContainer.new()
	columnas.add_theme_constant_override("separation", 14)
	margen.add_child(columnas)

	# --- Left: one slider per attribute, generated from the registry --------
	var izquierda := VBoxContainer.new()
	izquierda.custom_minimum_size = Vector2(330, 0)
	columnas.add_child(izquierda)

	var titulo := Label.new()
	titulo.text = "Laboratorio de Admisiones  (F1 para cerrar)"
	titulo.add_theme_font_size_override("font_size", 20)
	izquierda.add_child(titulo)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	izquierda.add_child(scroll)
	var lista := VBoxContainer.new()
	lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(lista)

	for categoria in AttributeRegistry.get_all_categories():
		var cabecera := Label.new()
		cabecera.text = String(categoria).to_upper()
		cabecera.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
		lista.add_child(cabecera)
		for definicion_res in AttributeRegistry.get_by_category(categoria):
			var definicion: AttributeDefinition = definicion_res
			var fila := HBoxContainer.new()
			lista.add_child(fila)
			var nombre := Label.new()
			nombre.text = definicion.nombre_display
			nombre.custom_minimum_size = Vector2(170, 0)
			nombre.tooltip_text = definicion.descripcion
			fila.add_child(nombre)
			var slider := HSlider.new()
			slider.min_value = 0.0
			slider.max_value = definicion.valor_maximo
			slider.step = 1.0
			slider.custom_minimum_size = Vector2(110, 0)
			slider.value_changed.connect(func(_v): _recalcular())
			fila.add_child(slider)
			var valor := Label.new()
			valor.custom_minimum_size = Vector2(38, 0)
			valor.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			fila.add_child(valor)
			_sliders[definicion.id] = slider
			_etiquetas_valor[definicion.id] = valor

	# --- Middle: choices, presets and the live table ------------------------
	var centro := VBoxContainer.new()
	centro.custom_minimum_size = Vector2(430, 0)
	columnas.add_child(centro)

	var presets := HFlowContainer.new()
	centro.add_child(presets)
	for nombre_preset in PRESETS:
		var boton := Button.new()
		boton.text = nombre_preset
		boton.pressed.connect(_aplicar_preset.bind(nombre_preset))
		presets.add_child(boton)

	var elecciones := HBoxContainer.new()
	centro.add_child(elecciones)
	elecciones.add_child(_hacer_etiqueta("Carrera:"))
	_carrera = OptionButton.new()
	for carrera_res in CareerRegistry.obtener_todos():
		_carrera.add_item((carrera_res as CareerData).nombre_display)
		_carrera.set_item_metadata(_carrera.item_count - 1, (carrera_res as CareerData).id)
	_carrera.item_selected.connect(func(_i): _recalcular())
	elecciones.add_child(_carrera)

	var elecciones2 := HBoxContainer.new()
	centro.add_child(elecciones2)
	elecciones2.add_child(_hacer_etiqueta("Ensayo:"))
	_ensayo = OptionButton.new()
	for ensayo_res in EssayRegistry.obtener_todos():
		var ensayo: EssayNarrative = ensayo_res
		_ensayo.add_item("%s  [%s]" % [ensayo.titulo, ensayo.narrativa_tipo])
		_ensayo.set_item_metadata(_ensayo.item_count - 1, ensayo.id)
	_ensayo.item_selected.connect(func(_i): _recalcular())
	elecciones2.add_child(_ensayo)

	_early = CheckBox.new()
	_early.text = "Early decision / action"
	_early.toggled.connect(func(_p): _recalcular())
	centro.add_child(_early)

	var cabecera_tabla := Label.new()
	cabecera_tabla.text = "Universidad            base     probabilidad"
	cabecera_tabla.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	centro.add_child(cabecera_tabla)

	for universidad_res in UniversityRegistry.obtener_todos():
		var universidad: UniversityData = universidad_res
		var boton := Button.new()
		boton.alignment = HORIZONTAL_ALIGNMENT_LEFT
		boton.pressed.connect(func():
			_seleccionada = universidad.id
			_recalcular())
		centro.add_child(boton)
		_filas[universidad.id] = boton

	# --- Right: full breakdown of the selected school -----------------------
	var derecha := VBoxContainer.new()
	derecha.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columnas.add_child(derecha)
	_desglose = RichTextLabel.new()
	_desglose.bbcode_enabled = true
	_desglose.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desglose.add_theme_stylebox_override("normal", _caja())
	derecha.add_child(_desglose)

func _hacer_etiqueta(texto: String) -> Label:
	var etiqueta := Label.new()
	etiqueta.text = texto
	etiqueta.custom_minimum_size = Vector2(70, 0)
	return etiqueta

func _caja() -> StyleBoxFlat:
	var caja := StyleBoxFlat.new()
	caja.bg_color = Color(0.11, 0.12, 0.15)
	caja.set_content_margin_all(10)
	caja.set_corner_radius_all(4)
	return caja

func _aplicar_preset(nombre: String) -> void:
	var preset: Dictionary = PRESETS[nombre]
	for atributo_id in _sliders:
		# Attributes a preset does not mention fall back to neutral, so adding
		# an attribute never invalidates the presets.
		(_sliders[atributo_id] as HSlider).value = float(preset.get(atributo_id, VALOR_NEUTRO))
	_recalcular()

func _valores_actuales() -> Dictionary:
	var valores: Dictionary = {}
	for atributo_id in _sliders:
		valores[atributo_id] = (_sliders[atributo_id] as HSlider).value
	return valores

func _recalcular() -> void:
	var valores: Dictionary = _valores_actuales()
	for atributo_id in _etiquetas_valor:
		(_etiquetas_valor[atributo_id] as Label).text = "%d" % int(valores[atributo_id])

	var carrera_id: StringName = _carrera.get_selected_metadata() if _carrera.selected >= 0 else &""
	var ensayo_id: StringName = _ensayo.get_selected_metadata() if _ensayo.selected >= 0 else &""
	var early: bool = _early.button_pressed

	var resultados: Array[AdmissionResult] = AdmissionCalculator.calcular_todas(carrera_id, ensayo_id, early, valores)
	for resultado in resultados:
		var boton: Button = _filas.get(resultado.universidad_id)
		if not boton:
			continue
		var universidad: UniversityData = UniversityRegistry.obtener(resultado.universidad_id)
		var marca: String = ">" if resultado.universidad_id == _seleccionada else " "
		boton.text = "%s %-22s %5.1f%%  ->  %5.1f%%" % [
			marca, universidad.nombre_display.substr(0, 22),
			resultado.tasa_base * 100.0, resultado.probabilidad * 100.0]
		boton.add_theme_color_override("font_color", universidad.color_primario.lightened(0.35))

	_mostrar_desglose(AdmissionCalculator.calcular_probabilidad(_seleccionada, carrera_id, ensayo_id, early, valores))

func _mostrar_desglose(r: AdmissionResult) -> void:
	var universidad: UniversityData = UniversityRegistry.obtener(r.universidad_id)
	if not universidad:
		return
	var t := PackedStringArray()
	t.append("[b]%s[/b]   (formula v%d)" % [universidad.nombre_display, r.version_formula])
	t.append("[i]%s[/i]" % universidad.descripcion_cultura)
	t.append("")
	t.append("[b]Probabilidad: %.2f%%[/b]   (tasa%s real %.1f%%)" % [
		r.probabilidad * 100.0, " early" if r.es_early else " base", r.tasa_base * 100.0])
	t.append("Aplicar early multiplica la tasa de partida x%.2f" % r.bonus_early)
	t.append("Odds x%.3f sobre esa tasa   |   aleatoriedad al resolver: +-%.0f%%" % [
		r.multiplicador_odds, r.factor_aleatoriedad * 100.0])
	t.append("")
	t.append("[b]Puntaje %.4f[/b] = fit %.4f + ensayo %.4f + carrera %.4f - umbrales %.4f" % [
		r.puntaje_final, r.fit_score, r.efecto_ensayo,
		r.efecto_carrera + r.efecto_ajuste_carrera, r.penalizacion_umbrales])
	t.append("")

	t.append("[b]Aporte de cada atributo al fit[/b]")
	var aportes: Array = []
	for atributo_id in r.contribuciones_atributo:
		aportes.append([atributo_id, r.contribuciones_atributo[atributo_id]])
	aportes.sort_custom(func(a, b): return a[1]["aporte"] > b[1]["aporte"])
	for par in aportes:
		var definicion: AttributeDefinition = AttributeRegistry.get_definition(par[0])
		t.append("  %-26s %3d  x peso %.2f  =  %.4f" % [
			definicion.nombre_display if definicion else String(par[0]),
			int(par[1]["valor"]), par[1]["peso"], par[1]["aporte"]])

	if not r.umbrales_incumplidos.is_empty():
		t.append("")
		t.append("[b][color=#ff8080]Umbrales incumplidos[/color][/b]")
		for u in r.umbrales_incumplidos:
			var definicion: AttributeDefinition = AttributeRegistry.get_definition(u["atributo"])
			t.append("  [color=#ff8080]%-26s %3d < %3d  ->  -%.4f[/color]" % [
				definicion.nombre_display if definicion else String(u["atributo"]),
				int(u["valor"]), int(u["umbral"]), u["penalizacion"]])

	var ensayo: EssayNarrative = EssayRegistry.obtener(r.ensayo_id)
	if ensayo:
		t.append("")
		t.append("[b]Ensayo[/b]: %s" % ensayo.titulo)
		t.append("  tipo '%s', afinidad de esta escuela x%.2f  ->  %+.4f" % [
			ensayo.narrativa_tipo, r.afinidad_ensayo, r.efecto_ensayo])

	var carrera: CareerData = CareerRegistry.obtener(r.carrera_id)
	if carrera:
		t.append("")
		t.append("[b]Carrera[/b]: %s" % carrera.nombre_display)
		t.append("  fortaleza de la escuela %.2f  ->  %+.4f" % [r.fortaleza_carrera, r.efecto_carrera])
		t.append("  ajuste de tu perfil %.2f     ->  %+.4f" % [r.ajuste_carrera, r.efecto_ajuste_carrera])

	_desglose.text = "\n".join(t)
