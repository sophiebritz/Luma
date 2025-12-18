
// Feature indices for ESP32 classifier
// Generated automatically from training script

#ifndef FEATURE_INDICES_H
#define FEATURE_INDICES_H

// Number of features
#define N_FEATURES 61

// Class definitions
#define CLASS_BRAKE 0
#define CLASS_BUMP 1
#define CLASS_CRASH 2
#define CLASS_NORMAL 3
#define CLASS_TURN 4

// Feature scaling parameters (MinMax)
const float FEATURE_MIN[61] = {0.388800f, 0.078398f, 1.162842f, -1.286865f, 0.395264f, 0.315918f, -4.931273f, -0.695874f, -0.226845f, 0.044658f, 0.093994f, -1.555176f, 0.215088f, -0.253174f, -2.884106f, -1.278120f, -0.258309f, 0.046912f, -0.083496f, -2.008789f, 0.266357f, -0.255615f, -4.612069f, -1.564704f, 0.977766f, 0.087799f, 1.215832f, 0.000000f, 0.438810f, 0.980691f, -4.766998f, -0.684184f, -27.296906f, 6.637652f, -0.885496f, -415.725200f, 26.900762f, 16.167938f, -7.377045f, 7.841969f, 13.877863f, -200.274810f, 34.717557f, 20.015266f, -6.505294f, 4.543371f, 9.786260f, -173.755720f, 20.167939f, 10.167939f, 10.937498f, 27.977523f, 2.511429f, 17.747520f, 4.603635f, 0.977055f, 179.161528f, 0.105263f, 0.129032f, 0.140351f, 0.000000f};
const float FEATURE_MAX[61] = {1.056658f, 0.694109f, 5.460205f, 0.843262f, 5.496338f, 1.022705f, 4.950679f, 32.206904f, 0.301675f, 0.366312f, 2.062988f, 0.172363f, 2.530518f, 0.291260f, 4.109403f, 20.249442f, 0.889212f, 0.380533f, 1.055908f, 0.673584f, 2.426025f, 0.904785f, 2.354949f, 28.000906f, 1.104866f, 0.690564f, 5.595227f, 0.878737f, 5.397933f, 1.058364f, 5.360379f, 34.753841f, 27.095693f, 99.260149f, 291.633580f, -3.328244f, 565.175580f, 415.725200f, 7.260087f, 38.147673f, 161.068700f, -14.244275f, 284.198480f, 200.274810f, 4.370698f, 44.701517f, 220.656500f, -8.442748f, 364.152690f, 220.656500f, 65.670322f, 429.472156f, 18.174698f, 240.094993f, 47.223768f, 1.612561f, 10593.124585f, 0.517857f, 0.625000f, 0.696429f, 0.928571f};

// Feature names (for debugging)
const char* FEATURE_NAMES[61] = {
    "accel_x_mean",
    "accel_x_std",
    "accel_x_max",
    "accel_x_min",
    "accel_x_range",
    "accel_x_median",
    "accel_x_skew",
    "accel_x_kurtosis",
    "accel_y_mean",
    "accel_y_std",
    "accel_y_max",
    "accel_y_min",
    "accel_y_range",
    "accel_y_median",
    "accel_y_skew",
    "accel_y_kurtosis",
    "accel_z_mean",
    "accel_z_std",
    "accel_z_max",
    "accel_z_min",
    "accel_z_range",
    "accel_z_median",
    "accel_z_skew",
    "accel_z_kurtosis",
    "accel_mag_mean",
    "accel_mag_std",
    "accel_mag_max",
    "accel_mag_min",
    "accel_mag_range",
    "accel_mag_median",
    "accel_mag_skew",
    "accel_mag_kurtosis",
    "gyro_x_mean",
    "gyro_x_std",
    "gyro_x_max",
    "gyro_x_min",
    "gyro_x_range",
    "gyro_x_abs_max",
    "gyro_y_mean",
    "gyro_y_std",
    "gyro_y_max",
    "gyro_y_min",
    "gyro_y_range",
    "gyro_y_abs_max",
    "gyro_z_mean",
    "gyro_z_std",
    "gyro_z_max",
    "gyro_z_min",
    "gyro_z_range",
    "gyro_z_abs_max",
    "gyro_mag_mean",
    "gyro_mag_max",
    "jerk_mean",
    "jerk_max",
    "jerk_std",
    "accel_energy",
    "gyro_energy",
    "gyro_x_zcr",
    "gyro_y_zcr",
    "gyro_z_zcr",
    "peak_position"
};

#endif
