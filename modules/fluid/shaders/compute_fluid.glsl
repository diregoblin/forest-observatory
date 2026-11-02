#[compute]
#version 450
const float PI = 3.1415926;

layout(push_constant, std430) uniform Params {
    int run_mode;
    float radius;
    float smoothing_radius;
    float gravity;
    float default_density;
    float pressure_multiply;
    float damping;
    uint  count;
    uint  hash_size;
    float  mass;
    float delta;
    float _length;
    float width;
    float height;
    float viscosity_multiplier;
    float mouse_x;
    float mouse_y;
    uint boundary_count;
    float boundary_radius;
    uint sdf_enabled;
    float contact_epsilon;
    float density_floor;
    float padding0;
    float padding1;
} pc;

layout(set = 0, binding = 0, std430) restrict buffer ParticleBuffer {
    vec3 positions[];
}  particleBuf;

layout(set = 0, binding = 1, std430) restrict buffer PredictedBuffer {
    vec3 pred_positions[];
}  predictedBuf;

layout(set = 0, binding = 2, std430) restrict buffer VelocityBuffer {
    vec3 velocity[];
}  velocityBuf;

layout(set = 0, binding = 3, std430) restrict buffer DensityBuffer {
    float density[];
} densityBuf;

layout(set = 0, binding = 4, std430) restrict buffer HashCountBuffer {
    uint hash_count[];
}  hashCountBuf;

layout(set = 0, binding = 5, std430) restrict buffer PrefSumHashBuffer {
    uint pref_sum_hash_count[];
}  prefSumHashBuf;

layout(set = 0, binding = 7, std430) restrict buffer PrefSumHashBuffer2 {
    uint pref_sum_hash_count[];
}  prefSumHashBuf2;

layout(set = 0, binding = 6, std430) restrict buffer HashIndexBuffer {
    uint hash_indexes[];
} hashIndexBuf;

layout(set = 0, binding = 9, std430) restrict buffer ForceBuffer {
    vec3 forces[];
};

layout(set = 0, binding = 11) uniform sampler3D collision_sdf;

layout(set = 0, binding = 10, std430) restrict buffer MultiMeshBuffer {
    float instances[];
};

layout(set = 0, binding = 12, std430) restrict buffer BoundaryPositionBuffer {
    vec4 positions[];
} boundaryPosBuf;

layout(set = 0, binding = 13, std430) restrict buffer BoundaryVelocityBuffer {
    vec4 velocities[];
} boundaryVelBuf;

// Reuse the exact ordered fluid-neighbor candidates discovered by density.
// Overflow takes the original full hash walk, so capacity never truncates physics.
const uint NEIGHBOR_CAPACITY = 128u;
layout(set=0,binding=15,std430) restrict buffer NeighborCount { uint neighbor_counts[]; };
layout(set=0,binding=16,std430) restrict buffer NeighborIndex { uint neighbor_indices[]; };

layout(set=0,binding=17,std430) readonly buffer BoundaryBounds { vec4 boundary_min; vec4 boundary_max; };

// Conservative bounds for every boundary member of a hash bucket, including
// hash collisions. Ordered float bits allow exact unsigned atomic min/max.
layout(set=0,binding=18,std430) restrict buffer BucketBounds { uint bucket_bounds[]; };
uint ordered_float(float x) {
    uint b = floatBitsToUint(x);
    return b ^ ((b & 0x80000000u) != 0u ? 0xffffffffu : 0x80000000u);
}
float unordered_float(uint b) {
    return uintBitsToFloat(b ^ ((b & 0x80000000u) != 0u ? 0x80000000u : 0xffffffffu));
}
bool bucket_distant(uint h, vec3 p, float reach) {
    if (bucket_bounds[h * 8u + 6u] == 0u) return true;
    uint b = h * 8u;
    vec3 lo = vec3(unordered_float(bucket_bounds[b]), unordered_float(bucket_bounds[b+1u]), unordered_float(bucket_bounds[b+2u]));
    vec3 hi = vec3(unordered_float(bucket_bounds[b+3u]), unordered_float(bucket_bounds[b+4u]), unordered_float(bucket_bounds[b+5u]));
    // Axis-only comparison avoids a rounding-sensitive squared-distance gate.
    vec3 margin = vec3(reach + max(reach * 1e-5, 1e-7));
    return any(lessThan(p, lo-margin)) || any(greaterThan(p, hi+margin));
}

