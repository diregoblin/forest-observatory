#pragma once
#include "soil.hpp"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <unordered_map>

class ForestSoilNative : public RefCounted {
    GDCLASS(ForestSoilNative,RefCounted);
    static Vector3 vector(forest::Elements e) {return Vector3(e.c,e.n,e.p);}
    static forest::Elements elements(Vector3 v) {return {v.x,v.y,v.z};}
    static Dictionary cell_fields(const std::vector<forest::SoilCell> &cells) {
        Dictionary d;std::vector<double> area,oc,on,op,lc,ln,lp,mn,mp,surface;
        for(const auto &c:cells){surface.push_back(c.surface_c);area.push_back(c.area);oc.push_back(c.organic.c);on.push_back(c.organic.n);op.push_back(c.organic.p);lc.push_back(c.labile.c);ln.push_back(c.labile.n);lp.push_back(c.labile.p);mn.push_back(c.mineral.n);mp.push_back(c.mineral.p);}
        d["surface_c"]=pack(surface);d["area"]=pack(area);d["organic_c"]=pack(oc);d["organic_n"]=pack(on);d["organic_p"]=pack(op);d["labile_c"]=pack(lc);d["labile_n"]=pack(ln);d["labile_p"]=pack(lp);d["mineral_n"]=pack(mn);d["mineral_p"]=pack(mp);return d;
    }
    static bool load_cells(const Dictionary &d,std::vector<forest::SoilCell> &cells) {
        for(auto name:{"area","organic_c","organic_n","organic_p","labile_c","labile_n","labile_p","mineral_n","mineral_p","surface_c"}) {
            if(!d.has(name)||d[name].get_type()!=Variant::PACKED_FLOAT64_ARRAY)return false;
            PackedFloat64Array a=d[name];if(a.size()!=int64_t(cells.size()))return false;
            for(double v:a)if(!std::isfinite(v)||v<0)return false;
        }
        PackedFloat64Array surface=d["surface_c"],area=d["area"],oc=d["organic_c"],on=d["organic_n"],op=d["organic_p"],lc=d["labile_c"],ln=d["labile_n"],lp=d["labile_p"],mn=d["mineral_n"],mp=d["mineral_p"];
        for(std::size_t k=0;k<cells.size();++k){if(std::abs(cells[k].area-area[k])>1e-8)return false;cells[k].surface_c=surface[k];cells[k].organic={oc[k],on[k],op[k]};cells[k].labile={lc[k],ln[k],lp[k]};cells[k].mineral={0,mn[k],mp[k]};if(area[k]==0&&(oc[k]+on[k]+op[k]+lc[k]+ln[k]+lp[k]+mn[k]+mp[k])!=0)return false;}
        return true;
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("configure","size","cell_m","organic_density","mineral_density","labile_density"),&ForestSoilNative::configure);
        ClassDB::bind_method(D_METHOD("add_patch","size","cell_m","origin_x","origin_z"),&ForestSoilNative::add_patch);
        ClassDB::bind_method(D_METHOD("advance","seconds","moisture","temperature_c"),&ForestSoilNative::advance);
        ClassDB::bind_method(D_METHOD("deposit","position","amount","organic"),&ForestSoilNative::deposit);
        ClassDB::bind_method(D_METHOD("withdraw","position","amount","organic"),&ForestSoilNative::withdraw);
        ClassDB::bind_method(D_METHOD("withdraw_many","positions","amounts","organic"),&ForestSoilNative::withdraw_many);
        ClassDB::bind_method(D_METHOD("sample","position"),&ForestSoilNative::sample);
        ClassDB::bind_method(D_METHOD("deposit_elements","position","carbon","nitrogen","phosphorus","organic"),&ForestSoilNative::deposit_elements);
        ClassDB::bind_method(D_METHOD("withdraw_nutrients","positions","nitrogen","phosphorus"),&ForestSoilNative::withdraw_nutrients);
        ClassDB::bind_method(D_METHOD("metrics"),&ForestSoilNative::metrics);
        ClassDB::bind_method(D_METHOD("initialize_pattern","organic_weights","mineral_weights","surface_fractions"),&ForestSoilNative::initialize_pattern);
        ClassDB::bind_method(D_METHOD("surface_fields","moisture","cover"),&ForestSoilNative::surface_fields);
        ClassDB::bind_method(D_METHOD("diagnostic_field","field"),&ForestSoilNative::diagnostic_field);
        ClassDB::bind_method(D_METHOD("diagnostic_patches","field"),&ForestSoilNative::diagnostic_patches);
        ClassDB::bind_method(D_METHOD("diagnostic_background","field"),&ForestSoilNative::diagnostic_background);
        ClassDB::bind_method(D_METHOD("snapshot"),&ForestSoilNative::snapshot);
        ClassDB::bind_method(D_METHOD("restore","state"),&ForestSoilNative::restore);
    }
