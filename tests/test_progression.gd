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
			["ensayos", EssayRegistry], ["actividades", ActivityRegistry]]:
		var registro: ResourceRegistry = par[1]
		var errores: PackedStringArray = registro.obtener_errores()
		_verificar(errores.is_empty(), "%s reporto errores: %s" % [par[0], ", ".join(errores)])
		_verificar(registro.contar() > 0, "%s no cargo ningun recurso" % par[0])
	print("registros:      %d atributos, %d sinergias, %d universidades, %d carreras, %d ensayos, %d actividades" % [
		AttributeRegistry.contar(), SynergyRegistry.contar(), UniversityRegistry.contar(),
		CareerRegistry.contar(), EssayRegistry.contar(), ActivityRegistry.contar()])

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
