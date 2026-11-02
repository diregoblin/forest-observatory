#[compute]
#version 450
layout(local_size_x=64, local_size_y=1, local_size_z=1) in;
// Match PackedInt32Array([mode, 0, 0, 0]) on Godot as well as Redot.
layout(push_constant, std430) uniform Push { ivec4 dispatch_data; } pc;
layout(set=0,binding=0,std430) readonly buffer Positions { vec4 positions[]; };
layout(set=0,binding=1,std430) buffer Fields { uvec2 fields[]; };
layout(set=0,binding=2,std430) readonly buffer Meta {
 mat4 model; mat4 view; mat4 projection; mat4 inverse_projection;
 vec4 sizes; vec4 config; vec4 tint;
} m;
layout(set=0,binding=3,rg32f) uniform writeonly image2D surface_out;
layout(set=0,binding=4,rgba16f) uniform image2D color_out;
layout(set=0,binding=5) uniform sampler2D scene_depth;
layout(set=0,binding=6) uniform sampler2D background;
layout(set=0,binding=7) uniform sampler2D surface_in;
layout(set=0,binding=8,rgba16f) uniform writeonly image2D background_out;
vec3 ray(vec2 uv) {
 vec4 p=m.inverse_projection*vec4(uv*2.-1.,0.5,1.);
 return p.xyz/p.w;
}
vec2 field(ivec2 p) {
 ivec2 sz=ivec2(m.sizes.zw);
 if(any(lessThan(p,ivec2(0)))||any(greaterThanEqual(p,sz))) return vec2(0);
 uvec2 f=fields[p.y*sz.x+p.x];
 return f.x==0x7f7fffffu ? vec2(0) : vec2(uintBitsToFloat(f.x),float(f.y)*1e-6);
}
vec3 point(vec2 uv,float z) { vec3 r=ray(uv); return r*(-z/r.z); }
void main() {
 uint id=gl_GlobalInvocationID.x;
 ivec2 sz=ivec2(m.sizes.zw), full=ivec2(m.sizes.xy);
 if(pc.dispatch_data.x==4) {
  if(id<uint(full.x*full.y)) {
   ivec2 p=ivec2(int(id)%full.x,int(id)/full.x);
   imageStore(background_out,p,imageLoad(color_out,p));
  }
 } else if(pc.dispatch_data.x==0) {
  if(id<uint(sz.x*sz.y)) fields[id]=uvec2(0x7f7fffffu,0u);
 } else if(pc.dispatch_data.x==1) {
  if(id>=uint(m.config.x)) return;
  vec3 center=(m.view*m.model*vec4(positions[id].xyz,1.)).xyz;
  float radius=m.config.y;
  if(center.z>=-radius*1.5) return;
  vec4 c=m.projection*vec4(center,1.);
  vec2 uv=(c.xy/c.w)*.5+.5;
  vec2 extent=abs(vec2(m.projection[0][0],m.projection[1][1]))*radius/(-center.z-radius)*.5;
  ivec2 lo=max(ivec2(floor((uv-extent)*vec2(sz))),ivec2(0));
  ivec2 hi=min(ivec2(ceil((uv+extent)*vec2(sz))),sz-1);
  for(int y=lo.y;y<=hi.y;y++) for(int x=lo.x;x<=hi.x;x++) {
   vec3 d=normalize(ray((vec2(x,y)+.5)/vec2(sz)));
   float b=dot(d,center), disc=b*b-dot(center,center)+radius*radius;
   if(disc<=0.) continue;
   float root=sqrt(disc), depth=-(b-root)*d.z;
   if(depth<=0.) continue;
   uint index=uint(y*sz.x+x);
   atomicMin(fields[index].x,floatBitsToUint(depth));
   atomicAdd(fields[index].y,uint(min(root*2.,.1)*1e6));
  }
 } else if(pc.dispatch_data.x==2) {
  if(id>=uint(sz.x*sz.y)) return;
  ivec2 p=ivec2(int(id)%sz.x,int(id)/sz.x);
  vec2 base=field(p);
  if(base.x==0.) { imageStore(surface_out,p,vec4(0)); return; }
  vec2 sum=vec2(0); float wsum=0.;
  int blur_radius=int(m.config.w);
  for(int y=-blur_radius;y<=blur_radius;y++) for(int x=-blur_radius;x<=blur_radius;x++) {
   vec2 v=field(p+ivec2(x,y));
   if(v.x==0.) continue;
   float dz=(v.x-base.x)/max(m.config.y*2.,1e-5);
   float w=exp(-float(x*x+y*y)/8.-dz*dz*2.);
   sum+=w*v; wsum+=w;
  }
  imageStore(surface_out,p,vec4(sum/max(wsum,1e-6),0,0));
 } else if(pc.dispatch_data.x==3) {
  if(id>=uint(full.x*full.y)) return;
  ivec2 p=ivec2(int(id)%full.x,int(id)/full.x);
  vec2 uv=(vec2(p)+.5)/vec2(full);
  vec2 s=textureLod(surface_in,uv,0.).xy;
  if(s.x<=0.) return;
  vec3 pos=point(uv,s.x);
  vec4 clip=m.projection*vec4(pos,1.);
  float depth=clip.z/clip.w, scene=texelFetch(scene_depth,p,0).r;
  // Forward+ reverse Z: a larger value is closer to the camera.
  if(depth+1e-6<scene) return;
  vec2 e=1./vec2(sz);
  float zx=textureLod(surface_in,uv+vec2(e.x,0),0.).x;
  float zy=textureLod(surface_in,uv+vec2(0,e.y),0.).x;
  zx=(zx<=0.||abs(zx-s.x)>m.config.y*3.)?s.x:zx;
  zy=(zy<=0.||abs(zy-s.x)>m.config.y*3.)?s.x:zy;
  vec3 dx=point(uv+vec2(e.x,0),zx)-pos;
  vec3 dy=point(uv+vec2(0,e.y),zy)-pos;
  vec3 n=normalize(cross(dx,dy));
  if(dot(n,-pos)<0.) n=-n;
  vec3 eye=normalize(-pos), light=normalize(vec3(-.4,.8,.7));
  float f=.02+.98*pow(1.-max(dot(n,eye),0.),5.);
  float thick=clamp(s.y,.001,.2);
  vec2 refract_uv=clamp(uv+n.xy*min(thick*.18,.018),vec2(0),vec2(1));
  // Don't sample foreground objects across the water silhouette.
  if(textureLod(scene_depth,refract_uv,0.).r>depth) refract_uv=uv;
  // Low-cost mode shades against this pixel without a full-size background copy.
  vec3 bg=m.config.z>.5 ? imageLoad(color_out,p).rgb : textureLod(background,refract_uv,0.).rgb;
  vec3 transmit=exp(-mix(vec3(11.,3.5,1.8),vec3(150.,150.,160.),m.tint.a)*thick);
  vec3 water=bg*transmit+m.tint.rgb*(1.-transmit)*(.4+.6*max(dot(n,light),0.));
  vec3 sky=mix(vec3(.025,.06,.09),vec3(.65,.85,1.),clamp(n.y*.5+.5,0.,1.));
  float spec=pow(max(dot(n,normalize(eye+light)),0.),90.);
  imageStore(color_out,p,vec4(mix(water,sky,f)+spec*.8,1.));
 }
}
