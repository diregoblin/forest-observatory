class_name ForestSoilProfile
extends Resource

## SI inputs for the two-bucket profile; theta is m³ water / m³ soil.
@export var top_depth_m := 0.15
@export var root_depth_m := 0.60
@export var porosity := 0.45
@export var field_capacity_theta := 0.28
@export var residual_theta := 0.06
@export var saturated_conductivity_m_s := 8.0 / 1000.0 / 3600.0
@export var root_conductivity_m_s := 2.0 / 1000.0 / 3600.0
@export var groundwater_enabled := true
@export var aquifer_depth_m := 1.5
@export var specific_yield := 0.18
@export var lateral_conductivity_m_s := 0.0001
@export var initial_groundwater_fraction := 0.6


func validate() -> void:
	assert(top_depth_m > 0 and root_depth_m > 0)
	assert(0 <= residual_theta and residual_theta < field_capacity_theta)
	assert(field_capacity_theta < porosity and porosity <= 1)
	assert(saturated_conductivity_m_s >= 0 and root_conductivity_m_s >= 0)
	assert(aquifer_depth_m > 0 and specific_yield > 0 and specific_yield <= 1)
	assert(lateral_conductivity_m_s >= 0)
	assert(initial_groundwater_fraction >= 0 and initial_groundwater_fraction <= 1)
