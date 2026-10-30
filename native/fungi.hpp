#pragma once
#include <vector>
#include <cstdint>

namespace forest {
// One isolated soil observation plot. State: kg carbon / m²; time: s; space: m.
// Biomass diffusion is an effective colony-spread approximation, not moving hyphae.
struct FungalParameters {
    double diffusion_b_m2_s = .125*.125/(30*86400.0);
    double diffusion_r_m2_s = 2*.125*.125/(30*86400.0);
    double uptake_m4_kg2_s = 1/(.05*.05*30*86400.0);
    double mortality_s = .0475/(30*86400.0);
    double replenishment_s = .0075/(30*86400.0);
    double resource_capacity_kg_m2 = .05;
    double yield = 1; // Paper comparison uses c2/c1=1; not a measured carbon yield.
    double fruiting_s = .001/86400.0;
    double fruit_lifetime_s = 10*86400.0;
    double fruit_threshold_kg_m2 = .005;
    double max_step_s = .2*30*86400.0;
    bool finite_litter = true;
    bool valid() const;
};
class Fungi {
public:
    int n = 0;
    double dx = 0, time_s = 0, initial_kg = 0, input_kg = 0, output_kg = 0;
    std::uint64_t steps = 0;
    FungalParameters p;
    std::vector<double> biomass, resource, litter, fruit, activity, fruit_suitability;
    bool initialize(int size, double cell_m, const FungalParameters &parameters,
                    const std::vector<double> &b, const std::vector<double> &r,
                    const std::vector<double> &l);
    bool advance(double seconds);
    double carbon_kg() const;
    double balance_error_kg() const;
    bool finite_state() const;
    double edge_biomass_kg() const;
private:
    std::vector<double> next_b, next_r;
    void step(double dt);
};
}
