extends Control

## The activities and time screen: where a player actually spends their week.
##
## Everything on it is generated from the registries and the trackers - the
## categories, the rows, the ladder requirements and the Common App slots all
## come from data, so an activity added tomorrow appears here by existing.
##
## The whole screen is a thin shell over systems that already worked and had
## no way in: ActivityTracker for the ladders, TimeBudget for the week and
## ApplicationBuilder for the ten slots. It adds no rules of its own except
## the two below, which are UI policy, not simulation:
##
##   1. Enrolling in something that does not fit the week is BLOCKED by
##      default. The engine allows overcommitment and charges burnout for it,
##      which is the honest model - but a player should have to mean it, so
##      the block lifts behind an explicit checkbox that states the weekly
##      cost.
##   2. An activity can be given its hours once per in-game week. Otherwise
##      the button is a free progress machine: the budget limits what you can
##      commit to, not how many times you can click.

## Colour of a requirement that is already satisfied, and of one that is not.
const COLOR_OK := Color(0.55, 0.85, 0.6)
const COLOR_FALTA := Color(0.95, 0.7, 0.45)
const COLOR_TENUE := Color(0.62, 0.65, 0.72)

var _etiqueta_presupuesto: RichTextLabel
var _aviso: Label
var _permitir_exceso: CheckBox
var _lista: VBoxContainer
var _panel_slots: RichTextLabel
var _bitacora: RichTextLabel
var _lineas_bitacora: Array[String] = []

## actividad_id -> semana en la que ya se le dieron sus horas.
var _invertido_en_semana: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	get_viewport().size_changed.connect(func(): size = get_viewport_rect().size)
	_construir()
	# Immediate feedback: a promotion anywhere lands in the log, whether it
	# came from a click here or from a sport statistic posted elsewhere.
	ActivityTracker.nivel_alcanzado.connect(_on_nivel_alcanzado)
	_refrescar()

func _semana_actual() -> int:
	return int(DayNightCycle.get_days_elapsed() / 7)

# --- Construction ------------------------------------------------------------

func _construir() -> void:
	var fondo := ColorRect.new()
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.color = Color(0.06, 0.07, 0.10, 0.97)
	add_child(fondo)

	var margen := MarginContainer.new()
	margen.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right", "top", "bottom"]:
		margen.add_theme_constant_override("margin_" + lado, 24)
	add_child(margen)

	var raiz := VBoxContainer.new()
	raiz.add_theme_constant_override("separation", 12)
	margen.add_child(raiz)

	# --- Cabecera: el presupuesto de la semana, siempre visible -------------
	var titulo := Label.new()
	titulo.text = "Tu tiempo"
	titulo.add_theme_font_size_override("font_size", 28)
	raiz.add_child(titulo)

	_etiqueta_presupuesto = RichTextLabel.new()
	_etiqueta_presupuesto.bbcode_enabled = true
	_etiqueta_presupuesto.fit_content = true
	_etiqueta_presupuesto.custom_minimum_size = Vector2(0, 26)
	raiz.add_child(_etiqueta_presupuesto)

	_aviso = Label.new()
	_aviso.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	raiz.add_child(_aviso)

	var acciones := HBoxContainer.new()
	acciones.add_theme_constant_override("separation", 14)
	raiz.add_child(acciones)

	_permitir_exceso = CheckBox.new()
	_permitir_exceso.text = "Permitir sobrecompromiso"
	_permitir_exceso.tooltip_text = ("Deja inscribirte por encima de tu semana. " +
		"Cada hora de exceso te cobra bienestar y gestión del tiempo, todas las semanas.")
	_permitir_exceso.toggled.connect(func(_p): _refrescar())
	acciones.add_child(_permitir_exceso)

	var pasar := Button.new()
	pasar.text = "Pasar una semana"
	pasar.tooltip_text = ("Avanza 7 días y le da a cada actividad activa sus horas. " +
		"El sobrecompromiso se cobra al pasar la semana.")
	pasar.pressed.connect(_pasar_semana)
	acciones.add_child(pasar)

	var cerrar := Button.new()
	cerrar.text = "Cerrar (T)"
	cerrar.pressed.connect(func(): ActivitiesScreen.cerrar())
	acciones.add_child(cerrar)

	# --- Cuerpo: actividades a la izquierda, aplicación a la derecha --------
	var columnas := HBoxContainer.new()
	columnas.add_theme_constant_override("separation", 16)
	columnas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	raiz.add_child(columnas)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columnas.add_child(scroll)
	_lista = VBoxContainer.new()
	_lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lista.add_theme_constant_override("separation", 6)
	scroll.add_child(_lista)

	var derecha := VBoxContainer.new()
	derecha.custom_minimum_size = Vector2(430, 0)
	derecha.add_theme_constant_override("separation", 10)
	columnas.add_child(derecha)

	_panel_slots = RichTextLabel.new()
	_panel_slots.bbcode_enabled = true
	_panel_slots.custom_minimum_size = Vector2(420, 300)
	_panel_slots.add_theme_stylebox_override("normal", _caja())
	derecha.add_child(_panel_slots)

	_bitacora = RichTextLabel.new()
	_bitacora.bbcode_enabled = true
	_bitacora.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bitacora.add_theme_stylebox_override("normal", _caja())
	derecha.add_child(_bitacora)

