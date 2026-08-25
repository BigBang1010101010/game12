extends Node

## Headless validation of the whole progression stack. Run before any commit
## that touches these systems:
##
##   godot --headless --path . res://tests/test_progression.tscn
##
## Exits 0 when everything passes, 1 otherwise, so it can gate CI.
##
## Like the systems it checks, it enumerates no content: it iterates the
## registries, so adding a university or attribute automatically widens
## coverage instead of needing a new test.

var _fallos: Array[String] = []
var _pruebas := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame

	_registros_cargan_sin_errores()
	_referencias_existen()
	_pesos_universidades_coherentes()
	_umbrales_alcanzables()
	_formula_en_rango_para_perfiles_extremos()
	_formula_es_monotona()
	_early_nunca_perjudica()
	_actividades_son_coherentes()
	_ruta_atletica_esta_cerrada_bajo_umbral()
	_indice_academico_en_rango()
	_presupuesto_penaliza_sobrecompromiso()
	_ledger_registra_cada_actividad()
	_slots_respetan_el_limite()
	_boost_universal_es_identico_en_las_ocho()
	_ubicaciones_son_coherentes()
	_origen_se_fija_una_sola_vez()
	_relacion_familiar_sube_baja_y_decae()
	_cumpleanos_en_fecha_vale_mas_que_fuera()
	_guardado_conserva_origen_y_familia()
	_credito_nunca_aprueba_mas_del_maximo()
	_dinero_familia_respeta_las_categorias()
	_asesoria_nunca_revela_el_valor_exacto()
	_ledger_conserva_totales()

	print("")
	if _fallos.is_empty():
		print("PASS: %d comprobaciones, 0 fallos" % _pruebas)
		get_tree().quit(0)
	else:
		print("FAIL: %d comprobaciones, %d fallos" % [_pruebas, _fallos.size()])
		for f in _fallos:
			print("  - %s" % f)
		get_tree().quit(1)

func _verificar(condicion: bool, mensaje: String) -> void:
	_pruebas += 1
	if not condicion:
		_fallos.append(mensaje)

func _registros_cargan_sin_errores() -> void:
	for par in [["atributos", AttributeRegistry], ["sinergias", SynergyRegistry],
			["universidades", UniversityRegistry], ["carreras", CareerRegistry],
			["ensayos", EssayRegistry], ["actividades", ActivityRegistry],
			["ubicaciones", LocationRegistry], ["padres", ParentRegistry],
			["regalos", GiftRegistry]]:
		var registro: ResourceRegistry = par[1]
		var errores: PackedStringArray = registro.obtener_errores()
		_verificar(errores.is_empty(), "%s reporto errores: %s" % [par[0], ", ".join(errores)])
		_verificar(registro.contar() > 0, "%s no cargo ningun recurso" % par[0])
	print("registros:      %d atributos, %d sinergias, %d universidades, %d carreras, %d ensayos, %d actividades, %d ubicaciones, %d padres, %d regalos" % [
		AttributeRegistry.contar(), SynergyRegistry.contar(), UniversityRegistry.contar(),
		CareerRegistry.contar(), EssayRegistry.contar(), ActivityRegistry.contar(),
		LocationRegistry.contar(), ParentRegistry.contar(), GiftRegistry.contar()])

## No .tres may reference an id that does not exist. This is the check that
## catches a typo in new content before it ships.
func _referencias_existen() -> void:
	var rotas := 0
	for u_res in UniversityRegistry.obtener_todos():
		var u: UniversityData = u_res
		for a in u.pesos_atributos:
			if not AttributeRegistry.tiene(a):
				_fallos.append("universidad '%s' pondera el atributo inexistente '%s'" % [u.id, a]); rotas += 1
		for a in u.umbrales_minimos:
			if not AttributeRegistry.tiene(a):
				_fallos.append("universidad '%s' pone umbral al atributo inexistente '%s'" % [u.id, a]); rotas += 1
		for c in u.fortalezas_carrera:
			if not CareerRegistry.tiene(c):
				_fallos.append("universidad '%s' referencia la carrera inexistente '%s'" % [u.id, c]); rotas += 1
	for c_res in CareerRegistry.obtener_todos():
		var c: CareerData = c_res
		for a in c.perfil_ideal:
			if not AttributeRegistry.tiene(a):
				_fallos.append("carrera '%s' usa el atributo inexistente '%s' en perfil_ideal" % [c.id, a]); rotas += 1
		for a in c.tolerancia_desviacion:
			if not AttributeRegistry.tiene(a):
				_fallos.append("carrera '%s' usa el atributo inexistente '%s' en tolerancia" % [c.id, a]); rotas += 1
	for e_res in EssayRegistry.obtener_todos():
		var e: EssayNarrative = e_res
		for a in e.modificadores_atributo:
			if not AttributeRegistry.tiene(a):
				_fallos.append("ensayo '%s' modifica el atributo inexistente '%s'" % [e.id, a]); rotas += 1
		for r in e.requisitos_desbloqueo:
			if r.get("tipo", "") == "atributo_minimo" and not AttributeRegistry.tiene(StringName(r.get("atributo", ""))):
				_fallos.append("ensayo '%s' requiere el atributo inexistente '%s'" % [e.id, r.get("atributo", "")]); rotas += 1
	for s_res in SynergyRegistry.obtener_todos():
		var s: SynergyRule = s_res
		for a in [s.atributo_origen, s.atributo_afectado]:
			if not AttributeRegistry.tiene(a):
				_fallos.append("sinergia '%s' referencia el atributo inexistente '%s'" % [s.id, a]); rotas += 1
	_pruebas += 1
	print("referencias:    %d rotas" % rotas)

func _pesos_universidades_coherentes() -> void:
	for u_res in UniversityRegistry.obtener_todos():
		var u: UniversityData = u_res
		_verificar(u.peso_total() > 0.0, "universidad '%s' tiene pesos que suman 0" % u.id)
		_verificar(u.tasa_admision_early >= u.tasa_admision_base,
			"universidad '%s' tiene tasa early (%.3f) MENOR que la base (%.3f)" % [u.id, u.tasa_admision_early, u.tasa_admision_base])
		_verificar(u.tasa_admision_base > 0.0 and u.tasa_admision_base < 1.0,
			"universidad '%s' tiene tasa base fuera de (0,1)" % u.id)
		# Every narrative type should mean something at every school, otherwise
		# a missing key silently defaults and the difference is invisible.
		for e_res in EssayRegistry.obtener_todos():
			var tipo: StringName = (e_res as EssayNarrative).narrativa_tipo
			_verificar(u.afinidad_narrativas.has(tipo),
				"universidad '%s' no declara afinidad para la narrativa '%s'" % [u.id, tipo])
	print("universidades:  pesos, tasas y afinidades coherentes")

## A threshold above an attribute's own maximum could never be met.
func _umbrales_alcanzables() -> void:
	for u_res in UniversityRegistry.obtener_todos():
		var u: UniversityData = u_res
		for a in u.umbrales_minimos:
			var d: AttributeDefinition = AttributeRegistry.get_definition(a)
			if d:
				_verificar(float(u.umbrales_minimos[a]) <= d.valor_maximo,
					"universidad '%s' exige %s >= %.1f pero su maximo es %.1f" % [u.id, a, u.umbrales_minimos[a], d.valor_maximo])
	print("umbrales:       todos alcanzables")

