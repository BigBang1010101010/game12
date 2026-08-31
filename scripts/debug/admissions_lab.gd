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
	"Perfil equilibrado": {"atributos": {
			&"rigor_academico": 72, &"aptitud_cuantitativa": 68, &"aptitud_verbal": 70,
			&"aptitud_cientifica": 65, &"aptitud_investigacion": 60, &"liderazgo": 65,
			&"impacto_comunitario": 62, &"curiosidad_intelectual": 68, &"resiliencia": 65,
			&"logro_atletico": 45, &"profundidad_extracurricular": 62, &"habilidad_artistica": 45,
			&"red_social": 60, &"bienestar": 65, &"gestion_tiempo": 62,
	}, "actividades": {}},
	"Genio academico sin vida social": {"atributos": {
			&"rigor_academico": 97, &"aptitud_cuantitativa": 96, &"aptitud_verbal": 88,
			&"aptitud_cientifica": 94, &"aptitud_investigacion": 92, &"liderazgo": 18,
			&"impacto_comunitario": 12, &"curiosidad_intelectual": 90, &"resiliencia": 55,
			&"logro_atletico": 8, &"profundidad_extracurricular": 35, &"habilidad_artistica": 15,
			&"red_social": 12, &"bienestar": 38, &"gestion_tiempo": 55,
	}, "actividades": {}},
	"Lider carismatico, promedio academico": {"atributos": {
			&"rigor_academico": 62, &"aptitud_cuantitativa": 55, &"aptitud_verbal": 72,
			&"aptitud_cientifica": 48, &"aptitud_investigacion": 35, &"liderazgo": 94,
			&"impacto_comunitario": 88, &"curiosidad_intelectual": 55, &"resiliencia": 72,
			&"logro_atletico": 45, &"profundidad_extracurricular": 78, &"habilidad_artistica": 40,
			&"red_social": 92, &"bienestar": 70, &"gestion_tiempo": 75,
	}, "actividades": {}},
	"Atleta estrella": {"atributos": {
			&"rigor_academico": 58, &"aptitud_cuantitativa": 50, &"aptitud_verbal": 52,
			&"aptitud_cientifica": 45, &"aptitud_investigacion": 25, &"liderazgo": 68,
			&"impacto_comunitario": 45, &"curiosidad_intelectual": 38, &"resiliencia": 92,
			&"logro_atletico": 96, &"profundidad_extracurricular": 90, &"habilidad_artistica": 20,
			&"red_social": 72, &"bienestar": 80, &"gestion_tiempo": 70,
	}, "actividades": {}},
	"Atleta de remo reclutable": {
		"atributos": {
			&"rigor_academico": 78, &"aptitud_cuantitativa": 74, &"aptitud_verbal": 76,
			&"aptitud_cientifica": 72, &"aptitud_investigacion": 58, &"liderazgo": 62,
			&"impacto_comunitario": 48, &"curiosidad_intelectual": 60, &"resiliencia": 70,
			&"logro_atletico": 55, &"profundidad_extracurricular": 55, &"habilidad_artistica": 25,
			&"red_social": 65, &"bienestar": 70, &"gestion_tiempo": 68,
		},
		"actividades": {
			&"remo_crew": {"anios": 4.0, "reconocimiento": &"regional", "rol": &"oficial"},
			&"trabajo_remunerado": {"anios": 2.0},
		},
	},
	"Investigador STEM sin vida social": {
		"atributos": {
			&"rigor_academico": 94, &"aptitud_cuantitativa": 92, &"aptitud_verbal": 78,
			&"aptitud_cientifica": 90, &"aptitud_investigacion": 88, &"liderazgo": 22,
			&"impacto_comunitario": 15, &"curiosidad_intelectual": 88, &"resiliencia": 55,
			&"logro_atletico": 10, &"profundidad_extracurricular": 40, &"habilidad_artistica": 18,
			&"red_social": 15, &"bienestar": 42, &"gestion_tiempo": 58,
		},
		"actividades": {
			&"regeneron_sts_isef": {"anios": 3.0, "reconocimiento": &"nacional", "impacto": 600.0},
			&"club_matematicas": {"anios": 4.0, "reconocimiento": &"regional"},
			&"programacion_competitiva_usaco": {"anios": 3.0, "reconocimiento": &"regional"},
		},
	},
	"Lider equilibrado con club propio": {
		"atributos": {
			&"rigor_academico": 84, &"aptitud_cuantitativa": 78, &"aptitud_verbal": 86,
			&"aptitud_cientifica": 74, &"aptitud_investigacion": 62, &"liderazgo": 80,
			&"impacto_comunitario": 72, &"curiosidad_intelectual": 76, &"resiliencia": 70,
			&"logro_atletico": 35, &"profundidad_extracurricular": 72, &"habilidad_artistica": 40,
			&"red_social": 80, &"bienestar": 68, &"gestion_tiempo": 74,
		},
		"actividades": {
			&"fundar_club": {"anios": 3.0, "reconocimiento": &"regional", "rol": &"fundador", "impacto": 600.0},
			&"model_un": {"anios": 3.0, "reconocimiento": &"regional", "rol": &"oficial"},
			&"consejo_estudiantil": {"anios": 2.0, "reconocimiento": &"escolar", "rol": &"presidente", "impacto": 150.0},
			&"periodico_escolar": {"anios": 2.0, "rol": &"oficial"},
		},
	},
}

