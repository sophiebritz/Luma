/*
 * I2C Scanner for ESP32-C3
 * 
 * Tests different GPIO pins to find your MPU6500
 * Upload this first to verify your wiring
 */

#include <Arduino.h>
#include <Wire.h>

// Try these pin combinations one at a time
// Uncomment the one you're using:

// Option 1: GPIO8/GPIO9 (default)
#define SDA_PIN 10
#define SCL_PIN 8

// Option 2: GPIO4/GPIO5
// #define SDA_PIN 4
// #define SCL_PIN 5

// Option 3: GPIO6/GPIO7
// #define SDA_PIN 6
// #define SCL_PIN 7

// Option 4: GPIO0/GPIO1 
// #define SDA_PIN 0
// #define SCL_PIN 1

void scanI2C() {
    Serial.println("\n========================================");
    Serial.print("Scanning I2C on SDA=GPIO");
    Serial.print(SDA_PIN);
    Serial.print(", SCL=GPIO");
    Serial.println(SCL_PIN);
    Serial.println("========================================");
    
    int devicesFound = 0;
    
    for (byte address = 1; address < 127; address++) {
        Wire.beginTransmission(address);
        byte error = Wire.endTransmission();
        
        if (error == 0) {
            Serial.print("✓ Device found at 0x");
            if (address < 16) Serial.print("0");
            Serial.print(address, HEX);
            
            // Identify common devices
            if (address == 0x68) {
                Serial.print(" <- MPU6500/MPU6050/MPU9250 (AD0=LOW)");
            } else if (address == 0x69) {
                Serial.print(" <- MPU6500/MPU6050/MPU9250 (AD0=HIGH)");
            } else if (address == 0x76 || address == 0x77) {
                Serial.print(" <- BMP280/BME280");
            } else if (address == 0x3C || address == 0x3D) {
                Serial.print(" <- OLED Display");
            }
            
            Serial.println();
            devicesFound++;
        } else if (error == 4) {
            Serial.print("✗ Error at 0x");
            if (address < 16) Serial.print("0");
            Serial.println(address, HEX);
        }
    }
    
    Serial.println("----------------------------------------");
    if (devicesFound == 0) {
        Serial.println("No I2C devices found!");
        Serial.println("\nTroubleshooting:");
        Serial.println("1. Check VCC is connected to 3.3V");
        Serial.println("2. Check GND is connected");
        Serial.println("3. Try swapping SDA and SCL wires");
        Serial.println("4. Try different GPIO pins (edit code)");
        Serial.println("5. Check if MPU6500 board has power LED on");
    } else {
        Serial.print("Found ");
        Serial.print(devicesFound);
        Serial.println(" device(s)");
    }
    Serial.println("========================================\n");
}

void setup() {
    Serial.begin(115200);
    delay(2000);  // Wait for serial monitor
    
    Serial.println("\n\n");
    Serial.println("################################");
    Serial.println("#     ESP32-C3 I2C Scanner     #");
    Serial.println("################################");
    
    Wire.begin(SDA_PIN, SCL_PIN);
    Wire.setClock(100000);  // 100kHz - slower for reliability
    
    scanI2C();
}

void loop() {
    // Scan every 5 seconds
    delay(5000);
    scanI2C();
}
