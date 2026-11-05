#pragma once
#include <algorithm>
#include <cmath>
#include <vector>

namespace forest {
// Immutable periodic cloud input. All interpolation and rainfall are double;
// presentation converts submitted fields once at the GPU boundary.
class CloudField {
public:
    int n = 0;
    double span_m = 0;
    std::vector<double> density;
    bool configure(int size, double span, const std::vector<double> &values) {
        if (size < 2 || size > 2048 || !std::isfinite(span) || span <= 0 ||
            values.size() != static_cast<std::size_t>(size) * size) return false;
        for (double v : values) if (!std::isfinite(v) || v < 0 || v > 1) return false;
        n = size; span_m = span; density = values; return true;
    }
    static double smooth(double a, double b, double value) {
        const double t = std::clamp((value-a)/(b-a), 0.0, 1.0);
        return t*t*(3-2*t);
    }
    static double rain_weight(double value, double cover) {
        // Dense cores only: the visible cloud fringe ends at threshold+.10.
        const double threshold = .69 - .32*cover;
        return smooth(threshold+.10, threshold+.24, value);
    }
    double sample_uv(double u, double v) const {
        if (n == 0) return 0;
        const double x = (u-std::floor(u))*n-.5, z = (v-std::floor(v))*n-.5;
        const int ix = static_cast<int>(std::floor(x)), iz = static_cast<int>(std::floor(z));
        const double wx = x-ix, wz = z-iz;
        auto at = [&](int i,int j) { return density[((j%n+n)%n)*n+(i%n+n)%n]; };
        return (at(ix,iz)*(1-wx)+at(ix+1,iz)*wx)*(1-wz)+
            (at(ix,iz+1)*(1-wx)+at(ix+1,iz+1)*wx)*wz;
    }
    double sample(double x, double z, double extent, double offset_x, double offset_z) const {
        return sample_uv(.5+(x-extent*.5-offset_x)/span_m,
                         .5+(z-extent*.5-offset_z)/span_m);
    }
};
}