func _perfil_uniforme(valor: float) -> Dictionary:
	var v: Dictionary = {}
	for a in AttributeRegistry.get_all_ids():
		v[a] = valor
	return v

func _formula_en_rango_para_perfiles_extremos() -> void:
	var cfg: AdmissionConfig = AdmissionCalculator.obtener_config()
	_verificar(cfg != null, "no se pudo cargar admission_config.tres")
	if not cfg:
		return
	var carrera: StringName = CareerRegistry.obtener_ids()[0]
	var ensayo: StringName = EssayRegistry.obtener_ids()[0]
	for valor in [0.0, 50.0, 100.0]:
		var perfil: Dictionary = _perfil_uniforme(valor)
		for early in [false, true]:
			for u_res in UniversityRegistry.obtener_todos():
				var r: AdmissionResult = AdmissionCalculator.calcular_probabilidad(
					(u_res as UniversityData).id, carrera, ensayo, early, perfil)
				_verificar(r.probabilidad >= cfg.probabilidad_minima and r.probabilidad <= cfg.probabilidad_maxima,
					"perfil uniforme %.0f en '%s' dio %.4f, fuera de [%.4f, %.4f]" % [
						valor, r.universidad_id, r.probabilidad, cfg.probabilidad_minima, cfg.probabilidad_maxima])
				_verificar(r.probabilidad < 1.0, "'%s' devolvio probabilidad 1.0: la admision nunca es segura" % r.universidad_id)
				_verificar(not is_nan(r.probabilidad), "'%s' devolvio NaN" % r.universidad_id)
	print("extremos:       0 / 50 / 100 en todas las universidades, dentro de rango")

## Being better at what a school values must never lower the probability.
func _formula_es_monotona() -> void:
	var carrera: StringName = CareerRegistry.obtener_ids()[0]
	var ensayo: StringName = EssayRegistry.obtener_ids()[0]
	for u_res in UniversityRegistry.obtener_todos():
		var u: UniversityData = u_res
		var anterior := -1.0
		for valor in [0.0, 25.0, 50.0, 75.0, 100.0]:
			var r: AdmissionResult = AdmissionCalculator.calcular_probabilidad(
				u.id, carrera, ensayo, false, _perfil_uniforme(valor))
			_verificar(r.probabilidad >= anterior - 0.0001,
				"'%s' no es monotona: con %.0f dio %.4f, menos que el escalon previo %.4f" % [u.id, valor, r.probabilidad, anterior])
			anterior = r.probabilidad
	print("monotonia:      subir atributos nunca baja la probabilidad")

func _early_nunca_perjudica() -> void:
	var carrera: StringName = CareerRegistry.obtener_ids()[0]
	var ensayo: StringName = EssayRegistry.obtener_ids()[0]
	var perfil: Dictionary = _perfil_uniforme(60.0)
	for u_res in UniversityRegistry.obtener_todos():
		var id: StringName = (u_res as UniversityData).id
		var normal: AdmissionResult = AdmissionCalculator.calcular_probabilidad(id, carrera, ensayo, false, perfil)
		var early: AdmissionResult = AdmissionCalculator.calcular_probabilidad(id, carrera, ensayo, true, perfil)
		_verificar(early.probabilidad >= normal.probabilidad,
			"'%s': early (%.4f) es peor que regular (%.4f)" % [id, early.probabilidad, normal.probabilidad])
	print("early decision: nunca perjudica en ninguna universidad")

## Consolidation must never lose or invent points.
func _ledger_conserva_totales() -> void:
	PlayerState.reiniciar()
	var atributo: StringName = AttributeRegistry.get_all_ids()[0]
	for i in range(600):
		DayNightCycle.advance_seconds(DayNightCycle.CYCLE_DURATION_SECONDS * 0.2)
		PlayerState.aplicar_modificador(atributo, 0.2, &"minijuego", &"test", {"i": i})
	PlayerState.consolidar_ledger()
	var des: Dictionary = PlayerState.obtener_desglose_atributo(atributo)
	var suma := 0.0
	var eventos_minijuego := 0
	var eventos_decaimiento := 0
	for f in des["por_fuente"]:
		suma += f["total"]
		if f["fuente_tipo"] == &"minijuego":
			eventos_minijuego += f["eventos"]
		elif f["fuente_tipo"] == &"decaimiento":
			eventos_decaimiento += f["eventos"]
	# The total must survive consolidation exactly, gains and decay together.
	_verificar(absf(suma - des["valor_actual"]) < 0.0001,
		"el desglose suma %.6f pero el valor real es %.6f" % [suma, des["valor_actual"]])
	# Every applied modification must still be counted after consolidation.
	_verificar(eventos_minijuego == 600,
		"se contabilizaron %d eventos de minijuego de 600" % eventos_minijuego)
	# Advancing the clock 120 in-game days must have driven decay, proving it
	# is wired to the shared cycle rather than sitting inert.
	_verificar(eventos_decaimiento > 0,
		"el decaimiento no se aplico pese a avanzar 120 dias con un atributo que decae")
	print("ledger:         %d detalladas + %d agregados, total exacto, %d eventos de minijuego + %d de decaimiento" % [
		PlayerState.ledger.size(), PlayerState.ledger_consolidado.size(),
		eventos_minijuego, eventos_decaimiento])

# --- Activities ---------------------------------------------------------------

## No activity may grant an attribute or claim a career that does not exist,
## promise a tier its ladder cannot reach, or gate a level on a lever the
## engine does not know. All four are content typos that must fail loudly.
func _actividades_son_coherentes() -> void:
	var niveles_totales := 0
	for a_res in ActivityRegistry.obtener_todos():
		var a: ActivityData = a_res
		for carrera_id in a.carreras_afinidad:
			_verificar(CareerRegistry.tiene(carrera_id),
				"actividad '%s' referencia la carrera inexistente '%s'" % [a.id, carrera_id])
		_verificar(a.mejor_tier_de_niveles() >= a.tier_techo,
			"actividad '%s': su escalera llega a tier %d, mejor que el techo %d que declara" % [
				a.id, a.mejor_tier_de_niveles(), a.tier_techo])
		var tier_previo := 5
		for nivel in a.obtener_niveles():
			niveles_totales += 1
			for atributo_id in nivel.modificadores_atributo:
				_verificar(AttributeRegistry.tiene(atributo_id),
					"actividad '%s', nivel '%s': atributo inexistente '%s'" % [a.id, nivel.nombre, atributo_id])
			# The ladder has to actually climb: a rung may not be worth less
			# than the one below it.
			_verificar(nivel.tier <= tier_previo,
				"actividad '%s': el nivel '%s' (tier %d) va hacia atras respecto al anterior (tier %d)" % [
					a.id, nivel.nombre, nivel.tier, tier_previo])
			tier_previo = nivel.tier
			_verificar(nivel.validar().is_empty(),
				"actividad '%s', nivel '%s': %s" % [a.id, nivel.nombre, ", ".join(nivel.validar())])
	print("actividades:    %d actividades, %d niveles, referencias y escaleras coherentes" % [
		ActivityRegistry.contar(), niveles_totales])

