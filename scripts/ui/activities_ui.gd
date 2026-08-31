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

## --- Pestaña de dinero ---
var _saldo: RichTextLabel
var _contexto_credito: RichTextLabel
var _a_quien: OptionButton
var _monto: SpinBox
var _prevision: RichTextLabel
var _resultado_prestamo: RichTextLabel
var _boton_pedir: Button

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
	# Two tabs behind one key: the week you spend and the money you spend it
	# with are the same decision, and splitting them across two screens would
	# hide the trade-off that makes both interesting.
	var pestanas := TabContainer.new()
	pestanas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	raiz.add_child(pestanas)

	var columnas := HBoxContainer.new()
	columnas.name = "Tiempo"
	columnas.add_theme_constant_override("separation", 16)
	columnas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pestanas.add_child(columnas)

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

	pestanas.add_child(_panel_dinero())

## The money tab: what you have, what your family might lend, and the ask.
func _panel_dinero() -> Control:
	var raiz := HBoxContainer.new()
	raiz.name = "Dinero"
	raiz.add_theme_constant_override("separation", 16)

	var izquierda := VBoxContainer.new()
	izquierda.custom_minimum_size = Vector2(520, 0)
	izquierda.add_theme_constant_override("separation", 10)
	raiz.add_child(izquierda)

	_saldo = RichTextLabel.new()
	_saldo.bbcode_enabled = true
	_saldo.fit_content = true
	_saldo.custom_minimum_size = Vector2(0, 30)
	izquierda.add_child(_saldo)

	_contexto_credito = RichTextLabel.new()
	_contexto_credito.bbcode_enabled = true
	_contexto_credito.fit_content = true
	_contexto_credito.custom_minimum_size = Vector2(0, 90)
	_contexto_credito.add_theme_stylebox_override("normal", _caja())
	izquierda.add_child(_contexto_credito)

	var fila_padre := HBoxContainer.new()
	izquierda.add_child(fila_padre)
	var etiqueta_padre := Label.new()
	etiqueta_padre.text = "¿A quién le pides?"
	etiqueta_padre.custom_minimum_size = Vector2(160, 0)
	fila_padre.add_child(etiqueta_padre)
	_a_quien = OptionButton.new()
	for padre_res in ParentRegistry.obtener_todos():
		var padre: ParentData = padre_res
		_a_quien.add_item(padre.nombre_display)
		_a_quien.set_item_metadata(_a_quien.item_count - 1, padre.id)
	_a_quien.item_selected.connect(func(_i): _refrescar_dinero())
	fila_padre.add_child(_a_quien)

	var fila_monto := HBoxContainer.new()
	izquierda.add_child(fila_monto)
	var etiqueta_monto := Label.new()
	etiqueta_monto.text = "¿Cuánto?"
	etiqueta_monto.custom_minimum_size = Vector2(160, 0)
	fila_monto.add_child(etiqueta_monto)
	_monto = SpinBox.new()
	_monto.min_value = 25.0
	_monto.max_value = 5000.0
	_monto.step = 25.0
	_monto.value = 200.0
	_monto.custom_minimum_size = Vector2(130, 0)
	_monto.value_changed.connect(func(_v): _refrescar_dinero())
	fila_monto.add_child(_monto)

	_prevision = RichTextLabel.new()
	_prevision.bbcode_enabled = true
	_prevision.fit_content = true
	_prevision.custom_minimum_size = Vector2(0, 76)
	izquierda.add_child(_prevision)

	_boton_pedir = Button.new()
	_boton_pedir.text = "Pedir el préstamo"
	_boton_pedir.pressed.connect(_pedir_prestamo)
	izquierda.add_child(_boton_pedir)

	_resultado_prestamo = RichTextLabel.new()
	_resultado_prestamo.bbcode_enabled = true
	_resultado_prestamo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resultado_prestamo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_resultado_prestamo.add_theme_stylebox_override("normal", _caja())
	_resultado_prestamo.text = "[i]Todavía no has pedido nada.[/i]"
	raiz.add_child(_resultado_prestamo)
	return raiz

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
	_refrescar_dinero()

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

