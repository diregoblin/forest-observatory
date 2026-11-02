#include "soil.hpp"
#include "fungi.hpp"
#include <cmath>
#include <iostream>
#include <stdexcept>
using namespace forest;
void require(bool ok,const char *why){if(!ok)throw std::runtime_error(why);}
void close(Elements a,Elements b,double tolerance=1e-9){require(std::abs(a.c-b.c)<tolerance&&std::abs(a.n-b.n)<tolerance&&std::abs(a.p-b.p)<tolerance,"CNP mismatch");}
int main(){try{
    Soil patterned;require(patterned.initialize(8,4),"pattern initialize");
    const auto before_pattern=patterned.total();
    std::vector<double> ow(64),mw(64),sf(64,.08);
    for(int k=0;k<64;++k){ow[k]=.3+(k%8)*.2;mw[k]=.4+(k/8)*.2;}
    require(patterned.initialize_pattern(ow,mw,sf),"pattern apply");close(before_pattern,patterned.total(),1e-8);close(patterned.error(),{},1e-8);
    require(patterned.cells[0].organic.c!=patterned.cells[7].organic.c,"initial pattern changes actual stocks");
    require(patterned.cells[0].surface_c<patterned.cells[0].organic.c,"surface tag subset");
    const auto before_bad=patterned.total();ow[2]=-1;require(!patterned.initialize_pattern(ow,mw,sf),"bad pattern rejected");close(before_bad,patterned.total());
    require(patterned.advance(1,std::vector<double>(64,.65),14),"pattern advance");ow[2]=1;
    require(!patterned.initialize_pattern(ow,mw,sf),"never reinitialize an active world");
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
    Soil surface;require(surface.initialize(8,4),"surface soil");surface.deposit(5,5,{1,.1,.01});
    const auto surface_total=surface.total();require(surface.at(5,5)->surface_c==1,"surface tag tracks deposition");
    require(surface.add_patch(16,.25,4,4)==0,"surface refinement");close(surface.total(),surface_total);
    double marked=0;for(const auto &cell:surface.patches[0].cells)marked+=cell.surface_c;
    require(std::abs(marked-1)<1e-12,"refinement transfers surface tag, not duplicate carbon");
    require(surface.advance(86400*365,std::vector<double>(64,.65),14),"surface decomposition");
    double decayed=0;for(const auto &cell:surface.patches[0].cells)decayed+=cell.surface_c;
    require(decayed<marked,"soil appearance remembers and decomposes real deposited litter");close(surface.error(),{});
    Soil myco_soil;require(myco_soil.initialize(8,4),"mycorrhizal soil");require(myco_soil.add_patch(16,.25,4,4)==0,"myco patch");
    Fungi myco;auto mp=p;mp.ectomycorrhizal=true;
    require(myco.initialize(16,.25,mp,std::vector<double>(256,.02),std::vector<double>(256,.05),std::vector<double>(256,.6)),"myco init");require(myco.bind_soil(&myco_soil,0),"myco bind");
    const double myco_before=myco.carbon_kg();require(myco.advance(86400*30),"no host control");
    require(std::abs(myco.carbon_kg()-myco_before)<1e-12,"ECM cannot eat soil carbon instead of host carbon");
    const auto guild_before=myco_soil.total()+Elements{myco.carbon_kg(),myco.carbon_kg()/myco.cn_ratio,myco.carbon_kg()/myco.cp_ratio};
    const auto traded=myco.trade(6,6,.002,.0002,.02,2);
    require(traded.c>0&&traded.n>0&&traded.p>0&&traded.c<=.02+1e-12,"bounded paid exchange");
    const auto guild_after=myco_soil.total()+Elements{myco.carbon_kg(),myco.carbon_kg()/myco.cn_ratio,myco.carbon_kg()/myco.cp_ratio};
    close(guild_before+Elements{traded.c,0,0},guild_after+Elements{0,traded.n,traded.p},1e-9);
    require(std::abs(myco.balance_error_kg())<1e-10,"mycorrhizal carbon input in ledger");close(myco_soil.error(),{});
    close(myco.trade(6,6,.002,.0002,0,2),{});close(myco.trade(30,30,.002,.0002,.02,2),{});close(f.trade(6,6,.002,.0002,.02,2),{});
    std::cout<<"{\"passed\":true,\"refinement_conserves_cnp\":true,\"overlap_rejected\":true,\"soil_balance\":true,\"coupled_cnp_conserved\":true,\"nutrient_null\":true}\n";
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}
