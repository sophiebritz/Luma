/**
 * Luma Smart Helmet - Feature Extraction
 * =======================================
 * Extracts statistical features from IMU data windows
 * for event classification
 */

#ifndef FEATURE_EXTRACTION_H
#define FEATURE_EXTRACTION_H

#include <Arduino.h>
#include <math.h>
#include "classifier.h"

// IMU data structure
struct IMUData {
    float accel_x, accel_y, accel_z;
    float gyro_x, gyro_y, gyro_z;
    float accel_mag;
    unsigned long timestamp;
};

// Helper functions
float calculateMean(float* data, int size) {
    float sum = 0;
    for (int i = 0; i < size; i++) {
        sum += data[i];
    }
    return sum / size;
}

float calculateStd(float* data, int size, float mean) {
    float sum = 0;
    for (int i = 0; i < size; i++) {
        sum += (data[i] - mean) * (data[i] - mean);
    }
    return sqrt(sum / size);
}

float calculateSkewness(float* data, int size, float mean, float std) {
    if (std == 0) return 0;
    float sum = 0;
    for (int i = 0; i < size; i++) {
        float diff = (data[i] - mean) / std;
        sum += diff * diff * diff;
    }
    return sum / size;
}

float calculateKurtosis(float* data, int size, float mean, float std) {
    if (std == 0) return 0;
    float sum = 0;
    for (int i = 0; i < size; i++) {
        float diff = (data[i] - mean) / std;
        sum += diff * diff * diff * diff;
    }
    return sum / size - 3.0f;  // Excess kurtosis
}

float calculateZeroCrossingRate(float* data, int size) {
    float mean = calculateMean(data, size);
    int crossings = 0;
    for (int i = 1; i < size; i++) {
        if ((data[i] - mean) * (data[i-1] - mean) < 0) {
            crossings++;
        }
    }
    return (float)crossings / (2.0f * size);
}

