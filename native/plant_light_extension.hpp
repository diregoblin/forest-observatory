#pragma once
#include <godot_cpp/templates/sort_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <unordered_map>

// Pure batch arithmetic; ForestTrees still owns all state and model time.
class ForestPlantLightNative : public RefCounted {
    GDCLASS(ForestPlantLightNative, RefCounted);
    struct HeightOrder {
        const double *height = nullptr;
        bool operator()(int a, int b) const { return height[a] > height[b]; }
    };
    struct Column { Vector2i key; std::vector<int> ids; };
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("compute", "species", "positions", "sizes", "alive",
            "reference_heights", "crown_radii"), &ForestPlantLightNative::compute);
    }
public:
    Dictionary compute(const PackedInt32Array &species, const PackedVector3Array &positions,
            const PackedFloat64Array &sizes, const PackedByteArray &alive,
            const PackedFloat64Array &reference_heights, const PackedFloat64Array &crown_radii) const {
        const int64_t n = species.size();
        if (positions.size() != n || sizes.size() != n || alive.size() != n ||
                reference_heights.size() != crown_radii.size()) return {};
        for (int64_t s = 0; s < reference_heights.size(); ++s)
            if (!std::isfinite(reference_heights[s]) || reference_heights[s] < 0 ||
                    !std::isfinite(crown_radii[s]) || crown_radii[s] < 0) return {};
        std::vector<double> height(n);
        std::vector<Column> columns;
        std::unordered_map<uint64_t, size_t> membership;
        for (int64_t i = 0; i < n; ++i) {
            const int s = species[i];
            const auto p = positions[i];
            if (s < 0 || s >= reference_heights.size() || !std::isfinite(sizes[i]) || sizes[i] < 0 ||
                    alive[i] > 1 || !p.is_finite() || std::abs(p.x) > 1e9 || std::abs(p.z) > 1e9) return {};
            height[i] = sizes[i] * reference_heights[s];
            const int x = int(double(p.x) / 16.0), z = int(double(p.z) / 16.0);
            const uint64_t key = (uint64_t(uint32_t(x)) << 32) | uint32_t(z);
            auto inserted = membership.emplace(key, columns.size());
            if (inserted.second) columns.push_back({Vector2i(x, z), {}});
            columns[inserted.first->second].ids.push_back(int(i));
        }
        PackedFloat64Array light;
        light.resize(n);
        auto *values = light.ptrw();
        Dictionary covers;
        SortArray<int, HeightOrder> sorter;
        sorter.compare.height = height.data();
        constexpr double pi = 3.14159265358979323846;
        // GDScript's pow receives a runtime exponent. Keep the same libm path,
        // rather than silently replacing it with a differently rounded formula.
        volatile double exponent = 2.0;
        for (auto &column : columns) {
            if (column.ids.size() > 1) sorter.sort(column.ids.data(), column.ids.size());
            double cover = 0.0;
            for (int i : column.ids) {
                values[i] = std::exp(-cover);
                if (alive[i]) {
                    const double radius = crown_radii[species[i]] * sizes[i];
                    const double area = pi * std::pow(radius, exponent);
                    cover += area / 256.0;
                }
            }
            covers[column.key] = cover;
        }
        Dictionary result;
        result["light"] = light;
        result["columns"] = covers;
        return result;
    }
};
