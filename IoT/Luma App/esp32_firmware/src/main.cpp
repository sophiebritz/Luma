/**
 * Luma Smart Helmet - ESP32-C3 Firmware
 * =====================================
 * 
 * Features:
 * - MPU6500 IMU data acquisition at 50Hz
 * - Local fallback detection (instant brake/crash response)
 * - ML-based event classification (brake, crash, normal, bump, turn)
 * - BLE 5.0 communication with iOS app
 * - WS2812B LED strip control for visual feedback
 * 
 * Hardware:
 * - ESP32-C3 Mini
 * - MPU6500 6-axis IMU (I2C)
 * - WS2812B LED Strip (12 LEDs)
 */

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_NeoPixel.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "classifier.h"
#include "feature_extraction.h"

// Debug output - comment out for production
// #define DEBUG_ENABLED

#ifdef DEBUG_ENABLED
  #include <HardwareSerial.h>
  HardwareSerial DebugSerial(0);
  #define DEBUG_PRINT(x) DebugSerial.print(x)
  #define DEBUG_PRINTLN(x) DebugSerial.println(x)
  #define DEBUG_PRINTF(...) DebugSerial.printf(__VA_ARGS__)
  #define DEBUG_BEGIN(x) DebugSerial.begin(x, SERIAL_8N1, 20, 21)
#else
  #define DEBUG_PRINT(x)
  #define DEBUG_PRINTLN(x)
  #define DEBUG_PRINTF(...)
  #define DEBUG_BEGIN(x)
#endif

// ===== Pin Definitions =====
#define LED_PIN         8
#define I2C_SDA         6
#define I2C_SCL         7

// ===== Configuration =====
#define LED_COUNT       12
#define IMU_SAMPLE_RATE 50
#define EVENT_WINDOW_SIZE 150
#define SAMPLE_INTERVAL_MS (1000 / IMU_SAMPLE_RATE)

// ===== Cooldown Timers =====
#define LOCAL_BRAKE_COOLDOWN_MS  400
#define LOCAL_CRASH_COOLDOWN_MS  3000
#define ML_BRAKE_COOLDOWN_MS     1500
#define ML_CRASH_COOLDOWN_MS     5000
#define ML_ATTEMPT_COOLDOWN_MS   800

// ===== MPU6500 Registers =====
#define MPU6500_ADDR         0x68
#define MPU6500_PWR_MGMT_1   0x6B
#define MPU6500_CONFIG       0x1A
#define MPU6500_GYRO_CONFIG  0x1B
#define MPU6500_ACCEL_CONFIG 0x1C
#define MPU6500_ACCEL_XOUT_H 0x3B

// ===== BLE UUIDs =====
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define IMU_CHAR_UUID       "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define EVENT_CHAR_UUID     "beb5483e-36e1-4688-b7f5-ea07361b26a9"
#define COMMAND_CHAR_UUID   "beb5483e-36e1-4688-b7f5-ea07361b26aa"

// ===== LED Patterns =====
enum LEDPattern {
    LED_OFF,
    LED_BRAKE,
    LED_CRASH,
    LED_TURN_LEFT,
    LED_TURN_RIGHT,
    LED_PARTY,
    LED_CONNECTED_GREEN,
    LED_ARMED_RED,
    LED_IDLE
};

// ===== Global Variables =====
Adafruit_NeoPixel strip(LED_COUNT, LED_PIN, NEO_GRB + NEO_KHZ800);

// BLE
BLEServer* pServer = nullptr;
BLECharacteristic* pIMUCharacteristic = nullptr;
BLECharacteristic* pEventCharacteristic = nullptr;
BLECharacteristic* pCommandCharacteristic = nullptr;
bool deviceConnected = false;

// IMU buffer
IMUData imuBuffer[EVENT_WINDOW_SIZE];
int bufferIndex = 0;
bool bufferFull = false;

// Event detection state
float lastAccelMag = 1.0f;

// Cooldown timestamps
unsigned long lastLocalBrakeMs = 0;
unsigned long lastLocalCrashMs = 0;
unsigned long lastMLBrakeMs = 0;
unsigned long lastMLCrashMs = 0;
unsigned long lastMLAttemptMs = 0;

