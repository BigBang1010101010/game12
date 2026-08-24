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
			["ensayos", EssayRegistry]]:
		var registro: ResourceRegistry = par[1]
		var errores: PackedStringArray = registro.obtener_errores()
		_verificar(errores.is_empty(), "%s reporto errores: %s" % [par[0], ", ".join(errores)])
		_verificar(registro.contar() > 0, "%s no cargo ningun recurso" % par[0])
	print("registros:      %d atributos, %d sinergias, %d universidades, %d carreras, %d ensayos" % [
		AttributeRegistry.contar(), SynergyRegistry.contar(), UniversityRegistry.contar(),
		CareerRegistry.contar(), EssayRegistry.contar()])

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
