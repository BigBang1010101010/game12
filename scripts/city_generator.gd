extends Node3D
class_name CityGenerator

## Semi-procedural city blockout: a grid of raised sidewalk platforms with
## simple box buildings on them, separated by asphalt streets. Everything is
## built in _ready() from the parameters below, so the layout is changed by
## editing numbers rather than by hand-placing geometry.
##
## Deliberately placed clear of the original grass area: the existing trees
## span x [-83, 105] and z [-80, 109] and the house sits at (50, 50), so the
## whole city lives at negative Z beyond all of it (see CITY_CENTER) and the
## starting area is left exactly as it was.
##
## Layout per grid cell (viewed from above):
##
##     |<--------- cell_pitch --------->|
##     +----------------------+  street |
##     |  sidewalk platform   |  gap    |
##     |   +--------------+   |         |
##     |   |   building   |   |         |
##     |   +--------------+   |         |
##     +----------------------+         |
##     |<---- block_size ---->|<- street_width ->|
##
## The streets are the gaps between platforms; they sit at world ground level
## (the scene's own Floor provides their collision), with an asphalt slab
## drawn just above it for colour. The platforms are what the player steps up
## onto, so they are kept low enough to walk onto without jumping.

## Grid size, in blocks.
@export var blocks_x: int = 5
@export var blocks_z: int = 5
## Footprint of one block, sidewalk included.
@export var block_size: float = 30.0
## Gap between neighbouring blocks - the street.
@export var street_width: float = 10.0
## How much sidewalk is left around a building, on each side of its block.
@export var sidewalk_width: float = 4.0
## Sidewalk kerb height. Kept low on purpose: a CharacterBody3D has no
## built-in step-up, so it only climbs a kerb because the capsule's rounded
## bottom turns the edge into a slope it can slide up. Raising this much
## further turns the kerb into a wall (verified by walking into it).
@export var sidewalk_height: float = 0.12
@export var min_building_height: float = 6.0
@export var max_building_height: float = 26.0
## Fixed seed so the same layout is generated every run - a city that
## reshuffles itself on each load would make anything built against it
## (verification included) meaningless.
@export var rng_seed: int = 20260824

## Where the middle of the grid sits in world space.
@export var city_center := Vector3(0, 0, -220)

## RESERVED FOR THE SCHOOL BUILDING (task pending): this block's platform and
## sidewalk are generated as normal, but no building is placed on it, leaving
## an empty lot ready for the school to be dropped in later. Grid coordinates
## are 0-based, so this is the middle block of a 5x5 grid.
@export var reserved_block := Vector2i(2, 2)

const ASPHALT_COLOR := Color(0.16, 0.16, 0.18)
const SIDEWALK_COLOR := Color(0.62, 0.62, 0.60)
const BUILDING_COLORS: Array[Color] = [
	Color(0.55, 0.52, 0.48),
	Color(0.45, 0.47, 0.52),
	Color(0.60, 0.50, 0.44),
	Color(0.50, 0.54, 0.50),
	Color(0.42, 0.42, 0.45),
]

func _ready() -> void:
	generate()

## Rebuilds the whole city. Safe to call again: it clears anything it made
## before, so the parameters can be tweaked and re-run.
func generate() -> void:
	for child in get_children():
		child.queue_free()

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var cell_pitch: float = block_size + street_width
	var span_x: float = blocks_x * cell_pitch
	var span_z: float = blocks_z * cell_pitch

	_add_asphalt(span_x, span_z)

	for ix in range(blocks_x):
		for iz in range(blocks_z):
			var center := _block_center(ix, iz, cell_pitch)
			_add_sidewalk(ix, iz, center)
			if Vector2i(ix, iz) == reserved_block:
				continue # school lot - intentionally left empty
			_add_building(ix, iz, center, rng)

## World-space centre of block (ix, iz), with the grid centred on city_center.
func _block_center(ix: int, iz: int, cell_pitch: float) -> Vector3:
	var offset_x: float = (float(ix) - (blocks_x - 1) * 0.5) * cell_pitch
	var offset_z: float = (float(iz) - (blocks_z - 1) * 0.5) * cell_pitch
	return city_center + Vector3(offset_x, 0.0, offset_z)

## One flat slab covering the whole grid, purely for the street colour. It
## carries no collision: the scene's Floor already covers this ground, and a
## second overlapping collider would just fight it.
func _add_asphalt(span_x: float, span_z: float) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "StreetSurface"
	var plane := PlaneMesh.new()
	plane.size = Vector2(span_x, span_z)
	plane.material = _make_material(ASPHALT_COLOR)
	mesh_instance.mesh = plane
	mesh_instance.position = city_center + Vector3(0, 0.02, 0)
	add_child(mesh_instance)

func _add_sidewalk(ix: int, iz: int, center: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Sidewalk_%d_%d" % [ix, iz]
	body.position = center + Vector3(0, sidewalk_height * 0.5, 0)
	add_child(body)

	var size := Vector3(block_size, sidewalk_height, block_size)
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = _make_material(SIDEWALK_COLOR)
	mesh_instance.mesh = box
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

func _add_building(ix: int, iz: int, center: Vector3, rng: RandomNumberGenerator) -> void:
	# Buildings vary in footprint and height, but always stay inside their own
	# lot so the sidewalk around them stays walkable.
	var max_footprint: float = block_size - 2.0 * sidewalk_width
	var width: float = rng.randf_range(max_footprint * 0.55, max_footprint)
	var depth: float = rng.randf_range(max_footprint * 0.55, max_footprint)
	var height: float = rng.randf_range(min_building_height, max_building_height)

	var body := StaticBody3D.new()
	body.name = "Building_%d_%d" % [ix, iz]
	# Sits on top of the sidewalk platform, so its base is the kerb height.
	body.position = center + Vector3(0, sidewalk_height + height * 0.5, 0)
	add_child(body)

	var size := Vector3(width, height, depth)
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = _make_material(BUILDING_COLORS[rng.randi() % BUILDING_COLORS.size()])
	mesh_instance.mesh = box
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
