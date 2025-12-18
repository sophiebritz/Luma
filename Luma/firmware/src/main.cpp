/*
 * Smart Bike Helmet Firmware
 * 
 * Features:
 * - Crash detection (high-G impact) with app confirmation
 * - Brake detection (deceleration pattern)
 * - Turn signals (left/right via BLE command)
 * - BLE communication with iOS app
 * 
 * Hardware:
 * - ESP32-C3 Mini
 * - MPU6500 IMU
 * - WS2812B LED Strip (12 LEDs)
 */

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_NeoPixel.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <deque>
#include "config.h"

// ============================================
// GLOBAL OBJECTS
// ============================================

Adafruit_NeoPixel leds(NUM_LEDS, PIN_LED, NEO_GRB + NEO_KHZ800);

// BLE objects
BLEServer* pServer = nullptr;
BLECharacteristic* pSensorChar = nullptr;
BLECharacteristic* pCommandChar = nullptr;
BLECharacteristic* pCrashChar = nullptr;

// ============================================
// STATE VARIABLES
// ============================================

volatile HelmetState currentState = STATE_NORMAL;
volatile HelmetState previousState = STATE_NORMAL;

// Connection state
bool deviceConnected = false;
bool oldDeviceConnected = false;

// Sensor data buffers for moving average
std::deque<float> gValueBuffer;

// Timing variables
unsigned long lastSensorRead = 0;
unsigned long brakeStartTime = 0;
unsigned long crashDetectedTime = 0;
unsigned long lastBLEUpdate = 0;

// Animation frame counters
int animationFrame = 0;
unsigned long lastAnimationUpdate = 0;

// ============================================
// BLE CALLBACKS
// ============================================

class ServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
        deviceConnected = true;
        Serial.println("BLE: Device connected");
    }

    void onDisconnect(BLEServer* pServer) {
        deviceConnected = false;
        Serial.println("BLE: Device disconnected");
    }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* pCharacteristic) {
        std::string value = pCharacteristic->getValue();
        
        if (value.length() > 0) {
            uint8_t command = value[0];
            Serial.print("BLE Command received: 0x");
            Serial.println(command, HEX);
            
            switch (command) {
                case CMD_TURN_LEFT_ON:
                    if (currentState != STATE_CRASH_ALERT) {
                        previousState = currentState;
                        currentState = STATE_TURN_LEFT;
                    }
                    break;
                    
                case CMD_TURN_LEFT_OFF:
                    if (currentState == STATE_TURN_LEFT) {
                        currentState = STATE_NORMAL;
                    }
                    break;
                    
                case CMD_TURN_RIGHT_ON:
                    if (currentState != STATE_CRASH_ALERT) {
                        previousState = currentState;
                        currentState = STATE_TURN_RIGHT;
                    }
                    break;
                    
                case CMD_TURN_RIGHT_OFF:
                    if (currentState == STATE_TURN_RIGHT) {
                        currentState = STATE_NORMAL;
                    }
                    break;
                    
                case CMD_CRASH_FALSE_ALARM:
                    if (currentState == STATE_CRASH_ALERT) {
                        Serial.println("Crash alert cancelled by user");
                        currentState = STATE_NORMAL;
                    }
                    break;
                    
                case CMD_PARTY_MODE:
                    if (currentState != STATE_CRASH_ALERT) {
                        currentState = STATE_PARTY;
                    }
                    break;
                    
                case CMD_NORMAL_MODE:
                    if (currentState != STATE_CRASH_ALERT) {
                        currentState = STATE_NORMAL;
                    }
                    break;
            }
        }
    }
};

// ============================================
// BLE SETUP
// ============================================

void setupBLE() {
    Serial.println("Initializing BLE...");
    
    BLEDevice::init(BLE_DEVICE_NAME);
    
    // Create BLE Server
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks());
    
    // Create BLE Service
    BLEService* pService = pServer->createService(SERVICE_UUID);
    
    // Sensor characteristic (notify) - sends sensor data to app
    pSensorChar = pService->createCharacteristic(
        SENSOR_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ |
        BLECharacteristic::PROPERTY_NOTIFY
    );
    pSensorChar->addDescriptor(new BLE2902());
    
    // Command characteristic (write) - receives commands from app
    pCommandChar = pService->createCharacteristic(
        COMMAND_CHAR_UUID,
        BLECharacteristic::PROPERTY_WRITE
    );
    pCommandChar->setCallbacks(new CommandCallbacks());
    
    // Crash alert characteristic (notify) - urgent crash notifications
    pCrashChar = pService->createCharacteristic(
        CRASH_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ |
        BLECharacteristic::PROPERTY_NOTIFY
    );
    pCrashChar->addDescriptor(new BLE2902());
    
    // Start the service
    pService->start();
    
    // Start advertising
    BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();
    
    Serial.println("BLE initialized. Waiting for connections...");
}

