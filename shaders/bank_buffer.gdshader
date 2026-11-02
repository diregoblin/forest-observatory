// Static microrelief, not a terrain/soil simulation or an eroding river bank.
// Native atlas addressing adapted from Terrain3D 1.1.0 displacement_buffer.glsl.
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
shader_type canvas_item;

uniform float _tessellation_level = 2.0;
uniform vec3 _target_pos = vec3(0.0);
uniform float _mesh_size = 32.0;
uniform float _vertex_spacing = 1.0;
uniform float _vertex_density = 1.0;

float bank_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 f = fract(point);
	f = f * f * (3.0 - 2.0 * f);
	vec4 h = fract(sin(vec4(dot(cell, vec2(73.13, 39.27)),
		dot(cell + vec2(1, 0), vec2(73.13, 39.27)),
		dot(cell + vec2(0, 1), vec2(73.13, 39.27)),
		dot(cell + vec2(1, 1), vec2(73.13, 39.27)))) * 13427.17);
	return mix(mix(h.x, h.y, f.x), mix(h.z, h.w, f.x), f.y);
}

void fragment() {
	// Each atlas tile is a native clipmap level, aligned to world coordinates.
	float level = floor(UV.x * _tessellation_level);
	float density = exp2(level);
	vec2 point = (vec2(fract(UV.x * _tessellation_level), UV.y) - .5)
		* (_mesh_size * 2.0) / density;
	point += round(_target_pos.xz * _vertex_density * density) / density;
	point *= _vertex_spacing;
	// Rounded clods are resolvable on the 25 cm near mesh. No TIME or frame seed.
	float height = .7 * bank_noise(point * .9 + vec2(18.3, 71.7))
		+ .3 * bank_noise(point * 1.7 + vec2(41.2, 9.8));
	// Only Y is consumed. Habitat, water, snow and diagnostics remain live masks
	// in the terrain vertex shader, even with a stationary camera/buffer.
	COLOR = vec4(.5, height, .5, 1.0);
}