var _sliders: Dictionary = {}          # atributo_id -> HSlider
var _etiquetas_valor: Dictionary = {}  # atributo_id -> Label
var _filas: Dictionary = {}            # universidad_id -> Button
var _controles_actividad: Dictionary = {}  # actividad_id -> {anios, rec, rol, impacto, etiqueta}
var _etiqueta_presupuesto: Label
var _etiqueta_indice: Label
var _panel_slots: RichTextLabel
var _controles_stat: Dictionary = {}   # categoria_id -> {spin, etiqueta}
var _etiquetas_deporte: Dictionary = {}  # deporte_id -> Label
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

	# Four columns is more than a small window holds, so they live inside a
	# horizontal scroll instead of being clipped.
	var scroll_columnas := ScrollContainer.new()
	scroll_columnas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_columnas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Vertical scrolling OFF so the columns are stretched to the full height
	# instead of being given only their minimum; the horizontal one stays, for
	# windows too narrow to hold four columns.
	scroll_columnas.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margen.add_child(scroll_columnas)
	var columnas := HBoxContainer.new()
	columnas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columnas.add_theme_constant_override("separation", 14)
	scroll_columnas.add_child(columnas)

	# --- Left: one slider per attribute, generated from the registry --------
	var izquierda := VBoxContainer.new()
	izquierda.custom_minimum_size = Vector2(300, 0)
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

	# --- Activities: one row per activity, generated from the registry ------
	var actividades := VBoxContainer.new()
	actividades.custom_minimum_size = Vector2(512, 0)
	columnas.add_child(actividades)

	var titulo_act := Label.new()
	titulo_act.text = "Actividades  (años · reconocimiento · rol · impacto)"
	titulo_act.add_theme_font_size_override("font_size", 15)
	actividades.add_child(titulo_act)

	# Both wrap rather than stretch: the overcommitment warning is a long line,
	# and a Label that does not wrap widens its whole column, which pushed the
	# breakdown off the screen.
	_etiqueta_presupuesto = Label.new()
	_etiqueta_presupuesto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_etiqueta_presupuesto.custom_minimum_size = Vector2(500, 0)
	actividades.add_child(_etiqueta_presupuesto)
	_etiqueta_indice = Label.new()
	_etiqueta_indice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_etiqueta_indice.custom_minimum_size = Vector2(500, 0)
	actividades.add_child(_etiqueta_indice)

	var scroll_act := ScrollContainer.new()
	scroll_act.size_flags_vertical = Control.SIZE_EXPAND_FILL
	actividades.add_child(scroll_act)
	var lista_act := VBoxContainer.new()
	lista_act.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_act.add_child(lista_act)

	for categoria in ActivityRegistry.obtener_categorias():
		var cabecera_act := Label.new()
		cabecera_act.text = String(categoria).to_upper()
		cabecera_act.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
		lista_act.add_child(cabecera_act)
		for actividad_res in ActivityRegistry.obtener_por_categoria(categoria):
			lista_act.add_child(_fila_actividad(actividad_res as ActivityData))

	# --- Sport statistics: the numbers recognition is derived FROM ----------
	var stats := VBoxContainer.new()
	stats.custom_minimum_size = Vector2(500, 0)
	columnas.add_child(stats)

	var titulo_stats := Label.new()
	titulo_stats.text = "Estadísticas deportivas"
	titulo_stats.add_theme_font_size_override("font_size", 15)
	stats.add_child(titulo_stats)

	var nota_stats := Label.new()
	nota_stats.text = "El reconocimiento de un deporte se DERIVA de estos números; su desplegable de reconocimiento queda bloqueado."
	nota_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nota_stats.custom_minimum_size = Vector2(480, 0)
	nota_stats.add_theme_color_override("font_color", Color(0.72, 0.76, 0.85))
	stats.add_child(nota_stats)

	var scroll_stats := ScrollContainer.new()
	scroll_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats.add_child(scroll_stats)
	var lista_stats := VBoxContainer.new()
	lista_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_stats.add_child(lista_stats)

	for deporte_id in SportStatRegistry.deportes_con_estadisticas():
		var actividad: ActivityData = ActivityRegistry.obtener(deporte_id)
		var cabecera := Label.new()
		cabecera.text = actividad.nombre_display if actividad else String(deporte_id)
		cabecera.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
		lista_stats.add_child(cabecera)
		var derivado := Label.new()
		derivado.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
		lista_stats.add_child(derivado)
		_etiquetas_deporte[deporte_id] = derivado
		for categoria_res in SportStatRegistry.obtener_por_deporte(deporte_id):
			lista_stats.add_child(_fila_stat(categoria_res as SportStatCategory))

	# --- Middle: choices, presets and the live table ------------------------
	var centro := VBoxContainer.new()
	centro.custom_minimum_size = Vector2(380, 0)
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
	_carrera.clip_text = true
	_carrera.custom_minimum_size = Vector2(255, 0)
	_carrera.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_carrera.item_selected.connect(func(_i): _recalcular())
	elecciones.add_child(_carrera)

	var elecciones2 := HBoxContainer.new()
	centro.add_child(elecciones2)
	elecciones2.add_child(_hacer_etiqueta("Ensayo:"))
	_ensayo = OptionButton.new()
	for ensayo_res in EssayRegistry.obtener_todos():
		var ensayo: EssayNarrative = ensayo_res
		_ensayo.add_item(ensayo.titulo)
		_ensayo.set_item_tooltip(_ensayo.item_count - 1, "tipo: %s" % ensayo.narrativa_tipo)
		_ensayo.set_item_metadata(_ensayo.item_count - 1, ensayo.id)
	# Clipped: an essay title long enough to widen this column would push the
	# breakdown off the screen.
	_ensayo.clip_text = true
	_ensayo.custom_minimum_size = Vector2(255, 0)
	_ensayo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# Kept in sync with the essay screen in both directions: the lab is a
	# window onto the same choice, not a second one.
	var elegido: StringName = StringName(String(SaveSystem.obtener_eleccion(AdmissionCalculator.CLAVE_ENSAYO, "")))
	for i in range(_ensayo.item_count):
		if _ensayo.get_item_metadata(i) == elegido:
			_ensayo.selected = i
			break
	_ensayo.item_selected.connect(func(indice):
		SaveSystem.fijar_eleccion(AdmissionCalculator.CLAVE_ENSAYO, String(_ensayo.get_item_metadata(indice)))
		_recalcular())
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
	# A ScrollContainer gives its child its MINIMUM width, never more, so this
	# column cannot expand into a wide window - it is sized to be readable on
	# its own instead.
	derecha.custom_minimum_size = Vector2(430, 0)
	derecha.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columnas.add_child(derecha)
	_panel_slots = RichTextLabel.new()
	_panel_slots.bbcode_enabled = true
	_panel_slots.custom_minimum_size = Vector2(420, 200)
	_panel_slots.add_theme_stylebox_override("normal", _caja())
	derecha.add_child(_panel_slots)

	_desglose = RichTextLabel.new()
	_desglose.bbcode_enabled = true
	_desglose.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desglose.add_theme_stylebox_override("normal", _caja())
	derecha.add_child(_desglose)