func _caja() -> StyleBoxFlat:
	var caja := StyleBoxFlat.new()
	caja.bg_color = Color(0.11, 0.12, 0.15)
	caja.set_content_margin_all(12)
	caja.set_corner_radius_all(4)
	return caja

# --- Refresh -----------------------------------------------------------------

func _refrescar() -> void:
	_refrescar_presupuesto()
	_refrescar_lista()
	_refrescar_slots()
	_refrescar_bitacora()

func _refrescar_presupuesto() -> void:
	var comprometidas: float = TimeBudget.horas_comprometidas()
	var totales: float = TimeBudget.horas_totales()
	var libres: float = totales - comprometidas
	var color: String = "#88ddaa" if libres >= 0.0 else "#ff8080"
	_etiqueta_presupuesto.text = ("[b]Semana:[/b] [color=%s]%d de %d horas comprometidas[/color]   ·   " +
		"[b]%d libres[/b]   ·   %d actividades activas   ·   semana %d") % [
		color, int(comprometidas), int(totales), int(libres),
		ActivityTracker.actividades_activas().size(), _semana_actual()]

	var exceso: float = TimeBudget.horas_excedidas()
	if exceso > 0.0:
		var partes: Array = []
		for atributo_id in TimeBudget.penalizacion_semanal():
			var definicion: AttributeDefinition = AttributeRegistry.get_definition(atributo_id)
			partes.append("%s %.1f" % [
				definicion.nombre_display if definicion else String(atributo_id),
				TimeBudget.penalizacion_semanal()[atributo_id]])
		_aviso.text = "Sobrecompromiso de %d h: cada semana te cuesta %s." % [int(exceso), ", ".join(partes)]
		_aviso.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	else:
		_aviso.text = "Tu semana cabe. Inscribirte en algo que no quepa está bloqueado salvo que lo permitas arriba."
		_aviso.add_theme_color_override("font_color", COLOR_TENUE)

func _refrescar_lista() -> void:
	for hijo in _lista.get_children():
		hijo.queue_free()
	# What the player is already doing goes first, whatever its category: those
	# are the rows they came here to act on, and burying them under forty
	# alphabetised cards would make the screen useless the moment it matters.
	var activas: Array[StringName] = ActivityTracker.actividades_activas()
	if not activas.is_empty():
		_lista.add_child(_cabecera("EN CURSO"))
		for actividad_id in activas:
			var actividad: ActivityData = ActivityRegistry.obtener(actividad_id)
			if actividad:
				_lista.add_child(_tarjeta(actividad))

	for categoria in ActivityRegistry.obtener_categorias():
		var disponibles: Array[Resource] = []
		for actividad_res in ActivityRegistry.obtener_por_categoria(categoria):
			if not activas.has((actividad_res as ActivityData).id):
				disponibles.append(actividad_res)
		if disponibles.is_empty():
			continue
		_lista.add_child(_cabecera(String(categoria).replace("_", " / ").to_upper()))
		for actividad_res in disponibles:
			_lista.add_child(_tarjeta(actividad_res as ActivityData))

