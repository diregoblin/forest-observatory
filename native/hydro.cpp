#include "hydro.hpp"
#include <algorithm>
#include <cmath>
#include <numeric>

namespace forest {
namespace { constexpr double g = 9.81, dry = 1e-9; }
bool Parameters::valid() const {
    const double values[] = {max_step_s, cfl, manning_n, theta, max_froude, rain_m_s, source_m3_s,
        soil_interval_s, top_m, root_m, porosity, field_theta, residual_theta,
        conductivity_m_s, root_conductivity_m_s, evaporation_m_s,
        aquifer_m, specific_yield, lateral_k_m_s, initial_groundwater_fraction};
    for (double v : values) if (!std::isfinite(v) || v < 0) return false;
    return max_step_s > 0 && cfl > 0 && cfl <= 0.5 && manning_n > 0 &&
        theta >= 0 && theta <= 1 && max_froude > 0 &&
        soil_interval_s > 0 && top_m > 0 && root_m > 0 && porosity <= 1 &&
        residual_theta < field_theta && field_theta < porosity &&
        aquifer_m > 0 && specific_yield > 0 && specific_yield <= 1 && initial_groundwater_fraction <= 1;
}
bool Hydro::initialize(int size, double cell_m, const Parameters &params,
        const std::vector<double> &elevation, const std::vector<double> &initial_depth,
        const std::vector<double> &saturation, const std::vector<int> &source_cells,
        const std::vector<double> &initial_groundwater) {
    if (size < 2 || size > 4096 || !std::isfinite(cell_m) || cell_m <= 0 || !params.valid()) return false;
    const auto count = static_cast<std::size_t>(size) * size;
    if (elevation.size() != count || initial_depth.size() != count || saturation.size() != count) return false;
    for (std::size_t k = 0; k < count; ++k)
        if (!std::isfinite(elevation[k]) || !std::isfinite(initial_depth[k]) || initial_depth[k] < 0 ||
            !std::isfinite(saturation[k]) || saturation[k] < 0 || saturation[k] > 1) return false;
    for (int k : source_cells) if (k < 0 || static_cast<std::size_t>(k) >= count) return false;
    if (params.source_m3_s > 0 && source_cells.empty()) return false;
    if (!initial_groundwater.empty()) {
        if(initial_groundwater.size()!=count) return false;
        for(double v:initial_groundwater)
            if(!std::isfinite(v) || v<0 || v>params.aquifer_m*params.specific_yield || (!params.groundwater && v!=0)) return false;
    }
    n = size; dx = cell_m; p = params; sources = source_cells;
    evaporation_rate_m_s=p.evaporation_m_s;
    bed = elevation; depth = initial_depth;
    top.resize(count); root.resize(count);
    for (std::size_t k = 0; k < count; ++k) {
        top[k] = saturation[k] * p.porosity * p.top_m;
        root[k] = saturation[k] * p.porosity * p.root_m;
    }
    for (auto *v : {&pending, &evaporation_demand, &qx, &qz, &outgoing, &delta, &outlet_flux,&old_x,&old_z}) v->assign(count, 0);
    ground.assign(count, p.groundwater ? p.aquifer_m*p.specific_yield*p.initial_groundwater_fraction : 0);
    if(!initial_groundwater.empty()) ground=initial_groundwater;
    seepage_m_s.assign(count, 0);
    crest_x = bed; crest_z = bed;
    for (int z = 0; z < n; ++z) for (int x = 0; x < n; ++x) {
        int k = z*n+x;
        if (x+1 < n) crest_x[k] = std::max(bed[k], bed[k+1]);
        if (z+1 < n) crest_z[k] = std::max(bed[k], bed[k+n]);
    }
    time_s = soil_elapsed_s = input_m3 = outlet_m3 = evaporated_m3 = deep_drain_m3 = infiltrated_m3 = 0;
    water_steps = soil_ticks = limited_faces = froude_limited_faces = 0;
    recharged_m3 = seeped_m3 = transpired_m3 = 0;
    initial_m3 = surface_m3() + soil_m3() + groundwater_m3();
    return true;
}
double Hydro::surface_m3() const {
    return std::accumulate(depth.begin(), depth.end(), 0.0) * dx * dx;
}
double Hydro::soil_m3() const {
    double sum = 0;
    for (std::size_t k = 0; k < top.size(); ++k) sum += top[k] + root[k] + pending[k];
    return sum * dx * dx;
}
double Hydro::balance_error_m3() const {
    return surface_m3() + soil_m3() + groundwater_m3() + outlet_m3 + evaporated_m3 +
        deep_drain_m3 + transpired_m3 - initial_m3 - input_m3;
}
double Hydro::groundwater_m3() const {
    return std::accumulate(ground.begin(),ground.end(),0.0)*dx*dx;
}
std::vector<double> Hydro::withdraw_roots(const std::vector<double> &demand_m) {
    if (demand_m.size()!=root.size()) return {};
    for(double v:demand_m) if(!std::isfinite(v) || v<0) return {};
    std::vector<double> taken(root.size());
    for(std::size_t k=0;k<root.size();++k) {
        taken[k]=std::min(demand_m[k],std::max(0.0,root[k]-p.root_m*p.residual_theta));
        root[k]-=taken[k]; transpired_m3+=taken[k]*dx*dx;
    }
    return taken;
}
double Hydro::stable_step() const {
    // Local-inertial wave CFL. Source/rain increment also bounds a dry start.
    double hmax = *std::max_element(depth.begin(), depth.end());
    hmax += p.max_step_s * (p.rain_m_s + (sources.empty() ? 0 : p.source_m3_s / (sources.size()*dx*dx)));
    return std::min(p.max_step_s, p.cfl * dx / std::sqrt(g * std::max(hmax, dry)));
}
bool Hydro::advance(double duration_s, bool rain) {
    if (n == 0 || !std::isfinite(duration_s) || duration_s < 0) return false;
    double left = duration_s;
    while (left > 0) {
        const double soil_left = p.soil_interval_s - soil_elapsed_s;
        double dt = std::min({left, stable_step(), soil_left});
        if (!(dt > 0)) return false;
        water_step(dt, rain);
        left = std::max(0.0, left - dt);
        time_s += dt; soil_elapsed_s += dt; ++water_steps;
        if (soil_elapsed_s >= p.soil_interval_s - 1e-10) {
            soil_step(soil_elapsed_s); soil_elapsed_s = 0; ++soil_ticks;
        }
    }
    return true;
}
double Hydro::face_flux(int a, int b, double crest, double previous, double neighbours, double dt) {
    const double ea = bed[a] + depth[a], eb = bed[b] + depth[b];
    const double h = std::max(ea, eb) - crest;
    if (h <= dry) return 0;
    // Hydrostatic reconstruction respects bed steps and a raised barrier crest.
    const double slope = (std::max(eb, crest) - std::max(ea, crest)) / dx;
    const double wave_speed=std::sqrt(g*h);
    // Scale numerical mixing by dt/CFL: splitting a step must not apply a full
    // theta blend twice and thereby increase diffusion per physical second.
    const double mixing=(1-p.theta)*std::min(1.0,dt*wave_speed/(p.cfl*dx));
    const double mean=(1-mixing)*previous+mixing*neighbours;
    // Local inertia + weighted parallel-face memory (de Almeida 2012),
    // with semi-implicit Manning friction (Bates 2010).
    // No advective acceleration; this is not a full shallow-water solver.
    double q = (mean - g * h * dt * slope) /
        (1.0 + g * dt * p.manning_n * p.manning_n * std::abs(previous) / std::pow(h, 7.0/3.0));
    // Restrict to the subcritical/critical regime this approximation targets.
    // This is a declared limiter, not a claim to solve supercritical flow.
    const double bound=p.max_froude*h*wave_speed;
    if(std::abs(q)>bound) { q=std::copysign(bound,q); ++froude_limited_faces; }
    return q;
}
void Hydro::water_step(double dt, bool rain) {
    const double area = dx*dx;
    const double rain_h = rain ? p.rain_m_s * dt : 0;
    const double spring = p.source_m3_s * dt;
    for (int k : sources) depth[k] += spring / (sources.size()*area);
    input_m3 += spring + rain_h * depth.size() * area;
    const double cap = p.porosity * p.top_m;
    std::fill(outgoing.begin(), outgoing.end(), 0);
    std::fill(delta.begin(), delta.end(), 0);
    std::fill(outlet_flux.begin(), outlet_flux.end(), 0);
    old_x=qx; old_z=qz;
    for (std::size_t k = 0; k < depth.size(); ++k) {
        depth[k] += rain_h;
        // Cheap surface exchange every water step, with explicit reserved storage.
        // Column redistribution/evaporation is on the slower, aligned soil clock.
        const double soak = std::min({depth[k], p.conductivity_m_s * dt,
                                     std::max(0.0, cap - top[k] - pending[k])});
        depth[k] -= soak; pending[k] += soak; infiltrated_m3 += soak*area;
        const double evap = std::min(depth[k], evaporation_rate_m_s * dt);
        depth[k] -= evap; evaporated_m3 += evap*area;
        evaporation_demand[k] += evaporation_rate_m_s * dt - evap;
    }
    for (int z = 0; z < n; ++z) for (int x = 0; x < n; ++x) {
        const int k = z*n+x;
        if (x+1 < n) {
            const double neighbours=0.5*(old_x[x>0?k-1:k]+old_x[x+2<n?k+1:k]);
            qx[k] = face_flux(k,k+1,crest_x[k],old_x[k],neighbours,dt);
            outgoing[qx[k] > 0 ? k : k+1] += std::abs(qx[k])*dt/dx;
        }
        if (z+1 < n) {
            const double neighbours=0.5*(old_z[z>0?k-n:k]+old_z[z+2<n?k+n:k]);
            qz[k] = face_flux(k,k+n,crest_z[k],old_z[k],neighbours,dt);
            outgoing[qz[k] > 0 ? k : k+n] += std::abs(qz[k])*dt/dx;
        } else if (p.outlet) {
            // One-way normal-depth south outlet; other outer boundaries are walls.
            const double slope = std::max(0.0, (bed[k-n]-bed[k])/dx);
            outlet_flux[k] = std::pow(depth[k], 5.0/3.0)*std::sqrt(slope)/p.manning_n;
            outgoing[k] += outlet_flux[k]*dt/dx;
        }
    }
    auto apply = [&](int a, int b, double &q) {
        const int donor = q > 0 ? a : b;
        const double scale = outgoing[donor] > 0 ? std::min(1.0, depth[donor]*0.999999999/outgoing[donor]) : 1;
        if (scale < 1) ++limited_faces;
        q *= scale;
        const double transfer = q*dt/dx;
        delta[a] -= transfer; delta[b] += transfer;
    };
    for (int z = 0; z < n; ++z) for (int x = 0; x < n; ++x) {
        const int k = z*n+x;
        if (x+1 < n) apply(k,k+1,qx[k]);
        if (z+1 < n) apply(k,k+n,qz[k]);
        else if (p.outlet) {
            const double scale = outgoing[k] > 0 ? std::min(1.0, depth[k]*0.999999999/outgoing[k]) : 1;
            const double dh = outlet_flux[k]*scale*dt/dx;
            delta[k] -= dh; outlet_m3 += dh*area;
        }
    }
    for (std::size_t k = 0; k < depth.size(); ++k) depth[k] += delta[k];
    // No post-hoc clipping: positivity is enforced on shared donor fluxes.
}
void Hydro::soil_step(double dt) {
    const double top_cap = p.top_m*p.porosity, root_cap = p.root_m*p.porosity;
    for (std::size_t k = 0; k < top.size(); ++k) {
        top[k] += pending[k]; pending[k] = 0;
        const double excess = std::max(0.0, top[k]-p.top_m*p.field_theta);
        const double relative_excess = excess / (p.top_m*(p.porosity-p.field_theta));
        const double percolation = std::min({excess, p.conductivity_m_s*dt*relative_excess,
                                            std::max(0.0, root_cap-root[k])});
        top[k] -= percolation; root[k] += percolation;
        const double root_excess = std::max(0.0, root[k]-p.root_m*p.field_theta);
        const double drainage = std::min(root_excess, p.root_conductivity_m_s*dt*
            root_excess/(p.root_m*(p.porosity-p.field_theta)));
        root[k] -= drainage;
        if(p.groundwater) { ground[k]+=drainage; recharged_m3+=drainage*dx*dx; }
        else deep_drain_m3 += drainage*dx*dx;
        const double evaporation = std::min(evaporation_demand[k],
                                            std::max(0.0, top[k]-p.top_m*p.residual_theta));
        top[k] -= evaporation; evaporated_m3 += evaporation*dx*dx;
        evaporation_demand[k] = 0;
        (void)top_cap;
    }
    if(p.groundwater) groundwater_step(dt);
}
void Hydro::groundwater_step(double duration) {
    // Upwind Darcy transmissivity. Shared faces and summed-donor bounds.
    // Saturation excess spills to surface; boundaries are sealed below ground.
    // This conceptual returnflow does not resolve pond-stage backpressure.
    std::fill(seepage_m_s.begin(),seepage_m_s.end(),0);
    const double cap=p.aquifer_m*p.specific_yield;
    auto spill=[&]() {
        for(std::size_t k=0;k<ground.size();++k) {
            const double excess=std::max(0.0,ground[k]-cap);
            ground[k]-=excess; depth[k]+=excess;
            seepage_m_s[k]+=excess/duration; seeped_m3+=excess*dx*dx;
        }
    };
    spill();
    double left=duration;
    const double stable=p.lateral_k_m_s>0 ?
        0.2*dx*dx*p.specific_yield/(p.lateral_k_m_s*p.aquifer_m) : duration;
    while(left>0) {
        const double dt=std::min(left,stable);
        std::fill(outgoing.begin(),outgoing.end(),0);
        std::fill(delta.begin(),delta.end(),0);
        auto flux=[&](int a,int b) {
            const double base_a=bed[a]-p.aquifer_m, base_b=bed[b]-p.aquifer_m;
            const double ha=base_a+ground[a]/p.specific_yield;
            const double hb=base_b+ground[b]/p.specific_yield;
            const double thickness=std::max(0.0,std::max(ha,hb)-std::max(base_a,base_b));
            const double q=p.lateral_k_m_s*thickness*(ha-hb)/dx;
            outgoing[q>0?a:b]+=std::abs(q)*dt/dx;
            return q;
        };
        for(int z=0;z<n;++z) for(int x=0;x<n;++x) {
            int k=z*n+x;
            if(x+1<n) old_x[k]=flux(k,k+1);
            if(z+1<n) old_z[k]=flux(k,k+n);
        }
        auto apply=[&](int a,int b,double q) {
            const int donor=q>0?a:b;
            const double scale=outgoing[donor]>0 ? std::min(1.0,ground[donor]*0.999999999/outgoing[donor]) : 1;
            const double transfer=q*scale*dt/dx;
            delta[a]-=transfer; delta[b]+=transfer;
        };
        for(int z=0;z<n;++z) for(int x=0;x<n;++x) {
            int k=z*n+x;
            if(x+1<n) apply(k,k+1,old_x[k]);
            if(z+1<n) apply(k,k+n,old_z[k]);
        }
        for(std::size_t k=0;k<ground.size();++k) ground[k]+=delta[k];
        spill(); left=std::max(0.0,left-dt);
    }
}
bool Hydro::finite_state() const {
    if(!std::isfinite(evaporation_rate_m_s) || evaporation_rate_m_s<0) return false;
    for (const auto *v : {&bed,&depth,&top,&root,&pending,&evaporation_demand,&ground,&seepage_m_s,&qx,&qz,&crest_x,&crest_z})
        for (double x : *v) if (!std::isfinite(x)) return false;
    for (std::size_t k = 0; k < depth.size(); ++k)
        if (depth[k] < -1e-12 || top[k] < 0 || root[k] < 0 || pending[k] < 0 || evaporation_demand[k] < 0 ||
            top[k]+pending[k] > p.top_m*p.porosity+1e-12 || root[k] > p.root_m*p.porosity+1e-12 ||
            ground[k]<0 || ground[k]>p.aquifer_m*p.specific_yield+1e-12 || seepage_m_s[k]<0) return false;
    return true;
}
}