## One row of controls per activity, built from the activity's own data: the
## dropdowns are filled from ActivityScales, so a new rung of recognition
## would appear here without this file changing.
func _fila_actividad(actividad: ActivityData) -> HBoxContainer:
	var fila := HBoxContainer.new()
	var nombre := Label.new()
	nombre.text = actividad.nombre_display
	nombre.custom_minimum_size = Vector2(118, 0)
	nombre.clip_text = true
	nombre.tooltip_text = "%s\n%d h/semana, techo tier %d" % [
		actividad.descripcion, actividad.costo_horas_semana, actividad.tier_techo]
	fila.add_child(nombre)

	var anios := SpinBox.new()
	anios.min_value = 0.0
	anios.max_value = 4.0
	anios.step = 0.5
	anios.custom_minimum_size = Vector2(54, 0)
	anios.value_changed.connect(func(_v): _recalcular())
	fila.add_child(anios)

	var reconocimiento := OptionButton.new()
	for nivel in ActivityScales.RECONOCIMIENTO:
		reconocimiento.add_item(String(nivel))
		reconocimiento.set_item_metadata(reconocimiento.item_count - 1, nivel)
	reconocimiento.custom_minimum_size = Vector2(100, 0)
	reconocimiento.item_selected.connect(func(_i): _recalcular())
	fila.add_child(reconocimiento)

	var rol := OptionButton.new()
	for nivel_rol in ActivityScales.ROL:
		rol.add_item(String(nivel_rol))
		rol.set_item_metadata(rol.item_count - 1, nivel_rol)
	rol.selected = ActivityScales.indice_rol(&"miembro")
	rol.custom_minimum_size = Vector2(84, 0)
	rol.item_selected.connect(func(_i): _recalcular())
	fila.add_child(rol)

	var impacto := SpinBox.new()
	impacto.min_value = 0.0
	impacto.max_value = 5000.0
	impacto.step = 50.0
	impacto.custom_minimum_size = Vector2(64, 0)
	impacto.value_changed.connect(func(_v): _recalcular())
	fila.add_child(impacto)

	var etiqueta := Label.new()
	etiqueta.custom_minimum_size = Vector2(26, 0)
	fila.add_child(etiqueta)

	_controles_actividad[actividad.id] = {
		"anios": anios, "rec": reconocimiento, "rol": rol,
		"impacto": impacto, "etiqueta": etiqueta,
	}
	return fila

