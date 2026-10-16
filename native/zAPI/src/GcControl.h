#pragma once
#include <cmath>

// KB throughout. Lowering to a value still above live memory cannot collect;
// allow that escape even when memory is too tight to grant a larger threshold.
inline const char *GcThresholdRejection(double used, double current,
                                        double requested, double virtualFree,
                                        double commitFree) {
  if (!std::isfinite(requested) || requested != std::floor(requested) ||
      requested > 1024.0 * 1024.0 || requested < used + 1024.0)
    return "threshold must be above live memory plus 1 MiB and at most 1 GiB";
  if (requested <= current) return nullptr;
  const double additional = requested - used;
  if (virtualFree < additional + 256.0 * 1024.0)
    return "insufficient virtual address reserve";
  if (commitFree < additional + 128.0 * 1024.0)
    return "insufficient memory commit reserve";
  return nullptr;
}
