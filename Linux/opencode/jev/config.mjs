export const defaults = Object.freeze({
  enabled: true,
  features: Object.freeze({ routing: true, review: true, context: true, skills: true }),
  model: "jev-1.13.0", deadlineMs: 2000, concurrency: 2,
  maxRequestBytes: 48000, maxResponseBytes: 262144,
  cacheEntries: 256, cacheTtlMs: 900000, cooldownFailures: 3, cooldownMs: 30000,
  contextThresholdChars: 16000, contextTargetChars: 8000,
  archiveRetentionDays: 30, skillLimit: 3,
  routeConfidence: 0.8, reviewOmitProbability: 0.15, skillFitProbability: 0.65, contextKeepProbability: 0.65,
});

export function loadConfig(options = {}) {
  for (const [key,value] of Object.entries(options)) {
    if (!(key in defaults)) throw new Error("unknown-option");
    if (key === "features") {
      if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid-features");
      for (const [name,enabled] of Object.entries(value)) {
        if (!(name in defaults.features) || typeof enabled !== "boolean") throw new Error("invalid-feature");
      }
    } else if (typeof defaults[key] === "number") {
      const probability = /Probability|Confidence/.test(key);
      if (!Number.isFinite(value) || value < (probability ? 0 : 1) || (probability ? value > 1 : !Number.isInteger(value))) {
        throw new Error("invalid-number");
      }
    } else if (typeof value !== typeof defaults[key] || (key === "model" && !/^jev-[a-zA-Z0-9][a-zA-Z0-9.-]*$/.test(value))) {
      throw new Error("invalid-option");
    }
  }
  return { ...defaults, ...options, features: { ...defaults.features, ...options.features } };
}