## One row per statistic. The spinbox range comes from the benchmark bands
## themselves, so a statistic measured in seconds and one measured in home runs
## both get a sensible control without this file knowing either sport.
func _fila_stat(categoria: SportStatCategory) -> HBoxContainer:
	var fila := HBoxContainer.new()
	var nombre := Label.new()
	nombre.text = categoria.nombre_display
	nombre.custom_minimum_size = Vector2(140, 0)
	nombre.clip_text = true
	nombre.tooltip_text = "%s (%s)  ·  %s" % [categoria.nombre_display, categoria.unidad,
		"más alto es mejor" if categoria.es_mejor_mayor else "más BAJO es mejor"]
	fila.add_child(nombre)

	var benchmark: StatBenchmark = StatBenchmarkRegistry.para_categoria(categoria.id)
	var tope := 100.0
	var paso := 1.0
	if benchmark and not benchmark.bandas.is_empty():
		var extremo: float = float(benchmark.bandas[benchmark.bandas.size() - 1]["valor"])
		var primero: float = float(benchmark.bandas[0]["valor"])
		tope = maxf(extremo, primero) * 1.4
		paso = 0.005 if categoria.unidad == "promedio" else (1.0 if tope > 60.0 else 0.1)
	var spin := SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = maxf(tope, 1.0)
	spin.step = paso
	spin.custom_minimum_size = Vector2(88, 0)
	spin.value_changed.connect(func(valor):
		SportStatsTracker.fijar_valor(categoria.deporte_id, categoria.id, valor)
		_recalcular())
	fila.add_child(spin)

	var etiqueta := Label.new()
	etiqueta.custom_minimum_size = Vector2(230, 0)
	etiqueta.clip_text = true
	fila.add_child(etiqueta)

	_controles_stat[categoria.id] = {"spin": spin, "etiqueta": etiqueta, "categoria": categoria}
	return fila