public:
    forest::Soil core;
    bool configure(int n,double dx,Vector3 organic,Vector3 minerals,Vector3 labile) {return core.initialize(n,dx,elements(organic),elements(minerals),elements(labile));}
    int add_patch(int n,double dx,double ox,double oz) {return core.add_patch(n,dx,ox,oz);}
    bool advance(double seconds,const PackedFloat64Array &moisture,double temperature) {return core.advance(seconds,unpack(moisture),temperature);}
    Vector3 deposit(Vector3 position,Vector3 amount,bool organic) {return vector(core.deposit(position.x,position.z,elements(amount),organic));}
    Vector3 withdraw(Vector3 position,Vector3 amount,bool organic) {return vector(core.withdraw(position.x,position.z,elements(amount),organic));}
    PackedVector3Array withdraw_many(const PackedVector3Array &positions,const PackedVector3Array &amounts,bool organic) {
        PackedVector3Array result;if(positions.size()!=amounts.size())return result;
        result.resize(amounts.size());std::unordered_map<forest::SoilCell*,forest::Elements> totals;
        for(int64_t i=0;i<amounts.size();++i){Vector3 a=amounts[i];if(!a.is_finite()||a.x<0||a.y<0||a.z<0)return {};auto *cell=core.at(positions[i].x,positions[i].z);if(cell)totals[cell]+=elements(a);}
        std::unordered_map<forest::SoilCell*,double> ratios;
        for(auto &entry:totals){auto &pool=organic?entry.first->organic:entry.first->mineral;double r=1;auto q=entry.second;if(q.c>0)r=std::min(r,pool.c/q.c);if(q.n>0)r=std::min(r,pool.n/q.n);if(q.p>0)r=std::min(r,pool.p/q.p);ratios[entry.first]=r;}
        for(int64_t i=0;i<amounts.size();++i){auto *cell=core.at(positions[i].x,positions[i].z);if(!cell)continue;result.set(i,vector(core.withdraw(positions[i].x,positions[i].z,elements(amounts[i])*ratios[cell],organic)));}
        return result;
    }
    PackedFloat64Array deposit_elements(Vector3 position,double c,double n,double p,bool organic) {const auto a=core.deposit(position.x,position.z,{c,n,p},organic);return pack({a.c,a.n,a.p});}
    Dictionary withdraw_nutrients(const PackedVector3Array &positions,const PackedFloat64Array &nitrogen,const PackedFloat64Array &phosphorus) {
        Dictionary result;if(positions.size()!=nitrogen.size()||positions.size()!=phosphorus.size())return result;
        std::unordered_map<forest::SoilCell*,forest::Elements> totals;
        for(int64_t i=0;i<positions.size();++i){if(!std::isfinite(nitrogen[i])||nitrogen[i]<0||!std::isfinite(phosphorus[i])||phosphorus[i]<0)return {};auto *c=core.at(positions[i].x,positions[i].z);if(c)totals[c]+={0,nitrogen[i],phosphorus[i]};}
        std::unordered_map<forest::SoilCell*,double> ratios;
        for(const auto &v:totals){double r=1;if(v.second.n>0)r=std::min(r,v.first->mineral.n/v.second.n);if(v.second.p>0)r=std::min(r,v.first->mineral.p/v.second.p);ratios[v.first]=r;}
        std::vector<double> n(positions.size()),p(positions.size());
        for(int64_t i=0;i<positions.size();++i){auto *c=core.at(positions[i].x,positions[i].z);if(!c)continue;const double r=ratios[c];const auto amount=core.withdraw(positions[i].x,positions[i].z,{0,nitrogen[i]*r,phosphorus[i]*r});n[i]=amount.n;p[i]=amount.p;}
        result["nitrogen"]=pack(n);result["phosphorus"]=pack(p);return result;
    }
    bool initialize_pattern(const PackedFloat64Array &ow,const PackedFloat64Array &mw,const PackedFloat64Array &sf) { return core.initialize_pattern(unpack(ow),unpack(mw),unpack(sf)); }
    // Read-only kg element / m², projected from the actual non-overlapping owners.
    // Fine cells are summed, never sampled at a base-cell centre or counted twice.
    PackedFloat64Array diagnostic_field(int field) const {
        if(field<0||field>8||core.n==0)return {};
        std::vector<double> values(core.n*core.n,0);
        for(std::size_t k=0;k<values.size();++k)values[k]=diagnostic_amount(core.cells[k],field);
        for(const auto &p:core.patches)for(int z=0;z<p.n;++z)for(int x=0;x<p.n;++x){
            const int bx=std::clamp(int((p.ox+(x+.5)*p.dx)/core.dx),0,core.n-1);
            const int bz=std::clamp(int((p.oz+(z+.5)*p.dx)/core.dx),0,core.n-1);
            values[bz*core.n+bx]+=diagnostic_amount(p.cells[z*p.n+x],field);
        }
        for(auto &v:values)v/=core.dx*core.dx;
        return pack(values);
    }
    static double diagnostic_amount(const forest::SoilCell &c,int field) {
        switch(field) {
            case 0:return c.organic.c;case 1:return c.organic.n;case 2:return c.organic.p;
            case 3:return c.labile.c;case 4:return c.labile.n;case 5:return c.labile.p;
            case 6:return c.mineral.n;case 7:return c.mineral.p;default:return c.surface_c;
        }
    }
    // Density of the uncovered coarse owner, not a coarse/fine area average.
    Dictionary diagnostic_background(int field) const {
        Dictionary d;if(field<0||field>8)return d;
        std::vector<double> values,areas;
        for(const auto &c:core.cells) {
            values.push_back(c.area>0?diagnostic_amount(c,field)/c.area:0);
            areas.push_back(c.area);
        }
        d["values"]=pack(values);d["area"]=pack(areas);return d;
    }
    // Sparse fine display fields in kg/m². Does not expand a 25 cm whole-world grid.
    Array diagnostic_patches(int field) const {
        Array result;if(field<0||field>8)return result;
        for(const auto &p:core.patches) {
            std::vector<double> values;values.reserve(p.cells.size());
            for(const auto &c:p.cells)values.push_back(diagnostic_amount(c,field)/c.area);
            Dictionary d;d["n"]=p.n;d["dx"]=p.dx;d["origin"]=Vector2(p.ox,p.oz);d["values"]=pack(values);
            result.append(d);
        }
        return result;
    }
    PackedFloat64Array surface_fields(const PackedFloat64Array &moisture,const PackedFloat64Array &cover) const {
        if(moisture.size()!=core.n*core.n||cover.size()!=moisture.size())return {};
        std::vector<double> litter(core.n*core.n,0),organic(litter.size(),0),values(litter.size()*4,0);
        for(std::size_t k=0;k<litter.size();++k){litter[k]=core.cells[k].surface_c;organic[k]=core.cells[k].organic.c;}
        for(const auto &patch:core.patches)for(int z=0;z<patch.n;++z)for(int x=0;x<patch.n;++x){
            const int bx=std::clamp(int((patch.ox+(x+.5)*patch.dx)/core.dx),0,core.n-1),bz=std::clamp(int((patch.oz+(z+.5)*patch.dx)/core.dx),0,core.n-1);
            const auto &c=patch.cells[z*patch.n+x];litter[bz*core.n+bx]+=c.surface_c;organic[bz*core.n+bx]+=c.organic.c;
        }
        for(std::size_t k=0;k<litter.size();++k){values[k*4]=litter[k]/(core.dx*core.dx);values[k*4+1]=cover[k];values[k*4+2]=moisture[k];values[k*4+3]=organic[k]/(core.dx*core.dx);}
        return pack(values);
    }
    Dictionary sample(Vector3 position) const {
        Dictionary d;const auto *c=core.at(position.x,position.z);if(!c||c->area<=0)return d;
        d["surface_litter_c_kg_m2"]=c->surface_c/c->area;d["organic_c_kg_m2"]=c->organic.c/c->area;d["organic_n_kg_m2"]=c->organic.n/c->area;d["organic_p_kg_m2"]=c->organic.p/c->area;d["labile_c_kg_m2"]=c->labile.c/c->area;d["mineral_n_kg_m2"]=c->mineral.n/c->area;d["mineral_p_kg_m2"]=c->mineral.p/c->area;d["area"]=c->area;d["patch"]=core.find_patch(position.x,position.z);return d;
    }
    Dictionary metrics() const {
        Dictionary d;const auto t=core.total(),e=core.error();
        d["carbon_kg"]=t.c;d["nitrogen_kg"]=t.n;d["phosphorus_kg"]=t.p;
        d["carbon_error_kg"]=e.c;d["nitrogen_error_kg"]=e.n;d["phosphorus_error_kg"]=e.p;
        d["respired_kg_c"]=core.respired_kg;d["elapsed_s"]=core.time_s;d["patches"]=int(core.patches.size());d["finite"]=core.finite_state();return d;
    }
    Dictionary snapshot() const {
        Dictionary d;d["version"]=2;d["n"]=core.n;d["dx"]=core.dx;d["cells"]=cell_fields(core.cells);Array patches;
        for(const auto &p:core.patches){Dictionary s=cell_fields(p.cells);s["n"]=p.n;s["dx"]=p.dx;s["ox"]=p.ox;s["oz"]=p.oz;patches.append(s);}d["patches"]=patches;
        d["time_s"]=core.time_s;d["respired_kg"]=core.respired_kg;
        // Scalars stay float64; Vector3 is deliberately only the command boundary.
        for(const auto &entry:std::initializer_list<std::pair<const char*,forest::Elements>>{{"initial",core.initial},{"input",core.input},{"output",core.output}}){Dictionary e;e["c"]=entry.second.c;e["n"]=entry.second.n;e["p"]=entry.second.p;d[entry.first]=e;}
        return d;
    }
    bool restore(const Dictionary &d) {
        if(int(d.get("version",0))!=2||!d.has("cells")||d["cells"].get_type()!=Variant::DICTIONARY||!d.has("patches")||d["patches"].get_type()!=Variant::ARRAY)return false;
        forest::Soil c;if(!c.initialize(d.get("n",0),d.get("dx",0.0)))return false;
        Array patches=d["patches"];
        for(int i=0;i<patches.size();++i){if(patches[i].get_type()!=Variant::DICTIONARY)return false;Dictionary p=patches[i];if(c.add_patch(p.get("n",0),p.get("dx",0.0),p.get("ox",-1.0),p.get("oz",-1.0))<0)return false;if(!load_cells(p,c.patches.back().cells))return false;}
        if(!load_cells(d["cells"],c.cells))return false;
        for(const auto &entry:std::initializer_list<std::pair<const char*,forest::Elements*>>{{"initial",&c.initial},{"input",&c.input},{"output",&c.output}}){if(!d.has(entry.first)||d[entry.first].get_type()!=Variant::DICTIONARY)return false;Dictionary e=d[entry.first];for(auto name:{"c","n","p"})if(!e.has(name))return false;*entry.second={double(e["c"]),double(e["n"]),double(e["p"])};}
        if(!d.has("time_s")||!d.has("respired_kg"))return false;c.time_s=d["time_s"];c.respired_kg=d["respired_kg"];
        if(!c.finite_state())return false;const auto e=c.error(),t=c.total();if(std::abs(e.c)>1e-8*std::max(1.0,t.c)||std::abs(e.n)>1e-8*std::max(1.0,t.n)||std::abs(e.p)>1e-8*std::max(1.0,t.p))return false;
        core=std::move(c);return true;
    }
};
