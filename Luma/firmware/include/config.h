#ifndef CONFIG_H
#define CONFIG_H

// ============================================
// PIN DEFINITIONS - ESP32-C3 Mini
// ============================================

// I2C pins for MPU6500 (ACTIVE ACTIVE - TESTED WORKING)
#define PIN_SDA 10
#define PIN_SCL 8

// WS2812B LED Strip
#define PIN_LED 0
#define NUM_LEDS 12

// ============================================
// DETECTION THRESHOLDS
// ============================================

// Crash detection - high G-force impact
// Typical crash: 4-10G, we use 4G as threshold
#define CRASH_G_THRESHOLD 4.0f

// Brake detection - deceleration threshold
// Normal braking: 0.3-0.8G
#define BRAKE_G_THRESHOLD 0.5f

// Moving average samples for smoothing
#define SENSOR_SAMPLE_SIZE 10

// Crash confirmation timeout (ms)
// If user doesn't respond within this time, it's a real crash
#define CRASH_CONFIRMATION_MS 30000  // 30 seconds

// ============================================
// LED ANIMATION SETTINGS
// ============================================

#define DEFAULT_ANIMATION_SPEED 30  // ms between frames
#define BRAKE_FLASH_DURATION 3000   // ms to show brake light
#define TURN_SIGNAL_SPEED 100       // ms for turn signal animation

// LED brightness (0-255)
#define LED_BRIGHTNESS 150

// ============================================
// BLE SETTINGS
// ============================================

#define BLE_DEVICE_NAME "SmartHelmet"

// Custom UUIDs for helmet service
#define SERVICE_UUID        "19B10000-E8F2-537E-4F6C-D104768A1214"
#define SENSOR_CHAR_UUID    "19B10001-E8F2-537E-4F6C-D104768A1214"  // Sensor data (notify)
#define COMMAND_CHAR_UUID   "19B10002-E8F2-537E-4F6C-D104768A1214"  // Commands from app (write)
#define CRASH_CHAR_UUID     "19B10003-E8F2-537E-4F6C-D104768A1214"  // Crash alert (notify)

// ============================================
// BLE COMMANDS (from iOS app)
// ============================================

#define CMD_TURN_LEFT_ON    0x01
#define CMD_TURN_LEFT_OFF   0x02
#define CMD_TURN_RIGHT_ON   0x03
#define CMD_TURN_RIGHT_OFF  0x04
#define CMD_CRASH_FALSE_ALARM 0x05  // User responded - not a real crash
#define CMD_PARTY_MODE      0x06
#define CMD_NORMAL_MODE     0x07

// ============================================
// HELMET STATES
// ============================================

enum HelmetState {
    STATE_NORMAL,       // Normal running light animation
    STATE_BRAKING,      // Brake light active
    STATE_TURN_LEFT,    // Left turn signal
    STATE_TURN_RIGHT,   // Right turn signal
    STATE_CRASH_ALERT,  // Crash detected, waiting for confirmation
    STATE_PARTY         // Party mode (rainbow)
};

#endif // CONFIG_H