func _refrescar_stats() -> void:
	for categoria_id in _controles_stat:
		var controles: Dictionary = _controles_stat[categoria_id]
		var categoria: SportStatCategory = controles["categoria"]
		var reconocimiento: StringName = SportStatsTracker.reconocimiento_de_categoria(
			categoria.deporte_id, categoria.id)
		var etiqueta: Label = controles["etiqueta"]
		etiqueta.text = "%s  ->  %s" % [categoria.formatear((controles["spin"] as SpinBox).value), reconocimiento]
		etiqueta.add_theme_color_override("font_color",
			Color(0.7, 0.9, 0.7) if reconocimiento != &"ninguno" else Color(0.6, 0.6, 0.65))
	for deporte_id in _etiquetas_deporte:
		var derivado: StringName = SportStatsTracker.reconocimiento_derivado(deporte_id)
		var tiene: bool = SportStatsTracker.tiene_stats(deporte_id)
		(_etiquetas_deporte[deporte_id] as Label).text = "  deriva: %s%s" % [
			derivado, "" if tiene else "   (sin datos, manda el manual)"]

## The activity profile the controls currently describe. Activities at zero
## years are simply not in it - that IS "not doing it".
func _perfil_actividades() -> Dictionary:
	var perfil: Dictionary = {}
	for actividad_id in _controles_actividad:
		var controles: Dictionary = _controles_actividad[actividad_id]
		var anios: float = (controles["anios"] as SpinBox).value
		if anios <= 0.0:
			continue
		# A sport with numbers on record ignores the dropdown: its recognition
		# is whatever the benchmarks make of those numbers.
		var reconocimiento: StringName = (controles["rec"] as OptionButton).get_selected_metadata()
		if SportStatsTracker.tiene_stats(actividad_id):
			reconocimiento = SportStatsTracker.reconocimiento_derivado(actividad_id)
		perfil[actividad_id] = {
			"anios": anios,
			"reconocimiento": reconocimiento,
			"rol": (controles["rol"] as OptionButton).get_selected_metadata(),
			"impacto": (controles["impacto"] as SpinBox).value,
		}
	return perfil

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
	var atributos: Dictionary = preset.get("atributos", {})
	for atributo_id in _sliders:
		# Attributes a preset does not mention fall back to neutral, so adding
		# an attribute never invalidates the presets.
		(_sliders[atributo_id] as HSlider).value = float(atributos.get(atributo_id, VALOR_NEUTRO))

	var actividades: Dictionary = preset.get("actividades", {})
	for actividad_id in _controles_actividad:
		var controles: Dictionary = _controles_actividad[actividad_id]
		var entrada: Dictionary = actividades.get(actividad_id, {})
		(controles["anios"] as SpinBox).set_value_no_signal(float(entrada.get("anios", 0.0)))
		(controles["impacto"] as SpinBox).set_value_no_signal(float(entrada.get("impacto", 0.0)))
		(controles["rec"] as OptionButton).selected = ActivityScales.indice_reconocimiento(
			entrada.get("reconocimiento", &"ninguno"))
		(controles["rol"] as OptionButton).selected = ActivityScales.indice_rol(
			entrada.get("rol", &"miembro"))
	_recalcular()

func _valores_actuales() -> Dictionary:
	var valores: Dictionary = {}
	for atributo_id in _sliders:
		valores[atributo_id] = (_sliders[atributo_id] as HSlider).value
	return valores