uint total_count() { return pc.count + pc.boundary_count; }

vec3 particle_position(uint i) {
    return i < pc.count ? predictedBuf.pred_positions[i] : boundaryPosBuf.positions[i - pc.count].xyz;
}

vec3 particle_velocity(uint i) {
    return i < pc.count ? velocityBuf.velocity[i] : boundaryVelBuf.velocities[i - pc.count].xyz;
}



void draw_sphere(uint i) {
    vec3 dop = particleBuf.positions[i];
    instances[16 * i + 3] = dop[0];
    instances[16 * i + 7] = dop[1];
    instances[16 * i + 11] = dop[2];


    float dens = densityBuf.density[i];
    vec4 color;
    float ratio;
    if (dens >= pc.default_density) {
        ratio = pc.default_density / dens;
        color = vec4(ratio, ratio, 1, 1);
    } else {
        ratio = dens / pc.default_density;
        color = vec4(1, 1, ratio, 1);
    }

    instances[16 * i + 12] = color.x;
    instances[16 * i + 13] = color.y;
    instances[16 * i + 14] = color.z;
    instances[16 * i + 15] = 1;
}


float spiky_kernel_pow2(float dst, float radius)
{
	if (dst < radius)
	{
		float scale = 15 / (2 * PI * pow(radius, 5));
		float v = radius - dst;
		return v * v * scale;
	}
	return 0;
}

float scale2 = 45 / (pow(pc.smoothing_radius, 6) * PI);
float derivative_spiky_pow3(float dst)
{
	if (dst <= pc.smoothing_radius)
	{
		float v = pc.smoothing_radius - dst;
		return -v * v * scale2;
	}
	return 0;
}

float mult1 = 315.0 / (64.0 * PI * pow(pc.smoothing_radius, 9.0));
float mult2 = pow(pc.smoothing_radius, 2);
float density_kernel(float d) {
    if (d >= pc.smoothing_radius) return 0;
    return mult1 * pow(mult2 - d * d, 3.0);
    // return spiky_kernel_pow2(d, h);
    // if (d >= h) return 0.0;
    // float v = (3.14159265359 * pow(h, 4.0)) / 6.0;
    // return pow(h - d, 2.0) / v;
}

float scale = 45 / (pow(pc.smoothing_radius, 6) * PI);
float viscosity_kernel(float dst) {
    if (dst <= pc.smoothing_radius)
	{
		float v = pc.smoothing_radius - dst;
		return v * scale;
	}
	return 0;
}

float density_derivative(float d) {
    return derivative_spiky_pow3(d);
    // if (d >= h) return 0.0;
    // float scale = 12.0 / (pow(h, 4.0) * 3.14159265359);
    // return (d - h) * scale;
}

float density_to_pressure(float rho) {
   return max(0, (rho - pc.default_density) * pc.pressure_multiply);
//    return pc.pressure_multiply * (pow(rho / pc.default_density, 7.0) - 1 );
}

float shared_pressure(float rho1, float rho2) {
    return (density_to_pressure(rho1) + density_to_pressure(rho2)) * 0.5;
}

uvec3 coord_to_cell_pos(vec3 pos) { 
    ivec3 ip = ivec3(floor(pos / pc.smoothing_radius));
    return uvec3(ip);
}

uint cell_hash(uvec3 cell) {
    uint a = uint(cell.x) * 73856093u;
    uint b = uint(cell.y) * 19349663u;
    uint c = uint(cell.z) * 83492791u;
    return a + b + c;
}



uint get_cell_count(uint h) {
    return hashCountBuf.hash_count[h];
}

void clear_hash_buffer(uint i) {
    hashCountBuf.hash_count[i] = 0;
    prefSumHashBuf.pref_sum_hash_count[i] = 0;
    prefSumHashBuf2.pref_sum_hash_count[i] = 0;
    bucket_bounds[i*8u+6u] = 0u;
    for (uint axis=0u; axis<3u; ++axis) {
        bucket_bounds[i*8u+axis] = 0xffffffffu;
        bucket_bounds[i*8u+axis+3u] = 0u;
    }
}

