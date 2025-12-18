# Luma
DESE71003 – Sensing and Internet of Things Project - Luma

An IoT smart helmet system that automatically enhances cyclist visibility and safety through real-time brake/crash detection, navigation, and weather-aware guidance.

**Demo Video**: [https://youtu.be/-_lCCfsrfOs](https://youtu.be/-_lCCfsrfOs)

- ### Hardware 
- ESP32-C3 Mini development board
- MPU6500 6-axis IMU
- WS2812B LED strip (12 LEDs)
- 3.7V LiPo battery (2500mAh recommended)
- 100nF ceramic capacitor (for IMU decoupling)

- ## System Architecture

```
┌─────────────────────┐
│   ESP32-C3 Helmet   │
│  ┌──────────────┐   │
│  │  MPU6500 IMU │   │ 50Hz @ ±8g
│  │  (I²C 400kHz)│───┤
│  └──────────────┘   │
│  ┌──────────────┐   │
│  │ WS2812B LEDs │◄──┤ Brake/Crash/Turn Signals
│  │  (12x RGB)   │   │
│  └──────────────┘   │
│  ┌──────────────┐   │
│  │Random Forest │   │ Local ML Inference
│  │  Classifier  │   │ (77.8% accuracy)
│  └──────────────┘   │
└──────┬──────────────┘
       │ BLE 5.0 (28-byte packets @ 10Hz)
       │
┌──────▼──────────────┐
│    iOS App (Swift)  │
│  ┌──────────────┐   │
│  │CoreLocation  │   │ GPS (1-5Hz adaptive)
│  │CoreBluetooth │   │
│  └──────────────┘   │
│  ┌──────────────┐   │
│  │   MapKit     │   │ Navigation
│  │ OpenMeteo API│   │ Weather (5min polling)
│  └──────────────┘   │
│  ┌──────────────┐   │
│  │  InfluxDB    │◄──┤ Cloud Storage
│  │   (HTTPS)    │   │ (Labeled events, GPS, Weather)
│  └──────────────┘   │
└─────────────────────┘
```


## Repository Structure

```
Luma/
├── firmware/              # ESP32-C3 embedded firmware
│   ├── src/              # Main source files
│   │   └── main.cpp      # IMU sampling, BLE, LED control, local RF inference
│   ├── include/          # Header files
│   │   └── config.h      # Pin definitions, thresholds, BLE UUIDs
│   └── platformio.ini    # Build configuration
│
├── ios-app/              # iOS application (SwiftUI)
│   ├── Luma/             # Main production app
│   │   ├── Models/       # Data models (HelmetModels, WeatherModels, EventModels)
│   │   ├── Services/     # Business logic (Bluetooth, InfluxDB, Navigation, etc.)
│   │   ├── Views/        # SwiftUI views (ContentView, Navigation, Weather, etc.)
│   │   └── SmartHelmetApp.swift  # App entry point
│   └── NavHaloPilot/     # Data collection/labeling app (research phase)
│       └── NavHaloPilotApp.swift
│
├── data-analysis/        # ML training pipeline
│   ├── scripts/          # Python scripts
│   │   └── train_classifier.py  # Random Forest training
│   ├── models/           # Trained .pkl models
│   ├── data/             # CSV datasets from InfluxDB
│   └── notebooks/        # Jupyter analysis notebooks
│
├── tests/                # Unit tests
│   ├── firmware/         # ESP32 tests (PlatformIO)
│   └── ios/              # Swift tests (XCTest)
│
├── scripts/              # Utility scripts
│   ├── flash_firmware.sh # Quick firmware update
│   └── export_influxdb.py  # Data export helper
│
├── .gitignore
├── LICENSE               # MIT License
└── README.md             # This file

---

* Disclaimer**: This is a coursework project and not intended for commercial use without further safety testing and regulatory compliance. Always wear a properly certified helmet when cycling.
