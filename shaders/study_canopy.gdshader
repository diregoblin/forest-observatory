shader_type spatial;
render_mode cull_disabled;

// Isolated visual study, NOT the reference author's shader and not a live-world
// material. Object-anchored leaf stamps modulate a light-dependent warm/cool ramp.
uniform vec4 canopy_base : source_color = vec4(.40,.49,.43,1);
uniform vec4 leaf_base : source_color = vec4(.56,.63,.44,1);
uniform bool flat_normals = false;
uniform float leaf_scale = 3.3;
varying vec3 local_position;
varying vec3 local_normal;
varying vec3 crown_view_normal;
varying float leaf_part;
varying float stamp;

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3))))*43758.5453);
}
float leaves(vec2 p) {
	vec2 cell = floor(p);
	float result = 0.0;
	for (int y=-1;y<=1;y++) {
		for (int x=-1;x<=1;x++) {
			vec2 id=cell+vec2(float(x),float(y));
			vec2 h=hash2(id);
			vec2 d=p-id-(.15+.7*h);
			float a=h.x*6.2831853;
			d=mat2(vec2(cos(a),sin(a)),vec2(-sin(a),cos(a)))*d;
			float r=length(d/vec2(.22+.19*h.y,.12+.08*h.x));
			float feather=max(fwidth(r),.12);
			float shape=1.0-smoothstep(.8-feather,1.0+feather,r);
			result=max(result,shape*(.5+.5*h.y));
		}
	}
	return result;
}
void vertex() {
	local_position=VERTEX;
	local_normal=NORMAL;
	crown_view_normal=MODELVIEW_NORMAL_MATRIX*NORMAL;
	leaf_part=1.0-COLOR.a;
}
void fragment() {
	NORMAL=normalize(crown_view_normal);
	vec3 n=normalize(local_normal);
	// Soft triplanar projection keeps the markings anchored to the crown rather
	// than the screen; derivatives fade detail instead of sparkling at distance.
	vec3 weights=pow(abs(n),vec3(6.0));
	weights/=max(dot(weights,vec3(1.0)),.001);
	vec3 p=local_position*leaf_scale;
	stamp=dot(vec3(leaves(p.zy),leaves(p.xz),leaves(p.xy)),weights);
	stamp*=1.0-smoothstep(.6,1.4,length(fwidth(p)));
	float cloud=sin(local_position.x*1.3+sin(local_position.z*.9))*sin(local_position.y*.95);
	vec3 crown=mix(canopy_base.rgb,leaf_base.rgb,.45+.2*cloud);
	crown*=.96+.10*stamp;
	ALBEDO=mix(COLOR.rgb,crown,leaf_part);
	ROUGHNESS=1.0;
	if (flat_normals) {NORMAL=normalize((VIEW_MATRIX*vec4(vec3(.25,.9,.35),0.0)).xyz);}
}
void light() {
	float ndl=dot(NORMAL,LIGHT);
	float feather=max(fwidth(ndl),.055);
	float value=.20+1.0*smoothstep(-.1-feather,.85+feather,ndl);
	float warm=smoothstep(.05-feather,.55+feather,ndl)*stamp;
	vec3 paint=mix(vec3(.70,.83,1.0),vec3(1.65,1.40,.68),warm);
	vec3 leaf_light=paint*value*(1.0+.26*stamp*warm);
	vec3 bark_light=vec3(.25+.75*max(0.0,ndl));
	DIFFUSE_LIGHT+=mix(bark_light,leaf_light,leaf_part)*ATTENUATION*LIGHT_COLOR/PI;
}
