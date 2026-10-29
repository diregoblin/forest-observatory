class_name ForestPlantDefinition
extends Resource

## A new species is a resource, not another branch in rendering or placement.
@export var species_id: StringName
@export var display_name := ""
@export var weight := 1.0
@export var scale_range := Vector2(.72, 1.5)
@export var minimum_channel_distance := 14.0
@export var wind_strength := .015
@export var modules: Array[ForestPlantModule] = []
