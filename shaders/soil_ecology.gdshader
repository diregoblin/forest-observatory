// Copyright © 2023-2026 Cory Petkovsek, Roope Palmroos, and Contributors.
// This shader is the minimum needed to allow the terrain to function, without any texturing.

shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx,skip_vertex_transform;

/* This is an example stripped down shader with maximum performance in mind.
 * Only Autoshader/Base/Over/Blend/Holes/Colormap are supported.
 * Optional bank displacement uses the native buffer and its clipmap geomorph.
 * All terrain normal calculations take place in vertex().
 *
 * Control map indices are processed such that each ID only requires reading ONCE.
 * The following features: projection, detiling, and paintable rotation / scale
 * cannot work with this method, without the additional samples required for blending
 * between same ID textures with different values across indices.
 */

/*
MIT License

Copyright (c) 2023-2026 Cory Petkovsek, Roope Palmroos, and Contributors.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
// Terrain3D 1.1.0 lightweight base, with model-driven soil display.
uniform sampler2D ecology_previous : filter_linear, repeat_disable;
uniform sampler2D ecology_current : filter_linear, repeat_disable;
uniform float ecology_blend = 1.0;
uniform float ecology_extent = 512.0;
uniform bool ecology_enabled = false;
// Decorative fine turf, not an additional plant/food/carbon pool.
uniform float ground_greenness = 0.85;
uniform bool turf_enabled = false;
uniform sampler2D turf_albedo_height : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Linear packed RG=normal XZ, B=roughness, A=local ambient occlusion.
uniform sampler2D turf_normal_roughness_ao : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float turf_tile_m = 1.6;
uniform float turf_normal_strength = 0.55;
uniform sampler2D habitat_map : filter_linear, repeat_disable;
uniform bool traffic_enabled = false;
uniform sampler2D traffic_map : filter_linear;
uniform sampler2D rooting_map : filter_linear, repeat_disable;
uniform float snow_water_m = 0.0;
uniform bool soil_layer_enabled = false;
#include "res://shaders/soil_diagnostic.gdshaderinc"
// Optional presentation microrelief. Dynamic masks are NOT cached in the buffer.
uniform bool bank_relief_enabled = false;
uniform highp sampler2D bank_water_current : filter_linear, repeat_disable;
uniform highp sampler2D bank_water_previous : filter_linear, repeat_disable;
uniform float bank_water_blend = 1.0;

// Defined Constants
#define MAX_REGIONS 1024 // Match Terrain3DMaterial.max_regions. Set to 64-256 for mobile
#define COLOR_MAP vec4(1.0, 1.0, 1.0, 0.5)
#define DIV_255 0.003921568627450 // 1. / 255.

// Inline Functions
#define DECODE_BLEND(control) float(control >>14u & 0xFFu) * DIV_255
#define DECODE_AUTO(control) bool(control & 0x1u)
#define DECODE_BASE(control) int(control >>27u & 0x1Fu)
#define DECODE_OVER(control) int(control >>22u & 0x1Fu)
#define DECODE_HOLE(control) bool(control >>2u & 0x1u)

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    #define fma(a, b, c) ((a) * (b) + (c))
    #define dFdxCoarse(a) dFdx(a)
    #define dFdyCoarse(a) dFdy(a)
#endif

// Private uniforms
group_uniforms private;
uniform vec3 _target_pos = vec3(0.f);
uniform float _mesh_size = 48.f;
uniform uint _background_mode = 1u; // NONE = 0, FLAT = 1, NOISE = 2
uniform uint _mouse_layer = 0x80000000u; // Layer 32
uniform float _vertex_spacing = 1.0;
uniform float _vertex_density = 1.0; // = 1./_vertex_spacing
uniform float _subdiv = 1.0;
uniform float _displacement_scale = 0.04;
uniform highp sampler2D _displacement_buffer : repeat_disable, filter_linear;
uniform float _region_size = 1024.0;
uniform float _region_texel_size = 0.0009765625; // = 1./region_size
uniform int _region_map_size = 32;
uniform int _region_map[1024];
uniform vec2 _region_locations[MAX_REGIONS];
uniform float _texture_normal_depth_array[32];
uniform float _texture_ao_strength_array[32];
uniform float _texture_ao_affect_array[32];
uniform float _texture_roughness_mod_array[32];
uniform float _texture_uv_scale_array[32];
uniform vec4 _texture_color_array[32];
uniform highp sampler2DArray _height_maps : repeat_disable;
uniform highp sampler2DArray _control_maps : repeat_disable;
uniform highp sampler2DArray _color_maps : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform highp sampler2DArray _texture_array_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform highp sampler2DArray _texture_array_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
group_uniforms;

// Public uniforms
group_uniforms general_uniforms;
uniform float ground_level : hint_range(-1000., 1000.) = 0.0;
uniform float region_blend : hint_range(.001, 1., 0.001) = 0.25;
uniform bool flat_terrain_normals = false;
uniform bool textures_enabled = true;
uniform float blend_sharpness : hint_range(0, 1) = 0.5;
group_uniforms;

group_uniforms auto_shader;
uniform float auto_slope : hint_range(0, 10) = 1.0;
uniform float auto_height_reduction : hint_range(0, 1) = 0.1;
uniform int auto_base_texture : hint_range(0, 31) = 0;
uniform int auto_overlay_texture : hint_range(0, 31) = 1;
group_uniforms;

group_uniforms macro_variation;
uniform bool macro_variation_enabled = true;
uniform vec3 macro_variation1 : source_color = vec3(1.);
uniform vec3 macro_variation2 : source_color = vec3(1.);
uniform float macro_variation_slope : hint_range(0., 1.)  = 0.333;
uniform highp sampler2D noise_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float noise1_scale : hint_range(0.001, 1.) = 0.04; // Used for macro variation 1. Scaled up 10x
uniform float noise1_angle : hint_range(0, 6.283) = 0.;
uniform vec2 noise1_offset = vec2(0.5);
uniform float noise2_scale : hint_range(0.001, 1.) = 0.076; // Used for macro variation 2. Scaled up 10x
group_uniforms;

// Varyings & Types
varying vec3 v_vertex;
varying float v_vertex_xz_dist;
varying vec3 v_normal;
varying vec3 v_camera_pos;
varying mat3 TBN;

////////////////////////
// Vertex
////////////////////////

// Takes in world space XZ (UV) coordinates
// Returns ivec3 with:
// XY: (0 to _region_size - 1) coordinates within a region
// Z: layer index used for texturearrays, -1 if not in a region
ivec3 get_index_coord(const vec2 uv) {
	vec2 r_uv = round(uv);
	ivec2 pos = ivec2(floor(r_uv * _region_texel_size)) + (_region_map_size / 2);
	int bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
	int map_val = _region_map[pos.y * _region_map_size + pos.x];
	int raw_index = map_val - 1;
	// Real regions limited by max_regions
	int is_region = bounds * int(raw_index >= 0) * int(raw_index < MAX_REGIONS);
	// Editor dummies are negative; keep them != -1 so the shader still sees a region
	int is_dummy = bounds * int(map_val < 0);
	int layer_index = is_region * raw_index
	               + is_dummy * (map_val - 1)
	               - (1 - is_region - is_dummy);
	return ivec3(ivec2(mod(r_uv, _region_size)), layer_index);
}

// Takes in descaled (world_space / region_size) world to region space XZ (UV2) coordinates, returns vec3 with:
// XY: (0. to 1.) coordinates within a region
// Z: layer index used for texturearrays, -1 if not in a region
vec3 get_index_uv(const vec2 uv2) {
	ivec2 pos = ivec2(floor(uv2)) + (_region_map_size / 2);
	int bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
	int map_val = _region_map[pos.y * _region_map_size + pos.x];
	int raw_index = map_val - 1;
	int is_region = bounds * int(raw_index >= 0) * int(raw_index < MAX_REGIONS);
	int is_dummy = bounds * int(map_val < 0);
	int layer_index = is_region * raw_index
	               + is_dummy * (map_val - 1)
	               - (1 - is_region - is_dummy);
	return vec3(uv2 - _region_locations[layer_index], float(layer_index));
}

// Takes in world space XZ (UV) and returns if the coordinate should be part of the NONE background.
bool is_none_bg(const vec2 uv) {
	ivec4 regions = ivec4(
		get_index_coord(uv - vec2(0.5, 0.0)).z,
		get_index_coord(uv - vec2(0.0, 0.5)).z,
		get_index_coord(uv + vec2(1.0, 0.0)).z,
		get_index_coord(uv + vec2(0.0, 1.0)).z);
	return any(equal(regions, ivec4(-1)));
}

// Takes in UV2 region space coordinates, returns 1.0 or 0.0 if a region is present or not.
float check_region(const vec2 uv2) {
	ivec2 pos = ivec2(floor(uv2)) + (_region_map_size / 2);
    int bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
    int raw_index = _region_map[pos.y * _region_map_size + pos.x] - 1;
    int is_valid = bounds * int(raw_index >= 0) * int(raw_index < MAX_REGIONS);
	return float(is_valid);
}

// Takes in UV2 region space coordinates, returns a blend value (0 - 1 range) between empty, and valid regions
float get_region_blend(vec2 uv2) {
	uv2 -= 0.5011; // correct for floating point error
	const vec2 offset = vec2(0.0, 1.0);
	float a = check_region(uv2 + offset.xy);
	float b = check_region(uv2 + offset.yy);
	float c = check_region(uv2 + offset.yx);
	float d = check_region(uv2 + offset.xx);
	vec2 blend_factor = vec2(2.0 + 126.0 * (1.0 - region_blend));
	vec2 f = clamp(fract(uv2), 1e-6, 1.0 - 1e-6);
	vec2 w = 1.0 / (1.0 + exp(blend_factor * log((1.0 - f) / f)));
	float blend = mix(mix(d, c, w.x), mix(a, b, w.x), w.y);
	return (1.0 - blend) * 2.0;
}

float interpolated_height(vec2 pos) {
	const vec2 offsets = vec2(0, 1);
	vec2 index_id = floor(pos);
	ivec3 index[4];
	index[0] = get_index_coord(index_id + offsets.xy);
	index[1] = get_index_coord(index_id + offsets.yy);
	index[2] = get_index_coord(index_id + offsets.yx);
	index[3] = get_index_coord(index_id + offsets.xx);
	float h0 = texelFetch(_height_maps, index[0], 0).r;
	float h1 = texelFetch(_height_maps, index[1], 0).r;
	float h2 = texelFetch(_height_maps, index[2], 0).r;
	float h3 = texelFetch(_height_maps, index[3], 0).r;
	vec2 f = fract(pos);
	vec2 i = 1.0 - f;
	vec4 w = vec4(i.x * f.y, f.x * f.y, f.x * i.y, i.x * i.y);
	float h = h0 * w[0] + h1 * w[1] + h2 * w[2] + h3 * w[3];
	return h;
}

// Native Terrain3D 1.1 displacement atlas lookup. Coarse levels tend to zero
// through the same geomorph as the base height, avoiding a near-detail ring.
float bank_height(vec2 pos, float scale) {
	float level = floor(log2(1.0 / (scale * _vertex_density)));
	if (level < 1.0 || _subdiv < 2.0) { return 0.0; }
	float density = exp2(level) * .5;
	vec2 uv = (density * pos - round(_target_pos.xz * _vertex_density * density))
		/ (_mesh_size * 2.0) + .5;
	uv.x = (uv.x + level - 1.0) / log2(_subdiv);
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) { return 0.0; }
	vec2 world_uv = pos * _vertex_spacing / ecology_extent;
	float sand = smoothstep(.35, .85, textureLod(habitat_map, world_uv, 0.0).a);
	float depth = mix(textureLod(bank_water_previous, world_uv, 0.0).r,
		textureLod(bank_water_current, world_uv, 0.0).r, bank_water_blend);
	float dry = 1.0 - smoothstep(.0001, .008, depth);
	float exposed = 1.0 - smoothstep(.0001, .006, snow_water_m);
	return (textureLod(_displacement_buffer, uv, 0.0).g * 2.0 - 1.0)
		* _displacement_scale * sand * dry * exposed;
}

float bank_morph(vec2 start, vec2 end, float scale, float morph) {
	return mix(bank_height(start, scale), bank_height(end, scale * 2.0), morph);
}

void vertex() {
	// Save Camera Position to varying for access in later functions
	v_camera_pos = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;

	// Get vertex of flat plane in world coordinates and set world UV
	v_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Distance from target node to vertex on a flat plane
	v_vertex_xz_dist = length(v_vertex.xz - _target_pos.xz);

	// Geomorph vertex across clipmap LODs, set end and start for linear height interpolate
	float scale = MODEL_MATRIX[0][0];
	float inv_scale = 1.0 / scale;
	float max_xz = max(abs(v_vertex.x - _target_pos.x), abs(v_vertex.z - _target_pos.z));
	float vertex_lerp = smoothstep(0.0, 1.0, (max_xz * inv_scale - _mesh_size - 4.0) / (_mesh_size - 4.0));
	vec2 vertex_fract = fract(VERTEX.xz * 0.5) * 2.0;
	// For LOD0 morph from a regular grid to an alternating grid to align with LOD1+
	vec2 shift = (scale < _vertex_spacing / _subdiv + 1e-6) ? // LOD0 or not
		// Shift from regular to symmetric
		mix(vertex_fract, vec2(vertex_fract.x, -vertex_fract.y),
			round(fract(round(mod(v_vertex.z * inv_scale, 4.0)) *
			round(mod(v_vertex.x * inv_scale, 4.0)) * 0.25))) :
		// Symmetric shift
		vertex_fract * round((fract(v_vertex.xz * 0.25 * inv_scale) - 0.5) * 4.0);
	vec2 start_pos = v_vertex.xz * _vertex_density;
	vec2 end_pos = (v_vertex.xz - shift * scale) * _vertex_density;
	v_vertex.xz -= shift * scale * vertex_lerp;

	// UV coordinates in region space. 0-1 covers 1 region, 1-2 is the next region, etc.
	UV = v_vertex.xz * _vertex_density;

	// UV coordinates in region space + texel offset. Values are 0 to 1 within regions
	UV2 = fma(UV, vec2(_region_texel_size), vec2(0.5 * _region_texel_size));

	// Discard vertices for Holes. 1 lookup
	ivec3 v_region = get_index_coord(start_pos);
	uint control = floatBitsToUint(texelFetch(_control_maps, v_region, 0)).r;
	bool hole = DECODE_HOLE(control);

	// Show holes to all cameras except mouse camera (on exactly 1 layer)
	if ( !(CAMERA_VISIBLE_LAYERS == _mouse_layer) &&
			(hole || (_background_mode == 0u && is_none_bg(UV)))) {
		v_vertex.x = 0. / 0.;
	} else {
		// Set final vertex height, and vertex normal.
		float h, u, v;
		// This branch is static for each of the clipmap segments
		// Interpolated reads only occur where sub-texel values are required.
		if (scale < _vertex_spacing) {
			h = interpolated_height(UV);
			u = interpolated_height(UV + vec2(1, 0));
			v = interpolated_height(UV + vec2(0, 1));
		} else {
			ivec3 coord_a = get_index_coord(start_pos);
			ivec3 coord_b = get_index_coord(end_pos);
			ivec3 coord_ua = get_index_coord(start_pos + vec2(1, 0));
			ivec3 coord_ub = get_index_coord(end_pos + vec2(1, 0));
			ivec3 coord_va = get_index_coord(start_pos + vec2(0, 1));
			ivec3 coord_vb = get_index_coord(end_pos + vec2(0, 1));
			h = mix(texelFetch(_height_maps, coord_a, 0).r, texelFetch(_height_maps, coord_b, 0).r, vertex_lerp);
			u = mix(texelFetch(_height_maps, coord_ua, 0).r, texelFetch(_height_maps, coord_ub, 0).r, vertex_lerp);
			v = mix(texelFetch(_height_maps, coord_va, 0).r, texelFetch(_height_maps, coord_vb, 0).r, vertex_lerp);
		}

		// Apply background ground level and region blend
		vec2 ruv = UV * _region_texel_size;
		h = mix(h, ground_level, smoothstep(0.0, 1.0, get_region_blend(ruv)));
		u = mix(u, ground_level, smoothstep(0.0, 1.0, get_region_blend(ruv + vec2(_region_texel_size, 0.0))));
		v = mix(v, ground_level, smoothstep(0.0, 1.0, get_region_blend(ruv + vec2(0.0, _region_texel_size))));

		v_vertex.y = h;
		v_normal = normalize(vec3(h - u, _vertex_spacing, h - v));
	}

	vec3 displacement = vec3(0.0);
	if (bank_relief_enabled && _subdiv > 1.0 && !soil_layer_enabled &&
			!(CAMERA_VISIBLE_LAYERS == _mouse_layer)) {
		displacement.y = bank_morph(start_pos, end_pos, scale, vertex_lerp);
		// Derive smooth normals from the SAME masked, LoD-morphed field. Water
		// interpolation cannot leave old geometry or normals in a cached buffer.
		float e = max(scale, _vertex_spacing / _subdiv);
		vec2 dx = vec2(e * _vertex_density, 0.0);
		vec2 dz = dx.yx;
		float gx = (bank_morph(start_pos+dx, end_pos+dx, scale, vertex_lerp)
			- bank_morph(start_pos-dx, end_pos-dx, scale, vertex_lerp)) / (2.0 * e);
		float gz = (bank_morph(start_pos+dz, end_pos+dz, scale, vertex_lerp)
			- bank_morph(start_pos-dz, end_pos-dz, scale, vertex_lerp)) / (2.0 * e);
		v_normal = normalize(vec3(v_normal.x / v_normal.y - gx, 1.0,
			v_normal.z / v_normal.y - gz));
	}
	// Keep v_vertex and model-field UVs undisplaced. This is decoration only.
	VERTEX = (VIEW_MATRIX * vec4(v_vertex + displacement, 1.0)).xyz;

	// Apply terrain normals
	vec3 w_tangent = normalize(cross(v_normal, vec3(0.0, 0.0, 1.0)));
	vec3 w_binormal = normalize(cross(v_normal, w_tangent));
	TBN = mat3(w_tangent, w_binormal, v_normal);

	NORMAL = normalize((VIEW_MATRIX * vec4(v_normal, 0.0)).xyz);
	BINORMAL = normalize((VIEW_MATRIX * vec4(w_binormal, 0.0)).xyz);
	TANGENT = normalize((VIEW_MATRIX * vec4(w_tangent, 0.0)).xyz);
}

////////////////////////
// Fragment
////////////////////////

mat2 rotate_plane(float angle) {
	float c = cos(angle), s = sin(angle);
	return mat2(vec2(c, s), vec2(-s, c));
}

// Smooth world-space noise. Grid cells are interpolation supports, not stamps.
float surface_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 f = fract(point);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(cell, vec2(73.13,39.27))) * 13427.17);
	float b = fract(sin(dot(cell + vec2(1,0), vec2(73.13,39.27))) * 13427.17);
	float c = fract(sin(dot(cell + vec2(0,1), vec2(73.13,39.27))) * 13427.17);
	float d = fract(sin(dot(cell + vec2(1,1), vec2(73.13,39.27))) * 13427.17);
	return mix(mix(a,b,f.x), mix(c,d,f.x), f.y);
}

void fragment() {
	// Recover UVs
	vec2 uv = UV;
	vec2 uv2 = UV2;

	// Lookup offsets, ID and blend weight
	vec3 region_uv = get_index_uv(uv2);
	const vec3 offsets = vec3(0, 1, 2);
	vec2 index_id = floor(uv);
	vec2 weight = min(fract(uv), 1.0 - 1e-7);
	vec2 invert = 1.0 - weight;
	vec4 weights = vec4(
		invert.x * weight.y, // 0
		weight.x * weight.y, // 1
		weight.x * invert.y, // 2
		invert.x * invert.y  // 3
	);

	ivec3 index[4];
	// control map lookups, used for some normal lookups as well
	index[0] = get_index_coord(index_id + offsets.xy);
	index[1] = get_index_coord(index_id + offsets.yy);
	index[2] = get_index_coord(index_id + offsets.yx);
	index[3] = get_index_coord(index_id + offsets.xx);

	vec3 base_ddx = dFdxCoarse(v_vertex);
	vec3 base_ddy = dFdyCoarse(v_vertex);
	vec4 base_dd = vec4(base_ddx.xz, base_ddy.xz);
	// Calculate the effective mipmap for regionspace
	float region_mip = log2(max(length(base_ddx.xz), length(base_ddy.xz)) * _vertex_density);

	// Color map
	vec4 color_map = region_uv.z > -1.0 ? textureLod(_color_maps, region_uv, region_mip) : COLOR_MAP;

	if (flat_terrain_normals) {
		NORMAL = normalize(cross(dFdyCoarse(VERTEX),dFdxCoarse(VERTEX)));
		TANGENT = normalize(cross(NORMAL, VIEW_MATRIX[2].xyz));
		BINORMAL = normalize(cross(NORMAL, TANGENT));
	}

	// defaults
	vec4 normal_rough = vec4(0., 1., 0., 0.7);
	vec4 albedo_height = vec4(1.);
	float normal_map_depth = 1.;
	float ao = 1.0;
	float ao_affect = 0.;

	if (textures_enabled) {
		// set to zero before accumulation
		albedo_height = vec4(0.);
		normal_rough = vec4(0.);
		normal_map_depth = 0.;
		ao = 0.;
		float total_weight = 0.;
		float sharpness = fma(56., blend_sharpness, 8.);

		// Get index control data
		// 1 - 4 lookups
		uvec4 control = floatBitsToUint(vec4(
			texelFetch(_control_maps, index[0], 0).r,
			texelFetch(_control_maps, index[1], 0).r,
			texelFetch(_control_maps, index[2], 0).r,
			texelFetch(_control_maps, index[3], 0).r));

		{
			// Auto blend calculation
			float auto_blend = clamp(fma(auto_slope * 2.0, (v_normal.y - 1.0), 1.0)
				- auto_height_reduction * 0.01 * v_vertex.y, 0.0, 1.0);
			// Enable Autoshader if outside regions or painted in regions, otherwise manual painted
			uvec4 is_auto = (control & uvec4(0x1u)) |
				uvec4(lessThan(ivec4(index[0].z, index[1].z, index[2].z, index[3].z), ivec4(0)));
			uint u_auto =
				((uint(auto_base_texture) & 0x1Fu) << 27u) |
				((uint(auto_overlay_texture) & 0x1Fu) << 22u) |
				((uint(fma(auto_blend, 255.0 , 0.5)) & 0xFFu) << 14u);
			control = control * (1u - is_auto) + u_auto * is_auto;
		}


		// Texture weights
		// Vectorised Deocode of all texture IDs, then swizzle to per index mapping.
		ivec4 t_id[2] = {ivec4(control >> uvec4(27u) & uvec4(0x1Fu)),
			ivec4(control >> uvec4(22u) & uvec4(0x1Fu))};
		ivec2 texture_ids[4] = ivec2[4](
			ivec2(t_id[0].x, t_id[1].x),
			ivec2(t_id[0].y, t_id[1].y),
			ivec2(t_id[0].z, t_id[1].z),
			ivec2(t_id[0].w, t_id[1].w));

		// interpolated weights.
		vec4 weights_id_1 = vec4(control >> uvec4(14u) & uvec4(0xFFu)) * DIV_255 * weights;
		vec4 weights_id_0 = weights - weights_id_1;
		vec2 t_weights[4] = {vec2(0), vec2(0), vec2(0), vec2(0)};
		for (int i = 0; i < 4; i++) {
				vec2 w_0 = vec2(weights_id_0[i]);
				vec2 w_1 = vec2(weights_id_1[i]);
				ivec2 id_0 = texture_ids[i].xx;
				ivec2 id_1 = texture_ids[i].yy;
				t_weights[0] += fma(w_0, vec2(equal(texture_ids[0], id_0)), w_1 * vec2(equal(texture_ids[0], id_1)));
				t_weights[1] += fma(w_0, vec2(equal(texture_ids[1], id_0)), w_1 * vec2(equal(texture_ids[1], id_1)));
				t_weights[2] += fma(w_0, vec2(equal(texture_ids[2], id_0)), w_1 * vec2(equal(texture_ids[2], id_1)));
				t_weights[3] += fma(w_0, vec2(equal(texture_ids[3], id_0)), w_1 * vec2(equal(texture_ids[3], id_1)));
		}


		// Process control data to determine each texture ID present, so that only
		// a single sample will be needed later, as all id are contiguous when features
		// like detiling, scale, rotation, and projection are not present.
		// 2 to 16 lookups
		uint id_read = 0u; // 1 bit per possible ID
		// world normal adjustment requires acess to previous id during next iteration
		vec4 nrm = vec4(0.0, 1.0, 0.0, 1.0);

		vec2 world_uv = v_vertex.xz;
		for (int i = 0; i < 4; i++) {
			for (int t = 0; t < 2; t++) {
				int id = texture_ids[i][t];
				uint mask = 1u << uint(id);
				if ((id_read & mask) == 0u) {
					// Set this id bit
					id_read |= mask;
					float id_w = t_weights[i][t];
					float id_scale = _texture_uv_scale_array[id] * 0.5;
					vec2 id_uv = fma(world_uv, vec2(id_scale), vec2(0.5));
					vec4 i_dd = base_dd * id_scale;
					vec4 alb = textureGrad(_texture_array_albedo, vec3(id_uv, float(id)), i_dd.xy, i_dd.zw);
					float world_normal = clamp(fma(TBN[0], vec3(nrm.x), fma(TBN[1], vec3(nrm.z), v_normal * vec3(nrm.y))).y, 0., 1.);
					nrm = textureGrad(_texture_array_normal, vec3(id_uv, float(id)), i_dd.xy, i_dd.zw);
					alb.rgb *= _texture_color_array[id].rgb;
					nrm.a = clamp(nrm.a + _texture_roughness_mod_array[id], 0., 1.);
					// Unpack normal map for blending.
					nrm.xyz = fma(nrm.xzy, vec3(2.0), vec3(-1.0));
					float id_ao = length(nrm.xyz) * 2.0 - 1.0;
					id_ao = mix(id_ao * id_ao * _texture_ao_strength_array[id] + 1.0 - _texture_ao_strength_array[id], 1.0, alb.a * alb.a);
					// height weight modifier.
					float id_weight = exp2(sharpness * log2(id_w + alb.a * world_normal));
					albedo_height += alb * id_weight;
					normal_rough += nrm * id_weight;
					normal_map_depth += _texture_normal_depth_array[id] * id_weight;
					ao_affect += _texture_ao_affect_array[id] * id_weight;
					ao += id_ao * id_weight;
					total_weight += id_weight;
				}
			}
		}
		// normalize accumulated values back to 0.0 - 1.0 range.
		float weight_inv = 1.0 / max(total_weight, 1e-8);
		albedo_height *= weight_inv;
		normal_rough *= weight_inv;
		normal_map_depth *= weight_inv;
		ao_affect *= weight_inv;
		ao *= weight_inv;
	}

	// Macro variation. 2 lookups
	vec3 macrov = vec3(1.);
	if (macro_variation_enabled) {
		float noise1 = texture(noise_texture, (uv * noise1_scale * .1 + noise1_offset) * rotate_plane(noise1_angle)).r;
		float noise2 = texture(noise_texture, uv * noise2_scale * .1).r;
		macrov = mix(macro_variation1, vec3(1.), noise1);
		macrov *= mix(macro_variation2, vec3(1.), noise2);
		macrov = mix(vec3(1.0), macrov, clamp(v_normal.y + macro_variation_slope, 0., 1.));
	}

	// Wetness/roughness modifier, converting 0 - 1 range to -1 to 1 range, clamped to Godot roughness values
	float roughness = clamp(fma(color_map.a - 0.5, 2.0, normal_rough.a), 0., 1.);

	// Apply PBR
	vec3 turf_normal = vec3(0.0, 0.0, 1.0);
	float turf_weight = 0.0;
	float turf_ao = 1.0;
	ALBEDO = albedo_height.rgb * color_map.rgb * macrov;
	if (ecology_enabled) {
		roughness = .95;
		vec2 eco_uv = v_vertex.xz / ecology_extent;
		vec4 eco = mix(texture(ecology_previous, eco_uv), texture(ecology_current, eco_uv), ecology_blend);
		vec4 site = texture(habitat_map, eco_uv);
		float litter = 1.0 - exp(-max(0.0, eco.r) * 2.5);
		float humus = 1.0 - exp(-max(0.0, eco.a - eco.r) * .55);
		float cover = 1.0 - exp(-max(0.0, eco.g) * 7.0);
		float wet = smoothstep(0.4, 0.95, eco.b);
		float fine = surface_noise(v_vertex.xz * 9.7 + vec2(71.3,19.1));
		// 1. Mineral/humic ground, with a distinct sandy substrate on shore bars.
		vec3 soil_tint = mix(vec3(.38,.30,.21), vec3(.17,.125,.085), humus);
		vec3 sand_tint = vec3(.56,.48,.34) * (.94 + .06 * fine);
		ALBEDO = mix(soil_tint * macrov, sand_tint, site.a);
		ALBEDO *= .985 + .015 * fine;
		// 2. Living low-cover patches. Coverage reads the authoritative plants.
		float grass_noise = .65 * surface_noise(v_vertex.xz * .8) + .35 * surface_noise(v_vertex.xz * 2.3 + vec2(17.2,39.8));
		float grass_mask = cover * (.45 + .55 * grass_noise);
		grass_mask *= smoothstep(0.0, .04, cover);
		// Fine unindividuated turf provides a continuous green visual ground.
		// Named plants remain separate, finite and inspectable. Sand stays open.
		float turf = dot(site.rgb, vec3(.48, .92, .98)) * (1.0 - site.a);
		turf *= ground_greenness * (.72 + .28 * grass_noise);
		grass_mask = max(grass_mask, turf);
		vec3 grass_tint = mix(vec3(.20,.32,.105), vec3(.31,.43,.16), .5 + .5 * fine);
		if (turf_enabled) {
			// World-locked periodic microtexture. Smooth warp breaks alignment
			// without per-cell stamps or geometry. Mips suppress distant sparkle.
			vec2 turf_uv = v_vertex.xz / turf_tile_m + vec2(grass_noise * .21, fine * .015);
			vec4 turf_color = texture(turf_albedo_height, turf_uv);
			vec4 turf_pbr = texture(turf_normal_roughness_ao, turf_uv);
			grass_tint = turf_color.rgb * mix(vec3(.82,.76,.55), vec3(1.0), ground_greenness);
			grass_mask *= mix(.88, 1.12, turf_color.a);
			grass_mask = clamp(grass_mask, 0.0, 1.0);
			vec2 slope = (turf_pbr.rg * 2.0 - 1.0) * turf_normal_strength;
			vec3 perturbation = vec3(slope.x, 0.0, slope.y);
			turf_normal = normalize(vec3(dot(perturbation, TBN[0]), dot(perturbation, TBN[1]), 1.0));
			turf_weight = grass_mask * (1.0 - smoothstep(12.0, 45.0, length(v_vertex - v_camera_pos)));
			turf_ao = mix(1.0, turf_pbr.a, grass_mask);
			roughness = mix(roughness, turf_pbr.b, grass_mask);
		}
		ALBEDO = mix(ALBEDO, grass_tint, grass_mask * .92);
		// 3. Discrete, subdued litter over that surface, never an all-ground stamp.
		vec2 leaf_uv = v_vertex.xz * 6.0;
		vec2 cell = floor(leaf_uv);
		float hash = fract(sin(dot(cell, vec2(12.9898,78.233))) * 43758.5453);
		vec2 p = fract(leaf_uv) - vec2(.5) - (vec2(fract(hash * 17.3),fract(hash * 41.7)) - .5) * .35;
		float angle = hash * 6.283185;
		p = rotate_plane(angle) * p;
		float edge = length(p * vec2(1.2, 2.0)) + .045 * sin(p.x * 67.0);
		float aa = max(.025, fwidth(edge));
		float leaf = 1.0 - smoothstep(.32-aa, .32+aa, edge);
		float vein = 1.0 - smoothstep(.007, .02, abs(p.y));
		float litter_mask = leaf * step(hash, litter) * (1.0 - grass_mask * .7);
		vec3 leaf_tint = mix(vec3(.20,.14,.085), vec3(.33,.24,.13), hash) * (1.0 + vein * .07);
		ALBEDO = mix(ALBEDO, leaf_tint, litter_mask * .7);
		turf_weight *= 1.0 - litter_mask * .7;
		ALBEDO *= mix(1.0,.64,wet);
		roughness = mix(roughness,.52,wet);
	}

	if (traffic_enabled) {
		float pressure = texture(traffic_map, v_vertex.xz / ecology_extent).r;
		float trail = smoothstep(.025, .35, pressure);
		turf_weight *= 1.0 - trail;
		ALBEDO = mix(ALBEDO, vec3(.105,.075,.045), trail * .92);
		roughness = mix(roughness, .65, trail);
		float rooted = texture(rooting_map, v_vertex.xz / ecology_extent).r;
		turf_weight *= 1.0 - smoothstep(.01, .4, rooted);
		float furrow = .78 + .22 * sin(v_vertex.x * 13.0 + sin(v_vertex.z * 4.0) * 3.0 + sin(v_vertex.x * 2.0 + v_vertex.z * 7.0) * 2.0);
		ALBEDO = mix(ALBEDO, vec3(.20,.115,.052) * furrow, smoothstep(.01,.4,rooted) * .95);
		roughness = mix(roughness, .92, rooted);
	}
	float snow = smoothstep(.0001, .006, snow_water_m) * smoothstep(.45, .85, v_normal.y);
	turf_weight *= 1.0 - snow;
	ALBEDO = mix(ALBEDO, vec3(.82,.88,.91), snow);
	ROUGHNESS = mix(roughness, .9, snow);
	SPECULAR = 1. - normal_rough.a;
	// Repack final normal map value.
	NORMAL_MAP = fma(normalize(mix(normalize(normal_rough.xzy), turf_normal, turf_weight)), vec3(0.5), vec3(0.5));
	NORMAL_MAP_DEPTH = normal_map_depth;

	// Higher and/or facing up, less occluded.
	AO = clamp(ao, 0., 1.) * mix(1.0, turf_ao, turf_weight);
	AO_LIGHT_AFFECT = ao_affect;
	if (soil_layer_enabled) {
		// Diagnostic colours bypass snow, lighting and decorative soil texture.
		// The exact same cell colours and fixed scale appear on the HUD map.
		ALBEDO = vec3(0.0);
		EMISSION = soil_diagnostic_colour(v_vertex.xz, ecology_extent);
		AO = 1.0;
		SPECULAR = 0.0;
		NORMAL_MAP_DEPTH = 0.0;
	}

}