// ============================================
// SENSOR FUNCTIONS
// ============================================

void initSensors() {
    Serial.println("Initializing MPU6500...");
    Serial.print("Using I2C pins - SDA: GPIO");
    Serial.print(PIN_SDA);
    Serial.print(", SCL: GPIO");
    Serial.println(PIN_SCL);
    
    // Initialize I2C exactly like working code
    Wire.begin(PIN_SDA, PIN_SCL);
    Wire.setClock(400000);  // 400kHz like working code
    delay(100);
    
    // Check if MPU is present
    Wire.beginTransmission(0x68);
    byte error = Wire.endTransmission();
    
    if (error != 0) {
        Serial.print("MPU6500 NOT FOUND! Error: ");
        Serial.println(error);
        Serial.println("Check wiring!");
        
        // Flash error pattern on LEDs
        while (1) {
            leds.fill(leds.Color(255, 0, 0));
            leds.show();
            delay(500);
            leds.clear();
            leds.show();
            delay(500);
        }
    }
    
    Serial.println("MPU6500 Found!");
    
    // Wake up MPU6500 (same as working code)
    Wire.beginTransmission(0x68);
    Wire.write(0x6B);  // PWR_MGMT_1
    Wire.write(0);     // Wake up
    Wire.endTransmission(true);
    
    delay(100);
    
    // Configure for 8G range (for crash detection)
    // ACCEL_CONFIG register (0x1C), set to Â±8g (bits 4:3 = 10)
    Wire.beginTransmission(0x68);
    Wire.write(0x1C);  // ACCEL_CONFIG
    Wire.write(0x10);  // Â±8g range
    Wire.endTransmission(true);
    
    // Configure gyro for 500Â°/s range
    Wire.beginTransmission(0x68);
    Wire.write(0x1B);  // GYRO_CONFIG  
    Wire.write(0x08);  // Â±500Â°/s range
    Wire.endTransmission(true);
    
    Serial.println("MPU6500 initialized successfully!");
}

// Helper function to read 16-bit register
int16_t readMPURegister16(byte reg) {
    Wire.beginTransmission(0x68);
    Wire.write(reg);
    Wire.endTransmission(false);
    Wire.requestFrom(0x68, 2);
    
    if (Wire.available() >= 2) {
        int16_t value = Wire.read() << 8 | Wire.read();
        return value;
    }
    return 0;
}

// Structure to hold processed sensor data
struct SensorData {
    float gForce;       // Current G-force magnitude
    float avgGForce;    // Averaged G-force
    float accelX;       // Acceleration X (g)
    float accelY;       // Acceleration Y (g)
    float accelZ;       // Acceleration Z (g)
    float pitch;        // Pitch angle
    float roll;         // Roll angle
    bool isBraking;     // Braking detected
    bool isCrash;       // Crash detected
};

SensorData readSensors() {
    SensorData data = {0};
    
    // Read raw accelerometer values
    int16_t ax = readMPURegister16(0x3B);  // ACCEL_XOUT_H
    int16_t ay = readMPURegister16(0x3D);  // ACCEL_YOUT_H
    int16_t az = readMPURegister16(0x3F);  // ACCEL_ZOUT_H
    
    // Convert to G (Â±8g range = 4096 LSB/g)
    data.accelX = ax / 4096.0f;
    data.accelY = ay / 4096.0f;
    data.accelZ = az / 4096.0f;
    
    // Calculate resultant G-force (magnitude)
    data.gForce = sqrt(data.accelX * data.accelX + 
                       data.accelY * data.accelY + 
                       data.accelZ * data.accelZ);
    
    // Add to moving average buffer
    gValueBuffer.push_back(data.gForce);
    if (gValueBuffer.size() > SENSOR_SAMPLE_SIZE) {
        gValueBuffer.pop_front();
    }
    
    // Calculate moving average
    if (gValueBuffer.size() == SENSOR_SAMPLE_SIZE) {
        float sum = 0;
        for (float val : gValueBuffer) {
            sum += val;
        }
        data.avgGForce = sum / SENSOR_SAMPLE_SIZE;
    } else {
        data.avgGForce = data.gForce;
    }
    
    // Calculate pitch and roll for orientation
    data.pitch = atan2(data.accelX, sqrt(data.accelY * data.accelY + data.accelZ * data.accelZ)) * 180.0 / PI;
    data.roll = atan2(data.accelY, sqrt(data.accelX * data.accelX + data.accelZ * data.accelZ)) * 180.0 / PI;
    
    // Crash detection - sudden high G impact
    if (data.gForce > CRASH_G_THRESHOLD) {
        data.isCrash = true;
        Serial.print("!!! HIGH G DETECTED: ");
        Serial.println(data.gForce);
    }
    
    // Brake detection - sustained deceleration
    // Only trigger if we're not in crash state
    if (!data.isCrash && data.avgGForce > BRAKE_G_THRESHOLD && data.avgGForce < CRASH_G_THRESHOLD) {
        // Check for forward deceleration (negative X typically)
        if (data.accelX < -BRAKE_G_THRESHOLD) {
            data.isBraking = true;
        }
    }
    
    return data;
}

