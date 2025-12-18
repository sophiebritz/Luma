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
├── hardware/             # Physical design files
│   ├── circuit_diagram.pdf  # Wiring schematic
│   ├── bom.csv           # Bill of materials
│   └── assembly_guide.md # Build instructions
│
├── docs/                 # Documentation
│   ├── final_report.pdf  # Complete coursework report
│   ├── IOS_SETUP.md      # iOS build instructions
│   └── api_documentation.md  # BLE protocol specs
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