func _recalcular() -> void:
	var base: Dictionary = _valores_actuales()

	# The activity profile is simulated FIRST: what an activity pays in
	# attributes has to be part of the profile the schools then judge, or the
	# lab would be showing a player who did four years of rowing and gained
	# nothing from it.
	var perfil: Dictionary = _perfil_actividades()
	var simulacion: Dictionary = ActivityTracker.simular_perfil(perfil, base)
	var valores: Dictionary = simulacion["valores"]
	var indice: float = AcademicIndex.calcular_desde(valores)

	for atributo_id in _etiquetas_valor:
		var ganado: float = float(valores.get(atributo_id, 0.0)) - float(base.get(atributo_id, 0.0))
		var etiqueta: Label = _etiquetas_valor[atributo_id]
		etiqueta.text = "%d%s" % [int(valores.get(atributo_id, 0.0)),
			"+%d" % int(round(ganado)) if ganado >= 0.5 else ""]

	var estados: Dictionary = {}
	for actividad_id in simulacion["actividades"]:
		var detalle: Dictionary = simulacion["actividades"][actividad_id]
		estados[actividad_id] = detalle["estado"]
		var controles: Dictionary = _controles_actividad[actividad_id]
		(controles["etiqueta"] as Label).text = "T%d" % detalle["tier"] if detalle["tier"] <= 4 else "-"
	for actividad_id in _controles_actividad:
		if not estados.has(actividad_id):
			((_controles_actividad[actividad_id] as Dictionary)["etiqueta"] as Label).text = ""

	_refrescar_stats()
	for actividad_id in _controles_actividad:
		var actividad: ActivityData = ActivityRegistry.obtener(actividad_id)
		if actividad and actividad.es_deporte and SportStatsTracker.tiene_stats(actividad_id):
			var rec: OptionButton = (_controles_actividad[actividad_id] as Dictionary)["rec"]
			rec.disabled = true
			rec.selected = ActivityScales.indice_reconocimiento(
				SportStatsTracker.reconocimiento_derivado(actividad_id))

	_actualizar_presupuesto(estados.keys(), indice)

	var detalles: Array[Dictionary] = ApplicationBuilder.detalle_desde_estados(estados, indice)
	var seleccion: Array[Dictionary] = ApplicationBuilder.seleccionar(detalles)
	_mostrar_slots(detalles, seleccion)

	var carrera_id: StringName = _carrera.get_selected_metadata() if _carrera.selected >= 0 else &""
	var ensayo_id: StringName = _ensayo.get_selected_metadata() if _ensayo.selected >= 0 else &""
	var early: bool = _early.button_pressed

	var resultados: Array[AdmissionResult] = AdmissionCalculator.calcular_todas(
		carrera_id, ensayo_id, early, valores, seleccion)
	for resultado in resultados:
		var boton: Button = _filas.get(resultado.universidad_id)
		if not boton:
			continue
		var universidad: UniversityData = UniversityRegistry.obtener(resultado.universidad_id)
		var marca: String = ">" if resultado.universidad_id == _seleccionada else " "
		boton.text = "%s %-22s %5.1f%%  ->  %5.1f%%%s" % [
			marca, universidad.nombre_display.substr(0, 22),
			resultado.tasa_base * 100.0, resultado.probabilidad * 100.0,
			"  [reclutado]" if resultado.es_reclutado else ""]
		boton.add_theme_color_override("font_color", universidad.color_primario.lightened(0.35))

	_mostrar_desglose(AdmissionCalculator.calcular_probabilidad(
		_seleccionada, carrera_id, ensayo_id, early, valores, seleccion))

func _actualizar_presupuesto(ids: Array, indice: float) -> void:
	var comprometidas: float = TimeBudget.horas_de(ids)
	var totales: float = TimeBudget.horas_totales()
	var exceso: float = maxf(comprometidas - totales, 0.0)
	_etiqueta_presupuesto.text = "Tiempo: %.0f de %.0f h/semana" % [comprometidas, totales]
	if exceso > 0.0:
		var castigo: Dictionary = TimeBudget.penalizacion_semanal(ids)
		var partes: Array = []
		for atributo_id in castigo:
			var definicion: AttributeDefinition = AttributeRegistry.get_definition(atributo_id)
			partes.append("%s %.1f" % [
				definicion.nombre_display if definicion else String(atributo_id), castigo[atributo_id]])
		_etiqueta_presupuesto.text += "   SOBRECOMPROMISO +%.0f h  ->  por semana: %s" % [
			exceso, ", ".join(partes)]
		_etiqueta_presupuesto.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	else:
		_etiqueta_presupuesto.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))

	var config: AdmissionConfig = AdmissionCalculator.obtener_config()
	_etiqueta_indice.text = "Índice académico: %.0f   (regular %.0f · atlético %.0f)" % [
		indice, config.umbral_indice_competitivo, config.umbral_indice_atletico]
	_etiqueta_indice.add_theme_color_override("font_color",
		Color(0.7, 0.9, 0.7) if indice >= config.umbral_indice_competitivo else Color(1.0, 0.75, 0.45))

