# iOS App Setup Guide

## Prerequisites

- **Mac** with macOS 13.0 or later
- **Xcode 15.0+** (download from Mac App Store)
- **iPhone or iPad** running iOS 16.0 or later
- **Apple Developer Account** (free account works for testing)

## Step-by-Step Setup (15 minutes)

### 1. Create New Xcode Project

1. Open Xcode
2. Select **File → New → Project**
3. Choose **iOS → App**
4. Click **Next**

**Project Settings:**
- Product Name: `NavHaloPilot`
- Team: Select your Apple ID
- Organization Identifier: `com.yourname`
- Interface: **SwiftUI**
- Language: **Swift**
- Storage: **None**
- Uncheck "Include Tests"

5. Click **Next** and choose save location
6. Click **Create**

### 2. Add Swift Files to Project

**Copy all files from `ios-app/` folder into Xcode:**

#### Models Group
1. Right-click project → **New Group** → Name it "Models"
2. Drag `EventModels.swift` into Models group

#### Services Group
1. Right-click project → **New Group** → Name it "Services"
2. Drag these files into Services group:
   - `BluetoothManager.swift`
   - `EventDetectionService.swift`
   - `DataCollectionService.swift`

#### Views Group
1. Right-click project → **New Group** → Name it "Views"
2. Drag these files into Views group:
   - `EventClassificationView.swift`
   - `EventClassificationSheet.swift`

#### Update App File
1. Delete the default `ContentView.swift` (select and press Delete)
2. Open `NavHaloPilotApp.swift`
3. Replace its contents with the provided `NavHaloPilotApp.swift` file

### 3. Configure Bluetooth Permissions

1. Select your project in Project Navigator (blue icon at top)
2. Select target **NavHaloPilot**
3. Go to **Info** tab
4. Click **+** under "Custom iOS Target Properties"
5. Add these privacy keys:

**Required Permissions:**

| Key | Type | Value |
|-----|------|-------|
| Privacy - Bluetooth Always Usage Description | String | "NavHalo needs Bluetooth to connect to your smart helmet and collect safety data." |
| Privacy - Bluetooth Peripheral Usage Description | String | "NavHalo needs Bluetooth to communicate with your helmet's sensors." |

### 4. Configure InfluxDB Credentials

1. Open `DataCollectionService.swift`
2. Find the configuration section at the top:

```swift
// ⚠️ UPDATE THESE WITH YOUR INFLUXDB CREDENTIALS
private let influxURL = "https://YOUR-INFLUX-URL.influxdata.com"
private let influxToken = "YOUR_API_TOKEN_HERE"
private let influxOrg = "YOUR_ORG_HERE"
private let influxBucket = "navhalo-pilot"
```

3. Replace with your actual InfluxDB values:
   - **URL**: From InfluxDB Cloud dashboard (e.g., `https://us-east-1-1.aws.cloud2.influxdata.com`)
   - **Token**: API token with write permissions
   - **Org**: Your organization name
   - **Bucket**: Leave as `navhalo-pilot` (or your custom bucket name)

### 5. Configure Signing & Capabilities

1. Select project → Target → **Signing & Capabilities**
2. Check **Automatically manage signing**
3. Select your **Team** (Apple ID)
4. A unique **Bundle Identifier** will be generated automatically

**Important:** If you get code signing errors, change the bundle identifier to something unique (e.g., add your initials).

### 6. Build and Run

#### On Simulator (for testing UI only - Bluetooth won't work):
1. Select **iPhone 15 Pro** from device menu
2. Press **⌘R** or click **Play** button

#### On Physical Device (required for Bluetooth):
1. Connect iPhone/iPad via USB
2. Unlock device and trust computer if prompted
3. Select your device from device menu
4. Press **⌘R** or click **Play** button
5. On device, go to **Settings → General → VPN & Device Management**
6. Tap your Apple ID and select **Trust**

### 7. First Run Checklist

When you launch the app:

✅ **Grant Bluetooth permission** when prompted
✅ **Tap "Scan for Helmet"** to search for ESP32
✅ **Connect to "NavHalo-Pilot"** device
✅ **Tap Record** to start data collection
✅ **Shake phone** to trigger test event (if helmet not connected)

## Troubleshooting

### "Build Failed" Errors

**Missing Swift files:**
- Ensure all `.swift` files are added to project target
- Check Project Navigator: files should NOT be grayed out
- Right-click file → **Target Membership** → Check NavHaloPilot

**Code signing issues:**
- In Signing & Capabilities, try different Team
- Change Bundle Identifier to something unique
- Restart Xcode

### Bluetooth Issues

**"Scanning..." but no devices found:**
- Ensure ESP32 is powered on and running firmware
- Check Serial Monitor shows "BLE initialized and advertising"
- Try restarting ESP32
- Move phone closer to helmet

**Can't connect to device:**
- Restart Bluetooth on iPhone (Settings → Bluetooth → toggle off/on)
- Restart ESP32
- Check ESP32 Serial Monitor for error messages

**Connection drops frequently:**
- Check LiPo battery voltage (should be >3.5V)
- Move phone closer to helmet
- Check for Bluetooth interference

### InfluxDB Upload Fails

**"❌ Auth failed":**
- Verify API token in DataCollectionService.swift
- Check token has WRITE permissions in InfluxDB Cloud
- Regenerate token if needed

**"❌ Bucket not found":**
- Verify bucket name matches exactly (case-sensitive)
- Create bucket in InfluxDB Cloud if it doesn't exist

**"⚠️ HTTP 400":**
- Check Line Protocol format in DataCollectionService
- Look for special characters in notes field

## Project Structure

```
NavHaloPilot/
├── NavHaloPilotApp.swift          # Main app entry
├── Models/
│   └── EventModels.swift          # Data structures
├── Services/
│   ├── BluetoothManager.swift     # BLE communication
│   ├── EventDetectionService.swift # Spike detection
│   └── DataCollectionService.swift # InfluxDB uploads
└── Views/
    ├── EventClassificationView.swift  # Main interface
    └── EventClassificationSheet.swift # Classification modal
```

## Testing Without Helmet

You can test the UI without connecting to actual hardware:

1. **Comment out** Bluetooth requirement:
   - In `EventClassificationView.swift`
   - Comment out the `.onReceive(bluetoothManager.$latestIMUSample)` block

2. **Generate test events:**
   - Use "Manual Triggers" buttons
   - These will create sample events for classification

3. **Test InfluxDB upload:**
   - Events will still upload to InfluxDB
   - Check InfluxDB Cloud Data Explorer to verify

## Next Steps

After successful setup:

1. ✅ Connect to helmet and verify IMU data streaming
2. ✅ Collect 20+ rides with varied conditions
3. ✅ Manually label 100+ events
4. ✅ Export data from InfluxDB
5. ✅ Train Random Forest model (see `/python` folder)

## Resources

- **Apple Developer:** https://developer.apple.com/documentation/swiftui
- **CoreBluetooth Guide:** https://developer.apple.com/documentation/corebluetooth
- **InfluxDB Swift:** https://docs.influxdata.com/influxdb/cloud/api-guide/client-libraries/

---

**Need Help?** Check the main README.md or ESP32 firmware documentation.