void fill_hash_count_buffer(uint i) {
    vec3 p = particle_position(i);
	uint h = cell_hash(coord_to_cell_pos(p)) % pc.hash_size;
    atomicAdd(hashCountBuf.hash_count[h], 1u);
    atomicAdd(prefSumHashBuf.pref_sum_hash_count[h], 1u);
    if (i < pc.count) return;
    atomicAdd(bucket_bounds[h*8u+6u], 1u);
    for (uint axis=0u; axis<3u; ++axis) {
        uint bits = ordered_float(p[axis]);
        atomicMin(bucket_bounds[h*8u+axis], bits);
        atomicMax(bucket_bounds[h*8u+axis+3u], bits);
    }
}

void fill_hash_indexes(uint i) {
	uint h = cell_hash(coord_to_cell_pos(particle_position(i))) % pc.hash_size;                    
    uint val = atomicAdd(prefSumHashBuf2.pref_sum_hash_count[h], -1u);                                  
    hashIndexBuf.hash_indexes[val - 1u] = i;  
}

void compute_density(uint j) {
    vec3 pos_j = predictedBuf.pred_positions[j];
    float rho = 0.0;
    uint neighbors = 0u;
    uvec3 base = coord_to_cell_pos(pos_j);
    for (int dx = -1; dx <= 1; ++dx) {
        for (int dy = -1; dy <= 1; ++dy) {
            for(int dz = -1; dz <= 1; ++dz) {
                uvec3 cell = base + uvec3(dx, dy, dz);
                uint h = cell_hash(cell) % pc.hash_size;
                uint start = prefSumHashBuf.pref_sum_hash_count[h] - 1;
                uint cnt   = get_cell_count(h);
                for (uint k = 0u; k < cnt; ++k) {
                    uint i = hashIndexBuf.hash_indexes[start - k];
                    vec3 rij = particle_position(i) - pos_j;
                    // The kernel is exactly zero outside its support. Reject
                    // candidates before sqrt/pow without shortening the support.
                    if (dot(rij, rij) >= pc.smoothing_radius * pc.smoothing_radius) continue;
                    if (i < pc.count && i != j) {
                        if (neighbors < NEIGHBOR_CAPACITY) neighbor_indices[j * NEIGHBOR_CAPACITY + neighbors] = i;
                        neighbors++;
                    }
                    float d = length(rij);
                    // Boundary samples use the same normalized particle mass as fluid
                    // samples; pc.mass remains the legacy fluid tuning parameter.
                    rho += density_kernel(d);
                }
            }
        }
    }
    densityBuf.density[j] = rho;
    neighbor_counts[j] = neighbors;
}

// vec2 add_viscosity_force(uint j) {
//     vec2 force = vec2(0, 0);
//     vec2 pos_j = predictedBuf.pred_positions[j];
//     uvec2 base = coord_to_cell_pos(predictedBuf.pred_positions[j]);

//     for (int dx = -1; dx <= 1; ++dx) {
//         for (int dy = -1; dy <= 1; ++dy) {
//             uvec2 cell = base + uvec2(dx, dy);
//             uint h = cell_hash(cell) % pc.hash_size;
//             uint start = prefSumHashBuf.pref_sum_hash_count[h] - 1;
//             uint cnt   = get_cell_count(h);
//             for (uint k = 0u; k < cnt; ++k) {
//                 uint i = hashIndexBuf.hash_indexes[start - k];
//                 float d = length(predictedBuf.pred_positions[i] - pos_j);
//                 rho += density_kernel(pc.smoothing_radius, d) * pc.mass;
//             }
//         }
//     }
//     densityBuf.density[j] = rho;
// } 

void accumulate_force(uint i, uint j, vec3 pos_j, float rho_j, float Pj,
                      inout vec3 force, inout vec3 viscosity_force) {
    vec3 rij = particle_position(i) - pos_j;
    if (dot(rij, rij) >= pc.smoothing_radius * pc.smoothing_radius) return;
    float rho_i = max(pc.density_floor, densityBuf.density[i]);
    float d = length(rij);
    float slope = density_derivative(d);
    vec3 dir;
    if (d > 0.0) {
        dir = rij / d;
    } else {
        dir = vec3(i - 2 * j, i + 3 * j, j - i);
        dir = dir / length(dir);
    }
    float Pi = density_to_pressure(rho_i);
    viscosity_force += (particle_velocity(i) - velocityBuf.velocity[j]) * viscosity_kernel(d) / rho_i;
    force += (Pj / (rho_j * rho_j) + Pi / (rho_i * rho_i)) * dir * slope;

}