// LED state
LEDPattern currentPattern = LED_IDLE;
LEDPattern savedPattern = LED_IDLE;
unsigned long lastLEDUpdate = 0;
int ledAnimationStep = 0;
unsigned long brakeEndTime = 0;
unsigned long connectGreenUntil = 0;

// Timing
unsigned long lastSampleTime = 0;

// ===== Helper: Set all LEDs =====
static inline void setAll(uint8_t r, uint8_t g, uint8_t b) {
    for (int i = 0; i < LED_COUNT; i++) {
        strip.setPixelColor(i, strip.Color(r, g, b));
    }
}

// ===== BLE Callbacks =====
class ServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
        deviceConnected = true;
        currentPattern = LED_CONNECTED_GREEN;
        connectGreenUntil = millis() + 3000;
        ledAnimationStep = 0;
    }

    void onDisconnect(BLEServer* pServer) {
        deviceConnected = false;
        currentPattern = LED_IDLE;
    }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* pCharacteristic) {
        std::string value = pCharacteristic->getValue();
        if (value.length() > 0) {
            if (value == "LEFT_ON") {
                currentPattern = LED_TURN_LEFT;
                ledAnimationStep = 0;
            } else if (value == "RIGHT_ON") {
                currentPattern = LED_TURN_RIGHT;
                ledAnimationStep = 0;
            } else if (value == "TURN_OFF") {
                currentPattern = deviceConnected ? LED_ARMED_RED : LED_IDLE;
            } else if (value == "PARTY_ON") {
                currentPattern = LED_PARTY;
                ledAnimationStep = 0;
            } else if (value == "PARTY_OFF") {
                currentPattern = deviceConnected ? LED_ARMED_RED : LED_IDLE;
            } else if (value == "CRASH_DISMISS") {
                currentPattern = deviceConnected ? LED_ARMED_RED : LED_IDLE;
            }
        }
    }
};

// ===== MPU6500 Functions =====
void writeMPU6500Register(uint8_t reg, uint8_t val) {
    Wire.beginTransmission(MPU6500_ADDR);
    Wire.write(reg);
    Wire.write(val);
    Wire.endTransmission();
}

uint8_t readMPU6500Register(uint8_t reg) {
    Wire.beginTransmission(MPU6500_ADDR);
    Wire.write(reg);
    Wire.endTransmission(false);
    Wire.requestFrom((uint8_t)MPU6500_ADDR, (uint8_t)1);
    return Wire.read();
}

bool initMPU6500() {
    Wire.begin(I2C_SDA, I2C_SCL);
    Wire.setClock(400000);

    uint8_t whoami = readMPU6500Register(0x75);
    if (whoami != 0x70 && whoami != 0x71) {
        return false;
    }

    writeMPU6500Register(MPU6500_PWR_MGMT_1, 0x00);
    delay(100);
    writeMPU6500Register(MPU6500_CONFIG, 0x04);
    writeMPU6500Register(MPU6500_GYRO_CONFIG, 0x08);   // ±500°/s
    writeMPU6500Register(MPU6500_ACCEL_CONFIG, 0x10); // ±8g

    return true;
}

void readMPU6500(IMUData* d) {
    Wire.beginTransmission(MPU6500_ADDR);
    Wire.write(MPU6500_ACCEL_XOUT_H);
    Wire.endTransmission(false);
    Wire.requestFrom((uint8_t)MPU6500_ADDR, (uint8_t)14);

    int16_t ax = (Wire.read() << 8) | Wire.read();
    int16_t ay = (Wire.read() << 8) | Wire.read();
    int16_t az = (Wire.read() << 8) | Wire.read();
    Wire.read(); Wire.read();  // Skip temp
    int16_t gx = (Wire.read() << 8) | Wire.read();
    int16_t gy = (Wire.read() << 8) | Wire.read();
    int16_t gz = (Wire.read() << 8) | Wire.read();

    d->accel_x = ax / 4096.0f;
    d->accel_y = ay / 4096.0f;
    d->accel_z = az / 4096.0f;
    d->gyro_x = gx / 65.5f;
    d->gyro_y = gy / 65.5f;
    d->gyro_z = gz / 65.5f;
    d->accel_mag = sqrtf(d->accel_x * d->accel_x + d->accel_y * d->accel_y + d->accel_z * d->accel_z);
    d->timestamp = millis();
}