// Extract all features from IMU buffer
void extractFeatures(IMUData* buffer, int windowSize, float* features) {
    // Temporary arrays for calculations
    float accel_x[windowSize], accel_y[windowSize], accel_z[windowSize];
    float accel_mag[windowSize];
    float gyro_x[windowSize], gyro_y[windowSize], gyro_z[windowSize];
    float gyro_mag[windowSize];
    float jerk[windowSize - 1];
    
    // Extract data from buffer
    for (int i = 0; i < windowSize; i++) {
        accel_x[i] = buffer[i].accel_x;
        accel_y[i] = buffer[i].accel_y;
        accel_z[i] = buffer[i].accel_z;
        accel_mag[i] = buffer[i].accel_mag;
        gyro_x[i] = buffer[i].gyro_x;
        gyro_y[i] = buffer[i].gyro_y;
        gyro_z[i] = buffer[i].gyro_z;
        gyro_mag[i] = sqrt(gyro_x[i]*gyro_x[i] + gyro_y[i]*gyro_y[i] + gyro_z[i]*gyro_z[i]);
    }
    
    // Calculate jerk
    float dt = 1.0f / 50.0f;  // 50Hz sample rate
    for (int i = 0; i < windowSize - 1; i++) {
        jerk[i] = fabs(accel_mag[i+1] - accel_mag[i]) / dt;
    }
    
    int idx = 0;
    
    // Accelerometer X features
    float ax_mean = calculateMean(accel_x, windowSize);
    float ax_std = calculateStd(accel_x, windowSize, ax_mean);
    float ax_max = accel_x[0], ax_min = accel_x[0];
    for (int i = 1; i < windowSize; i++) {
        if (accel_x[i] > ax_max) ax_max = accel_x[i];
        if (accel_x[i] < ax_min) ax_min = accel_x[i];
    }
    features[idx++] = ax_mean;
    features[idx++] = ax_std;
    features[idx++] = ax_max;
    features[idx++] = ax_min;
    features[idx++] = ax_max - ax_min;  // range
    
    // Sort for median (simplified - use mean as approximation for speed)
    features[idx++] = ax_mean;  // median approximation
    features[idx++] = calculateSkewness(accel_x, windowSize, ax_mean, ax_std);
    features[idx++] = calculateKurtosis(accel_x, windowSize, ax_mean, ax_std);
    
    // Accelerometer Y features
    float ay_mean = calculateMean(accel_y, windowSize);
    float ay_std = calculateStd(accel_y, windowSize, ay_mean);
    float ay_max = accel_y[0], ay_min = accel_y[0];
    for (int i = 1; i < windowSize; i++) {
        if (accel_y[i] > ay_max) ay_max = accel_y[i];
        if (accel_y[i] < ay_min) ay_min = accel_y[i];
    }
    features[idx++] = ay_mean;
    features[idx++] = ay_std;
    features[idx++] = ay_max;
    features[idx++] = ay_min;
    features[idx++] = ay_max - ay_min;
    features[idx++] = ay_mean;
    features[idx++] = calculateSkewness(accel_y, windowSize, ay_mean, ay_std);
    features[idx++] = calculateKurtosis(accel_y, windowSize, ay_mean, ay_std);
    
    // Accelerometer Z features
    float az_mean = calculateMean(accel_z, windowSize);
    float az_std = calculateStd(accel_z, windowSize, az_mean);
    float az_max = accel_z[0], az_min = accel_z[0];
    for (int i = 1; i < windowSize; i++) {
        if (accel_z[i] > az_max) az_max = accel_z[i];
        if (accel_z[i] < az_min) az_min = accel_z[i];
    }
    features[idx++] = az_mean;
    features[idx++] = az_std;
    features[idx++] = az_max;
    features[idx++] = az_min;
    features[idx++] = az_max - az_min;
    features[idx++] = az_mean;
    features[idx++] = calculateSkewness(accel_z, windowSize, az_mean, az_std);
    features[idx++] = calculateKurtosis(accel_z, windowSize, az_mean, az_std);
    
    // Accel magnitude features
    float am_mean = calculateMean(accel_mag, windowSize);
    float am_std = calculateStd(accel_mag, windowSize, am_mean);
    float am_max = accel_mag[0], am_min = accel_mag[0];
    for (int i = 1; i < windowSize; i++) {
        if (accel_mag[i] > am_max) am_max = accel_mag[i];
        if (accel_mag[i] < am_min) am_min = accel_mag[i];
    }
    features[idx++] = am_mean;
    features[idx++] = am_std;
    features[idx++] = am_max;
    features[idx++] = am_min;
    features[idx++] = am_max - am_min;
    features[idx++] = am_mean;
    features[idx++] = calculateSkewness(accel_mag, windowSize, am_mean, am_std);
    features[idx++] = calculateKurtosis(accel_mag, windowSize, am_mean, am_std);
    
    // Gyroscope features (X, Y, Z)
    float gx_mean = calculateMean(gyro_x, windowSize);
    float gx_std = calculateStd(gyro_x, windowSize, gx_mean);
    float gx_max = gyro_x[0], gx_min = gyro_x[0];
    for (int i = 1; i < windowSize; i++) {
        if (gyro_x[i] > gx_max) gx_max = gyro_x[i];
        if (gyro_x[i] < gx_min) gx_min = gyro_x[i];
    }
    features[idx++] = gx_mean;
    features[idx++] = gx_std;
    features[idx++] = gx_max;
    features[idx++] = gx_min;
    features[idx++] = gx_max - gx_min;
    features[idx++] = max(fabs(gx_max), fabs(gx_min));  // abs_max
    
    float gy_mean = calculateMean(gyro_y, windowSize);
    float gy_std = calculateStd(gyro_y, windowSize, gy_mean);
    float gy_max = gyro_y[0], gy_min = gyro_y[0];
    for (int i = 1; i < windowSize; i++) {
        if (gyro_y[i] > gy_max) gy_max = gyro_y[i];
        if (gyro_y[i] < gy_min) gy_min = gyro_y[i];
    }
    features[idx++] = gy_mean;
    features[idx++] = gy_std;
    features[idx++] = gy_max;
    features[idx++] = gy_min;
    features[idx++] = gy_max - gy_min;
    features[idx++] = max(fabs(gy_max), fabs(gy_min));
    
    float gz_mean = calculateMean(gyro_z, windowSize);
    float gz_std = calculateStd(gyro_z, windowSize, gz_mean);
    float gz_max = gyro_z[0], gz_min = gyro_z[0];
    for (int i = 1; i < windowSize; i++) {
        if (gyro_z[i] > gz_max) gz_max = gyro_z[i];
        if (gyro_z[i] < gz_min) gz_min = gyro_z[i];
    }
    features[idx++] = gz_mean;
    features[idx++] = gz_std;
    features[idx++] = gz_max;
    features[idx++] = gz_min;
    features[idx++] = gz_max - gz_min;
    features[idx++] = max(fabs(gz_max), fabs(gz_min));
    
    // Gyro magnitude
    float gm_mean = calculateMean(gyro_mag, windowSize);
    float gm_max = gyro_mag[0];
    for (int i = 1; i < windowSize; i++) {
        if (gyro_mag[i] > gm_max) gm_max = gyro_mag[i];
    }
    features[idx++] = gm_mean;
    features[idx++] = gm_max;
    
    // Jerk features
    float jerk_mean = calculateMean(jerk, windowSize - 1);
    float jerk_std = calculateStd(jerk, windowSize - 1, jerk_mean);
    float jerk_max = jerk[0];
    for (int i = 1; i < windowSize - 1; i++) {
        if (jerk[i] > jerk_max) jerk_max = jerk[i];
    }
    features[idx++] = jerk_mean;
    features[idx++] = jerk_max;
    features[idx++] = jerk_std;
    
    // Energy features
    float accel_energy = 0, gyro_energy = 0;
    for (int i = 0; i < windowSize; i++) {
        accel_energy += accel_mag[i] * accel_mag[i];
        gyro_energy += gyro_mag[i] * gyro_mag[i];
    }
    features[idx++] = accel_energy / windowSize;
    features[idx++] = gyro_energy / windowSize;
    
    // Zero crossing rates
    features[idx++] = calculateZeroCrossingRate(gyro_x, windowSize);
    features[idx++] = calculateZeroCrossingRate(gyro_y, windowSize);
    features[idx++] = calculateZeroCrossingRate(gyro_z, windowSize);
    
    // Peak position (normalized)
    int peak_idx = 0;
    for (int i = 1; i < windowSize; i++) {
        if (accel_mag[i] > accel_mag[peak_idx]) peak_idx = i;
    }
    features[idx++] = (float)peak_idx / windowSize;
    
    // Pad remaining features if needed
    while (idx < N_FEATURES) {
        features[idx++] = 0.0f;
    }
}

#endif // FEATURE_EXTRACTION_H