func _cabecera(texto: String) -> Label:
	var cabecera := Label.new()
	cabecera.text = texto
	cabecera.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	return cabecera

## One card per activity: what it costs, where the player stands in it, what
## the next rung asks for, and the one button that applies.
func _tarjeta(actividad: ActivityData) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _caja())
	var columna := VBoxContainer.new()
	panel.add_child(columna)

	var activa: bool = ActivityTracker.esta_activa(actividad.id)
	var estado: Dictionary = ActivityTracker.obtener_estado(actividad.id)

	var fila := HBoxContainer.new()
	columna.add_child(fila)

	var nombre := Label.new()
	nombre.text = actividad.nombre_display
	nombre.custom_minimum_size = Vector2(250, 0)
	nombre.tooltip_text = actividad.descripcion
	fila.add_child(nombre)

	var costo := Label.new()
	costo.text = "%d h/sem" % actividad.costo_horas_semana
	costo.custom_minimum_size = Vector2(80, 0)
	costo.add_theme_color_override("font_color", COLOR_TENUE)
	fila.add_child(costo)

	var nivel := Label.new()
	nivel.custom_minimum_size = Vector2(230, 0)
	if activa:
		var niveles: Array[ActivityLevel] = actividad.obtener_niveles()
		var indice: int = int(estado["nivel_indice"])
		nivel.text = "%s  ·  tier %d  ·  %.1f años" % [
			niveles[indice].nombre if indice >= 0 else "sin nivel",
			ActivityTracker.tier_actual(actividad.id, estado), estado["anios_invertidos"]]
		nivel.add_theme_color_override("font_color", COLOR_OK)
	else:
		nivel.text = "no inscrito  ·  techo tier %d" % actividad.tier_techo
		nivel.add_theme_color_override("font_color", COLOR_TENUE)
	fila.add_child(nivel)

	fila.add_child(_boton_de(actividad, activa))
	columna.add_child(_requisitos(actividad, estado, activa))
	return panel

func _boton_de(actividad: ActivityData, activa: bool) -> Button:
	var boton := Button.new()
	boton.custom_minimum_size = Vector2(190, 0)
	if not activa:
		var contexto: Dictionary = {"hitos": SaveSystem.hitos}
		if not RequirementChecker.cumple_todos(actividad.requisitos_desbloqueo, contexto):
			boton.text = "Bloqueada"
			boton.disabled = true
			boton.tooltip_text = "Todavía no cumples lo que pide para empezar."
			return boton
		var libres: float = TimeBudget.horas_totales() - TimeBudget.horas_comprometidas()
		var cabe: bool = float(actividad.costo_horas_semana) <= libres
		if not cabe and not _permitir_exceso.button_pressed:
			boton.text = "No cabe (+%d h)" % int(float(actividad.costo_horas_semana) - libres)
			boton.disabled = true
			boton.tooltip_text = ("Te faltan horas esta semana. Marca 'Permitir sobrecompromiso' " +
				"si aceptas pagar el burnout.")
			return boton
		boton.text = "Inscribirse" if cabe else "Inscribirse (excede)"
		boton.pressed.connect(_inscribir.bind(actividad.id))
		return boton

	if int(_invertido_en_semana.get(actividad.id, -1)) == _semana_actual():
		boton.text = "Ya invertido esta semana"
		boton.disabled = true
		boton.tooltip_text = "Pasa una semana para volver a dedicarle horas."
		return boton
	boton.text = "Invertir %d h" % actividad.costo_horas_semana
	boton.pressed.connect(_invertir.bind(actividad.id))
	return boton