// ===== BLE Functions =====
void initBLE() {
    BLEDevice::init("Luma Helmet");

    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks());

    BLEService* svc = pServer->createService(SERVICE_UUID);

    pIMUCharacteristic = svc->createCharacteristic(
        IMU_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
    );
    pIMUCharacteristic->addDescriptor(new BLE2902());

    pEventCharacteristic = svc->createCharacteristic(
        EVENT_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
    );
    pEventCharacteristic->addDescriptor(new BLE2902());

    pCommandCharacteristic = svc->createCharacteristic(
        COMMAND_CHAR_UUID,
        BLECharacteristic::PROPERTY_WRITE
    );
    pCommandCharacteristic->setCallbacks(new CommandCallbacks());

    svc->start();

    BLEAdvertising* adv = BLEDevice::getAdvertising();
    adv->addServiceUUID(SERVICE_UUID);
    adv->setScanResponse(true);
    adv->setMinPreferred(0x06);
    BLEDevice::startAdvertising();
}

void sendIMUData(const IMUData* d) {
    if (!deviceConnected) return;

    uint8_t p[28];
    memcpy(&p[0],  &d->accel_x, 4);
    memcpy(&p[4],  &d->accel_y, 4);
    memcpy(&p[8],  &d->accel_z, 4);
    memcpy(&p[12], &d->gyro_x,  4);
    memcpy(&p[16], &d->gyro_y,  4);
    memcpy(&p[20], &d->gyro_z,  4);
    memcpy(&p[24], &d->timestamp, 4);

    pIMUCharacteristic->setValue(p, 28);
    pIMUCharacteristic->notify();
}

void sendEventNotification(int cls, float conf) {
    if (!deviceConnected) return;

    uint8_t p[5];
    p[0] = (uint8_t)cls;
    memcpy(&p[1], &conf, 4);

    pEventCharacteristic->setValue(p, 5);
    pEventCharacteristic->notify();
}

// ===== Local Event Reporting =====
static inline float confFromJerk(float jerk_gps, float lo, float hi) {
    float t = (jerk_gps - lo) / (hi - lo);
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    return 0.2f + 0.8f * t;
}

static inline void reportLocalBrake(float jerk_gps) {
    sendEventNotification(CLASS_BRAKE, confFromJerk(jerk_gps, 14.0f, 30.0f));
}

static inline void reportLocalCrash(float jerk_gps, float accel_mag) {
    float c1 = confFromJerk(jerk_gps, 40.0f, 90.0f);
    float c2 = confFromJerk(accel_mag, 3.0f, 5.0f);
    float c = (c1 > c2) ? c1 : c2;
    sendEventNotification(CLASS_CRASH, c);
}

// ===== LED Functions =====
void initLEDs() {
    strip.begin();
    strip.setBrightness(153);
    strip.clear();
    strip.show();
}

