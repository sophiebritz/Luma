#ifndef FEATURE_EXTRACTION_H
#define FEATURE_EXTRACTION_H

#include <Arduino.h>
#include <math.h>
#include "classifier.h"

// IMU data structure (shared with main.cpp)
struct IMUData {
    float accel_x, accel_y, accel_z;
    float gyro_x, gyro_y, gyro_z;
    float accel_mag;
    unsigned long timestamp;
};

static inline float calculateMean(const float* data, int n) {
    float s = 0.0f;
    for (int i = 0; i < n; i++) s += data[i];
    return s / (float)n;
}

static inline float calculateStd(const float* data, int n, float mean) {
    float s = 0.0f;
    for (int i = 0; i < n; i++) {
        float d = data[i] - mean;
        s += d * d;
    }
    return sqrtf(s / (float)n);
}

static inline float calculateSkewness(const float* data, int n, float mean, float std) {
    if (std < 1e-6f) return 0.0f;
    float s = 0.0f;
    for (int i = 0; i < n; i++) {
        float d = (data[i] - mean) / std;
        s += d * d * d;
    }
    return s / (float)n;
}

static inline float calculateKurtosis(const float* data, int n, float mean, float std) {
    if (std < 1e-6f) return 0.0f;
    float s = 0.0f;
    for (int i = 0; i < n; i++) {
        float d = (data[i] - mean) / std;
        s += d * d * d * d;
    }
    return (s / (float)n) - 3.0f; // excess kurtosis
}

static inline float calculateZeroCrossingRate(const float* data, int n) {
    float m = calculateMean(data, n);
    int crossings = 0;
    for (int i = 1; i < n; i++) {
        if ((data[i] - m) * (data[i - 1] - m) < 0.0f) crossings++;
    }
    return (float)crossings / (2.0f * (float)n);
}

// Extract all features from IMU buffer (RAW values, no scaling)
static inline void extractFeatures(const IMUData* buffer, int windowSize, float* features) {
    // NOTE: these are variable-length arrays (GCC extension). For ESP32 this is OK,
    // but keep windowSize reasonable. You are using 150.
    float ax[windowSize], ay[windowSize], az[windowSize], am[windowSize];
    float gx[windowSize], gy[windowSize], gz[windowSize], gm[windowSize];
    float jerk[windowSize - 1];

    for (int i = 0; i < windowSize; i++) {
        ax[i] = buffer[i].accel_x;
        ay[i] = buffer[i].accel_y;
        az[i] = buffer[i].accel_z;
        am[i] = buffer[i].accel_mag;

        gx[i] = buffer[i].gyro_x;
        gy[i] = buffer[i].gyro_y;
        gz[i] = buffer[i].gyro_z;

        gm[i] = sqrtf(gx[i]*gx[i] + gy[i]*gy[i] + gz[i]*gz[i]);
    }

    const float dt = 1.0f / 50.0f;
    for (int i = 0; i < windowSize - 1; i++) {
        jerk[i] = fabsf(am[i + 1] - am[i]) / dt; // g/s
    }

    int idx = 0;

    auto add8 = [&](float* s, int n) {
        float mean = calculateMean(s, n);
        float std  = calculateStd(s, n, mean);
        float mx = s[0], mn = s[0];
        for (int i = 1; i < n; i++) { mx = max(mx, s[i]); mn = min(mn, s[i]); }

        features[idx++] = mean;
        features[idx++] = std;
        features[idx++] = mx;
        features[idx++] = mn;
        features[idx++] = mx - mn;
        features[idx++] = mean; // median approx
        features[idx++] = calculateSkewness(s, n, mean, std);
        features[idx++] = calculateKurtosis(s, n, mean, std);
    };

    // Accel X/Y/Z/Mag (4*8 = 32)
    add8(ax, windowSize);
    add8(ay, windowSize);
    add8(az, windowSize);
    add8(am, windowSize);

    auto add6gyro = [&](float* s, int n) {
        float mean = calculateMean(s, n);
        float std  = calculateStd(s, n, mean);
        float mx = s[0], mn = s[0];
        for (int i = 1; i < n; i++) { mx = max(mx, s[i]); mn = min(mn, s[i]); }

        features[idx++] = mean;
        features[idx++] = std;
        features[idx++] = mx;
        features[idx++] = mn;
        features[idx++] = mx - mn;
        features[idx++] = max(fabsf(mx), fabsf(mn)); // abs max
    };

    // Gyro X/Y/Z (3*6 = 18) => total 50
    add6gyro(gx, windowSize);
    add6gyro(gy, windowSize);
    add6gyro(gz, windowSize);

    // Gyro Mag mean + max (2) => 52
    float gm_mean = calculateMean(gm, windowSize);
    float gm_max = gm[0];
    for (int i = 1; i < windowSize; i++) gm_max = max(gm_max, gm[i]);
    features[idx++] = gm_mean;
    features[idx++] = gm_max;

    // Jerk mean, max, std (3) => 55
    float jm = calculateMean(jerk, windowSize - 1);
    float js = calculateStd(jerk, windowSize - 1, jm);
    float jx = jerk[0];
    for (int i = 1; i < windowSize - 1; i++) jx = max(jx, jerk[i]);
    features[idx++] = jm;
    features[idx++] = jx;
    features[idx++] = js;

    // Energy accel, gyro (2) => 57
    float ae = 0.0f, ge = 0.0f;
    for (int i = 0; i < windowSize; i++) { ae += am[i]*am[i]; ge += gm[i]*gm[i]; }
    features[idx++] = ae / (float)windowSize;
    features[idx++] = ge / (float)windowSize;

    // ZCR gx, gy, gz (3) => 60
    features[idx++] = calculateZeroCrossingRate(gx, windowSize);
    features[idx++] = calculateZeroCrossingRate(gy, windowSize);
    features[idx++] = calculateZeroCrossingRate(gz, windowSize);

    // Peak position (1) => 61
    int peak = 0;
    for (int i = 1; i < windowSize; i++) if (am[i] > am[peak]) peak = i;
    features[idx++] = (float)peak / (float)windowSize;

    // Pad if ever short
    while (idx < N_FEATURES) features[idx++] = 0.0f;
}

// No scaling
static inline void scaleFeatures(float* features) { (void)features; }

#endif // FEATURE_EXTRACTION_H
