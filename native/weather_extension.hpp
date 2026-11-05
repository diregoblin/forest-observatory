#pragma once
#include "weather_field.hpp"
#include <godot_cpp/variant/vector2.hpp>

class ForestWeatherFieldNative : public RefCounted {
    GDCLASS(ForestWeatherFieldNative,RefCounted);
    forest::CloudField field;
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("configure","size","span_m","density"),&ForestWeatherFieldNative::configure);
        ClassDB::bind_method(D_METHOD("sample_grid","resolution","extent_m","offset_m","cover","potential_m_s","uniform_liquid_m_s"),&ForestWeatherFieldNative::sample_grid,DEFVAL(0.0));
        ClassDB::bind_method(D_METHOD("sample_density","x","z","extent_m","offset_m"),&ForestWeatherFieldNative::sample_density);
    }
public:
    bool configure(int size,double span,const PackedFloat64Array &values) {
        return field.configure(size,span,unpack(values));
    }
    double sample_density(double x,double z,double extent,const Vector2 &offset) const {
        return field.sample(x,z,extent,offset.x,offset.y);
    }
    Dictionary sample_grid(int resolution,double extent,const Vector2 &offset,double cover,
                           double potential,double uniform_liquid) const {
        Dictionary result;
        if (field.n == 0 || resolution < 2 || resolution > 2048 ||
            !std::isfinite(extent) || extent <= 0 || !offset.is_finite() ||
            !std::isfinite(cover) || cover < 0 || cover > 1 ||
            !std::isfinite(potential) || potential < 0 ||
            !std::isfinite(uniform_liquid) || uniform_liquid < 0) return result;
        PackedFloat64Array rates; rates.resize(resolution*resolution);
        double *out = rates.ptrw(), sum=0;
        const double dx=extent/resolution;
        for (int z=0;z<resolution;++z) for(int x=0;x<resolution;++x) {
            const double rate=potential*forest::CloudField::rain_weight(
                field.sample((x+.5)*dx,(z+.5)*dx,extent,offset.x,offset.y),cover);
            out[z*resolution+x]=rate+uniform_liquid;
            sum+=rate;
        }
        result["rates"]=rates;
        result["mean_precipitation_m_s"]=sum/(resolution*resolution);
        return result;
    }
};