void updateLEDs() {
    unsigned long now = millis();

    // Brake timeout
    if (currentPattern == LED_BRAKE && brakeEndTime && now > brakeEndTime) {
        currentPattern = savedPattern;
        brakeEndTime = 0;
    }

    // Connected green timeout -> armed red
    if (currentPattern == LED_CONNECTED_GREEN && now > connectGreenUntil) {
        currentPattern = LED_ARMED_RED;
        ledAnimationStep = 0;
        lastLEDUpdate = 0;
    }

    switch (currentPattern) {
        case LED_OFF:
            strip.clear();
            break;

        case LED_CONNECTED_GREEN:
            if (now - lastLEDUpdate > 30) {
                lastLEDUpdate = now;
                float breath = (sinf(ledAnimationStep * 0.06f) + 1.0f) * 0.5f;
                uint8_t b = (uint8_t)(breath * 110.0f);
                setAll(0, b, 0);
                ledAnimationStep++;
            }
            break;

        case LED_ARMED_RED:
            setAll(60, 0, 0);
            break;

        case LED_BRAKE: {
            const int leftCenter  = (LED_COUNT / 2) - 1;
            const int rightCenter = (LED_COUNT / 2);

            if (now - lastLEDUpdate > 40) {
                lastLEDUpdate = now;
                strip.clear();

                int half = LED_COUNT / 2;
                int w = ledAnimationStep;
                if (w > half) w = 0;

                for (int k = 0; k <= w; k++) {
                    int li = leftCenter - k;
                    int ri = rightCenter + k;
                    if (li >= 0) strip.setPixelColor(li, strip.Color(255, 0, 0));
                    if (ri < LED_COUNT) strip.setPixelColor(ri, strip.Color(255, 0, 0));
                }

                ledAnimationStep++;
                if (ledAnimationStep > half) ledAnimationStep = 0;
            }
            break;
        }

        case LED_CRASH:
            if (now - lastLEDUpdate > 100) {
                lastLEDUpdate = now;
                ledAnimationStep = !ledAnimationStep;
                if (ledAnimationStep) setAll(255, 0, 0);
                else strip.clear();
            }
            break;

        case LED_TURN_LEFT: {
            if (now - lastLEDUpdate > 70) {
                lastLEDUpdate = now;
                strip.clear();

                int half = LED_COUNT / 2;
                int centerLeft = (LED_COUNT / 2) - 1;

                for (int k = 0; k <= ledAnimationStep && k < half; k++) {
                    int idx = centerLeft - k;
                    if (idx >= 0) strip.setPixelColor(idx, strip.Color(255, 165, 0));
                }

                ledAnimationStep++;
                if (ledAnimationStep > half + 2) ledAnimationStep = 0;
            }
            break;
        }

        case LED_TURN_RIGHT: {
            if (now - lastLEDUpdate > 70) {
                lastLEDUpdate = now;
                strip.clear();

                int half = LED_COUNT / 2;
                int centerRight = (LED_COUNT / 2);

                for (int k = 0; k <= ledAnimationStep && k < half; k++) {
                    int idx = centerRight + k;
                    if (idx < LED_COUNT) strip.setPixelColor(idx, strip.Color(255, 165, 0));
                }

                ledAnimationStep++;
                if (ledAnimationStep > half + 2) ledAnimationStep = 0;
            }
            break;
        }

        case LED_PARTY:
            if (now - lastLEDUpdate > 20) {
                lastLEDUpdate = now;
                for (int i = 0; i < LED_COUNT; i++) {
                    int hue = (i * 65536 / LED_COUNT + ledAnimationStep * 256) % 65536;
                    strip.setPixelColor(i, strip.gamma32(strip.ColorHSV(hue)));
                }
                ledAnimationStep = (ledAnimationStep + 1) % 256;
            }
            break;

        case LED_IDLE:
        default:
            if (now - lastLEDUpdate > 50) {
                lastLEDUpdate = now;
                float pulse = (sinf(ledAnimationStep * 0.03f) + 1.0f) * 0.5f;
                uint8_t b = (uint8_t)(pulse * 30.0f + 10.0f);
                setAll(0, 0, b);
                ledAnimationStep++;
            }
            break;
    }

    strip.show();
}

// ===== Event Detection =====
static inline bool detectEventTrigger(const IMUData* cur) {
    float jerk = fabsf(cur->accel_mag - lastAccelMag) * IMU_SAMPLE_RATE;
    lastAccelMag = cur->accel_mag;
    return (cur->accel_mag > 1.6f) || (jerk > 6.0f);
}

static inline void fireBrakePattern(unsigned long ms) {
    savedPattern = deviceConnected ? LED_ARMED_RED : LED_IDLE;
    currentPattern = LED_BRAKE;
    brakeEndTime = millis() + ms;
    ledAnimationStep = 0;
    lastLEDUpdate = 0;
}

static inline void fireCrashPattern() {
    savedPattern = deviceConnected ? LED_ARMED_RED : LED_IDLE;
    currentPattern = LED_CRASH;
    ledAnimationStep = 0;
    lastLEDUpdate = 0;
}

