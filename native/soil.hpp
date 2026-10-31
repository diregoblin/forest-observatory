#pragma once
#include <array>
#include <vector>

namespace forest {
// Element quantities are kg C, kg N, kg P. Cells hold amounts, not densities.
struct Elements {
    double c=0,n=0,p=0;
    Elements operator+(const Elements &b) const {return {c+b.c,n+b.n,p+b.p};}
    Elements operator-(const Elements &b) const {return {c-b.c,n-b.n,p-b.p};}
    Elements operator*(double f) const {return {c*f,n*f,p*f};}
    Elements &operator+=(const Elements &b) {c+=b.c;n+=b.n;p+=b.p;return *this;}
};
struct SoilCell {
    double area=0;
    Elements organic,labile,mineral;
    Elements total() const {return organic+labile+mineral;}
};
struct SoilPatch {
    int n=0; double dx=0,ox=0,oz=0;
    std::vector<SoilCell> cells;
};
class Soil {
public:
    int n=0; double dx=0,time_s=0,respired_kg=0;
    Elements initial,input,output;
    std::vector<SoilCell> cells;
    std::vector<SoilPatch> patches;
    bool initialize(int size,double cell_m,Elements organic_density={2,.1,.008},
                    Elements mineral_density={0,.02,.002},Elements labile_density={.05,.0025,.0002});
    // Refinement conservatively transfers covered coarse reserves. No overlap.
    int add_patch(int size,double cell_m,double ox,double oz);
    int find_patch(double x,double z) const;
    SoilCell *at(double x,double z);
    const SoilCell *at(double x,double z) const;
    Elements deposit(double x,double z,Elements amount,bool organic=true);
    Elements withdraw(double x,double z,Elements requested,bool organic=false);
    void exchange(Elements difference);
    bool advance(double seconds,const std::vector<double> &moisture,double temperature_c);
    Elements total() const;
    Elements error() const {return total()+output-initial-input;}
    bool finite_state() const;
};
}
