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

## License

MIT License - See root LICENSE file for details.

## Support

For firmware issues, open an issue on GitHub:
https://github.com/sophiebritz/Luma/issues

**Label**: `firmware` or `hardware`