# --- Money ------------------------------------------------------------------

func _padre_elegido() -> StringName:
	if _a_quien and _a_quien.selected >= 0:
		return _a_quien.get_selected_metadata()
	return FamilyCredit.mejor_pariente()

func _refrescar_dinero() -> void:
	if not _saldo:
		return
	_saldo.text = "[b]Tu dinero:[/b] %d propio   ·   %d de familia" % [
		int(Wallet.dinero_personal()), int(Wallet.dinero_familia())]

	var ubicacion: LocationData = PlayerOrigin.obtener_ubicacion()
	var padre_id: StringName = _padre_elegido()
	var maximo: float = FamilyCredit.monto_maximo(padre_id)
	_monto.max_value = maxf(maximo * 1.5, 100.0)

	var rechazos: int = FamilyCredit.rechazos_recientes()
	var t := PackedStringArray()
	if ubicacion:
		t.append("[b]%s[/b]: tu familia presta con %d%% de disposición base." % [
			ubicacion.nombre_display, int(round(ubicacion.facilidad_credito_familiar * 100.0))])
	else:
		t.append("[color=#ff8f8f]Sin lugar de nacimiento: no hay familia que pueda prestar.[/color]")
	t.append("Máximo que te darían ahora: [b]%d[/b]   ·   relación contigo: %s" % [
		int(maximo), InfoPolicy.describir_atributo(FamilyRelationship.obtener_nivel_relacion(padre_id))])
	if rechazos > 0:
		t.append("[color=#ffcc80]Te dijeron que no %d %s hace poco: la siguiente petición es más difícil.[/color]" % [
			rechazos, "vez" if rechazos == 1 else "veces"])
	_contexto_credito.text = "\n".join(t)

	# Live forecast straight from the engine's own evaluation, which is the
	# same object the real request returns - no second implementation.
	var prevision: LoanResult = FamilyCredit.evaluar(_monto.value, padre_id)
	_boton_pedir.disabled = prevision.motivo != &""
	if prevision.motivo != &"":
		_prevision.text = "[color=#ff8f8f]%s[/color]" % prevision.mensaje
		return
	var recorte := ""
	if prevision.recortado:
		recorte = "  [color=#ffcc80](te ofrecerían %d, no %d)[/color]" % [
			int(prevision.monto_evaluado), int(prevision.monto_solicitado)]
	_prevision.text = ("Probabilidad de que digan que sí: [b]%.0f%%[/b]%s\n" +
		"[color=#9aa0aa]responsabilidad %.2f · relación %+.2f · monto %+.2f · rechazos %.2f[/color]") % [
		prevision.probabilidad * 100.0, recorte, prevision.fit_responsabilidad,
		prevision.efecto_relacion, prevision.efecto_monto, -prevision.penalizacion_rechazos]

func _pedir_prestamo() -> void:
	var padre_id: StringName = _padre_elegido()
	var resultado: LoanResult = FamilyCredit.solicitar_prestamo(_monto.value, padre_id)
	_resultado_prestamo.text = _formatear_prestamo(resultado)
	var padre: ParentData = ParentRegistry.obtener(padre_id)
	var nombre: String = padre.nombre_display if padre else String(padre_id)
	if resultado.aprobado:
		_anotar("[color=#88ddaa][b]%s te prestó %d.[/b][/color]" % [nombre, int(resultado.monto_aprobado)])
	else:
		_anotar("[color=#ff8f8f]%s te dijo que no.[/color]" % nombre)
	_refrescar()

