# Waypoint — Ditto GPS

A dark, single-page Flutter app for manually sharing a username, GPS coordinates, and status across devices. Flutter clients sync peer-to-peer and through Ditto Server; the TypeScript/Node service joins the same Ditto database and offers configuration and REST inspection endpoints.

```text
Flutter device A ─┐                         ┌─ Flutter device B
                  ├── Ditto mesh/server ───┤
Node.js backend ──┘                         └─ Flutter web
```

Each device persists a UUID and owns one document in `user_presence`. Updating the username changes that document instead of creating a duplicate. Ditto DQL subscriptions sync all presence documents and store observers refresh the live mesh list.

## Project layout

- `lib/` — Flutter UI, configuration loader, model, and Ditto controller
- `backend/` — TypeScript server and a Ditto SDK peer
- `backend/.env.example` — required Ditto credentials

## 1. Configure Ditto

Create a database in the [Ditto Portal](https://portal.ditto.live/) and copy its Database ID, Playground Token, and server URL from **Connect via SDK**.

```bash
cd backend
cp .env.example .env
```

Fill in `.env`, then start the backend:

```bash
npm install
npm run dev
```

Available routes:

- `GET /health`
- `GET /api/ditto-config`
- `GET /api/presence`
- `POST /api/presence`

The config endpoint intentionally returns a Ditto Playground Token for local development. For production, replace Playground authentication with your own short-lived authentication provider and never expose a privileged secret.

## 2. Create the Flutter platform runners

This repository contains the authored Flutter source. Because generated native runner files are machine- and Flutter-version-specific, generate them once after installing Flutter 3.24+:

```bash
flutter create --org live.ditto.demo --project-name ditto_gps --platforms=android,ios,web .
flutter pub get
```

### Android permissions

Add `xmlns:tools="http://schemas.android.com/tools"` to the root `manifest` element in `android/app/src/main/AndroidManifest.xml`, then add these before `<application>`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" tools:targetApi="s" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" tools:targetApi="s" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" tools:targetApi="s" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="32" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" android:usesPermissionFlags="neverForLocation" tools:targetApi="tiramisu" />
```

Ensure the Android project uses Kotlin Gradle plugin 1.9.20 or newer.

### iOS permissions

Add these keys inside the dictionary in `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Uses Bluetooth to connect and sync with nearby devices.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Uses Bluetooth to connect and sync with nearby devices.</string>
<key>NSLocalNetworkUsageDescription</key>
<string>Uses Wi-Fi to connect and sync with nearby devices.</string>
<key>NSBonjourServices</key>
<array>
  <string>_http-alt._tcp.</string>
</array>
```

## 3. Run the app

The app loads credentials from the Node backend by default:

```bash
flutter run --dart-define=BACKEND_URL=http://localhost:8080
```

Android emulators reach the host at `http://10.0.2.2:8080`. Physical devices need your computer's LAN address. You can also bypass the backend config route during development:

```bash
flutter run \
  --dart-define=DITTO_DATABASE_ID=your-database-id \
  --dart-define=DITTO_SERVER_URL=https://your-server-url \
  --dart-define=DITTO_PLAYGROUND_TOKEN=your-token
```

Run the app on two devices, save a waypoint on each, and both should appear in the **Live Mesh** section. Flutter web syncs through Ditto Server; browser restrictions prevent direct peer-to-peer transports.

## Validation

```bash
cd backend
npm run typecheck
npm test
npm run build

# When Flutter is installed
cd ..
flutter analyze
flutter test
```

The backend targets Node 22+ and Ditto SDK 5.0.2.
