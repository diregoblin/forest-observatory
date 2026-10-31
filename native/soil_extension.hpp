#pragma once
#include "soil.hpp"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <unordered_map>

class ForestSoilNative : public RefCounted {
    GDCLASS(ForestSoilNative,RefCounted);
    static Vector3 vector(forest::Elements e) {return Vector3(e.c,e.n,e.p);}
    static forest::Elements elements(Vector3 v) {return {v.x,v.y,v.z};}
    static Dictionary cell_fields(const std::vector<forest::SoilCell> &cells) {
        Dictionary d;std::vector<double> area,oc,on,op,lc,ln,lp,mn,mp;
        for(const auto &c:cells){area.push_back(c.area);oc.push_back(c.organic.c);on.push_back(c.organic.n);op.push_back(c.organic.p);lc.push_back(c.labile.c);ln.push_back(c.labile.n);lp.push_back(c.labile.p);mn.push_back(c.mineral.n);mp.push_back(c.mineral.p);}
        d["area"]=pack(area);d["organic_c"]=pack(oc);d["organic_n"]=pack(on);d["organic_p"]=pack(op);d["labile_c"]=pack(lc);d["labile_n"]=pack(ln);d["labile_p"]=pack(lp);d["mineral_n"]=pack(mn);d["mineral_p"]=pack(mp);return d;
    }
    static bool load_cells(const Dictionary &d,std::vector<forest::SoilCell> &cells) {
        for(auto name:{"area","organic_c","organic_n","organic_p","labile_c","labile_n","labile_p","mineral_n","mineral_p"}) {
            if(!d.has(name)||d[name].get_type()!=Variant::PACKED_FLOAT64_ARRAY)return false;
            PackedFloat64Array a=d[name];if(a.size()!=int64_t(cells.size()))return false;
            for(double v:a)if(!std::isfinite(v)||v<0)return false;
        }
        PackedFloat64Array area=d["area"],oc=d["organic_c"],on=d["organic_n"],op=d["organic_p"],lc=d["labile_c"],ln=d["labile_n"],lp=d["labile_p"],mn=d["mineral_n"],mp=d["mineral_p"];
        for(std::size_t k=0;k<cells.size();++k){if(std::abs(cells[k].area-area[k])>1e-8)return false;cells[k].organic={oc[k],on[k],op[k]};cells[k].labile={lc[k],ln[k],lp[k]};cells[k].mineral={0,mn[k],mp[k]};if(area[k]==0&&(oc[k]+on[k]+op[k]+lc[k]+ln[k]+lp[k]+mn[k]+mp[k])!=0)return false;}
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
    Dictionary sample(Vector3 position) const {
        Dictionary d;const auto *c=core.at(position.x,position.z);if(!c||c->area<=0)return d;
        d["organic_c_kg_m2"]=c->organic.c/c->area;d["organic_n_kg_m2"]=c->organic.n/c->area;d["organic_p_kg_m2"]=c->organic.p/c->area;d["labile_c_kg_m2"]=c->labile.c/c->area;d["mineral_n_kg_m2"]=c->mineral.n/c->area;d["mineral_p_kg_m2"]=c->mineral.p/c->area;d["area"]=c->area;d["patch"]=core.find_patch(position.x,position.z);return d;
    }
    Dictionary metrics() const {
        Dictionary d;const auto t=core.total(),e=core.error();
        d["carbon_kg"]=t.c;d["nitrogen_kg"]=t.n;d["phosphorus_kg"]=t.p;
        d["carbon_error_kg"]=e.c;d["nitrogen_error_kg"]=e.n;d["phosphorus_error_kg"]=e.p;
        d["respired_kg_c"]=core.respired_kg;d["elapsed_s"]=core.time_s;d["patches"]=int(core.patches.size());d["finite"]=core.finite_state();return d;
    }
    Dictionary snapshot() const {
        Dictionary d;d["version"]=1;d["n"]=core.n;d["dx"]=core.dx;d["cells"]=cell_fields(core.cells);Array patches;
        for(const auto &p:core.patches){Dictionary s=cell_fields(p.cells);s["n"]=p.n;s["dx"]=p.dx;s["ox"]=p.ox;s["oz"]=p.oz;patches.append(s);}d["patches"]=patches;
        d["time_s"]=core.time_s;d["respired_kg"]=core.respired_kg;
        // Scalars stay float64; Vector3 is deliberately only the command boundary.
        for(const auto &entry:std::initializer_list<std::pair<const char*,forest::Elements>>{{"initial",core.initial},{"input",core.input},{"output",core.output}}){Dictionary e;e["c"]=entry.second.c;e["n"]=entry.second.n;e["p"]=entry.second.p;d[entry.first]=e;}
        return d;
    }
    bool restore(const Dictionary &d) {
        if(int(d.get("version",0))!=1||!d.has("cells")||d["cells"].get_type()!=Variant::DICTIONARY||!d.has("patches")||d["patches"].get_type()!=Variant::ARRAY)return false;
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