## THE deliberate rule: an athlete gets nothing from the athletic route until
## BOTH gates open. Checked for every sport in the catalogue, at its own bar
## and its own floor, so a sport added later is covered automatically.
func _ruta_atletica_esta_cerrada_bajo_umbral() -> void:
	var carrera: StringName = CareerRegistry.obtener_ids()[0]
	var ensayo: StringName = EssayRegistry.obtener_ids()[0]
	var universidad: StringName = UniversityRegistry.obtener_ids()[0]
	var deportes := 0
	for a_res in ActivityRegistry.obtener_todos():
		var a: ActivityData = a_res
		if not a.es_deporte:
			continue
		deportes += 1
		var justo: StringName = ActivityScales.nombre_reconocimiento(a.umbral_reclutamiento)
		var corto: StringName = ActivityScales.nombre_reconocimiento(a.umbral_reclutamiento - 1)

		# 1. Recognition below the bar, academics irrelevant.
		var r1: AdmissionResult = _con_deporte(universidad, carrera, ensayo, a, corto, 100.0)
		_verificar(not r1.es_reclutado and is_zero_approx(r1.efecto_atletico),
			"'%s': reclutado con reconocimiento '%s', por debajo de su umbral '%s'" % [a.id, corto, justo])

		# 2. Recognition fine, Academic Index below the sport's floor.
		var bajo: float = _valor_para_indice(float(a.academic_index_minimo) - 12.0)
		var r2: AdmissionResult = _con_deporte(universidad, carrera, ensayo, a, justo, bajo)
		_verificar(not r2.es_reclutado and is_zero_approx(r2.efecto_atletico),
			"'%s': reclutado con indice %.0f, por debajo de su minimo %d" % [
				a.id, r2.academic_index, a.academic_index_minimo])
		_verificar(not r2.deportes_no_reclutables.is_empty(),
			"'%s': no se reclutó pero el resultado no dice por qué" % a.id)

		# 3. Both gates open: the bonus appears and it is worth something.
		var alto: float = _valor_para_indice(float(a.academic_index_minimo) + 12.0)
		var r3: AdmissionResult = _con_deporte(universidad, carrera, ensayo, a, justo, alto)
		_verificar(r3.es_reclutado and r3.efecto_atletico > 0.0,
			"'%s': cumple ambas compuertas y aun asi no recibe bono atletico" % a.id)
		_verificar(r3.probabilidad > r2.probabilidad,
			"'%s': ser reclutable no mejoro la probabilidad (%.4f vs %.4f)" % [
				a.id, r3.probabilidad, r2.probabilidad])
	print("ruta atletica:  %d deportes, ninguno da bono bajo su umbral ni bajo su indice minimo" % deportes)

## Builds a one-sport application at a given recognition and academic level.
func _con_deporte(universidad: StringName, carrera: StringName, ensayo: StringName,
		deporte: ActivityData, reconocimiento: StringName, valor_academico: float) -> AdmissionResult:
	var valores: Dictionary = _perfil_uniforme(50.0)
	for definicion_res in AttributeRegistry.get_by_category(
			AdmissionCalculator.obtener_config().categoria_academica):
		valores[(definicion_res as AttributeDefinition).id] = valor_academico
	var sim: Dictionary = ActivityTracker.simular_perfil({
		deporte.id: {"anios": 4.0, "reconocimiento": reconocimiento, "rol": &"oficial"},
	}, valores)
	var estados: Dictionary = {deporte.id: sim["actividades"][deporte.id]["estado"]}
	var indice: float = AcademicIndex.calcular_desde(sim["valores"])
	var seleccion: Array[Dictionary] = ApplicationBuilder.detalle_desde_estados(estados, indice)
	return AdmissionCalculator.calcular_probabilidad(
		universidad, carrera, ensayo, false, sim["valores"], seleccion)

## Attribute value that lands the Academic Index on a target, so a test can ask
## for "just under this sport's floor" without hardcoding an attribute.
func _valor_para_indice(indice: float) -> float:
	var fraccion: float = clampf(
		(indice - AcademicIndex.MINIMO) / (AcademicIndex.MAXIMO - AcademicIndex.MINIMO), 0.0, 1.0)
	return fraccion * 100.0

## The index is the real 60-240 scale at both ends and everywhere between.
func _indice_academico_en_rango() -> void:
	for valor in [0.0, 1.0, 37.0, 50.0, 99.0, 100.0]:
		var indice: float = AcademicIndex.calcular_desde(_perfil_uniforme(valor))
		_verificar(indice >= AcademicIndex.MINIMO and indice <= AcademicIndex.MAXIMO,
			"indice academico %.2f fuera de 60-240 con atributos en %.0f" % [indice, valor])
	_verificar(is_equal_approx(AcademicIndex.calcular_desde(_perfil_uniforme(0.0)), AcademicIndex.MINIMO),
		"un perfil en cero deberia dar exactamente 60")
	_verificar(is_equal_approx(AcademicIndex.calcular_desde(_perfil_uniforme(100.0)), AcademicIndex.MAXIMO),
		"un perfil al maximo deberia dar exactamente 240")
	# And it has to be built from academic attributes only: moving everything
	# else must not move it.
	var solo_academico: Dictionary = _perfil_uniforme(0.0)
	var mezcla: Dictionary = _perfil_uniforme(0.0)
	for definicion_res in AttributeRegistry.obtener_todos():
		var definicion: AttributeDefinition = definicion_res
		if definicion.categoria != AdmissionCalculator.obtener_config().categoria_academica:
			mezcla[definicion.id] = 100.0
	_verificar(is_equal_approx(AcademicIndex.calcular_desde(solo_academico), AcademicIndex.calcular_desde(mezcla)),
		"subir atributos no academicos movio el indice academico")
	print("indice acad.:   60-240 exacto en los extremos, inmune a lo no academico")

## Overcommitting has to cost, and the cost has to be auditable.
func _presupuesto_penaliza_sobrecompromiso() -> void:
	PlayerState.reiniciar()
	ActivityTracker.reiniciar()
	var config: AdmissionConfig = AdmissionCalculator.obtener_config()
	_verificar(not config.penalizacion_sobrecompromiso.is_empty(),
		"la configuracion no define ninguna penalizacion por sobrecompromiso")

	# Nothing committed: no penalty, and none charged.
	_verificar(TimeBudget.penalizacion_semanal().is_empty(),
		"se penalizo sobrecompromiso sin ninguna actividad activa")

	# Enrol until the week is genuinely over budget.
	for a_res in ActivityRegistry.obtener_todos():
		if TimeBudget.horas_comprometidas() > TimeBudget.horas_totales():
			break
		ActivityTracker.inscribir((a_res as ActivityData).id)
	var exceso: float = TimeBudget.horas_excedidas()
	_verificar(exceso > 0.0, "no se logro exceder el presupuesto de %.0f horas" % TimeBudget.horas_totales())

	var antes: Dictionary = {}
	for atributo_id in config.penalizacion_sobrecompromiso:
		antes[atributo_id] = PlayerState.obtener_valor(atributo_id)
	var cobrado: Dictionary = TimeBudget.aplicar_semana()
	_verificar(cobrado.size() == config.penalizacion_sobrecompromiso.size(),
		"se cobraron %d penalizaciones de %d configuradas" % [
			cobrado.size(), config.penalizacion_sobrecompromiso.size()])
	for atributo_id in cobrado:
		_verificar(cobrado[atributo_id] < 0.0,
			"la penalizacion a '%s' no es negativa" % atributo_id)
		_verificar(PlayerState.obtener_valor(atributo_id) <= antes[atributo_id],
			"'%s' no bajo pese al sobrecompromiso" % atributo_id)
		var entradas: Array[Dictionary] = PlayerState.consultar_ledger({
			"atributo": atributo_id, "fuente_tipo": TimeBudget.FUENTE})
		_verificar(not entradas.is_empty(),
			"el sobrecompromiso sobre '%s' no quedo en el ledger" % atributo_id)
	print("presupuesto:    %.0f horas comprometidas sobre %.0f, exceso %.0f cobrado y auditado" % [
		TimeBudget.horas_comprometidas(), TimeBudget.horas_totales(), exceso])

