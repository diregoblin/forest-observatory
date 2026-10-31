#include "soil.hpp"
#include <algorithm>
#include <cmath>

namespace forest {
namespace {
bool valid(Elements a) {return std::isfinite(a.c)&&std::isfinite(a.n)&&std::isfinite(a.p)&&a.c>=0&&a.n>=0&&a.p>=0;}
Elements minimum(Elements a,Elements b) {return {std::min(a.c,b.c),std::min(a.n,b.n),std::min(a.p,b.p)};}
}
bool Soil::initialize(int size,double cell_m,Elements org,Elements minerals,Elements labile_density) {
    if(size<2||size>4096||!std::isfinite(cell_m)||cell_m<=0||!valid(org)||!valid(minerals)||!valid(labile_density)||minerals.c!=0) return false;
    n=size;dx=cell_m;time_s=0;respired_kg=0;input={};output={};patches.clear();
    cells.assign(n*n,{});
    for(auto &c:cells) {c.area=dx*dx;c.organic=org*c.area;c.mineral=minerals*c.area;c.labile=labile_density*c.area;}
    initial=total();return true;
}
int Soil::add_patch(int size,double step,double ox,double oz) {
    if(size<2||size>1024||!std::isfinite(step)||step<=0||step>dx||!std::isfinite(ox)||!std::isfinite(oz)||ox<0||oz<0||ox+size*step>n*dx+1e-8||oz+size*step>n*dx+1e-8) return -1;
    // Both grids align exactly: every fine cell has one base owner. This is
    // checked rather than silently rounding an arbitrary rectangle.
    for(double v:{dx/step,ox/step,oz/step}) if(std::abs(v-std::round(v))>1e-7) return -1;
    for(const auto &p:patches) if(ox<p.ox+p.n*p.dx-1e-8&&ox+size*step>p.ox+1e-8&&oz<p.oz+p.n*p.dx-1e-8&&oz+size*step>p.oz+1e-8) return -1;
    SoilPatch p;p.n=size;p.dx=step;p.ox=ox;p.oz=oz;p.cells.resize(size*size);
    for(int z=0;z<size;++z) for(int x=0;x<size;++x) {
        const int bx=std::clamp(int((ox+(x+.5)*step)/dx),0,n-1),bz=std::clamp(int((oz+(z+.5)*step)/dx),0,n-1);
        auto &b=cells[bz*n+bx];auto &f=p.cells[z*size+x];f.area=step*step;
        if(b.area<f.area-1e-8) return -1;
        const double fraction=f.area/b.area;
        f.organic=b.organic*fraction;f.labile=b.labile*fraction;f.mineral=b.mineral*fraction;
        b.organic=b.organic-f.organic;b.labile=b.labile-f.labile;b.mineral=b.mineral-f.mineral;b.area-=f.area;
        if(b.area<1e-9) {b.area=0;b.organic={};b.labile={};b.mineral={};}
    }
    patches.push_back(std::move(p));return static_cast<int>(patches.size()-1);
}
int Soil::find_patch(double x,double z) const {
    for(std::size_t i=0;i<patches.size();++i) {const auto &p=patches[i];if(x>=p.ox&&z>=p.oz&&x<p.ox+p.n*p.dx&&z<p.oz+p.n*p.dx)return static_cast<int>(i);}
    return -1;
}
SoilCell *Soil::at(double x,double z) {
    if(!std::isfinite(x)||!std::isfinite(z)||x<0||z<0||x>=n*dx||z>=n*dx)return nullptr;
    const int index=find_patch(x,z);
    if(index>=0) {auto &p=patches[index];return &p.cells[int((z-p.oz)/p.dx)*p.n+int((x-p.ox)/p.dx)];}
    return &cells[int(z/dx)*n+int(x/dx)];
}
const SoilCell *Soil::at(double x,double z) const {return const_cast<Soil*>(this)->at(x,z);}
Elements Soil::deposit(double x,double z,Elements amount,bool organic) {
    auto *c=at(x,z);if(!c||!valid(amount)||(!organic&&amount.c!=0))return {};
    if(organic)c->organic+=amount;else c->mineral+=amount;input+=amount;return amount;
}
Elements Soil::withdraw(double x,double z,Elements requested,bool organic) {
    auto *c=at(x,z);if(!c||!valid(requested))return {};
    auto &pool=organic?c->organic:c->mineral;const auto amount=minimum(pool,requested);pool=pool-amount;output+=amount;return amount;
}
void Soil::exchange(Elements d) {
    input+={std::max(0.0,d.c),std::max(0.0,d.n),std::max(0.0,d.p)};
    output+={std::max(0.0,-d.c),std::max(0.0,-d.n),std::max(0.0,-d.p)};
}
bool Soil::advance(double seconds,const std::vector<double> &moisture,double temperature) {
    if(n==0||!std::isfinite(seconds)||seconds<0||moisture.size()!=cells.size()||!std::isfinite(temperature))return false;
    for(double v:moisture)if(!std::isfinite(v)||v<0)return false;
    const double temp=std::clamp((temperature+2)/20.0,0.0,1.5);
    auto tick=[&](SoilCell &c,double saturation) {
        const double wet=std::clamp((saturation-.12)/.38,0.0,1.0)*std::clamp((1.05-saturation)/.18,0.0,1.0);
        const double fraction=-std::expm1(-.12*seconds/(365*86400.0)*temp*wet);
        const Elements decomposed=c.organic*fraction;c.organic=c.organic-decomposed;
        c.labile+=decomposed*.35;c.mineral+={0,decomposed.n*.65,decomposed.p*.65};
        const double respiration=decomposed.c*.65;respired_kg+=respiration;output.c+=respiration;
    };
    for(std::size_t i=0;i<cells.size();++i) tick(cells[i],moisture[i]);
    for(auto &p:patches) for(int z=0;z<p.n;++z)for(int x=0;x<p.n;++x) {
        const int bx=std::clamp(int((p.ox+(x+.5)*p.dx)/dx),0,n-1),bz=std::clamp(int((p.oz+(z+.5)*p.dx)/dx),0,n-1);
        tick(p.cells[z*p.n+x],moisture[bz*n+bx]);
    }
    time_s+=seconds;return finite_state();
}
Elements Soil::total() const {Elements r;for(const auto &c:cells)r+=c.total();for(const auto &p:patches)for(const auto &c:p.cells)r+=c.total();return r;}
bool Soil::finite_state() const {
    auto check=[](const SoilCell &c){return std::isfinite(c.area)&&c.area>=0&&valid(c.organic)&&valid(c.labile)&&valid(c.mineral)&&c.mineral.c==0;};
    for(const auto &c:cells)if(!check(c))return false;
    for(const auto &p:patches)for(const auto &c:p.cells)if(!check(c))return false;
    return valid(initial)&&valid(input)&&valid(output)&&std::isfinite(time_s)&&time_s>=0&&std::isfinite(respired_kg)&&respired_kg>=0;
}
}