## The four levers of the next rung, each marked met or not. This is the
## screen's real job: telling the player what the ladder actually wants.
func _requisitos(actividad: ActivityData, estado: Dictionary, activa: bool) -> Control:
	var linea := HBoxContainer.new()
	linea.add_theme_constant_override("separation", 14)
	var niveles: Array[ActivityLevel] = actividad.obtener_niveles()
	var siguiente: int = int(estado["nivel_indice"]) + 1 if activa else 0
	if siguiente >= niveles.size():
		var tope := Label.new()
		tope.text = "    Nivel máximo alcanzado."
		tope.add_theme_color_override("font_color", COLOR_OK)
		linea.add_child(tope)
		return linea

	var nivel: ActivityLevel = niveles[siguiente]
	var etiqueta := Label.new()
	etiqueta.text = "    Para '%s' (tier %d):" % [nivel.nombre, nivel.tier]
	etiqueta.add_theme_color_override("font_color", COLOR_TENUE)
	linea.add_child(etiqueta)

	if nivel.condiciones_ascenso.is_empty():
		var libre := Label.new()
		libre.text = "solo inscribirte"
		libre.add_theme_color_override("font_color", COLOR_OK)
		linea.add_child(libre)
		return linea

	for condicion in nivel.condiciones_ascenso:
		var cumple: bool = activa and ActivityTracker.cumple_ascenso(
			_nivel_de_una_condicion(nivel, condicion), estado, actividad.id)
		var texto := Label.new()
		texto.text = "%s %s" % ["✓" if cumple else "•", _texto_condicion(condicion, actividad, estado)]
		texto.add_theme_color_override("font_color", COLOR_OK if cumple else COLOR_FALTA)
		linea.add_child(texto)
	return linea

## A throwaway level carrying one condition, so a single lever can be asked
## about through the same code path the real ladder uses.
func _nivel_de_una_condicion(base: ActivityLevel, condicion: Dictionary) -> ActivityLevel:
	var uno := ActivityLevel.new()
	uno.nombre = base.nombre
	uno.tier = base.tier
	uno.condiciones_ascenso = [condicion]
	return uno

func _texto_condicion(condicion: Dictionary, actividad: ActivityData, estado: Dictionary) -> String:
	var valor: Variant = condicion.get("valor", "")
	match String(condicion.get("palanca", "")):
		"anios_continuidad":
			return "%.0f años (tienes %.1f)" % [float(valor), float(estado.get("anios_invertidos", 0.0))]
		"rol_liderazgo":
			return "rol %s (eres %s)" % [valor, estado.get("rol", &"ninguno")]
		"reconocimiento_externo":
			var actual: StringName = ActivityTracker.reconocimiento_efectivo(actividad.id, estado)
			var fuente: String = " (de tus estadísticas)" if actividad.es_deporte and SportStatsTracker.tiene_stats(actividad.id) else ""
			return "reconocimiento %s (tienes %s%s)" % [valor, actual, fuente]
		"impacto_medible":
			return "impacto %.0f (llevas %.0f)" % [float(valor), float(estado.get("impacto", 0.0))]
	return String(condicion.get("palanca", "?"))

func _refrescar_slots() -> void:
	var seleccion: Array[Dictionary] = ApplicationBuilder.seleccion_automatica()
	var fuera: Array[Dictionary] = ApplicationBuilder.fuera_de_slots()
	var t := PackedStringArray()
	t.append("[b]Common App: %d de %d slots[/b]" % [seleccion.size(), ApplicationBuilder.slots()])
	t.append("[i]Solo estas actividades llegan a la solicitud.[/i]")
	t.append("")
	if seleccion.is_empty():
		t.append("[color=#9aa0aa]Todavía no participas en nada.[/color]")
	for entrada in seleccion:
		t.append("  T%d  %-26s %.1f a  ·  %.2f pts%s" % [
			entrada["tier"], String(entrada["nombre"]).substr(0, 26), entrada["anios"],
			entrada["puntaje"], "  [color=#88ddaa]reclutable[/color]" if entrada["reclutable"] else ""])
	if not fuera.is_empty():
		t.append("")
		t.append("[color=#888888]Fuera de los slots:[/color]")
		for entrada in fuera:
			t.append("  [color=#888888]T%d  %-26s %.2f pts[/color]" % [
				entrada["tier"], String(entrada["nombre"]).substr(0, 26), entrada["puntaje"]])
	_panel_slots.text = "\n".join(t)

