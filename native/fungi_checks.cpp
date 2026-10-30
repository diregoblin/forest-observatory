#include "fungi.hpp"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <numeric>

void require(bool ok,const char *message) {
    if(!ok) {std::cerr<<"FAIL: "<<message<<'\n'; std::exit(1);}
}
forest::Fungi plot(int n,double dx,bool seed=true) {
    forest::FungalParameters p; p.fruiting_s=0; p.finite_litter=false;
    std::vector<double> b(n*n,0),r(n*n,.05),l(n*n,1);
    if(seed) for(int y=0;y<n;++y) for(int x=0;x<n;++x)
        if(std::hypot((x+.5-n/2.0)*dx,(y+.5-n/2.0)*dx)<.6) {
            b[y*n+x]=.025; r[y*n+x]=.0125;
        }
    forest::Fungi c; require(c.initialize(n,dx,p,b,r,l),"initialize"); return c;
}
double radius(const forest::Fungi &c) {
    double num=0,den=0;
    for(int y=0;y<c.n;++y) for(int x=0;x<c.n;++x) {
        const double b=c.biomass[y*c.n+x];
        num+=b*std::hypot((x+.5-c.n/2.0)*c.dx,(y+.5-c.n/2.0)*c.dx); den+=b;
    }
    return num/std::max(1e-30,den);
}
int main() {
    const double t0=30*86400.0;
    auto null=plot(24,.25,false);
    require(null.advance(100*t0),"null finite");
    require(std::accumulate(null.biomass.begin(),null.biomass.end(),0.0)==0,"no inoculum -> no spontaneous mushrooms");
    auto starved=plot(24,.25);
    starved.p.diffusion_b_m2_s=0; starved.p.diffusion_r_m2_s=0; starved.p.replenishment_s=0;
    std::fill(starved.resource.begin(),starved.resource.end(),0);
    const auto old=starved.biomass;
    require(starved.advance(10*t0),"starved finite");
    require(std::abs(starved.biomass[12*24+12]-old[12*24+12]*std::exp(-starved.p.mortality_s*10*t0))<1e-12,
        "resource-free analytical mortality, not growing rings");
    auto diffusion=plot(32,.25);
    diffusion.p.uptake_m4_kg2_s=0; diffusion.p.mortality_s=0; diffusion.p.replenishment_s=0;
    const double mass=diffusion.carbon_kg();
    require(diffusion.advance(40*t0),"diffusion finite");
    require(std::abs(diffusion.carbon_kg()-mass)<1e-10,"reflecting diffusion preserves mass");
    // An independently calculated homogeneous RHS catches swapped g/m or a missing B².
    auto uniform=plot(8,.25,false);
    std::fill(uniform.biomass.begin(),uniform.biomass.end(),.02);
    std::fill(uniform.resource.begin(),uniform.resource.end(),.03);
    const double ub=.03*.02*.02/(.05*.05*t0)-.0475/t0*.02;
    const double ur=-.03*.02*.02/(.05*.05*t0)+.0075/t0*(.05-.03);
    require(uniform.advance(1),"uniform finite");
    require(std::abs((uniform.biomass[0]-.02)-ub)<1e-14,"paper biomass RHS");
    require(std::abs((uniform.resource[0]-.03)-ur)<1e-14,"paper resource RHS");
    auto ring=plot(128,.25),fine=plot(256,.125),half=plot(128,.25),blocked=plot(128,.25);
    half.p.max_step_s*=.5; blocked.p.diffusion_b_m2_s=0;
    const auto began=std::chrono::steady_clock::now();
    require(ring.advance(160*t0) && fine.advance(160*t0) && half.advance(160*t0) && blocked.advance(160*t0),"wave comparisons finite");
    const double rr=radius(ring),rf=radius(fine),rh=radius(half),rb=radius(blocked);
    require(rr>2 && rb<.7,"expanding wave disappears without biomass spread");
    require(std::abs(rr-rf)<.5 && std::abs(rr-rh)<.12,"front radius stable under dx/dt refinement");
    auto closed=plot(48,.25); closed.p.finite_litter=true; closed.p.fruiting_s=.001/86400;
    std::fill(closed.fruit_suitability.begin(),closed.fruit_suitability.end(),1);
    require(closed.advance(80*t0),"closed finite");
    require(std::abs(closed.balance_error_kg())<1e-9 && closed.input_kg==0,"finite substrate + fruit carbon ledger");
    require(std::accumulate(closed.fruit.begin(),closed.fruit.end(),0.0)>0,"fruiting under eligible conditions");
    auto exhausted=plot(16,.25,false); exhausted.p.finite_litter=true;
    std::fill(exhausted.resource.begin(),exhausted.resource.end(),0);
    std::fill(exhausted.litter.begin(),exhausted.litter.end(),0);
    require(exhausted.advance(t0),"exhausted finite");
    require(std::accumulate(exhausted.resource.begin(),exhausted.resource.end(),0.0)==0,"empty litter cannot replenish resource");
    std::cout<<"{\"passed\":true,\"ring_radius_m\":"<<rr<<",\"fine_radius_m\":"<<rf
        <<",\"half_step_radius_m\":"<<rh<<",\"no_spread_radius_m\":"<<rb
        <<",\"closed_carbon_error_kg\":"<<closed.balance_error_kg()
        <<",\"comparison_wall_ms\":"<<std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-began).count();
    for(int n:{128,256,512}) {
        auto c=plot(n,.25);
        const auto start=std::chrono::steady_clock::now();
        for(int i=0;i<30;++i) require(c.advance(26280),"benchmark finite");
        const double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count()/30;
        std::cout<<",\"step_"<<n<<"_ms\":"<<ms;
    }
    std::cout<<"}\n";
}
