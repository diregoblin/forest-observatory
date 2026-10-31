#include "soil.hpp"
#include "fungi.hpp"
#include <cmath>
#include <iostream>
#include <stdexcept>
using namespace forest;
void require(bool ok,const char *why){if(!ok)throw std::runtime_error(why);}
void close(Elements a,Elements b,double tolerance=1e-9){require(std::abs(a.c-b.c)<tolerance&&std::abs(a.n-b.n)<tolerance&&std::abs(a.p-b.p)<tolerance,"CNP mismatch");}
int main(){try{
    Soil s;require(s.initialize(8,4),"initialize");const auto initial=s.total();
    int patch=s.add_patch(16,.25,4,4);require(patch==0,"patch creation");close(s.total(),initial);require(s.add_patch(16,.25,4,4)<0,"overlap rejection");close(s.total(),initial);
    require(s.at(4.1,4.1)->area==.0625,"fine owner");require(s.cells[9].area==0,"coarse owner relinquishes covered area");
    s.deposit(4.1,4.1,{1,.1,.01});auto got=s.withdraw(4.1,4.1,{0,99,99});require(got.n<99&&got.n>0,"bounded mineral uptake");close(s.error(),{});
    require(s.advance(86400*120,std::vector<double>(64,.65),14),"decomposition");close(s.error(),{});require(s.respired_kg>0,"soil respiration");
    Fungi f;FungalParameters p;p.mortality_s=0;p.fruiting_s=0;p.diffusion_b_m2_s=0;p.diffusion_r_m2_s=0;
    require(f.initialize(16,.25,p,std::vector<double>(256,.02),std::vector<double>(256,.05),std::vector<double>(256,.6)),"fungi init");require(f.bind_soil(&s,0),"bind");
    const auto before=s.total()+Elements{f.carbon_kg(),f.carbon_kg()/f.cn_ratio,f.carbon_kg()/f.cp_ratio};
    require(f.advance(86400*30),"coupled advance");close(s.error(),{},1e-8);require(std::abs(f.balance_error_kg())<1e-9,"fungal transfer ledger");
    const auto after=s.total()+Elements{f.carbon_kg(),f.carbon_kg()/f.cn_ratio,f.carbon_kg()/f.cp_ratio};close(before,after+Elements{f.respired_kg,0,0},1e-8);
    // Nutrient-null control goes through the identical coupled uptake kernel.
    Soil poor;require(poor.initialize(8,4,{2,0,0},{0,0,0},{.05,0,0}),"poor soil");require(poor.add_patch(16,.25,4,4)==0,"poor patch");Fungi zero;require(zero.initialize(16,.25,p,std::vector<double>(256,.02),std::vector<double>(256,.05),std::vector<double>(256,.6)),"null fungus");require(zero.bind_soil(&poor,0),"null bind");double c=zero.carbon_kg();require(zero.advance(86400*30),"null advance");require(std::abs(zero.carbon_kg()-c)<1e-12,"zero nutrients block new fungal biomass");
    std::cout<<"{\"passed\":true,\"refinement_conserves_cnp\":true,\"overlap_rejected\":true,\"soil_balance\":true,\"coupled_cnp_conserved\":true,\"nutrient_null\":true}\n";
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}