func _formatear_prestamo(r: LoanResult) -> String:
	var padre: ParentData = ParentRegistry.obtener(r.padre_id)
	var nombre: String = padre.nombre_display if padre else String(r.padre_id)
	var t := PackedStringArray()
	if r.motivo != &"":
		return "[color=#ff8f8f]%s[/color]" % r.mensaje

	if r.aprobado:
		t.append("[color=#88ddaa][b]%s dijo que sí: %d.[/b][/color]" % [nombre, int(r.monto_aprobado)])
		if r.recortado:
			t.append("Pediste %d y te dieron lo que había: %d." % [
				int(r.monto_solicitado), int(r.monto_aprobado)])
	else:
		t.append("[color=#ff8f8f][b]%s dijo que no.[/b][/color]" % nombre)
	t.append("")
	t.append("Tenías [b]%.0f%%[/b] de probabilidad y salió %.2f." % [r.probabilidad * 100.0, r.tirada])
	t.append("")
	t.append("[b]De dónde salió ese %.0f%%[/b]" % (r.probabilidad * 100.0))
	var ubicacion: LocationData = LocationRegistry.obtener(r.ubicacion_id)
	t.append("  disposición de tu familia en %s: %.2f" % [
		ubicacion.nombre_display if ubicacion else String(r.ubicacion_id), r.base_ubicacion])
	t.append("  responsabilidad que te ven:    %+.3f" % r.fit_responsabilidad)
	for atributo_id in r.contribuciones_atributo:
		var c: Dictionary = r.contribuciones_atributo[atributo_id]
		var definicion: AttributeDefinition = AttributeRegistry.get_definition(atributo_id)
		t.append("      [color=#9aa0aa]%-22s %s[/color]" % [
			definicion.nombre_display if definicion else String(atributo_id),
			InfoPolicy.describir_atributo(c["valor"])])
	t.append("  tu relación con %s:            %+.3f" % [nombre, r.efecto_relacion])
	t.append("  lo que pediste (%d de %d):     %+.3f" % [
		int(r.monto_evaluado), int(r.monto_maximo), r.efecto_monto])
	if r.penalizacion_rechazos > 0.0:
		t.append("  %d negativas recientes:        -%.3f" % [r.rechazos_recientes, r.penalizacion_rechazos])

	if not r.aprobado:
		t.append("")
		t.append("[b][color=#ffcc80]Qué te faltó[/color][/b]")
		for motivo in _diagnostico(r, nombre):
			t.append("  [color=#ffcc80]· %s[/color]" % motivo)
	return "\n".join(t)

## Turns a refusal into the two or three things the player could actually
## change, biggest first. A "no" that does not say why is a dead end.
func _diagnostico(r: LoanResult, nombre: String) -> Array[String]:
	var causas: Array = []
	if r.efecto_relacion < 0.0:
		causas.append([absf(r.efecto_relacion),
			"Tu relación con %s está por debajo de lo normal. Cena en casa, acuérdate de su cumpleaños." % nombre])
	if r.penalizacion_rechazos > 0.0:
		causas.append([r.penalizacion_rechazos,
			"Ya te dijeron que no %d %s hace poco. Deja pasar unas semanas." % [
				r.rechazos_recientes, "vez" if r.rechazos_recientes == 1 else "veces"]])
	var config: CreditConfig = FamilyCredit.obtener_config()
	if r.fit_responsabilidad < config.fit_referencia:
		causas.append([config.fit_referencia - r.fit_responsabilidad,
			"No te ven lo bastante responsable todavía: pesan tus notas, tu organización y tu carácter."])
	if absf(r.efecto_monto) > 0.15:
		causas.append([absf(r.efecto_monto),
			"Pediste %d de los %d que pueden dar. Pedir menos es mucho más fácil." % [
				int(r.monto_evaluado), int(r.monto_maximo)]])
	causas.sort_custom(func(a, b): return a[0] > b[0])
	var salida: Array[String] = []
	for causa in causas.slice(0, 3):
		salida.append(causa[1])
	if salida.is_empty():
		salida.append("Nada en particular: tenías %.0f%% y la suerte no acompañó. Vuelve a intentarlo." % [
			r.probabilidad * 100.0])
	return salida