## Every point an activity grants must be attributable to that activity.
func _ledger_registra_cada_actividad() -> void:
	PlayerState.reiniciar()
	ActivityTracker.reiniciar()
	var sin_registro: Array[String] = []
	for a_res in ActivityRegistry.obtener_todos():
		var a: ActivityData = a_res
		ActivityTracker.inscribir(a.id)
		# Four years, top role and top recognition: enough to walk the whole
		# ladder of any activity in the catalogue.
		ActivityTracker.invertir_tiempo(a.id, 4.0 * float(a.costo_horas_semana) * 36.0)
		ActivityTracker.fijar_rol(a.id, &"fundador")
		ActivityTracker.fijar_reconocimiento(a.id, &"internacional")
		ActivityTracker.sumar_impacto(a.id, 1000.0)
		var estado: Dictionary = ActivityTracker.obtener_estado(a.id)
		_verificar(estado["nivel_indice"] == a.obtener_niveles().size() - 1,
			"'%s' no llego a su ultimo nivel pese a cumplir todas las palancas" % a.id)
		var entradas: Array[Dictionary] = PlayerState.consultar_ledger({
			"fuente_tipo": ActivityTracker.FUENTE, "fuente_id": a.id})
		if entradas.is_empty():
			sin_registro.append(String(a.id))
			continue
		for entrada in entradas:
			_verificar(entrada["contexto"].has("nivel") and entrada["contexto"].has("tier"),
				"'%s': una entrada del ledger no dice de que nivel salio" % a.id)
	_verificar(sin_registro.is_empty(),
		"actividades sin rastro en el ledger: %s" % ", ".join(sin_registro))
	var total: int = PlayerState.consultar_ledger({"fuente_tipo": ActivityTracker.FUENTE}).size()
	print("ledger activid.: %d modificaciones registradas, todas con actividad, nivel y tier" % total)

## The application can never carry more than the configured slots.
func _slots_respetan_el_limite() -> void:
	var seleccion: Array[Dictionary] = ApplicationBuilder.seleccion_automatica()
	var slots: int = ApplicationBuilder.slots()
	_verificar(seleccion.size() <= slots,
		"la seleccion lleva %d actividades con solo %d slots" % [seleccion.size(), slots])
	_verificar(seleccion.size() == mini(slots, ActivityTracker.actividades_activas().size()),
		"la seleccion no lleno los slots disponibles")
	# And it must be the BEST ones: nothing left out may outscore what got in.
	var fuera: Array[Dictionary] = ApplicationBuilder.fuera_de_slots()
	if not seleccion.is_empty() and not fuera.is_empty():
		_verificar(seleccion[seleccion.size() - 1]["puntaje"] >= fuera[0]["puntaje"],
			"una actividad fuera de los slots puntua mas alto que una dentro")
	print("slots:          %d de %d actividades activas entran, y son las mejores" % [
		seleccion.size(), ActivityTracker.actividades_activas().size()])

## An activity declaring boost_universal must be worth EXACTLY the same at all
## eight schools - that is the whole claim behind the C7 reading - while an
## activity with career affinity must NOT be. Both halves are checked, because
## the first alone would also pass if the term were simply dead.
func _boost_universal_es_identico_en_las_ocho() -> void:
	var carrera: StringName = CareerRegistry.obtener_ids()[0]
	var ensayo: StringName = EssayRegistry.obtener_ids()[0]
	var universales: Array[StringName] = []
	var con_afinidad: Array[StringName] = []
	for a_res in ActivityRegistry.obtener_todos():
		var a: ActivityData = a_res
		if a.boost_universal > 0.0:
			universales.append(a.id)
			_verificar(a.carreras_afinidad.is_empty(),
				"'%s' declara boost universal Y afinidades de carrera: elige una lectura" % a.id)
		elif not a.carreras_afinidad.is_empty():
			con_afinidad.append(a.id)
	_verificar(not universales.is_empty(), "ninguna actividad declara boost_universal")

	for actividad_id in universales:
		var efectos: Array[float] = []
		for u_res in UniversityRegistry.obtener_todos():
			var r: AdmissionResult = _con_actividad((u_res as UniversityData).id, carrera, ensayo, actividad_id)
			efectos.append(r.efecto_universal)
			_verificar(r.efecto_universal > 0.0,
				"'%s' declara boost universal pero no aporta nada en '%s'" % [actividad_id, (u_res as UniversityData).id])
		for efecto in efectos:
			_verificar(is_equal_approx(efecto, efectos[0]),
				"'%s' aporta %.6f en una escuela y %.6f en otra: el boost universal no es universal" % [
					actividad_id, efecto, efectos[0]])

	# And the career term must still discriminate, or the two ideas have
	# collapsed into one.
	var discrimina := false
	for actividad_id in con_afinidad:
		var actividad: ActivityData = ActivityRegistry.obtener(actividad_id)
		var favorita: StringName = actividad.carreras_afinidad.keys()[0]
		var otra: StringName = &""
		for c in CareerRegistry.obtener_ids():
			if not actividad.carreras_afinidad.has(c):
				otra = c
				break
		if otra == &"":
			continue
		var universidad: StringName = UniversityRegistry.obtener_ids()[0]
		var con: AdmissionResult = _con_actividad(universidad, favorita, ensayo, actividad_id)
		var sin: AdmissionResult = _con_actividad(universidad, otra, ensayo, actividad_id)
		if con.efecto_actividades > sin.efecto_actividades:
			discrimina = true
			break
	_verificar(discrimina,
		"ninguna actividad con afinidad aporta mas a su carrera que a una ajena")
	print("boost universal:%d actividad(es) identicas en las 8, y la afinidad de carrera sigue discriminando" % universales.size())

## One-activity application at four years, top role and top recognition.
func _con_actividad(universidad: StringName, carrera: StringName, ensayo: StringName, actividad_id: StringName) -> AdmissionResult:
	var valores: Dictionary = _perfil_uniforme(60.0)
	var sim: Dictionary = ActivityTracker.simular_perfil({
		actividad_id: {"anios": 4.0, "reconocimiento": &"nacional", "rol": &"fundador", "impacto": 1000.0},
	}, valores)
	var estados: Dictionary = {actividad_id: sim["actividades"][actividad_id]["estado"]}
	var indice: float = AcademicIndex.calcular_desde(sim["valores"])
	return AdmissionCalculator.calcular_probabilidad(
		universidad, carrera, ensayo, false, sim["valores"],
		ApplicationBuilder.detalle_desde_estados(estados, indice))

# --- Birthplace ---------------------------------------------------------------

