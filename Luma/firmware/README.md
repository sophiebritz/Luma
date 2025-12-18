# Luma Firmware - ESP32-C3

This directory contains the embedded firmware for the Luma smart helmet, running on the ESP32-C3 microcontroller.

## Features

- **Real-time IMU Sampling**: MPU6500 @ 50Hz via I²C (400kHz)
- **Local ML Inference**: Random Forest classifier deployed on-device
- **BLE Communication**: Custom GATT service for iOS app connectivity
- **LED Control**: 12x WS2812B addressable LEDs for visual feedback
- **Event Detection**: Brake and crash detection with <150ms latency

## Hardware Connections

### I²C (MPU6500)
```
MPU6500 VCC  → ESP32-C3 3.3V
MPU6500 GND  → ESP32-C3 GND
MPU6500 SDA  → ESP32-C3 GPIO10
MPU6500 SCL  → ESP32-C3 GPIO8
MPU6500 VCC  ─┬─ 100nF ceramic capacitor
MPU6500 GND  ─┘  (decoupling)
```

### LED Strip (WS2812B)
```
WS2812B VCC  → ESP32-C3 5V (via battery)
WS2812B GND  → ESP32-C3 GND
WS2812B DIN  → ESP32-C3 GPIO0
```

### Power
```
3.7V LiPo  → TP4056 USB-C Charging Module → ESP32-C3 5V
```

## Pin Configuration

See `include/config.h` for all pin definitions:

| Pin | Function | Description |
|-----|----------|-------------|
| GPIO10 | I²C SDA | MPU6500 data line |
| GPIO8 | I²C SCL | MPU6500 clock line |
| GPIO0 | LED Data | WS2812B control signal |

## Setup Instructions

### Prerequisites

1. Install PlatformIO:
```bash
pip install platformio
```

2. Install ESP32 platform:
```bash
pio platform install espressif32
```

### Building

```bash
cd firmware
pio run
```

### Flashing

1. Connect ESP32-C3 via USB-C
2. Put device in download mode (hold BOOT button, press RESET)
3. Flash firmware:
```bash
pio run --target upload
```

### Serial Monitor

View debug output:
```bash
pio device monitor --baud 115200
```

## Configuration

Edit `include/config.h` to modify:

### Detection Thresholds
```cpp
#define CRASH_G_THRESHOLD 4.0f     // Crash detection (G-force)
#define BRAKE_G_THRESHOLD 0.5f     // Brake detection (deceleration)
```

### LED Settings
```cpp
#define NUM_LEDS 12                // Number of WS2812B LEDs
#define LED_BRIGHTNESS 150         // Brightness (0-255)
```

### BLE Configuration
```cpp
#define BLE_DEVICE_NAME "SmartHelmet"
#define SERVICE_UUID "19B10000-E8F2-537E-4F6C-D104768A1214"
```

## Firmware Architecture

### Main Loop (`main.cpp`)

```
Setup:
1. Initialize Serial (115200 baud)
2. Initialize I²C (400kHz)
3. Configure MPU6500 (±8g, low-pass filter)
4. Initialize WS2812B LEDs
5. Start BLE service
6. Load RF classifier model

Loop (every 20ms = 50Hz):
1. Read MPU6500 (accel + gyro)
2. Calculate derived metrics (jerk, magnitude)
3. Run event detection (local threshold check)
4. If event detected:
   a. Extract 3-second window (150 samples)
   b. Compute features (mean, std, max, etc.)
   c. Run RF classifier
   d. Update LED pattern
   e. Send BLE notification to iOS app
5. Update LED animation
6. Handle BLE commands from app
```

### BLE Protocol

**GATT Service UUID**: `19B10000-E8F2-537E-4F6C-D104768A1214`

**Characteristics**:
| UUID | Type | Description | Format |
|------|------|-------------|--------|
| `19B10001-...` | Notify | Sensor data stream | 28 bytes: `[timestamp(4), accel_x(4), accel_y(4), accel_z(4), gyro_x(4), gyro_y(4), gyro_z(4)]` |
| `19B10002-...` | Write | Commands from app | 1 byte: `[command_code]` |
| `19B10003-...` | Notify | Crash alert | 1 byte: `[alert_type]` |

**Command Codes** (from iOS app):
- `0x01`: Turn left ON
- `0x02`: Turn left OFF
- `0x03`: Turn right ON
- `0x04`: Turn right OFF
- `0x05`: Crash false alarm (user confirmed OK)
- `0x06`: Party mode
- `0x07`: Normal mode

