# Luma - Smart Cycling Helmet System

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-iOS%2015.0%2B-lightgrey)](https://www.apple.com/ios/)
[![Firmware](https://img.shields.io/badge/firmware-ESP32--C3-blue)](https://www.espressif.com/en/products/socs/esp32-c3)

An IoT smart helmet system that automatically enhances cyclist visibility and safety through real-time brake/crash detection, navigation, and weather-aware guidance.

📹 **Demo Video**: [https://youtu.be/-_lCCfsrfOs](https://youtu.be/-_lCCfsrfOs)

## Features

### 🚨 Safety Detection
- **Brake Detection**: Automatic LED activation on deceleration (83.3% recall)
- **Crash Detection**: 100% precision and recall using Random Forest ML classifier
- **Emergency Response**: Automatic emergency contact notification with 30-second user override

### 🗺️ Navigation
- **Bicycle-Specific Routing**: MapKit integration with turn-by-turn guidance
- **Manual Turn Signals**: LED indicators with automatic distance-based deactivation
- **Real-Time Speed Display**: Live speed tracking via GPS

### 🌤️ Weather Intelligence
- **Clothing Recommendations**: Context-aware suggestions based on temperature, precipitation, and UV index
- **Road Condition Warnings**: Real-time alerts for slippery surfaces and adverse weather

### 📊 Analytics
- **Ride Tracking**: Complete journey logging with GPS polyline reconstruction
- **Safety Score**: 0-100 score combining braking behavior, smoothness, and environmental factors
- **Ride History**: Session metrics including distance, speed, and event counts

## System Architecture

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

## Performance Metrics

| Metric | Value |
|--------|-------|
| **Overall Accuracy** | 77.8% |
| **Crash Precision** | 100% |
| **Crash Recall** | 100% |
| **Brake Recall** | 83.3% |
| **Brake Detection Latency** | <150ms |
| **Crash Detection Latency** | <380ms |
| **Dataset** | 132 events, 20 rides |
| **Hardware Cost** | £30-40 (vs £130-200 commercial) |

## Quick Start

### Hardware Requirements
- ESP32-C3 Mini development board
- MPU6500 6-axis IMU
- WS2812B LED strip (12 LEDs)
- 3.7V LiPo battery (2500mAh recommended)
- 100nF ceramic capacitor (for IMU decoupling)

### Firmware Setup
```bash
cd firmware
# Install PlatformIO
pip install platformio

# Build and flash
pio run --target upload
```

See [firmware/README.md](firmware/README.md) for detailed instructions.

### iOS App Setup
```bash
cd ios-app/Luma
# Open in Xcode
open Luma.xcodeproj

# Configure signing and provisioning
# Add your InfluxDB credentials to Config.plist
# Build and run on device (BLE requires physical device)
```

See [docs/IOS_SETUP.md](docs/IOS_SETUP.md) for complete setup guide.

### Data Analysis (Training Classifier)
```bash
cd data-analysis
pip install -r requirements.txt
python scripts/train_classifier.py --data data/labeled_events.csv
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
```

## Machine Learning Model

**Algorithm**: Random Forest Classifier  
**Hyperparameters**:
- `n_estimators`: 200
- `max_depth`: 10
- `min_samples_split`: 2
- `min_samples_leaf`: 1

**Features** (16 total):
- Accelerometer statistics (mean, std, max, min, range, median, skew, kurtosis)
- Gyroscope statistics (mean, std, max, range)
- Derived metrics (jerk, signal energy, zero-crossing rate)

**Top 3 Most Important Features**:
1. `accel_z_std` (14.0% importance)
2. `accel_mag_max` (10.9% importance)
3. `gyro_mag_mean` (9.8% importance)

## Data Collection Methodology

**Dataset**: 132 labeled events across 5 classes (Brake, Crash, Bump, Turn, Normal)  
**Collection Period**: 20 cycling journeys over varied conditions  
**Window Size**: 3 seconds (150 samples @ 50Hz)  
**Labeling**: Real-time manual classification via iOS testing app  
**Storage**: InfluxDB Cloud (timestamped, tagged by session_id and event_id)

**Crash Simulation**: Controlled falls onto gym mat (safety-compliant)

## Technical Specifications

### ESP32-C3 Firmware
- **Sampling Rate**: 50Hz (MPU6500 via I²C @ 400kHz)
- **Accelerometer Range**: ±8g (crash detection threshold: >4g)
- **Gyroscope Range**: ±500°/s
- **BLE Protocol**: Custom GATT service (50Hz IMU stream, 130 bytes/sec)
- **LED Control**: 12x WS2812B @ 60% brightness, GPIO data line
- **Power**: 3.7V LiPo, estimated 12-hour runtime

### iOS Application
- **Minimum Version**: iOS 15.0
- **Frameworks**: SwiftUI, CoreBluetooth, CoreLocation, MapKit
- **GPS Sampling**: Adaptive (1Hz logging mode, 5Hz navigation mode)
- **Weather API**: OpenMeteo (free tier, 5-minute polling, 1km² resolution)
- **Data Storage**: InfluxDB Cloud (Line Protocol over HTTPS)

### Safety Score Algorithm
```
S = 100 - P_brake - P_crash - P_smoothness - P_weather

Where:
P_brake = w_b * (N_brake / distance_km)  # Normalized by distance
P_crash = 50 (if any crash detected)
P_smoothness = f(jerk_mean, accel_variance)
P_weather = {0: Dry, 5: Wet, 10: Icy}
```

Output bands: **80-100** (Safe/Green), **50-79** (Moderate/Amber), **<50** (High Risk/Red)

## Security & Privacy

⚠️ **Important Considerations**:
- GPS location data stored in InfluxDB (GDPR implications)
- Emergency contact information stored locally on device
- BLE currently uses basic pairing (future: implement BLE bonding + encryption)
- API keys should use environment variables (not hardcoded)

**Recommendations for Production**:
- Implement spatial aggregation/anonymization for GPS data
- Offer on-device-only storage option
- Use iOS Keychain for sensitive credentials
- Regular security audits of BLE communication

## Bill of Materials (BOM)

| Component | Specification | Quantity | Est. Cost |
|-----------|---------------|----------|-----------|
| ESP32-C3 Mini | Microcontroller | 1 | £4 |
| MPU6500 | 6-axis IMU | 1 | £3 |
| WS2812B LED Strip | 12 LEDs, addressable | 1m | £5 |
| 3.7V LiPo Battery | 2500mAh | 1 | £8 |
| USB-C Charging Module | TP4056 | 1 | £2 |
| 100nF Capacitor | Ceramic, decoupling | 1 | £0.10 |
| Wires & Connectors | JST, Dupont | - | £3 |
| Helmet | MIPS-certified | 1 | £15 |
| **Total** | | | **£40** |

## Known Limitations

1. **Dataset Size**: 132 events (small for production deployment)
2. **Crash Simulation**: Drop testing doesn't capture all real-world crash dynamics
3. **Platform**: iOS-only (excludes ~50% of mobile market)
4. **Weather Resolution**: 1km² grid (may miss hyper-local conditions)
5. **No Certification**: Electronics not formally certified for safety-critical use
6. **Waterproofing**: Not IP-rated (electronics exposed to elements)

## Future Work

### Hardware
- [ ] Full IP67 waterproofing
- [ ] Automatic LED brightness adjustment (ambient light sensor)
- [ ] Battery monitoring with low-power alerts
- [ ] Formal safety certification (CE, EN 1078)

### Software
- [ ] Android app (cross-platform parity)
- [ ] User feedback loop for model retraining
- [ ] SHAP interpretability analysis for safety audits
- [ ] OpenRouteService API (bicycle-specific routing)
- [ ] Strava integration (social features)
- [ ] Offline maps support

### Machine Learning
- [ ] Expand dataset to 1000+ labeled events
- [ ] Conduct real-world crash testing (controlled environment)
- [ ] Add sub-classes (pothole detection, near-miss events)
- [ ] Federated learning for multi-user model improvement

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

**Sophie Britz**  
Student ID: 02235059  
Imperial College London - Dyson School of Design Engineering  
Course: DESE71003 – Sensing and Internet of Things

📧 Contact: [via GitHub Issues](https://github.com/sophiebritz/Luma/issues)

## Acknowledgments

- Imperial College London for coursework framework
- OpenMeteo for free weather API
- InfluxDB for cloud time-series database
- Apple for MapKit and CoreLocation frameworks

## Citation

If you use this project in your research, please cite:

```bibtex
@misc{britz2025luma,
  author = {Britz, Sophie},
  title = {Luma: Smart Cycling Helmet System with ML-based Safety Detection},
  year = {2025},
  publisher = {GitHub},
  journal = {GitHub Repository},
  howpublished = {\url{https://github.com/sophiebritz/Luma}},
  note = {Imperial College London DESE71003 Coursework}
}
```

---

**⚠️ Disclaimer**: This is a coursework project and not intended for commercial use without further safety testing and regulatory compliance. Always wear a properly certified helmet when cycling.