func _mostrar_slots(detalles: Array[Dictionary], seleccion: Array[Dictionary]) -> void:
	var t := PackedStringArray()
	t.append("[b]Common App: %d de %d slots[/b]" % [seleccion.size(), ApplicationBuilder.slots()])
	if detalles.is_empty():
		t.append("[i]sin actividades[/i]")
	var dentro: Array = []
	for entrada in seleccion:
		dentro.append(entrada["actividad_id"])
		t.append("  T%d  %-24s %.1f a  pts %.2f%s" % [
			entrada["tier"], String(entrada["nombre"]).substr(0, 24), entrada["anios"],
			entrada["puntaje"], "  [color=#88ddaa]reclutable[/color]" if entrada["reclutable"] else ""])
	for entrada in detalles:
		if dentro.has(entrada["actividad_id"]):
			continue
		t.append("  [color=#888888]T%d  %-24s %.1f a  pts %.2f  (fuera)[/color]" % [
			entrada["tier"], String(entrada["nombre"]).substr(0, 24), entrada["anios"], entrada["puntaje"]])
	_panel_slots.text = "\n".join(t)

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
	t.append("[b]Puntaje %.4f[/b] = fit %.4f + ensayo %.4f + carrera %.4f + actividades %.4f + universal %.4f + atlético %.4f - umbrales %.4f - índice %.4f" % [
		r.puntaje_final, r.fit_score, r.efecto_ensayo,
		r.efecto_carrera + r.efecto_ajuste_carrera, r.efecto_actividades,
		r.efecto_universal, r.efecto_atletico, r.penalizacion_umbrales, r.penalizacion_indice])
	t.append("Índice académico %.0f contra el umbral %.0f de esta ruta%s" % [
		r.academic_index, r.umbral_indice, "  [ATLETA RECLUTADO]" if r.es_reclutado else ""])
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

	if not r.aportes_actividad.is_empty():
		t.append("")
		t.append("[b]Aporte de cada actividad a esta carrera[/b]")
		for a in r.aportes_actividad:
			t.append("  T%d %-24s x%.2f afinidad, %.1f años (x%.2f)  ->  %+.4f" % [
				a["tier"], String(a["nombre"]).substr(0, 24), a["afinidad"],
				a["anios"], a["continuidad"], a["aporte"]])
		t.append("  [i]suma %.3f / referencia  ->  %+.4f al puntaje[/i]" % [
			r.afinidad_actividades, r.efecto_actividades])

	if not r.aportes_universales.is_empty():
		t.append("")
		t.append("[b]Apoyo universal[/b]  (igual en las 8, sin importar la carrera)")
		for u in r.aportes_universales:
			t.append("  T%d %-24s boost %.2f  ->  %+.4f" % [
				u["tier"], String(u["nombre"]).substr(0, 24), u["boost"], u["aporte"]])
		t.append("  [i]suma %.3f / referencia  ->  %+.4f al puntaje[/i]" % [
			r.fuerza_universal, r.efecto_universal])

	if not r.deportes_no_reclutables.is_empty():
		t.append("")
		t.append("[b][color=#ffcc80]Ruta atlética cerrada[/color][/b]")
		for d in r.deportes_no_reclutables:
			if d["motivo"] == "reconocimiento":
				t.append("  [color=#ffcc80]%s: reconocimiento '%s', necesita '%s'[/color]" % [
					d["nombre"], d["reconocimiento"], d["umbral"]])
			else:
				t.append("  [color=#ffcc80]%s: índice académico %.0f, necesita %.0f[/color]" % [
					d["nombre"], d["indice"], d["minimo"]])

	var carrera: CareerData = CareerRegistry.obtener(r.carrera_id)
	if carrera:
		t.append("")
		t.append("[b]Carrera[/b]: %s" % carrera.nombre_display)
		t.append("  fortaleza de la escuela %.2f  ->  %+.4f" % [r.fortaleza_carrera, r.efecto_carrera])
		t.append("  ajuste de tu perfil %.2f     ->  %+.4f" % [r.ajuste_carrera, r.efecto_ajuste_carrera])

	_desglose.text = "\n".join(t)
