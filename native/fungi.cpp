#include "fungi.hpp"
#include <algorithm>
#include <cmath>
#include <numeric>

namespace forest {
bool FungalParameters::valid() const {
    const double values[]={diffusion_b_m2_s,diffusion_r_m2_s,uptake_m4_kg2_s,
        mortality_s,replenishment_s,resource_capacity_kg_m2,yield,fruiting_s,
        fruit_lifetime_s,fruit_threshold_kg_m2,max_step_s};
    for(double v:values) if(!std::isfinite(v) || v<0) return false;
    return resource_capacity_kg_m2>0 && yield<=1 && fruit_lifetime_s>0 && max_step_s>0;
}
bool Fungi::initialize(int size,double cell_m,const FungalParameters &params,
        const std::vector<double> &b,const std::vector<double> &r,const std::vector<double> &l) {
    if(size<3 || size>4096 || !std::isfinite(cell_m) || cell_m<=0 || !params.valid()) return false;
    if(b.size()!=std::size_t(size*size) || r.size()!=b.size() || l.size()!=b.size()) return false;
    for(const auto *v:{&b,&r,&l}) for(double x:*v) if(!std::isfinite(x) || x<0) return false;
    n=size; dx=cell_m; p=params; biomass=b; resource=r; litter=l;
    fruit.assign(n*n,0); activity.assign(n*n,1); fruit_suitability.assign(n*n,0);
    next_b.resize(n*n); next_r.resize(n*n);
    time_s=0; input_kg=0; output_kg=0; steps=0; coupled=false;soil=nullptr;soil_patch=-1;respired_kg=0;initial_kg=carbon_kg();
    return true;
}
bool Fungi::advance(double seconds) {
    if(n==0 || !std::isfinite(seconds) || seconds<0 || (coupled && !soil)) return false;
    if(coupled)sync_soil_fields();
    double remaining=seconds;
    while(remaining>1e-9) {
        double dt=std::min(remaining,p.max_step_s);
        const double d=std::max(p.diffusion_b_m2_s,p.diffusion_r_m2_s);
        if(d>0) dt=std::min(dt,.225*dx*dx/d); // positive five-point 2D stencil
        // A reaction bound, too: no silent clipping of negative carbon stores.
        double rate=0;
        for(double b:biomass) rate=std::max(rate,p.uptake_m4_kg2_s*b*b);
        if(rate>0) dt=std::min(dt,.2/rate);
        step(dt); remaining-=dt; time_s+=dt; ++steps;
    }
    return finite_state();
}
void Fungi::step(double dt) {
    if(coupled){step_coupled(dt);return;}
    const double db=p.diffusion_b_m2_s*dt/(dx*dx),dr=p.diffusion_r_m2_s*dt/(dx*dx);
    const double mortality=-std::expm1(-p.mortality_s*dt);
    const double replenishment=-std::expm1(-p.replenishment_s*dt);
    const double senescence=-std::expm1(-dt/p.fruit_lifetime_s);
    const double fruiting=-std::expm1(-dt*p.fruiting_s);
    for(int y=0;y<n;++y) for(int x=0;x<n;++x) {
        const int k=y*n+x;
        // Reflecting physical boundary, not wrapping to the opposite side of the forest.
        const int a=y*n+std::max(0,x-1),c=y*n+std::min(n-1,x+1);
        const int u=std::max(0,y-1)*n+x,v=std::min(n-1,y+1)*n+x;
        next_b[k]=biomass[k]+db*(biomass[a]+biomass[c]+biomass[u]+biomass[v]-4*biomass[k]);
        next_r[k]=resource[k]+dr*(resource[a]+resource[c]+resource[u]+resource[v]-4*resource[k]);
    }
    biomass.swap(next_b); resource.swap(next_r);
    for(int k=0;k<n*n;++k) {
        const double uptake=std::min(resource[k],dt*p.uptake_m4_kg2_s*resource[k]*biomass[k]*biomass[k]*activity[k]);
        resource[k]-=uptake; biomass[k]+=p.yield*uptake;
        output_kg+=(1-p.yield)*uptake*dx*dx; // unresolved respiratory carbon
        const double dead=biomass[k]*mortality;
        biomass[k]-=dead; litter[k]+=dead;
        double refill=(p.resource_capacity_kg_m2-resource[k])*replenishment;
        if(p.finite_litter) {
            refill=std::min(refill,litter[k]); litter[k]-=refill;
        } else {
            if(refill>=0) input_kg+=refill*dx*dx;
            else output_kg-=refill*dx*dx;
        }
        resource[k]+=refill;
        const double senesced=fruit[k]*senescence;
        fruit[k]-=senesced; litter[k]+=senesced;
        // Phenomenological extension, absent from Karst et al.: transfer, not extra mass.
        const double eligible=std::max(0.0,biomass[k]-p.fruit_threshold_kg_m2);
        const double produced=eligible*fruiting*fruit_suitability[k];
        biomass[k]-=produced; fruit[k]+=produced;
    }
}
double Fungi::carbon_kg() const {
    double sum=0;
    for(const auto *a:{&biomass,&fruit}) sum+=std::accumulate(a->begin(),a->end(),0.0);
    if(!coupled)for(const auto *a:{&resource,&litter})sum+=std::accumulate(a->begin(),a->end(),0.0);
    return sum*dx*dx;
}
bool Fungi::bind_soil(Soil *owner,int patch,bool reset) {
    if(!owner||patch<0||patch>=int(owner->patches.size()))return false;
    const auto &p=owner->patches[patch];if(p.n!=n||p.dx!=dx)return false;
    soil=owner;soil_patch=patch;coupled=true;sync_soil_fields();
    if(reset){initial_kg=carbon_kg();input_kg=0;output_kg=0;respired_kg=0;}
    return true;
}
void Fungi::sync_soil_fields() {
    if(!soil||soil_patch<0)return;
    const auto &cells=soil->patches[soil_patch].cells;
    for(int k=0;k<n*n;++k){resource[k]=cells[k].labile.c/(dx*dx);litter[k]=cells[k].organic.c/(dx*dx);}
}
void Fungi::step_coupled(double dt) {
    auto &cells=soil->patches[soil_patch].cells;
    Elements before;for(const auto &c:cells)before+=c.total();
    const double db=p.diffusion_b_m2_s*dt/(dx*dx),dr=p.diffusion_r_m2_s*dt/(dx*dx),area=dx*dx;
    std::vector<Elements> labile(n*n);
    for(int z=0;z<n;++z)for(int x=0;x<n;++x){
        int k=z*n+x,a=z*n+std::max(0,x-1),c=z*n+std::min(n-1,x+1),u=std::max(0,z-1)*n+x,v=std::min(n-1,z+1)*n+x;
        next_b[k]=biomass[k]+db*(biomass[a]+biomass[c]+biomass[u]+biomass[v]-4*biomass[k]);
        labile[k]=cells[k].labile+(cells[a].labile+cells[c].labile+cells[u].labile+cells[v].labile-cells[k].labile*4)*dr;
    }
    biomass.swap(next_b);
    const double mortality=-std::expm1(-p.mortality_s*dt),replenishment=-std::expm1(-p.replenishment_s*dt),senescence=-std::expm1(-dt/p.fruit_lifetime_s),fruiting=-std::expm1(-dt*p.fruiting_s);
    for(int k=0;k<n*n;++k){
        auto &c=cells[k];c.labile=labile[k];
        double uptake=p.ectomycorrhizal?0:std::min(c.labile.c,dt*p.uptake_m4_kg2_s*c.labile.c*biomass[k]*biomass[k]*activity[k]);
        if(p.yield>0){uptake=std::min(uptake,(c.labile.n+c.mineral.n)*cn_ratio/p.yield);uptake=std::min(uptake,(c.labile.p+c.mineral.p)*cp_ratio/p.yield);}
        c.labile.c-=uptake;const double growth=p.yield*uptake;
        const double need_n=growth/cn_ratio,need_p=growth/cp_ratio,take_n=std::min(need_n,c.labile.n),take_p=std::min(need_p,c.labile.p);
        c.labile.n-=take_n;c.mineral.n=std::max(0.0,c.mineral.n-(need_n-take_n));c.labile.p-=take_p;c.mineral.p=std::max(0.0,c.mineral.p-(need_p-take_p));
        biomass[k]+=growth/area;input_kg+=uptake;const double respiration=uptake-growth;output_kg+=respiration;respired_kg+=respiration;
        const double dead=biomass[k]*mortality*area;biomass[k]-=dead/area;c.organic+={dead,dead/cn_ratio,dead/cp_ratio};c.surface_c+=dead;output_kg+=dead;
        const double refill=p.ectomycorrhizal?0:std::min(c.organic.c,std::max(0.0,p.resource_capacity_kg_m2*area-c.labile.c)*replenishment);
        if(c.organic.c>0){const double fraction=refill/c.organic.c;const auto moved=c.organic*fraction;c.surface_c*=1-fraction;c.organic=c.organic-moved;c.labile+=moved;}
        const double senesced=fruit[k]*senescence*area;fruit[k]-=senesced/area;c.organic+={senesced,senesced/cn_ratio,senesced/cp_ratio};c.surface_c+=senesced;output_kg+=senesced;
        const double produced=std::max(0.0,biomass[k]-p.fruit_threshold_kg_m2)*fruiting*fruit_suitability[k];biomass[k]-=produced;fruit[k]+=produced;
    }
    Elements after;for(const auto &c:cells)after+=c.total();soil->exchange(after-before);sync_soil_fields();
}
double Fungi::balance_error_kg() const {return carbon_kg()+output_kg-initial_kg-input_kg;}
bool Fungi::finite_state() const {
    for(const auto *v:{&biomass,&resource,&litter,&fruit})
        for(double x:*v) if(!std::isfinite(x) || x < -1e-12) return false;
    return true;
}
double Fungi::edge_biomass_kg() const {
    double sum=0;
    for(int y=0;y<n;++y) for(int x=0;x<n;++x)
        if(x<4 || y<4 || x>=n-4 || y>=n-4) sum+=biomass[y*n+x];
    return sum*dx*dx;
}
Elements Fungi::trade(double x,double z,double requested_n,double requested_p,double offered_c,double radius) {
    Elements result;
    if(!p.ectomycorrhizal||!coupled||!soil||!std::isfinite(x)||!std::isfinite(z)||
       !std::isfinite(requested_n)||!std::isfinite(requested_p)||!std::isfinite(offered_c)||
       !std::isfinite(radius)||requested_n<0||requested_p<0||offered_c<=0||radius<=0)return result;
    auto &patch=soil->patches[soil_patch];
    const int cx=int(std::floor((x-patch.ox)/dx)),cz=int(std::floor((z-patch.oz)/dx)),reach=int(std::ceil(radius/dx));
    for(int iz=std::max(0,cz-reach);iz<=std::min(n-1,cz+reach);++iz)
      for(int ix=std::max(0,cx-reach);ix<=std::min(n-1,cx+reach);++ix) {
        const int k=iz*n+ix;const double px=patch.ox+(ix+.5)*dx,pz=patch.oz+(iz+.5)*dx;
        if((px-x)*(px-x)+(pz-z)*(pz-z)>radius*radius||biomass[k]<1e-8||activity[k]<=0)continue;
        auto &cell=patch.cells[k];const double remaining=offered_c-result.c;
        if(remaining<=0)return result;
        double dn=std::min(std::max(0.0,requested_n-result.n),remaining*.10);
        double dp=std::min(std::max(0.0,requested_p-result.p),remaining*.01);
        double carbon=std::max(dn/.10,dp/.01);
        if(carbon<=0)continue;
        const double need_n=dn+carbon/cn_ratio,need_p=dp+carbon/cp_ratio;
        const double fraction=std::min({1.0,need_n>0?cell.mineral.n/need_n:1.0,need_p>0?cell.mineral.p/need_p:1.0});
        carbon*=fraction;dn*=fraction;dp*=fraction;
        cell.mineral.n-=dn+carbon/cn_ratio;cell.mineral.p-=dp+carbon/cp_ratio;
        cell.mineral.n=std::max(0.0,cell.mineral.n);cell.mineral.p=std::max(0.0,cell.mineral.p);
        biomass[k]+=carbon/(dx*dx);input_kg+=carbon;
        soil->exchange({0,-dn-carbon/cn_ratio,-dp-carbon/cp_ratio});
        result+={carbon,dn,dp};
      }
    return result;
}
}