// ============================================
// LED ANIMATION FUNCTIONS
// ============================================

void clearLeds() {
    leds.clear();
    leds.show();
}

// Normal running light - subtle red glow with breathing effect
void animateNormal() {
    static int brightness = 50;
    static int direction = 1;
    
    if (millis() - lastAnimationUpdate > 30) {
        lastAnimationUpdate = millis();
        
        brightness += direction * 2;
        if (brightness >= 100) direction = -1;
        if (brightness <= 30) direction = 1;
        
        // Soft red glow on center LEDs
        for (int i = 4; i < 8; i++) {
            leds.setPixelColor(i, leds.Color(brightness, 0, 0));
        }
        leds.show();
    }
}

// Brake light - all LEDs bright red, flashing
void animateBrake() {
    static bool isOn = true;
    
    if (millis() - lastAnimationUpdate > 100) {
        lastAnimationUpdate = millis();
        isOn = !isOn;
        
        if (isOn) {
            leds.fill(leds.Color(255, 0, 0));
        } else {
            leds.fill(leds.Color(100, 0, 0));
        }
        leds.show();
    }
}

// Left turn signal - sequential from center to left
void animateTurnLeft() {
    if (millis() - lastAnimationUpdate > TURN_SIGNAL_SPEED) {
        lastAnimationUpdate = millis();
        
        leds.clear();
        
        // Animate from center (LED 6) to left (LED 0)
        // LEDs 0-5 are left side, 6-11 are right side (adjust based on your layout)
        int activeLed = 5 - (animationFrame % 6);
        
        // Show trail effect
        for (int i = 5; i >= activeLed; i--) {
            int brightness = 255 - ((5 - i) * 40);
            if (brightness < 50) brightness = 50;
            leds.setPixelColor(i, leds.Color(255, 165, 0));  // Orange
        }
        
        leds.show();
        animationFrame++;
        
        if (animationFrame >= 12) {  // Complete cycle then pause
            animationFrame = 0;
            delay(200);  // Pause between cycles
        }
    }
}

// Right turn signal - sequential from center to right
void animateTurnRight() {
    if (millis() - lastAnimationUpdate > TURN_SIGNAL_SPEED) {
        lastAnimationUpdate = millis();
        
        leds.clear();
        
        // Animate from center (LED 5) to right (LED 11)
        int activeLed = 6 + (animationFrame % 6);
        
        // Show trail effect
        for (int i = 6; i <= activeLed; i++) {
            int brightness = 255 - ((i - 6) * 40);
            if (brightness < 50) brightness = 50;
            leds.setPixelColor(i, leds.Color(255, 165, 0));  // Orange
        }
        
        leds.show();
        animationFrame++;
        
        if (animationFrame >= 12) {
            animationFrame = 0;
            delay(200);
        }
    }
}

// Crash alert - rapid red/white flash (very visible)
void animateCrashAlert() {
    static bool isRed = true;
    
    if (millis() - lastAnimationUpdate > 50) {  // Very fast flash
        lastAnimationUpdate = millis();
        isRed = !isRed;
        
        if (isRed) {
            leds.fill(leds.Color(255, 0, 0));
        } else {
            leds.fill(leds.Color(255, 255, 255));
        }
        leds.show();
    }
}

// Party mode - rainbow
void animateParty() {
    if (millis() - lastAnimationUpdate > 20) {
        lastAnimationUpdate = millis();
        
        for (int i = 0; i < NUM_LEDS; i++) {
            int hue = (i * 256 / NUM_LEDS + animationFrame) & 255;
            leds.setPixelColor(i, leds.ColorHSV(hue * 256, 255, 200));
        }
        leds.show();
        
        animationFrame++;
        if (animationFrame >= 256) animationFrame = 0;
    }
}

// ============================================
// BLE DATA TRANSMISSION
// ============================================