func _refrescar_bitacora() -> void:
	var t := PackedStringArray()
	t.append("[b]Qué acaba de pasar[/b]")
	if _lineas_bitacora.is_empty():
		t.append("[color=#9aa0aa]Inscríbete en algo o invierte horas.[/color]")
	# Newest first: the feedback for what was just clicked has to be on top.
	for i in range(_lineas_bitacora.size() - 1, -1, -1):
		t.append(_lineas_bitacora[i])
	_bitacora.text = "\n".join(t)

# --- Actions -----------------------------------------------------------------

func _inscribir(actividad_id: StringName) -> void:
	var actividad: ActivityData = ActivityRegistry.obtener(actividad_id)
	var marca: int = PlayerState.ledger.size()
	if not ActivityTracker.inscribir(actividad_id, {"hitos": SaveSystem.hitos}):
		_anotar("[color=#ff8080]No pudiste inscribirte en %s.[/color]" % actividad.nombre_display)
		_refrescar()
		return
	_anotar("[b]Te inscribiste en %s[/b] (%d h/semana)." % [
		actividad.nombre_display, actividad.costo_horas_semana])
	_anotar_modificadores(marca)
	_refrescar()

func _invertir(actividad_id: StringName) -> void:
	var actividad: ActivityData = ActivityRegistry.obtener(actividad_id)
	var marca: int = PlayerState.ledger.size()
	var horas: float = float(actividad.costo_horas_semana)
	ActivityTracker.invertir_tiempo(actividad_id, horas)
	_invertido_en_semana[actividad_id] = _semana_actual()
	var estado: Dictionary = ActivityTracker.obtener_estado(actividad_id)
	_anotar("Dedicaste %d h a %s. Llevas %.2f años." % [
		int(horas), actividad.nombre_display, estado["anios_invertidos"]])
	_anotar_modificadores(marca)
	_refrescar()

## Advances the calendar a week and pays every active activity its hours. The
## overcommitment charge rides on the days passing, so it lands by itself.
func _pasar_semana() -> void:
	var marca: int = PlayerState.ledger.size()
	var activas: Array[StringName] = ActivityTracker.actividades_activas()
	for actividad_id in activas:
		var actividad: ActivityData = ActivityRegistry.obtener(actividad_id)
		ActivityTracker.invertir_tiempo(actividad_id, float(actividad.costo_horas_semana))
	for i in range(7):
		DayNightCycle.advance_seconds(DayNightCycle.CYCLE_DURATION_SECONDS)
	_invertido_en_semana.clear()
	_anotar("[b]Pasó una semana.[/b] %d actividades recibieron sus horas." % activas.size())
	_anotar_modificadores(marca)
	_refrescar()

func _on_nivel_alcanzado(actividad_id: StringName, _indice: int, nivel: ActivityLevel) -> void:
	var actividad: ActivityData = ActivityRegistry.obtener(actividad_id)
	_anotar("[color=#88ddaa][b]¡%s: subiste a '%s' (tier %d)![/b][/color]" % [
		actividad.nombre_display if actividad else String(actividad_id), nivel.nombre, nivel.tier])

## Reads the ledger entries an action produced and reports the attributes it
## actually moved - the real applied deltas, after curves and caps, not the
## numbers written in the data.
func _anotar_modificadores(desde: int) -> void:
	var totales: Dictionary = {}
	for i in range(desde, PlayerState.ledger.size()):
		var entrada: Dictionary = PlayerState.ledger[i]
		totales[entrada["atributo"]] = totales.get(entrada["atributo"], 0.0) + entrada["delta_aplicado"]
	if totales.is_empty():
		return
	var partes: Array = []
	for atributo_id in totales:
		var definicion: AttributeDefinition = AttributeRegistry.get_definition(atributo_id)
		if not definicion:
			continue
		partes.append("%s %+.1f" % [definicion.nombre_display, totales[atributo_id]])
	if not partes.is_empty():
		_anotar("      %s" % ", ".join(partes))

func _anotar(linea: String) -> void:
	_lineas_bitacora.append(linea)
	if _lineas_bitacora.size() > 40:
		_lineas_bitacora.remove_at(0)

func _unhandled_input(evento: InputEvent) -> void:
	if evento.is_action_pressed("toggle_activities") or evento.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		ActivitiesScreen.cerrar()
