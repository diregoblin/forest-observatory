#[compute]
#version 450
layout(local_size_x=256) in;
layout(set=0,binding=0,std430) readonly buffer Local { vec4 local_positions[]; };
layout(set=0,binding=1,std430) writeonly buffer Position { vec4 positions[]; };
layout(set=0,binding=2,std430) writeonly buffer Velocity { vec4 velocities[]; };
layout(set=0,binding=3,std430) readonly buffer Meta {
 mat4 body; mat4 inverse_sim; vec4 linear; vec4 angular;
} m;
// The CPU sends 16 bytes; keep the reflected block size identical in both engines.
layout(push_constant,std430) uniform Push { uvec4 dispatch_data; } pc;
void main() {
 uint i=gl_GlobalInvocationID.x;
 if(i>=pc.dispatch_data.x) return;
 vec3 world=(m.body*vec4(local_positions[i].xyz,1.)).xyz;
 positions[i]=vec4((m.inverse_sim*vec4(world,1.)).xyz,1.);
 vec3 r=world-m.body[3].xyz;
 vec3 velocity=(m.linear.xyz+cross(m.angular.xyz,r))*m.linear.w;
 velocities[i]=vec4(mat3(m.inverse_sim)*velocity,0.);
}