void sendSensorData(SensorData& data) {
    if (!deviceConnected) return;
    
    // Pack sensor data into bytes
    // Format: [state(1)][gForce(4)][pitch(4)][roll(4)] = 13 bytes
    uint8_t buffer[13];
    
    buffer[0] = (uint8_t)currentState;
    memcpy(&buffer[1], &data.gForce, 4);
    memcpy(&buffer[5], &data.pitch, 4);
    memcpy(&buffer[9], &data.roll, 4);
    
    pSensorChar->setValue(buffer, 13);
    pSensorChar->notify();
}

void sendCrashAlert() {
    if (!deviceConnected) return;
    
    // Send crash alert
    uint8_t alert = 0x01;  // Crash detected
    pCrashChar->setValue(&alert, 1);
    pCrashChar->notify();
    
    Serial.println("CRASH ALERT sent to app!");
}

// ============================================
// MAIN SETUP
// ============================================

void setup() {
    Serial.begin(115200);
    delay(1000);
    
    Serial.println("\n========================================");
    Serial.println("   Smart Bike Helmet - Starting Up");
    Serial.println("========================================\n");
    
    // Initialize LEDs
    leds.begin();
    leds.setBrightness(LED_BRIGHTNESS);
    leds.clear();
    leds.show();
    
    // Startup animation
    Serial.println("LED startup sequence...");
    for (int i = 0; i < NUM_LEDS; i++) {
        leds.setPixelColor(i, leds.Color(0, 255, 0));
        leds.show();
        delay(50);
    }
    delay(500);
    leds.clear();
    leds.show();
    
    // Initialize sensors
    initSensors();
    
    // Initialize BLE
    setupBLE();
    
    Serial.println("\n========================================");
    Serial.println("   Initialization Complete!");
    Serial.println("========================================\n");
}

// ============================================
// MAIN LOOP
// ============================================

void loop() {
    unsigned long currentTime = millis();
    
    // ----------------------------------------
    // Read sensors (every 20ms = 50Hz)
    // ----------------------------------------
    if (currentTime - lastSensorRead >= 20) {
        lastSensorRead = currentTime;
        
        SensorData sensorData = readSensors();
        
        // Handle crash detection
        if (sensorData.isCrash && currentState != STATE_CRASH_ALERT) {
            Serial.println("!!! CRASH DETECTED !!!");
            currentState = STATE_CRASH_ALERT;
            crashDetectedTime = currentTime;
            sendCrashAlert();
            gValueBuffer.clear();  // Reset buffer after crash
        }
        
        // Handle brake detection (only if not in special state)
        if (sensorData.isBraking && 
            currentState != STATE_CRASH_ALERT && 
            currentState != STATE_TURN_LEFT && 
            currentState != STATE_TURN_RIGHT) {
            
            if (currentState != STATE_BRAKING) {
                Serial.println("Braking detected!");
                currentState = STATE_BRAKING;
                brakeStartTime = currentTime;
            }
        }
        
        // Send sensor data via BLE (every 100ms)
        if (currentTime - lastBLEUpdate >= 100) {
            lastBLEUpdate = currentTime;
            sendSensorData(sensorData);
        }
    }
    
    // ----------------------------------------
    // State timeout handling
    // ----------------------------------------
    
    // Crash confirmation timeout
    if (currentState == STATE_CRASH_ALERT) {
        if (currentTime - crashDetectedTime >= CRASH_CONFIRMATION_MS) {
            Serial.println("!!! NO RESPONSE - CONFIRMING CRASH !!!");
            // Here you could trigger emergency protocols
            // For now, we'll keep flashing
        }
    }
    
    // Brake light timeout
    if (currentState == STATE_BRAKING) {
        if (currentTime - brakeStartTime >= BRAKE_FLASH_DURATION) {
            currentState = STATE_NORMAL;
        }
    }
    
    // ----------------------------------------
    // LED Animation based on state
    // ----------------------------------------
    leds.clear();
    
    switch (currentState) {
        case STATE_NORMAL:
            animateNormal();
            break;
            
        case STATE_BRAKING:
            animateBrake();
            break;
            
        case STATE_TURN_LEFT:
            animateTurnLeft();
            break;
            
        case STATE_TURN_RIGHT:
            animateTurnRight();
            break;
            
        case STATE_CRASH_ALERT:
            animateCrashAlert();
            break;
            
        case STATE_PARTY:
            animateParty();
            break;
    }
    
    // ----------------------------------------
    // Handle BLE reconnection
    // ----------------------------------------
    if (!deviceConnected && oldDeviceConnected) {
        delay(500);
        pServer->startAdvertising();
        Serial.println("BLE: Restarting advertising");
        oldDeviceConnected = deviceConnected;
    }
    
    if (deviceConnected && !oldDeviceConnected) {
        oldDeviceConnected = deviceConnected;
    }
}
