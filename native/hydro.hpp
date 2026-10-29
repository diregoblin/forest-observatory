#pragma once
#include <cstdint>
#include <vector>

namespace forest {
// All state is SI; soil stores equivalent water depth [m], not independent theta.
struct Parameters {
    double max_step_s = 1.0, cfl = 0.35, manning_n = 0.055;
    double theta = 0.8, max_froude = 1.0;
    double rain_m_s = 30.0 / 1000.0 / 3600.0, source_m3_s = 2.0;
    double soil_interval_s = 30.0;
    double top_m = 0.15, root_m = 0.60, porosity = 0.45;
    double field_theta = 0.28, residual_theta = 0.06;
    double conductivity_m_s = 8.0 / 1000.0 / 3600.0;
    double root_conductivity_m_s = 2.0 / 1000.0 / 3600.0;
    double evaporation_m_s = 0.12 / 1000.0 / 3600.0;
    bool outlet = true;
    bool valid() const;
};
class Hydro {
public:
    int n = 0;
    double dx = 0, time_s = 0, soil_elapsed_s = 0;
    Parameters p;
    std::vector<double> bed, depth, top, root, pending, evaporation_demand;
    // qx[k] is +east, qz[k] is +south, per-unit-width discharge [m²/s].
    // Last east/south faces are walls; south outlet is accounted separately.
    std::vector<double> qx, qz, crest_x, crest_z;
    std::vector<int> sources;
    double initial_m3 = 0, input_m3 = 0, outlet_m3 = 0;
    double evaporated_m3 = 0, deep_drain_m3 = 0, infiltrated_m3 = 0;
    std::uint64_t water_steps = 0, soil_ticks = 0, limited_faces = 0, froude_limited_faces = 0;

    bool initialize(int size, double cell_m, const Parameters &params,
                    const std::vector<double> &elevation,
                    const std::vector<double> &initial_depth,
                    const std::vector<double> &saturation,
                    const std::vector<int> &source_cells);
    bool advance(double duration_s, bool rain);
    double surface_m3() const;
    double soil_m3() const; // includes water reserved between soil ticks
    double balance_error_m3() const;
    bool finite_state() const;
private:
    std::vector<double> outgoing, delta, outlet_flux, old_x, old_z;
    double stable_step() const;
    void water_step(double dt, bool rain);
    void soil_step(double dt);
    double face_flux(int a, int b, double crest, double previous, double neighbours, double dt);
};
}