void compute_force(uint j) {
    vec3 pos_j = predictedBuf.pred_positions[j];
    float rho_j = max(densityBuf.density[j], pc.density_floor);
    float Pj = density_to_pressure(rho_j);
    vec3 force = vec3(0.0), viscosity_force = vec3(0.0);
    uint neighbors = neighbor_counts[j];
    if (neighbors <= NEIGHBOR_CAPACITY) {
        for (uint k=0u; k<neighbors; ++k) {
            accumulate_force(neighbor_indices[j*NEIGHBOR_CAPACITY+k],j,pos_j,rho_j,Pj,force,viscosity_force);
        }
    } else {
        uvec3 base = coord_to_cell_pos(pos_j);
        for (int dx=-1;dx<=1;++dx) for(int dy=-1;dy<=1;++dy) for(int dz=-1;dz<=1;++dz) {
            uint h=cell_hash(base+uvec3(dx,dy,dz))%pc.hash_size;
            uint start=prefSumHashBuf.pref_sum_hash_count[h]-1;
            uint cnt=get_cell_count(h);
            for(uint k=0u;k<cnt;++k) {
                uint i=hashIndexBuf.hash_indexes[start-k];
                if(i==j || i>=pc.count) continue;
                accumulate_force(i,j,pos_j,rho_j,Pj,force,viscosity_force);
            }
        }
    }
    forces[j] = force + pc.viscosity_multiplier * viscosity_force / rho_j;
}

void predict(uint id, float delta) {
    if (id < pc.count) {
        predictedBuf.pred_positions[id] = particleBuf.positions[id] + velocityBuf.velocity[id] * delta;
    }
}

void resolve_boundary(uint id, inout vec3 pos, inout vec3 vel) {
    // A conservative enclosing box rejects only positions that cannot touch any
    // boundary sphere. Once inside, retain the exact original sequential solve.
    float contact = pc.radius + pc.boundary_radius;
    if (pc.boundary_count == 0u || (boundary_min.w > 0.5 &&
        (any(lessThan(pos, boundary_min.xyz - vec3(contact))) ||
         any(greaterThan(pos, boundary_max.xyz + vec3(contact)))))) return;
    vec3 pos_j = pos;
    uvec3 base = coord_to_cell_pos(pos_j);
    for (int dx = -1; dx <= 1; ++dx) {
        for (int dy = -1; dy <= 1; ++dy) {
            for (int dz = -1; dz <= 1; ++dz) {
                uvec3 cell = base + uvec3(dx, dy, dz);
                uint h = cell_hash(cell) % pc.hash_size;
                if (bucket_distant(h, pos, contact)) continue;
                uint start = prefSumHashBuf.pref_sum_hash_count[h] - 1;
                uint cnt = get_cell_count(h);
                for (uint k = 0u; k < cnt; ++k) {
                    uint i = hashIndexBuf.hash_indexes[start - k];
                    if (i < pc.count) continue;
                    vec3 bp = particle_position(i);
                    vec3 delta_pos = pos - bp;
                    // Boundary samples are solid spheres. Their centers are inset into
                    // the modeled wall, so the full sum of radii gives the contact.
                    float min_d = pc.radius + pc.boundary_radius;
                    float d2 = dot(delta_pos, delta_pos);
                    if (d2 > pc.contact_epsilon * pc.contact_epsilon && d2 < min_d * min_d) {
                        float d = sqrt(d2);
                        vec3 n = delta_pos / d;
                        pos = bp + n * min_d;
                        vec3 surface_vel = particle_velocity(i);
                        vec3 relative = vel - surface_vel;
                        float vn = dot(relative, n);
                        if (vn < 0.0) relative -= (1.0 + pc.damping) * vn * n;
                        relative -= relative - dot(relative, n) * n;
                        vel = surface_vel + relative;
                    }
                }
            }
        }
    }
}


