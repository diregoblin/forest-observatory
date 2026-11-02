#[compute]
#version 450
layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer InputBuffer {
    uint in_data[];
};

layout(set = 0, binding = 1, std430) restrict buffer OutputBuffer {
    uint out_data[];
};

// Match the 16-byte CPU upload exactly on both Godot and Redot. A single
// scalar reflects as 4 bytes in Godot, while Redot rounds it up to 16.
layout(push_constant, std430) uniform Params {
    uvec4 scan; // x = offset; yzw reserved
} pc;

void main() {
    uint i = gl_GlobalInvocationID.x;
    if (i >= in_data.length()) {
        return;
    }

    if (i >= pc.scan.x) {
        out_data[i] = in_data[i] + in_data[i - pc.scan.x];
    } else {
        out_data[i] = in_data[i];
    }
}