void classifyAndRespondToEvent(unsigned long nowMs) {
    float features[N_FEATURES];
    extractFeatures(imuBuffer, EVENT_WINDOW_SIZE, features);

    int cls = classifyEvent(features);
    float conf = getClassConfidence(features, cls);

    DEBUG_PRINTF("ML CLS=%s conf=%.2f\n", CLASS_NAMES[cls], conf);

    if (cls == CLASS_BRAKE) {
        if (nowMs - lastMLBrakeMs >= ML_BRAKE_COOLDOWN_MS) {
            lastMLBrakeMs = nowMs;
            fireBrakePattern(900);
            sendEventNotification(cls, conf);
        } else {
            if (currentPattern == LED_BRAKE) brakeEndTime = nowMs + 900;
        }
    } else if (cls == CLASS_CRASH) {
        if (nowMs - lastMLCrashMs >= ML_CRASH_COOLDOWN_MS && currentPattern != LED_CRASH) {
            lastMLCrashMs = nowMs;
            fireCrashPattern();
            sendEventNotification(cls, conf);
        }
    } else {
        sendEventNotification(cls, conf);
    }
}

// Non-blocking post-event capture
void capturePostSamples(int nSamples) {
    for (int i = 0; i < nSamples; i++) {
        unsigned long t0 = millis();
        while (millis() - t0 < SAMPLE_INTERVAL_MS) {
            updateLEDs();
            delay(1);
        }

        IMUData d;
        readMPU6500(&d);

        imuBuffer[bufferIndex] = d;
        bufferIndex = (bufferIndex + 1) % EVENT_WINDOW_SIZE;
        if (bufferIndex == 0) bufferFull = true;

        sendIMUData(&d);
    }
}

// ===== Setup =====
void setup() {
    DEBUG_BEGIN(115200);
    delay(200);

    initLEDs();

    if (!initMPU6500()) {
        while (1) {
            setAll(255, 0, 0);
            strip.show();
            delay(300);
            strip.clear();
            strip.show();
            delay(300);
        }
    }

    initBLE();
}

// ===== Main Loop =====
void loop() {
    unsigned long now = millis();

    if (now - lastSampleTime >= SAMPLE_INTERVAL_MS) {
        lastSampleTime = now;

        IMUData d;
        readMPU6500(&d);

        imuBuffer[bufferIndex] = d;
        bufferIndex = (bufferIndex + 1) % EVENT_WINDOW_SIZE;
        if (bufferIndex == 0) bufferFull = true;

        sendIMUData(&d);

        // ========== LOCAL FALLBACK (instant response) ==========
        static float lastMagLocal = 1.0f;
        float jerkLocal = fabsf(d.accel_mag - lastMagLocal) * IMU_SAMPLE_RATE;
        lastMagLocal = d.accel_mag;

        // Crash: big hit
        if (currentPattern != LED_CRASH &&
            (now - lastLocalCrashMs >= LOCAL_CRASH_COOLDOWN_MS) &&
            (d.accel_mag > 3.0f || jerkLocal > 40.0f)) {

            lastLocalCrashMs = now;
            fireCrashPattern();
            reportLocalCrash(jerkLocal, d.accel_mag);
        }
        // Brake: strong jerk but not a big hit
        else if ((now - lastLocalBrakeMs >= LOCAL_BRAKE_COOLDOWN_MS) &&
                 (jerkLocal > 14.0f && d.accel_mag < 2.2f)) {

            lastLocalBrakeMs = now;

            if (currentPattern == LED_BRAKE) {
                brakeEndTime = now + 800;
            } else {
                fireBrakePattern(800);
                reportLocalBrake(jerkLocal);
            }
        }

        // ========== ML PATH ==========
        if (bufferFull && (now - lastMLAttemptMs >= ML_ATTEMPT_COOLDOWN_MS)) {
            if (detectEventTrigger(&d)) {
                lastMLAttemptMs = now;
                capturePostSamples(25);
                classifyAndRespondToEvent(now);
            }
        }
    }

    updateLEDs();
    delay(1);
}
