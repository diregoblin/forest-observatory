#include "hydro.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <algorithm>
#include <cmath>
#include <cstring>

using namespace godot;
namespace {
std::vector<double> unpack(const PackedFloat64Array &a) {
    return a.is_empty() ? std::vector<double>{} : std::vector<double>(a.ptr(),a.ptr()+a.size());
}
PackedFloat64Array pack(const std::vector<double> &a) {
    PackedFloat64Array result; result.resize(a.size());
    if (!a.empty()) std::memcpy(result.ptrw(),a.data(),a.size()*sizeof(double));
    return result;
}
forest::Parameters parameters(const Dictionary &d) {
    forest::Parameters p;
#define GET(name) p.name = d.get(#name,p.name)
    GET(max_step_s); GET(cfl); GET(manning_n); GET(theta); GET(max_froude); GET(rain_m_s); GET(source_m3_s);
    GET(soil_interval_s); GET(top_m); GET(root_m); GET(porosity); GET(field_theta);
    GET(residual_theta); GET(conductivity_m_s); GET(root_conductivity_m_s);
    GET(evaporation_m_s); GET(outlet);
#undef GET
    return p;
}
Dictionary options(const forest::Parameters &p) {
    Dictionary d;
#define PUT(name) d[#name] = p.name
    PUT(max_step_s); PUT(cfl); PUT(manning_n); PUT(theta); PUT(max_froude); PUT(rain_m_s); PUT(source_m3_s);
    PUT(soil_interval_s); PUT(top_m); PUT(root_m); PUT(porosity); PUT(field_theta);
    PUT(residual_theta); PUT(conductivity_m_s); PUT(root_conductivity_m_s);
    PUT(evaporation_m_s); PUT(outlet);
#undef PUT
    return d;
}
}
class ForestHydroNative : public RefCounted {
    GDCLASS(ForestHydroNative,RefCounted);
    forest::Hydro core;
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("configure","size","cell_m","options","bed","depth","saturation","sources"),&ForestHydroNative::configure);
        ClassDB::bind_method(D_METHOD("advance","seconds","raining"),&ForestHydroNative::advance);
        ClassDB::bind_method(D_METHOD("set_crests","east","south"),&ForestHydroNative::set_crests);
        ClassDB::bind_method(D_METHOD("fields"),&ForestHydroNative::fields);
        ClassDB::bind_method(D_METHOD("metrics"),&ForestHydroNative::metrics);
        ClassDB::bind_method(D_METHOD("snapshot"),&ForestHydroNative::snapshot);
        ClassDB::bind_method(D_METHOD("restore","state"),&ForestHydroNative::restore);
        ClassDB::bind_static_method("ForestHydroNative",D_METHOD("float32_field","values"),&ForestHydroNative::float32_field);
    }
