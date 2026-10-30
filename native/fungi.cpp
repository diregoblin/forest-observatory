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
    time_s=0; input_kg=0; output_kg=0; steps=0; initial_kg=carbon_kg();
    return true;
}
bool Fungi::advance(double seconds) {
    if(n==0 || !std::isfinite(seconds) || seconds<0) return false;
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
    for(const auto *a:{&biomass,&resource,&litter,&fruit}) sum+=std::accumulate(a->begin(),a->end(),0.0);
    return sum*dx*dx;
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
}