layout(set=0,binding=14,std430) readonly buffer SdfMetadata {
    mat4 simulation_to_sdf;
    vec4 sdf_min;
    vec4 sdf_extent_scale;
};
vec3 sdf_cell_world() {
    return sdf_extent_scale.xyz / vec3(textureSize(collision_sdf,0)) * sdf_extent_scale.w;
}
float static_distance(vec3 p) {
    vec3 local = (simulation_to_sdf * vec4(p,1)).xyz;
    vec3 uv = (local-sdf_min.xyz)/sdf_extent_scale.xyz;
    if (any(lessThan(uv,vec3(0))) || any(greaterThan(uv,vec3(1)))) return 1e20;
    return texture(collision_sdf,uv).r * sdf_extent_scale.w;
}
void collide_static(inout vec3 pos, inout vec3 vel) {
    vec3 cell = sdf_cell_world();
    float dist = static_distance(pos);
    if (dist >= pc.radius) return;
    vec3 gradient = vec3(
        (static_distance(pos+vec3(cell.x,0,0))-static_distance(pos-vec3(cell.x,0,0)))/cell.x,
        (static_distance(pos+vec3(0,cell.y,0))-static_distance(pos-vec3(0,cell.y,0)))/cell.y,
        (static_distance(pos+vec3(0,0,cell.z))-static_distance(pos-vec3(0,0,cell.z)))/cell.z);
    if (dot(gradient,gradient) < 1e-16) return;
    vec3 normal = normalize(gradient);
    pos += (pc.radius-dist) * normal;
    float vn = dot(vel,normal);
    if (vn < 0.0) vel -= (1.0+pc.damping)*vn*normal;
}
void correct(uint id, float delta) {
    vec3 pos = particleBuf.positions[id];
    vec3 vel = velocityBuf.velocity[id];
    vel += forces[id] * delta;
    vel.y -= pc.gravity * delta;
    if (pc.sdf_enabled != 0u) {
        vec3 cell = sdf_cell_world();
        float travel = length(vel * delta);
        int samples = max(1, int(ceil(travel / (0.5 * min(pc.radius,min(cell.x,min(cell.y,cell.z)))))));
        // Collision sweep only: forces are evaluated once, no velocity clamp.
        float dt = delta / float(samples);
        for (int i=0; i<samples; ++i) {
            pos += vel * dt;
            collide_static(pos,vel);
        }
    } else {
        pos += vel * delta;
    }
    resolve_boundary(id, pos, vel);
    float room_r = pc.radius;
    if (pos.x < room_r) { pos.x = room_r; vel.x *= -pc.damping; }
    if (pos.x > pc._length - room_r) { pos.x = pc._length - room_r; vel.x *= -pc.damping; }
    if (pos.y < room_r) { pos.y = room_r; vel.y *= -pc.damping; }
    if (pos.y > pc.height - room_r) { pos.y = pc.height - room_r; vel.y *= -pc.damping; }
    if (pos.z < room_r) { pos.z = room_r; vel.z *= -pc.damping; }
    if (pos.z > pc.width - room_r) { pos.z = pc.width - room_r; vel.z *= -pc.damping; }
    particleBuf.positions[id] = pos;
    velocityBuf.velocity[id] = vel;
    draw_sphere(id);
}

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
void main() {
	uint i = gl_GlobalInvocationID.x;
    switch(pc.run_mode) {
        case -1:
            if (i < pc.hash_size) {
                // clear_circle(i);
            }
            break;
        case 0:
            if (i < pc.hash_size) {
                clear_hash_buffer(i);
            }
            break;
        case 1:
            if (i < total_count()) {
                predict(i, pc.delta);
                fill_hash_count_buffer(i);
            }
            break;
        case 2:
            if (i < total_count()) {
                fill_hash_indexes(i);
            }
            break;
        case 3:
            if (i < pc.count) {
                // integrate(i, pc.delta);
            }
            break;
        case 4:
            if (i < pc.count) {
                compute_density(i);
            }
            break;
        case 5:
            if (i < pc.count) {
                compute_force(i);
            }
            break;
        case 6:
             if (i < pc.count) {
                correct(i, pc.delta);
            }
            break;
    }
}