public:
    static PackedFloat32Array float32_field(const PackedFloat64Array &values) {
        PackedFloat32Array result; result.resize(values.size());
        std::transform(values.ptr(),values.ptr()+values.size(),result.ptrw(),[](double x){return static_cast<float>(x);});
        return result;
    }
    bool configure(int size,double cell_m,const Dictionary &opts,const PackedFloat64Array &bed,
            const PackedFloat64Array &depth,const PackedFloat64Array &saturation,const PackedInt32Array &sources) {
        std::vector<int> source_cells;
        for (int i=0;i<sources.size();++i) source_cells.push_back(sources[i]);
        forest::Hydro candidate;
        if (!candidate.initialize(size,cell_m,parameters(opts),unpack(bed),unpack(depth),unpack(saturation),source_cells)) return false;
        core = std::move(candidate); return true;
    }
    bool advance(double seconds,bool rain) { return core.advance(seconds,rain); }
    bool set_crests(const PackedFloat64Array &east,const PackedFloat64Array &south) {
        if (east.size()!=core.n*core.n || south.size()!=east.size()) return false;
        const auto x=unpack(east),z=unpack(south);
        for (double v:x) if (!std::isfinite(v)) return false;
        for (double v:z) if (!std::isfinite(v)) return false;
        core.crest_x=x; core.crest_z=z;
        return true;
    }
    Dictionary fields() const {
        Dictionary d;
        d["depth"]=pack(core.depth); d["top_water_m"]=pack(core.top);
        d["root_water_m"]=pack(core.root); d["pending_water_m"]=pack(core.pending);
        d["qx"]=pack(core.qx); d["qz"]=pack(core.qz);
        std::vector<double> saturation(core.depth.size());
        for (std::size_t k=0;k<saturation.size();++k)
            saturation[k]=(core.top[k]+core.root[k]+core.pending[k]) /
                ((core.p.top_m+core.p.root_m)*core.p.porosity);
        d["soil"]=pack(saturation); return d;
    }
    Dictionary metrics() const {
        Dictionary d;
        d["surface_m3"]=core.surface_m3(); d["soil_m3"]=core.soil_m3();
        d["balance_error_m3"]=core.balance_error_m3();
#define METRIC(name) d[#name]=core.name
        METRIC(time_s); METRIC(soil_elapsed_s); METRIC(initial_m3); METRIC(input_m3);
        METRIC(outlet_m3); METRIC(evaporated_m3); METRIC(deep_drain_m3); METRIC(infiltrated_m3);
        METRIC(water_steps); METRIC(soil_ticks); METRIC(limited_faces); METRIC(froude_limited_faces);
#undef METRIC
        d["finite"]=core.finite_state();
        return d;
    }
    Dictionary snapshot() const {
        Dictionary d=metrics(); d["version"]=1; d["n"]=core.n; d["dx"]=core.dx;
        d["options"]=options(core.p);
#define FIELD(name) d[#name]=pack(core.name)
        FIELD(bed); FIELD(depth); FIELD(top); FIELD(root); FIELD(pending);
        FIELD(evaporation_demand); FIELD(qx); FIELD(qz); FIELD(crest_x); FIELD(crest_z);
#undef FIELD
        PackedInt32Array cells; for(int k:core.sources) cells.append(k);
        d["sources"]=cells; return d;
    }
    bool restore(const Dictionary &d) {
        if (int(d.get("version",0))!=1 || !d.has("options") || !d.has("sources")) return false;
        forest::Hydro candidate;
        const int n=d.get("n",0); const double dx=d.get("dx",0.0);
        if (n<2 || n>4096) return false;
        const char *names[]={"bed","depth","top","root","pending","evaporation_demand","qx","qz","crest_x","crest_z"};
        for (auto name:names) {
            if (!d.has(name) || d[name].get_type()!=Variant::PACKED_FLOAT64_ARRAY) return false;
            PackedFloat64Array v=d[name]; if (v.size()!=n*n) return false;
        }
        PackedFloat64Array bed=d["bed"],depth=d["depth"];
        PackedInt32Array sources=d["sources"]; std::vector<int> cells;
        for(int k:sources) cells.push_back(k);
        if (!candidate.initialize(n,dx,parameters(d["options"]),unpack(bed),unpack(depth),std::vector<double>(n*n,0),cells)) return false;
#define LOAD(name) candidate.name=unpack(PackedFloat64Array(d[#name]))
        LOAD(top); LOAD(root); LOAD(pending); LOAD(evaporation_demand);
        LOAD(qx); LOAD(qz); LOAD(crest_x); LOAD(crest_z);
#undef LOAD
#define SCALAR(name) if(!d.has(#name)) return false; candidate.name=d[#name]
        SCALAR(time_s); SCALAR(soil_elapsed_s); SCALAR(initial_m3); SCALAR(input_m3);
        SCALAR(outlet_m3); SCALAR(evaporated_m3); SCALAR(deep_drain_m3); SCALAR(infiltrated_m3);
        SCALAR(water_steps); SCALAR(soil_ticks); SCALAR(limited_faces); SCALAR(froude_limited_faces);
#undef SCALAR
        const double scalars[]={candidate.time_s,candidate.soil_elapsed_s,candidate.initial_m3,candidate.input_m3,
            candidate.outlet_m3,candidate.evaporated_m3,candidate.deep_drain_m3,candidate.infiltrated_m3};
        for(double v:scalars) if(!std::isfinite(v) || v<0) return false;
        if(candidate.soil_elapsed_s>=candidate.p.soil_interval_s || !candidate.finite_state()) return false;
        if(std::abs(candidate.balance_error_m3())>1e-7*std::max(1.0,candidate.initial_m3+candidate.input_m3)) return false;
        core=std::move(candidate); return true;
    }
};
void initialize_forest_hydro(ModuleInitializationLevel level) {
    if(level==MODULE_INITIALIZATION_LEVEL_SCENE) GDREGISTER_CLASS(ForestHydroNative);
}
void terminate_forest_hydro(ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT forest_hydro_init(GDExtensionInterfaceGetProcAddress get_proc,
        GDExtensionClassLibraryPtr library,GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc,library,initialization);
    init.register_initializer(initialize_forest_hydro); init.register_terminator(terminate_forest_hydro);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
