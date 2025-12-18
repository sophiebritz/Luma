/**
 * Luma Smart Helmet - Event Classifier
 * =====================================
 * Decision tree classifier tuned from Random Forest results
 * Uses RAW features (no scaling required)
 */

#ifndef CLASSIFIER_H
#define CLASSIFIER_H

#include <Arduino.h>
#include <math.h>

#define N_FEATURES 61

#define CLASS_BRAKE  0
#define CLASS_BUMP   1
#define CLASS_CRASH  2
#define CLASS_NORMAL 3
#define CLASS_TURN   4
#define N_CLASSES    5

static const char* CLASS_NAMES[N_CLASSES] = {"brake", "bump", "crash", "normal", "turn"};

/*
 * RAW features expected (NO scaling).
 * Indices (based on extractFeatures order):
 *   accel_z_std   = f[17]  (g)
 *   accel_mag_max = f[26]  (g)
 *   gyro_mag_max  = f[51]  (deg/s)
 *   jerk_mean     = f[52]  (g/s)
 *   jerk_max      = f[53]  (g/s)
 */

static inline int classifyEvent(float* f) {
    const float accel_z_std   = f[17];
    const float accel_mag_max = f[26];
    const float gyro_mag_max  = f[51];
    const float jerk_mean     = f[52];
    const float jerk_max      = f[53];

    // ---------------- CRASH ----------------
    // Must have: strong impact + strong jerk + strong rotation
    // (this stops "brake" being promoted to crash)
    const bool crashImpact = (accel_mag_max > 3.2f);
    const bool crashJerk   = (jerk_max > 55.0f);
    const bool crashGyro   = (gyro_mag_max > 220.0f);

    if ((crashImpact && crashJerk && crashGyro) ||
        (accel_mag_max > 3.6f && jerk_max > 45.0f && gyro_mag_max > 180.0f)) {
        return CLASS_CRASH;
    }

    // ---------------- BRAKE ----------------
    // Moderate jerk, low rotation, not a big impact
    const bool brakeJerkBand = (jerk_mean > 6.0f && jerk_mean < 35.0f);
    const bool brakeJerkMax  = (jerk_max  > 14.0f && jerk_max  < 55.0f);
    const bool brakeLowGyro  = (gyro_mag_max < 140.0f);
    const bool brakeLowImpact= (accel_mag_max < 2.6f);

    if (brakeJerkBand && brakeJerkMax && brakeLowGyro && brakeLowImpact && accel_z_std < 0.9f) {
        return CLASS_BRAKE;
    }

    // ---------------- TURN ----------------
    if (gyro_mag_max > 200.0f && accel_mag_max < 2.2f) {
        return CLASS_TURN;
    }

    // ---------------- BUMP ----------------
    if (accel_mag_max > 2.2f && accel_mag_max < 3.2f &&
        jerk_max > 18.0f && jerk_max < 70.0f) {
        return CLASS_BUMP;
    }

    return CLASS_NORMAL;
}

static inline float getClassConfidence(float* f, int c) {
    const float am = f[26];  // accel_mag_max
    const float jm = f[52];  // jerk_mean
    const float jx = f[53];  // jerk_max
    const float gm = f[51];  // gyro_mag_max

    switch (c) {
        case CLASS_CRASH: {
            float s1 = (am - 3.0f) / 1.8f;
            float s2 = (jx - 45.0f) / 60.0f;
            float s3 = (gm - 180.0f) / 260.0f;
            return constrain(max(s1, max(s2, s3)), 0.2f, 1.0f);
        }
        case CLASS_BRAKE: {
            float s1 = (jm - 6.0f) / 30.0f;
            float s2 = (jx - 14.0f) / 40.0f;
            return constrain(0.5f*s1 + 0.5f*s2, 0.2f, 0.95f);
        }
        case CLASS_TURN: {
            float s = (gm - 200.0f) / 250.0f;
            return constrain(s, 0.2f, 0.9f);
        }
        case CLASS_BUMP: {
            float s = (am - 2.0f) / 1.5f;
            return constrain(s, 0.2f, 0.85f);
        }
        default:
            return 0.8f;
    }
}

#endif // CLASSIFIER_H
