#pragma once
#include "fungi.hpp"

class ForestFungiNative : public RefCounted {
    GDCLASS(ForestFungiNative,RefCounted);
    forest::Fungi core;
    Dictionary configuration;
    static forest::FungalParameters parameters(const Dictionary &d) {
        forest::FungalParameters p;
#define GET(name) p.name=d.get(#name,p.name)
        GET(diffusion_b_m2_s); GET(diffusion_r_m2_s); GET(uptake_m4_kg2_s);
        GET(mortality_s); GET(replenishment_s); GET(resource_capacity_kg_m2);
        GET(yield); GET(fruiting_s); GET(fruit_lifetime_s); GET(fruit_threshold_kg_m2);
        GET(max_step_s); GET(finite_litter);
#undef GET
        return p;
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("configure","size","cell_m","options","biomass","resource","litter"),&ForestFungiNative::configure);
        ClassDB::bind_method(D_METHOD("advance","seconds"),&ForestFungiNative::advance);
        ClassDB::bind_method(D_METHOD("set_environment","soil","depth","water_size","water_cell_m","origin_x","origin_z","temperature_c"),&ForestFungiNative::set_environment);
        ClassDB::bind_method(D_METHOD("fields"),&ForestFungiNative::fields);
        ClassDB::bind_method(D_METHOD("metrics"),&ForestFungiNative::metrics);
        ClassDB::bind_method(D_METHOD("snapshot"),&ForestFungiNative::snapshot);
        ClassDB::bind_method(D_METHOD("restore","state"),&ForestFungiNative::restore);
    }
public:
    bool configure(int n,double dx,const Dictionary &options,const PackedFloat64Array &b,
            const PackedFloat64Array &r,const PackedFloat64Array &l) {
        forest::Fungi candidate;
        if(!candidate.initialize(n,dx,parameters(options),unpack(b),unpack(r),unpack(l))) return false;
        core=std::move(candidate); configuration=options.duplicate(true); return true;
    }
    bool advance(double seconds) {return core.advance(seconds);}
    bool set_environment(const PackedFloat64Array &soil,const PackedFloat64Array &depth,
            int water_n,double water_dx,double ox,double oz,double temperature) {
        if(core.n==0 || water_n<1 || soil.size()!=water_n*water_n || depth.size()!=soil.size()
            || !std::isfinite(water_dx) || water_dx<=0 || !std::isfinite(ox)
            || !std::isfinite(oz) || !std::isfinite(temperature) || ox<0 || oz<0
            || ox+core.n*core.dx>water_n*water_dx+1e-8 || oz+core.n*core.dx>water_n*water_dx+1e-8) return false;
        for(int i=0;i<soil.size();++i)
            if(!std::isfinite(soil[i]) || !std::isfinite(depth[i]) || soil[i]<0 || depth[i]<0) return false;
        for(int y=0;y<core.n;++y) for(int x=0;x<core.n;++x) {
            const int wx=std::clamp(int((ox+(x+.5)*core.dx)/water_dx),0,water_n-1);
            const int wz=std::clamp(int((oz+(y+.5)*core.dx)/water_dx),0,water_n-1);
            const int k=y*core.n+x,w=wz*water_n+wx;
            const double s=soil[w];
            core.activity[k]=depth[w]>.02 ? 0 : std::clamp((s-.15)/.3,0.0,1.0)*std::clamp((1-s)/.1,0.0,1.0);
            core.fruit_suitability[k]=(s>=.4 && s<=.92 && temperature>=5 && temperature<=22 && depth[w]<.02) ? 1 : 0;
        }
        return true;
    }
    Dictionary fields() const {
        Dictionary d;
        d["biomass"]=pack(core.biomass); d["resource"]=pack(core.resource);
        d["litter"]=pack(core.litter); d["fruit"]=pack(core.fruit);
        return d;
    }
    Dictionary metrics() const {
        Dictionary d;
        d["time_s"]=core.time_s; d["steps"]=static_cast<int64_t>(core.steps);
        d["carbon_kg"]=core.carbon_kg(); d["balance_error_kg"]=core.balance_error_kg();
        d["input_kg"]=core.input_kg; d["output_kg"]=core.output_kg; d["initial_kg"]=core.initial_kg;
        d["edge_biomass_kg"]=core.edge_biomass_kg(); d["finite"]=core.finite_state();
        const double biomass=std::accumulate(core.biomass.begin(),core.biomass.end(),0.0)*core.dx*core.dx;
        d["boundary_affected"]=core.edge_biomass_kg()>std::max(1e-8,.01*biomass);
        return d;
    }
    Dictionary snapshot() const {
        Dictionary d=fields(); d.merge(metrics()); d["version"]=1; d["n"]=core.n; d["dx"]=core.dx;
        d["options"]=configuration.duplicate(true);
        d["activity"]=pack(core.activity); d["fruit_suitability"]=pack(core.fruit_suitability);
        return d;
    }
    bool restore(const Dictionary &d) {
        if(int(d.get("version",0))!=1 || !d.has("options") || d["options"].get_type()!=Variant::DICTIONARY) return false;
        const int n=d.get("n",0);
        if(n<3 || n>4096) return false;
        for(auto name:{"biomass","resource","litter","fruit","activity","fruit_suitability"}) {
            if(!d.has(name) || d[name].get_type()!=Variant::PACKED_FLOAT64_ARRAY) return false;
            PackedFloat64Array a=d[name]; if(a.size()!=n*n) return false;
            for(double x:a) if(!std::isfinite(x) || x<0) return false;
        }
        forest::Fungi c;
        if(!c.initialize(n,d.get("dx",0.0),parameters(d["options"]),
            unpack(PackedFloat64Array(d["biomass"])),unpack(PackedFloat64Array(d["resource"])),unpack(PackedFloat64Array(d["litter"])))) return false;
        c.fruit=unpack(PackedFloat64Array(d["fruit"]));
        c.activity=unpack(PackedFloat64Array(d["activity"]));
        c.fruit_suitability=unpack(PackedFloat64Array(d["fruit_suitability"]));
        for(const auto *a:{&c.activity,&c.fruit_suitability}) for(double x:*a) if(x>1) return false;
#define LOAD(name) if(!d.has(#name)) return false; c.name=d[#name]; if(!std::isfinite(c.name) || c.name<0) return false
        LOAD(time_s); LOAD(initial_kg); LOAD(input_kg); LOAD(output_kg);
#undef LOAD
        if(!d.has("steps") || int64_t(d["steps"])<0) return false;
        c.steps=int64_t(d["steps"]);
        if(std::abs(c.balance_error_kg())>1e-8*std::max(1.0,c.initial_kg+c.input_kg)) return false;
        core=std::move(c); configuration=Dictionary(d["options"]).duplicate(true); return true;
    }
};
