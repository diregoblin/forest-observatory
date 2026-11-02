class_name ForestPlantModule
extends Resource

## Repeated geometric component, independent of species identity.
@export var mesh: Mesh
@export var count := 1
@export var offset := Vector3.ZERO
@export var step := Vector3.ZERO
@export var radial_offset := 0.0
@export var radial_step := 0.0
@export var turn := 0.0
@export var scale_start := Vector3.ONE
@export var scale_step := Vector3.ZERO
@export var color := Color.WHITE
@export var foliage := false
@export var component_kind: StringName = &"ordinary"
@export var rotation_degrees := Vector3.ZERO
@export var whorls := 1
@export var whorl_turn := 0.0
## A compact branched head at each repetition, e.g. a corymb or flower head.
## Defaults keep an ordinary module a single mesh, without extra geometry.
@export var cluster_members := 1
@export var cluster_spread := Vector3.ZERO
## Reusable botanical components; identity still lives only in plant resources.
@export_enum("mesh", "shoot", "leaf_card", "star", "bell", "spur", "aggregate", "panicle")
var shape := "mesh"
@export var bend := Vector3.ZERO
@export var tip_offset := Vector3.ZERO
@export var leaf_count := 0
@export var leaf_size := Vector2(.08, .16)
@export var leaf_color := Color(.27, .43, .19)
@export var leaflet_pairs := 0
@export var card_curve := .08
@export var card_fold := .06
@export var petiole_length := .02
@export var petal_count := 5