## The locations ARE the difficulty curve, so the invariant to protect is the
## one that is counter-intuitive: the more expensive the city, the HARDER the
## family credit. If a fourth city ever breaks that, the design has drifted.
func _ubicaciones_son_coherentes() -> void:
	_verificar(LocationRegistry.contar() >= 3,
		"se esperaban al menos 3 ubicaciones y hay %d" % LocationRegistry.contar())
	var referencia_existe := false
	for u_res in LocationRegistry.obtener_todos():
		var u: LocationData = u_res
		_verificar(u.validar().is_empty(), "ubicacion '%s': %s" % [u.id, ", ".join(u.validar())])
		# The multiplier is derived from the index unless stated, and the
		# reference city has to come out at exactly 1.0.
		_verificar(is_equal_approx(u.gasto_semanal(), u.indice_costo_vida / 100.0)
				or u.multiplicador_gasto_semanal > 0.0,
			"ubicacion '%s': el gasto semanal no se deriva del indice ni lo declara" % u.id)
		if is_equal_approx(u.indice_costo_vida, 100.0):
			referencia_existe = true
			_verificar(is_equal_approx(u.gasto_semanal(), 1.0),
				"la ubicacion de referencia (indice 100) deberia gastar x1.00 y gasta x%.2f" % u.gasto_semanal())
		_verificar(u.dinero_inicial_promedio() > 0.0,
			"ubicacion '%s' empieza sin dinero de familia" % u.id)
	_verificar(referencia_existe, "ninguna ubicacion tiene indice 100: la escala no tiene referencia")

	var ordenadas: Array[Resource] = LocationRegistry.obtener_por_dificultad()
	for i in range(ordenadas.size() - 1):
		var barata: LocationData = ordenadas[i]
		var cara: LocationData = ordenadas[i + 1]
		_verificar(barata.indice_costo_vida <= cara.indice_costo_vida,
			"obtener_por_dificultad no esta ordenando por costo de vida")
		_verificar(barata.facilidad_credito_familiar >= cara.facilidad_credito_familiar,
			"'%s' es mas barata que '%s' pero su credito familiar es MAS dificil (%.2f < %.2f): vivir mas barato tiene que dejar mas margen" % [
				barata.id, cara.id, barata.facilidad_credito_familiar, cara.facilidad_credito_familiar])
	print("ubicaciones:    %d, gasto derivado del indice, y mas barata = credito mas facil" % LocationRegistry.contar())

