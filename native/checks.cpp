#include "hydro.hpp"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>

using forest::Hydro;
using forest::Parameters;
namespace {
int checks = 0;
void require(bool v,const std::string &s) { if(!v) throw std::runtime_error(s); ++checks; }
void balanced(const Hydro &h) {
    require(h.finite_state(),"finite nonnegative state and soil capacities");
    require(std::abs(h.balance_error_m3())<1e-7*std::max(1.0,h.initial_m3+h.input_m3),"total water balance");
}
Parameters isolated() {
    Parameters p; p.source_m3_s=0; p.rain_m_s=0; p.conductivity_m_s=0;
    p.root_conductivity_m_s=0; p.evaporation_m_s=0; p.outlet=false; return p;
}
Hydro flat(int n,double dx,const Parameters &p,double h=0,double s=0.4) {
    Hydro v; require(v.initialize(n,dx,p,std::vector<double>(n*n,0),std::vector<double>(n*n,h),
                                 std::vector<double>(n*n,s),{}),"initialize"); return v;
}
double upstream(const Hydro &h) {
    double sum=0; for(int k=0;k<h.n*h.n/2;++k) sum+=h.depth[k]*h.dx*h.dx; return sum;
}
Hydro wave(int n,double dt) {
    auto p=isolated(); p.max_step_s=dt;
    auto v=flat(n,32.0/n,p);
    const double a=3.141592653589793*v.dx/32.0;
    for(int z=0;z<n;++z) for(int x=0;x<n;++x)
        v.depth[z*n+x]=0.3+0.05*std::cos(2*3.141592653589793*(x+0.5)/n)*std::sin(a)/a;
    v.initial_m3=v.surface_m3()+v.soil_m3(); v.advance(5,false); balanced(v); return v;
}
double field_error(const Hydro &coarse,const Hydro &fine) {
    const int ratio=fine.n/coarse.n; double total=0;
    for(int z=0;z<coarse.n;++z) for(int x=0;x<coarse.n;++x) {
        double average=0;
        for(int j=0;j<ratio;++j) for(int i=0;i<ratio;++i)
            average+=fine.depth[(z*ratio+j)*fine.n+x*ratio+i]/(ratio*ratio);
        total+=std::abs(average-coarse.depth[z*coarse.n+x]);
    }
    return total/(coarse.n*coarse.n);
}
void benchmark() {
    std::cout<<"{\"kind\":\"native CPU only, no renderer or transfer\",\"runs\":[";
    for(int n:{64,128,256}) {
        const double dx=512.0/n; auto p=isolated(); p.outlet=true;
        std::vector<double> bed(n*n),depth(n*n,0.15),sat(n*n,0.4);
        for(int z=0;z<n;++z) for(int x=0;x<n;++x) bed[z*n+x]=0.001*(512-z*dx);
        Hydro h; require(h.initialize(n,dx,p,bed,depth,sat,{}),"benchmark init");
        auto start=std::chrono::steady_clock::now(); require(h.advance(120,false),"benchmark advance");
        const double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
        balanced(h);
        if(n!=64) std::cout<<",";
        std::cout<<"{\"resolution\":"<<n<<",\"cell_m\":"<<dx<<",\"model_s\":120,\"wall_ms\":"<<ms
                 <<",\"ms_per_model_s\":"<<ms/120<<",\"water_steps\":"<<h.water_steps
                 <<",\"balance_error_m3\":"<<h.balance_error_m3()<<"}";
    }
    std::cout<<"]}\n";
}
}
int main(int argc,char **argv) {
    std::cout<<std::setprecision(15);
    try {
        if(argc>1 && std::string(argv[1])=="--benchmark") { benchmark(); return 0; }
        // A fully wet lake with exactly equal free-surface elevation over uneven bed.
        auto p=isolated(); Hydro lake;
        const int n=12; std::vector<double> bed(n*n),depth(n*n),sat(n*n,0.5);
        for(int k=0;k<n*n;++k) { bed[k]=0.2*std::sin(k*0.7); depth[k]=1-bed[k]; }
        require(lake.initialize(n,2,p,bed,depth,sat,{}),"lake init");
        auto before=lake.depth; require(lake.advance(100,false),"lake advance");
        double lake_error=0; for(int k=0;k<n*n;++k) lake_error=std::max(lake_error,std::abs(lake.depth[k]-before[k]));
        require(lake_error<1e-12,"lake at rest well balanced"); balanced(lake);
        auto dry=flat(8,4,p); require(dry.advance(300,false),"dry advance");
        require(dry.surface_m3()==0 && dry.outlet_m3==0,"dry stays dry"); balanced(dry);
        // Analytic rainfall: no loss, no spatial gradient, known volume.
        p.rain_m_s=0.03/3600;
        auto rain=flat(8,4,p); rain.advance(3600,true);
        require(std::abs(rain.surface_m3()-0.03*32*32)<1e-9,"analytic rain volume");
        require(std::abs(rain.depth[31]-0.03)<1e-12,"analytic rain depth"); balanced(rain);
        // Dam-break-like wetting front: positivity, internal conservation, no fake source.
        p=isolated(); auto front=flat(20,1,p);
        for(int k=0;k<200;++k) front.depth[k]=0.8;
        front.initial_m3=front.surface_m3()+front.soil_m3();
        front.advance(80,false); balanced(front);
        require(front.depth[300]>0,"wetting front advances into dry cells");
        // A shared high crest holds back flow; removing it releases stored water.
        auto closed=flat(20,1,p); for(int k=0;k<200;++k) closed.depth[k]=0.8;
        closed.initial_m3=closed.surface_m3()+closed.soil_m3();
        for(int x=0;x<20;++x) closed.crest_z[9*20+x]=1.5;
        auto opened=closed; closed.advance(60,false); opened.advance(60,false);
        for(int x=0;x<20;++x) opened.crest_z[9*20+x]=0;
        opened.advance(60,false); closed.advance(60,false);
        require(upstream(closed)-upstream(opened)>1,"barrier removal release"); balanced(closed); balanced(opened);
        // Overtopping uses the same faces, no dam-specific event.
        auto overtopping=closed;
        for(int x=0;x<20;++x) overtopping.crest_z[9*20+x]=0.4;
        overtopping.advance(40,false); require(overtopping.depth[11*20+8]>0,"crest overtopping"); balanced(overtopping);
        // Normal discharge fixed point on an inclined bed, away from boundaries.
        p=isolated(); const double slope=0.01,h=0.3;
        auto flow=flat(20,1,p,h);
        const double q=std::pow(h,5.0/3.0)*std::sqrt(slope)/p.manning_n;
        for(int z=0;z<20;++z) for(int x=0;x<20;++x) {flow.bed[z*20+x]=-z*slope; flow.qz[z*20+x]=q;}
        for(int z=0;z<19;++z) for(int x=0;x<20;++x) flow.crest_z[z*20+x]=flow.bed[z*20+x];
        flow.advance(0.01,false);
        require(std::abs(flow.qz[10*20+10]-q)<1e-12,"Manning normal-flow fixed point"); balanced(flow);
        // The alternating-face mode has amplification (1-2*mixing) before friction.
        // It must damp, not survive as a checkerboard on a flat water surface.
        auto alternating=flat(20,1,p,1.0);
        for(int z=0;z<20;++z) for(int x=0;x<19;++x) alternating.qx[z*20+x]=(x%2==0?0.01:-0.01);
        alternating.advance(0.01,false);
        const double mixing=(1-p.theta)*0.01*std::sqrt(9.81)/(p.cfl*alternating.dx);
        const double expected=0.01*(1-2*mixing)/(1+9.81*0.01*p.manning_n*p.manning_n*0.01);
        require(std::abs(alternating.qx[10*20+10]-expected)<1e-12,"alternating momentum mode damping"); balanced(alternating);
        auto excessive=flat(8,4,p,0.1);
        std::fill(excessive.qx.begin(),excessive.qx.end(),100);
        excessive.advance(0.001,false);
        require(std::abs(excessive.qx[3*8+3])<=p.max_froude*0.1*std::sqrt(9.81*0.1)+1e-12,
                "declared Froude bound limits unsupported flow regime");
        require(excessive.froude_limited_faces>0,"Froude limiting is observable"); balanced(excessive);
        // Slow soil clock: reserve infiltration before the column tick, no missing water.
        p=isolated(); p.conductivity_m_s=8.0/1000/3600; p.root_conductivity_m_s=2.0/1000/3600;
        p.evaporation_m_s=0.12/1000/3600; p.soil_interval_s=30;
        auto soil=flat(4,2,p,0.20,0.2);
        soil.advance(17,false); require(soil.soil_ticks==0 && soil.pending[0]>0,"pending reserve before slow soil tick"); balanced(soil);
        auto partitioned=soil;
        soil.advance(283,false); for(int i=0;i<283;++i) partitioned.advance(1,false);
        require(soil.soil_ticks==10 && soil.water_steps>=300,"soil less frequent than water");
        double partition_error=0;
        for(std::size_t k=0;k<soil.depth.size();++k)
            partition_error=std::max({partition_error,std::abs(soil.depth[k]-partitioned.depth[k]),
                std::abs(soil.top[k]-partitioned.top[k]),std::abs(soil.root[k]-partitioned.root[k])});
        require(partition_error<1e-12,"aligned soil clocks independent of call partition to roundoff"); balanced(soil);
        const double initial_root=soil.root[0]; soil.advance(24*3600,false); balanced(soil);
        require(soil.root[0]>initial_root,"percolation feeds root zone");
        require(soil.deep_drain_m3>0 && soil.evaporated_m3>0,"explicit deep drainage and evaporation");
        auto saturated=flat(4,2,p,0.10,1); saturated.advance(1,false);
        require(saturated.pending[0]==0,"saturated top cannot take more water"); balanced(saturated);
        auto empty=flat(4,2,p,0,0); empty.advance(3600,false);
        require(empty.surface_m3()==0 && empty.soil_m3()==0,"empty soil cannot supply evaporation"); balanced(empty);
        // Soil frequency sensitivity: physical rates unchanged, only splitting error.
        auto hourly_p=p; hourly_p.soil_interval_s=5;
        auto frequent=flat(4,2,hourly_p,0.10,0.7); frequent.advance(3600,false);
        auto slow=flat(4,2,p,0.10,0.7); slow.advance(3600,false);
        const double soil_frequency_error=std::abs(frequent.top[0]-slow.top[0])+std::abs(frequent.root[0]-slow.root[0]);
        require(soil_frequency_error<1e-4,"5/30 second soil splitting sensitivity below 0.1 mm");
        balanced(frequent); balanced(slow);
        // Same smooth closed-basin wave, analytic cell-average initial condition.
        // Finer-grid reference is restriction-averaged, not nearest sampled.
        auto grid16=wave(16,0.02),grid32=wave(32,0.02),reference=wave(64,0.01);
        const double grid_error16=field_error(grid16,reference),grid_error32=field_error(grid32,reference);
        require(grid_error32<grid_error16,"grid refinement reduces smooth-wave error");
        auto time_coarse=wave(32,0.1),time_fine=wave(32,0.05),time_reference=wave(32,0.0125);
        const double time_error1=field_error(time_coarse,time_reference),time_error2=field_error(time_fine,time_reference);
        require(time_error2<time_error1,"time refinement reduces smooth-wave error");
        // Known wrong state is rejected by accounting (checker does not repair it).
        opened.depth[0]+=0.1;
        require(std::abs(opened.balance_error_m3())>0.09,"known wrong unaccounted water detected");
        auto invalid=p; invalid.max_step_s=0;
        Hydro invalid_h; require(!invalid_h.initialize(4,2,invalid,std::vector<double>(16),std::vector<double>(16),std::vector<double>(16),{}),"invalid parameter rejected");
        std::cout<<"{\"passed\":true,\"assertions\":"<<checks<<",\"lake_max_error_m\":"<<lake_error
                 <<",\"soil_frequency_error_m\":"<<soil_frequency_error
                 <<",\"grid_error_16_m\":"<<grid_error16<<",\"grid_error_32_m\":"<<grid_error32
                 <<",\"time_error_0_1_m\":"<<time_error1<<",\"time_error_0_05_m\":"<<time_error2
                 <<",\"known_wrong_rejected\":true,\"boundary\":\"Numerical controls, not calibrated field hydrology\"}\n";
        return 0;
    } catch(const std::exception &e) { std::cerr<<"FAIL: "<<e.what()<<"\n"; return 1; }
}
