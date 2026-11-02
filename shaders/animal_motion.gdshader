shader_type spatial;
render_mode cull_disabled;
instance uniform float pose_stride = 0.0;
instance uniform float pose_head = 0.0;
instance uniform float pose_ears = 0.0;
instance uniform float pose_breath = 0.0;
instance uniform float pose_bob = 0.0;
instance uniform float pose_tail = 0.0;
instance uniform float pose_wings = 0.0;
instance uniform float pose_flight = 0.0;
instance uniform float pose_wrist = 0.0;
instance uniform vec3 wing_hinge = vec3(0.0);
instance uniform vec3 head_pivot = vec3(0.0);
instance uniform float body_height = 1.0;
vec3 rx(vec3 p, float a) {return vec3(p.x,p.y*cos(a)-p.z*sin(a),p.y*sin(a)+p.z*cos(a));}
vec3 ry(vec3 p, float a) {return vec3(p.x*cos(a)+p.z*sin(a),p.y,-p.x*sin(a)+p.z*cos(a));}
vec3 rz(vec3 p, float a) {return vec3(p.x*cos(a)-p.y*sin(a),p.x*sin(a)+p.y*cos(a),p.z);}
void vertex() {
	vec3 pivot = CUSTOM0.xyz;
	int role = int(round(CUSTOM0.w));
	if (role == 2) {
		float a = pose_ears * sign(pivot.x);
		VERTEX = pivot + rz(VERTEX-pivot,a); NORMAL = rz(NORMAL,a);
	}
	if (role == 1 || role == 2) {
		VERTEX = head_pivot + rx(VERTEX-head_pivot,pose_head); NORMAL = rx(NORMAL,pose_head);
	} else if (role == 3) {
		float a = pose_stride * (pivot.x < 0.0 ? 1.0 : -1.0);
		VERTEX = pivot + rx(VERTEX-pivot,a); NORMAL = rx(NORMAL,a);
	} else if (role == 4) {
		VERTEX = pivot + ry(VERTEX-pivot,pose_tail); NORMAL = ry(NORMAL,pose_tail);
	} else if (role == 5) {
		float a = pose_wings * sign(pivot.x);
		VERTEX = pivot + rz(VERTEX-pivot,a); NORMAL = rz(NORMAL,a);
	} else if (role == 6 || role == 7) {
		float side = sign(pivot.x);
		if (role == 7) {
			float yaw = side * mix(.45, .1 + pose_wrist, pose_flight);
			float flex = side * pose_wrist * pose_flight * .5;
			VERTEX = pivot + ry(VERTEX-pivot,yaw); NORMAL = ry(NORMAL,yaw);
			VERTEX = pivot + rz(VERTEX-pivot,flex); NORMAL = rz(NORMAL,flex);
		}
		vec3 shoulder = vec3(side*wing_hinge.x,wing_hinge.yz);
		float fold = side * 1.35 * (1.0-pose_flight);
		float flap = side * mix(-.25,pose_wings,pose_flight);
		VERTEX = shoulder + ry(VERTEX-shoulder,fold); NORMAL = ry(NORMAL,fold);
		float fold_pitch = -.75*(1.0-pose_flight);
		VERTEX = shoulder + rx(VERTEX-shoulder,fold_pitch); NORMAL = rx(NORMAL,fold_pitch);
		VERTEX = shoulder + rz(VERTEX-shoulder,flap); NORMAL = rz(NORMAL,flap);
	} else if (role == 8) {
		float a = pose_stride * (pivot.x < 0.0 ? 1.0 : -1.0) + 1.20*pose_flight;
		VERTEX = pivot + rx(VERTEX-pivot,a); NORMAL = rx(NORMAL,a);
	}
	if (wing_hinge.x > 0.0) {
		vec3 center = vec3(0.0,body_height*.52,0.0);
		VERTEX = center + rx(VERTEX-center,.55*pose_flight);
		NORMAL = rx(NORMAL,.55*pose_flight);
	}
	VERTEX.y *= 1.0 + pose_breath;
	VERTEX.y += pose_bob * body_height;
	NORMAL.y /= 1.0 + pose_breath;
	NORMAL = normalize(NORMAL);
}
void fragment() {ALBEDO=COLOR.rgb; ROUGHNESS=.95;}