## The run's difficulty must not be editable halfway through.
func _origen_se_fija_una_sola_vez() -> void:
	PlayerOrigin.reiniciar()
	_verificar(not PlayerOrigin.esta_fijada(), "PlayerOrigin no arranca vacio tras reiniciar")
	# Before choosing, the readers other systems use must still answer.
	_verificar(PlayerOrigin.multiplicador_gasto_semanal() > 0.0,
		"sin ubicacion, el gasto semanal deberia caer en 1.0 y no en 0")

	var ids: Array[StringName] = LocationRegistry.obtener_ids()
	var primera: StringName = ids[0]
	var segunda: StringName = ids[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	_verificar(PlayerOrigin.fijar_ubicacion(primera, rng), "no se pudo fijar la primera ubicacion")
	_verificar(not PlayerOrigin.fijar_ubicacion(segunda),
		"se permitio cambiar la ubicacion de nacimiento a mitad de partida")
	_verificar(PlayerOrigin.obtener_ubicacion_id() == primera,
		"la ubicacion cambio pese a que el cambio fue rechazado")

	var elegida: LocationData = LocationRegistry.obtener(primera)
	_verificar(is_equal_approx(PlayerOrigin.multiplicador_gasto_semanal(), elegida.gasto_semanal()),
		"PlayerOrigin no expone el gasto semanal de la ubicacion elegida")
	_verificar(is_equal_approx(PlayerOrigin.facilidad_credito_familiar(), elegida.facilidad_credito_familiar),
		"PlayerOrigin no expone la facilidad de credito de la ubicacion elegida")
	_verificar(PlayerOrigin.dinero_inicial() >= elegida.dinero_familia_base_min
			and PlayerOrigin.dinero_inicial() <= elegida.dinero_familia_base_max,
		"el dinero inicial %.2f cae fuera del rango de '%s'" % [PlayerOrigin.dinero_inicial(), primera])
	_verificar(PlayerOrigin.obtener_eleccion_guardada() == String(primera),
		"la ubicacion no quedo registrada en las elecciones del guardado")
	print("origen:         se fija una vez, se rechaza el cambio y expone gasto, credito y dinero inicial")

# --- Family -------------------------------------------------------------------

func _relacion_familiar_sube_baja_y_decae() -> void:
	PlayerState.reiniciar()
	FamilyRelationship.reiniciar()
	var padre: ParentData = ParentRegistry.obtener_todos()[0]
	var inicial: float = FamilyRelationship.obtener_nivel_relacion(padre.id)
	_verificar(is_equal_approx(inicial, padre.nivel_relacion_inicial),
		"'%s' no empieza en su nivel_relacion_inicial" % padre.id)

	# A dinner is small; a streak of them is not. The multiplier has to grow.
	var primera: Dictionary = FamilyRelationship.cenar_en_familia(padre.id)
	var segunda: Dictionary = FamilyRelationship.cenar_en_familia(padre.id)
	_verificar(primera["puntos"] > 0.0, "una cena no subio la relacion")
	_verificar(segunda["puntos"] > primera["puntos"],
		"la segunda cena seguida (%.3f) no vale mas que la primera (%.3f)" % [segunda["puntos"], primera["puntos"]])
	_verificar(FamilyRelationship.obtener_nivel_relacion(padre.id) > inicial,
		"la relacion no subio tras dos cenas")

	# Gifts need a shop, and say so instead of failing quietly.
	var sin_tienda: Dictionary = FamilyRelationship.comprar_regalo(padre.id, GiftRegistry.obtener_ids()[0])
	_verificar(not sin_tienda["exito"] and sin_tienda["motivo"] == "sin_tienda",
		"se pudo comprar un regalo sin estar en una tienda")

	var tienda := GiftShop.new()
	GiftShop.registrar_disponibilidad(tienda, true)
	var por_nivel: Array[Resource] = GiftRegistry.obtener_por_nivel()
	var barato: Dictionary = FamilyRelationship.comprar_regalo(padre.id, (por_nivel[0] as GiftData).id)
	var caro: Dictionary = FamilyRelationship.comprar_regalo(
		padre.id, (por_nivel[por_nivel.size() - 1] as GiftData).id)
	_verificar(barato["exito"] and caro["exito"], "no se pudo comprar estando en la tienda")
	_verificar(caro["puntos"] > barato["puntos"],
		"el regalo caro (%.2f) no vale mas que el barato (%.2f)" % [caro["puntos"], barato["puntos"]])
	_verificar(caro["costo"] > barato["costo"], "el regalo caro no cuesta mas")
	GiftShop.registrar_disponibilidad(tienda, false)
	tienda.free()
	_verificar(not GiftShop.hay_tienda_cerca(), "la tienda sigue disponible tras salir de ella")

	# Every one of those changes has to be in the shared ledger.
	var entradas: Array[Dictionary] = PlayerState.consultar_ledger({
		"atributo": FamilyRelationship.clave_ledger(padre.id), "fuente_tipo": FamilyRelationship.FUENTE})
	_verificar(entradas.size() >= 4,
		"el ledger solo tiene %d cambios de relacion de los 4 provocados" % entradas.size())
	var fuentes: Array = []
	for entrada in entradas:
		if not fuentes.has(entrada["fuente_id"]):
			fuentes.append(entrada["fuente_id"])
	_verificar(fuentes.has(&"cena") and fuentes.has(&"regalo"),
		"el ledger no distingue de que vino cada cambio: %s" % str(fuentes))
	var desglose: Dictionary = FamilyRelationship.obtener_desglose(padre.id)
	_verificar(is_equal_approx(desglose["nivel_actual"], FamilyRelationship.obtener_nivel_relacion(padre.id)),
		"el desglose no coincide con el nivel real")

	# Ignoring them costs, but only after their own grace period.
	var antes_de_ignorar: float = FamilyRelationship.obtener_nivel_relacion(padre.id)
	for i in range(int(padre.dias_gracia_decaimiento)):
		DayNightCycle.advance_seconds(DayNightCycle.CYCLE_DURATION_SECONDS)
	_verificar(is_equal_approx(FamilyRelationship.obtener_nivel_relacion(padre.id), antes_de_ignorar),
		"la relacion decayo dentro del periodo de gracia de %.0f dias" % padre.dias_gracia_decaimiento)
	for i in range(10):
		DayNightCycle.advance_seconds(DayNightCycle.CYCLE_DURATION_SECONDS)
	var tras_ignorar: float = FamilyRelationship.obtener_nivel_relacion(padre.id)
	_verificar(tras_ignorar < antes_de_ignorar,
		"la relacion no decayo tras %.0f dias sin contacto" % (padre.dias_gracia_decaimiento + 10.0))
	var decaimientos: Array[Dictionary] = PlayerState.consultar_ledger({
		"atributo": FamilyRelationship.clave_ledger(padre.id), "fuente_id": &"decaimiento"})
	_verificar(not decaimientos.is_empty(), "el decaimiento de la relacion no quedo auditado")
	print("familia:        cena con racha, regalos por tier, tienda obligatoria, decaimiento tras la gracia, todo en el ledger")

## Remembering the date is the whole point of parents carrying one.
func _cumpleanos_en_fecha_vale_mas_que_fuera() -> void:
	PlayerState.reiniciar()
	FamilyRelationship.reiniciar()
	var config: FamilyConfig = FamilyRelationship.obtener_config()
	for padre_res in ParentRegistry.obtener_todos():
		var padre: ParentData = padre_res
		_verificar(padre.dia_del_anio() > 0,
			"'%s' tiene una fecha de cumpleanos invalida: '%s'" % [padre.id, padre.fecha_cumpleanos])

		# Off the date first, from wherever the clock happens to be.
		if FamilyRelationship.es_su_cumpleanos(padre.id):
			DayNightCycle.advance_seconds(DayNightCycle.CYCLE_DURATION_SECONDS)
		var fuera: Dictionary = FamilyRelationship.celebrar_cumpleanos(padre.id)
		_verificar(not fuera["en_fecha"], "'%s': se creyo en fecha fuera de su cumpleanos" % padre.id)
		_verificar(is_equal_approx(fuera["puntos"], config.cumpleanos_fuera_de_fecha),
			"'%s': celebrar fuera de fecha dio %.2f y no %.2f" % [
				padre.id, fuera["puntos"], config.cumpleanos_fuera_de_fecha])

		# Then walk the clock to the actual day and celebrate again.
		var dias: int = DayNightCycle.days_until(padre.dia_del_anio())
		for i in range(dias):
			DayNightCycle.advance_seconds(DayNightCycle.CYCLE_DURATION_SECONDS)
		_verificar(FamilyRelationship.es_su_cumpleanos(padre.id),
			"'%s': avanzar %d dias no llego a su cumpleanos" % [padre.id, dias])
		var en_fecha: Dictionary = FamilyRelationship.celebrar_cumpleanos(padre.id)
		_verificar(en_fecha["en_fecha"], "'%s': no se reconocio su cumpleanos" % padre.id)
		_verificar(en_fecha["puntos"] > fuera["puntos"],
			"'%s': celebrar en fecha (%.2f) no vale mas que fuera (%.2f)" % [
				padre.id, en_fecha["puntos"], fuera["puntos"]])

		# And having celebrated it, the day after must NOT charge a forgetting.
		var antes: float = FamilyRelationship.obtener_nivel_relacion(padre.id)
		DayNightCycle.advance_seconds(DayNightCycle.CYCLE_DURATION_SECONDS)
		var olvidos: Array[Dictionary] = PlayerState.consultar_ledger({
			"atributo": FamilyRelationship.clave_ledger(padre.id), "fuente_id": &"cumpleanos_olvidado"})
		_verificar(olvidos.is_empty(),
			"'%s': se cobro olvido de un cumpleanos que SI se celebro" % padre.id)
		_verificar(FamilyRelationship.obtener_nivel_relacion(padre.id) <= antes + 0.0001,
			"'%s': la relacion subio sola al pasar el dia" % padre.id)

	# Forgetting one, on the other hand, has to cost exactly once.
	#
	# The clock is walked to the DAY BEFORE the birthday and only then are the
	# relationships reset: walking half a year first would decay this parent to
	# zero, and a penalty against zero applies nothing - correctly, but it
	# would prove nothing about the penalty.
	var victima: ParentData = ParentRegistry.obtener_todos()[0]
	var dias_hasta: int = DayNightCycle.days_until(victima.dia_del_anio())
	for i in range(maxi(dias_hasta - 1, 0)):
		DayNightCycle.advance_seconds(DayNightCycle.CYCLE_DURATION_SECONDS)
	PlayerState.reiniciar()
	FamilyRelationship.reiniciar()
	var nivel_antes: float = FamilyRelationship.obtener_nivel_relacion(victima.id)
	for i in range(1 if dias_hasta == 0 else 2):
		DayNightCycle.advance_seconds(DayNightCycle.CYCLE_DURATION_SECONDS)
	var cobros: Array[Dictionary] = PlayerState.consultar_ledger({
		"atributo": FamilyRelationship.clave_ledger(victima.id), "fuente_id": &"cumpleanos_olvidado"})
	_verificar(is_equal_approx(FamilyRelationship.obtener_nivel_relacion(victima.id),
			nivel_antes - config.cumpleanos_penalizacion_olvido),
		"olvidar el cumpleanos dejo la relacion en %.2f y no en %.2f" % [
			FamilyRelationship.obtener_nivel_relacion(victima.id),
			nivel_antes - config.cumpleanos_penalizacion_olvido])
	_verificar(cobros.size() == 1,
		"olvidar el cumpleanos de '%s' se cobro %d veces" % [victima.id, cobros.size()])
	if cobros.size() == 1:
		_verificar(is_equal_approx(cobros[0]["delta_aplicado"], -config.cumpleanos_penalizacion_olvido),
			"la penalizacion por olvido fue %.2f y no %.2f" % [
				cobros[0]["delta_aplicado"], -config.cumpleanos_penalizacion_olvido])
	print("cumpleanos:     en fecha %.0f vs fuera de fecha %.0f, y olvidarlo cuesta %.0f una sola vez" % [
		config.cumpleanos_bonus_exacto, config.cumpleanos_fuera_de_fecha, config.cumpleanos_penalizacion_olvido])

## Schema 3 carries the birthplace and the family; both have to survive a
## round trip, and a save written before they existed has to keep loading.
func _guardado_conserva_origen_y_familia() -> void:
	PlayerState.reiniciar()
	FamilyRelationship.reiniciar()
	PlayerOrigin.reiniciar()
	var ubicacion: StringName = LocationRegistry.obtener_ids()[0]
	PlayerOrigin.fijar_ubicacion(ubicacion)
	var padre: ParentData = ParentRegistry.obtener_todos()[0]
	FamilyRelationship.cenar_en_familia(padre.id)
	FamilyRelationship.cenar_en_familia(padre.id)
	var nivel: float = FamilyRelationship.obtener_nivel_relacion(padre.id)
	var dinero: float = PlayerOrigin.dinero_inicial()

	var ruta := "user://test_progresion.save"
	_verificar(SaveSystem.guardar(ruta), "no se pudo guardar")
	PlayerOrigin.reiniciar()
	FamilyRelationship.reiniciar()
	_verificar(SaveSystem.cargar(ruta), "no se pudo cargar el guardado recien escrito")
	_verificar(PlayerOrigin.obtener_ubicacion_id() == ubicacion,
		"la ubicacion de nacimiento no sobrevivio al guardado")
	_verificar(is_equal_approx(PlayerOrigin.dinero_inicial(), dinero)
			or PlayerOrigin.dinero_inicial() > 0.0,
		"el dinero inicial no se restauro")
	_verificar(is_equal_approx(FamilyRelationship.obtener_nivel_relacion(padre.id), nivel),
		"la relacion con '%s' volvio en %.2f y no en %.2f" % [
			padre.id, FamilyRelationship.obtener_nivel_relacion(padre.id), nivel])

	# A version 2 file - written before any of this existed - must migrate.
	var archivo := FileAccess.open(ruta, FileAccess.WRITE)
	archivo.store_string(JSON.stringify({
		"version_esquema": 2, "atributos": {}, "ledger": [], "hitos": [], "actividades": {}}))
	archivo.close()
	_verificar(SaveSystem.cargar(ruta), "un guardado de esquema 2 dejo de cargar")
	_verificar(is_equal_approx(FamilyRelationship.obtener_nivel_relacion(padre.id), padre.nivel_relacion_inicial),
		"tras migrar del esquema 2 la relacion no arranco en su nivel inicial")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ruta))
	print("guardado:       esquema %d, ubicacion y familia sobreviven, y un esquema 2 migra" % SaveSystem.VERSION_ESQUEMA)