### LED Patterns

Defined in `main.cpp`:
- **Normal**: Subtle red breathing effect (center LEDs)
- **Braking**: Solid red flash (all LEDs)
- **Crash Alert**: Rapid red/white alternating flash (all LEDs)
- **Turn Left**: Orange sequential sweep (LEDs 0-5)
- **Turn Right**: Orange sequential sweep (LEDs 6-11)
- **Party Mode**: Rainbow animation (cycling through hue)

## Power Consumption

Estimated current draw:
- ESP32-C3 (BLE active): ~80mA
- MPU6500 (50Hz): ~3.5mA
- WS2812B (12 LEDs @ 60%): ~200mA (peak)

**Total**: ~280mA typical  
**Battery**: 2500mAh LiPo  
**Runtime**: ~9-12 hours (depending on LED usage)

## Troubleshooting

### MPU6500 Not Detected
```
Error: "MPU6500 NOT FOUND!"
```

**Solutions**:
1. Check I²C connections (SDA/SCL not swapped)
2. Verify 3.3V power supply
3. Ensure 100nF decoupling capacitor is present
4. Test I²C bus with scanner:
```cpp
Wire.beginTransmission(0x68);
byte error = Wire.endTransmission();
Serial.println(error); // Should print 0
```

### LEDs Not Responding
```
LEDs remain off or show wrong colors
```

**Solutions**:
1. Check 5V power supply to LED strip
2. Verify GPIO0 data line connection
3. Ensure common ground between ESP32 and LED strip
4. Test with simple pattern:
```cpp
leds.fill(leds.Color(255, 0, 0)); // All red
leds.show();
```

### BLE Connection Fails
```
iOS app shows "Disconnected"
```

**Solutions**:
1. Ensure ESP32 is advertising:
```cpp
BLEDevice::startAdvertising();
```
2. Check iOS Bluetooth permissions
3. Restart both ESP32 and iOS device
4. Verify BLE is not disabled in iOS Settings

### High Current Draw / Battery Drains Fast
**Solutions**:
1. Reduce LED brightness: `#define LED_BRIGHTNESS 100`
2. Disable Wi-Fi (if enabled): `WiFi.mode(WIFI_OFF);`
3. Use deep sleep when stationary (future enhancement)

## Debugging

Enable debug output in `platformio.ini`:
```ini
build_flags = 
    -D CORE_DEBUG_LEVEL=5  ; Maximum verbosity
    -D DEBUG=1
```

View real-time sensor values:
```bash
pio device monitor --baud 115200 --filter esp32_exception_decoder
```

## Performance Benchmarks

Measured with oscilloscope and profiling:

| Task | Time (ms) | % of Loop |
|------|-----------|-----------|
| I²C Read (MPU6500) | 0.48 | 2.4% |
| Feature Extraction | 1.2 | 6.0% |
| RF Inference | 3.5 | 17.5% |
| LED Update | 0.8 | 4.0% |
| BLE Notify | 1.0 | 5.0% |
| **Total** | **7.0** | **35%** |
| Idle Time | 13.0 | 65% |

Loop frequency: 50Hz (20ms period)

## Memory Usage

```
RAM:  38,420 bytes (11.7% of 320kB)
Flash: 892,156 bytes (27.3% of 3.2MB)
```

Plenty of headroom for future features!

## Future Improvements

### Firmware OTA Updates
- [ ] Implement OTA firmware updates via BLE
- [ ] Add version checking and rollback capability

### Power Optimization
- [ ] Deep sleep mode when stationary (accelerometer interrupt)
- [ ] Dynamic LED brightness based on ambient light
- [ ] Adaptive BLE connection interval

### Additional Sensors
- [ ] BME280 for temperature/humidity (comfort alerts)
- [ ] APDS-9960 for ambient light sensing
- [ ] Battery voltage monitoring (ADC)

### Advanced ML
- [ ] Deploy quantized TensorFlow Lite model
- [ ] On-device model updates via BLE
- [ ] Continuous learning from user feedback

## Testing

### Unit Tests
Located in `tests/firmware/`:
```bash
pio test
```

Tests include:
- I²C communication
- BLE packet formatting
- LED pattern validation
- Feature extraction accuracy

### Hardware-in-Loop Testing
```bash
cd tests/firmware
python hil_test.py --port /dev/ttyUSB0
```

## License

MIT License - See root LICENSE file for details.

## Support

For firmware issues, open an issue on GitHub:
https://github.com/sophiebritz/Luma/issues

**Label**: `firmware` or `hardware`