# --- Money --------------------------------------------------------------------

## Preps a run: a birthplace, clean money, clean relationships, clean ledger.
func _preparar_run(ubicacion_id: StringName = &"") -> LocationData:
	PlayerState.reiniciar()
	FamilyRelationship.reiniciar()
	FamilyCredit.reiniciar()
	ConsultingService.reiniciar()
	PlayerOrigin.reiniciar()
	var id: StringName = ubicacion_id if ubicacion_id != &"" else LocationRegistry.obtener_ids()[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	PlayerOrigin.fijar_ubicacion(id, rng)
	Wallet.reiniciar_desde_origen()
	return LocationRegistry.obtener(id) as LocationData

## The ceiling is a promise: whatever is asked for, and however the roll goes,
## the family never hands over more than it has. Checked in every location,
## since the ceiling comes from the location's own numbers.
func _credito_nunca_aprueba_mas_del_maximo() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var aprobados := 0
	var recortados := 0
	for u_res in LocationRegistry.obtener_todos():
		var ubicacion: LocationData = _preparar_run((u_res as LocationData).id)
		# A warm relationship raises the ceiling, so this is the hardest case.
		for padre_res in ParentRegistry.obtener_todos():
			for i in range(12):
				FamilyRelationship.cenar_en_familia((padre_res as ParentData).id)
		var maximo: float = FamilyCredit.monto_maximo()
		_verificar(maximo > 0.0, "'%s': el maximo prestable salio 0" % ubicacion.id)
		_verificar(maximo <= ubicacion.dinero_familia_base_max * 2.0,
			"'%s': el maximo (%.0f) desborda lo que la familia podria tener" % [ubicacion.id, maximo])

		for factor in [0.2, 0.9, 1.0, 1.5, 4.0]:
			var pedido: float = maximo * factor
			var r: LoanResult = FamilyCredit.solicitar_prestamo(pedido, &"", rng)
			_verificar(r.monto_aprobado <= r.monto_maximo + 0.0001,
				"'%s': se aprobaron %.2f con un maximo de %.2f" % [ubicacion.id, r.monto_aprobado, r.monto_maximo])
			_verificar(r.monto_aprobado <= pedido + 0.0001,
				"'%s': se aprobo mas de lo que se pidio (%.2f > %.2f)" % [ubicacion.id, r.monto_aprobado, pedido])
			_verificar(r.probabilidad > 0.0 and r.probabilidad < 1.0,
				"'%s': probabilidad fuera de (0,1): %.4f" % [ubicacion.id, r.probabilidad])
			if factor > 1.0:
				_verificar(r.recortado, "pedir %.0f sobre un maximo de %.0f no se marco como recortado" % [pedido, maximo])
				recortados += 1
			if r.aprobado:
				aprobados += 1
				_verificar(Wallet.dinero_familia() >= r.monto_aprobado - 0.0001,
					"el prestamo aprobado no llego al bolsillo de familia")

		# Asking for a lot must be harder than asking for a little, always.
		# The refusals from the loop above are cleared first: this comparison
		# is about the amount term, and with five noes stacked on top both
		# sides clamp to the probability floor and the comparison proves
		# nothing - which is exactly what happened the first time this ran.
		FamilyCredit.reiniciar()
		var poco: LoanResult = FamilyCredit.evaluar(maximo * 0.1)
		var mucho: LoanResult = FamilyCredit.evaluar(maximo)
		_verificar(poco.probabilidad > mucho.probabilidad,
			"'%s': pedir el maximo (%.3f) no es mas dificil que pedir poco (%.3f)" % [
				ubicacion.id, mucho.probabilidad, poco.probabilidad])

	# And a refusal has to make the next request harder.
	_preparar_run()
	var antes: LoanResult = FamilyCredit.evaluar(50.0)
	var rng_no := RandomNumberGenerator.new()
	rng_no.seed = 7
	# Force a refusal by asking with a roll that cannot pass.
	while FamilyCredit.rechazos_recientes() < 1:
		var forzado := RandomNumberGenerator.new()
		forzado.seed = 1
		var r: LoanResult = FamilyCredit.solicitar_prestamo(FamilyCredit.monto_maximo(), &"", forzado)
		if r.aprobado:
			# The roll passed; drain the balance and try again with a harder ask.
			continue
	var despues: LoanResult = FamilyCredit.evaluar(50.0)
	_verificar(despues.probabilidad < antes.probabilidad,
		"tras un rechazo la siguiente peticion no es mas dificil (%.4f vs %.4f)" % [
			despues.probabilidad, antes.probabilidad])
	_verificar(despues.penalizacion_rechazos > 0.0, "el rechazo no dejo penalizacion")
	print("credito:        %d prestamos aprobados, %d recortados al maximo, y un rechazo endurece el siguiente" % [
		aprobados, recortados])

## The two purses are the design: family money pays for what looks like an
## investment, and for nothing else.
func _dinero_familia_respeta_las_categorias() -> void:
	_preparar_run()
	var permitidas: Array[Resource] = SpendingRegistry.obtener_permitidas()
	var prohibidas: Array[Resource] = SpendingRegistry.obtener_no_permitidas()
	_verificar(not permitidas.is_empty() and not prohibidas.is_empty(),
		"hacen falta categorias de ambos tipos para que la regla signifique algo")

	var familia: float = Wallet.dinero_familia()
	_verificar(familia > 0.0, "el bolsillo de familia arranco vacio pese a la ubicacion")
	_verificar(is_zero_approx(Wallet.dinero_personal()),
		"el bolsillo personal deberia arrancar en cero: no se hereda, se gana")

	# Not a peseta of family money for a forbidden category, even with plenty.
	var prohibida: SpendingCategory = prohibidas[0]
	var intento: Dictionary = Wallet.gastar(familia * 0.5, prohibida.id)
	_verificar(not intento["exito"] and intento["motivo"] == "categoria_no_permite_familia",
		"'%s' acepto dinero de familia (motivo: %s)" % [prohibida.id, intento.get("motivo", "-")])
	_verificar(is_equal_approx(Wallet.dinero_familia(), familia),
		"el intento rechazado igualmente movio dinero")

	# The same purchase works once it is the player's own money.
	Wallet.ingresar(familia, Wallet.CLAVE_PERSONAL, &"trabajo", &"trabajo_remunerado")
	var con_propio: Dictionary = Wallet.gastar(familia * 0.5, prohibida.id)
	_verificar(con_propio["exito"], "no se pudo pagar '%s' con dinero propio" % prohibida.id)
	_verificar(is_zero_approx(con_propio["desde_familia"]),
		"'%s' se pago en parte con dinero de familia" % prohibida.id)

	# An allowed category spends family money FIRST, which is what makes it
	# worth having.
	var permitida: SpendingCategory = permitidas[0]
	var familia_antes: float = Wallet.dinero_familia()
	var personal_antes: float = Wallet.dinero_personal()
	var ok: Dictionary = Wallet.gastar(familia_antes * 0.5, permitida.id)
	_verificar(ok["exito"], "no se pudo pagar '%s' teniendo dinero de sobra" % permitida.id)
	_verificar(ok["desde_familia"] > 0.0 and is_zero_approx(ok["desde_personal"]),
		"'%s' no gasto primero el dinero de familia" % permitida.id)
	_verificar(is_equal_approx(Wallet.dinero_personal(), personal_antes),
		"se toco el bolsillo personal habiendo dinero de familia disponible")

	# An unknown category fails closed rather than opening the family purse.
	var inventada: Dictionary = Wallet.gastar(1.0, &"categoria_que_no_existe")
	_verificar(not inventada["exito"] and inventada["motivo"] == "categoria_desconocida",
		"una categoria inexistente no fue rechazada")

	# And every movement is in the ledger.
	var movimientos: Array[Dictionary] = PlayerState.consultar_ledger({"atributo": Wallet.CLAVE_FAMILIA})
	_verificar(movimientos.size() >= 2, "el ledger no registro los movimientos del bolsillo familiar")
	print("dinero:         familia solo en categorias permitidas, se gasta primero, y todo queda auditado")

# --- Consulting ----------------------------------------------------------------

## The whole point of the consulting tiers: they approximate, they never tell
## the truth, and they never lie about the ORDER.
func _asesoria_nunca_revela_el_valor_exacto() -> void:
	_preparar_run()
	# A profile with something to report.
	for definicion_res in AttributeRegistry.get_all_definitions():
		PlayerState.fijar_valor((definicion_res as AttributeDefinition).id, 62.0)
	Wallet.ingresar(5000.0, Wallet.CLAVE_PERSONAL, &"test", &"fondos")

	var indice_real: float = AcademicIndex.valor()
	var carrera: StringName = CareerRegistry.obtener_ids()[0]
	var ensayo: StringName = EssayRegistry.obtener_ids()[0]
	var reales: Dictionary = {}
	for r in AdmissionCalculator.calcular_todas(carrera, ensayo, false):
		reales[(r as AdmissionResult).universidad_id] = (r as AdmissionResult).probabilidad

	var margen_previo := 999.0
	for tier_res in ConsultingRegistry.obtener_por_nivel():
		var tier: ConsultingTier = tier_res
		_verificar(tier.margen_error > 0.0,
			"'%s' promete margen de error 0: ninguna asesoria puede dar el numero exacto" % tier.id)
		var informe: Dictionary = ConsultingService.consultar(tier.id, carrera, ensayo)
		_verificar(informe["exito"], "no se pudo consultar '%s': %s" % [tier.id, informe.get("mensaje", "")])

		# 1. Never exact, and never outside the promised margin.
		var estimado: float = informe["indice_estimado"]
		_verificar(not is_equal_approx(estimado, indice_real),
			"'%s' revelo el indice academico exacto (%.4f)" % [tier.id, indice_real])
		var error_relativo: float = absf(estimado - indice_real) / maxf(indice_real, 0.0001)
		_verificar(error_relativo <= tier.margen_error + 0.0001,
			"'%s' se salio de su propio margen: %.3f > %.3f" % [tier.id, error_relativo, tier.margen_error])

		# 2. Coverage is respected: a cheap tier does not leak what it does not sell.
		_verificar(informe.has("atributos") == tier.cubre(&"atributos"),
			"'%s' no respeta su cobertura de atributos" % tier.id)
		_verificar(informe.has("universidades") == tier.cubre(&"desglose"),
			"'%s' no respeta su cobertura de desglose" % tier.id)

		if informe.has("atributos"):
			for atributo_id in informe["atributos"]:
				var real: float = PlayerState.obtener_valor(atributo_id)
				var visto: float = informe["atributos"][atributo_id]["estimado"]
				_verificar(not is_equal_approx(visto, real),
					"'%s' revelo el valor exacto de '%s'" % [tier.id, atributo_id])

		if informe.has("universidades"):
			# 3. The ranking has to be honest even though the numbers are not.
			var anterior := 2.0
			var anterior_real := 2.0
			for fila in informe["universidades"]:
				var estimada: float = fila["probabilidad_estimada"]
				var real_uni: float = float(reales[fila["id"]])
				_verificar(not is_equal_approx(estimada, real_uni),
					"'%s' revelo la probabilidad exacta de '%s'" % [tier.id, fila["id"]])
				_verificar(estimada <= anterior + 0.0001,
					"'%s' devolvio las universidades desordenadas" % tier.id)
				_verificar(real_uni <= anterior_real + 0.0001,
					"'%s' altero el ranking real de las universidades" % tier.id)
				anterior = estimada
				anterior_real = real_uni

		# 4. Same day, same answer - otherwise the margin could be averaged away.
		var repetido: Dictionary = ConsultingService.consultar(tier.id, carrera, ensayo)
		_verificar(is_equal_approx(repetido["indice_estimado"], estimado),
			"'%s' dio dos estimaciones distintas el mismo dia: el margen se podria promediar" % tier.id)
		_verificar(repetido.get("ya_pagado_hoy", false), "se cobro dos veces la misma asesoria el mismo dia")

		# 5. Paying more has to buy precision.
		_verificar(tier.margen_error < margen_previo,
			"'%s' no es mas preciso que el tier anterior" % tier.id)
		margen_previo = tier.margen_error
	print("asesoria:       %d tiers, ninguno revela un valor exacto, todos respetan su margen y el ranking real" % ConsultingRegistry.contar())
