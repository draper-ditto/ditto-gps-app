# Draper TAK

A dark, single-page Flutter app for manually sharing a username, GPS coordinates, and status across devices. Flutter clients sync peer-to-peer and through Ditto Server; the TypeScript/Node service joins the same Ditto database and offers configuration and REST inspection endpoints.

```text
Flutter device A ─┐                         ┌─ Flutter device B
                  ├── Ditto mesh/server ───┤
Node.js backend ──┘                         └─ Flutter web
```

Each device persists a UUID and owns one document in `user_presence`. Updating the username changes that document instead of creating a duplicate. Ditto DQL subscriptions sync all presence documents and store observers refresh the live mesh list. Presence documents include an `isDeleted` marker so a synchronized demo removal can be reversed when the same device publishes again.

See [CHANGELOG.md](CHANGELOG.md) for the feature history of each Draper TAK
version.

## Username uniqueness

Usernames are required and compared case-insensitively after trimming whitespace. The Flutter client checks all locally synchronized presence records before saving, while allowing a device to update its own record. The Node API performs the same check and returns HTTP `409` when another device already uses the requested username.

This validation prevents duplicates once the relevant records have synchronized, but it is not a database-level unique constraint. Two completely disconnected devices can choose the same new username at the same time because neither device has received the other's record yet. Ditto guarantees uniqueness for document `_id` values, not arbitrary fields such as `username`. If strict global username reservation becomes necessary, writes should be coordinated through a central service or the data model should use a deterministic username-based document ID with an explicit ownership strategy.

## Project layout

- `lib/` — Flutter UI, configuration loader, model, and Ditto controller
- `backend/` — TypeScript server and a Ditto SDK peer
- `backend/.env.example` — required Ditto credentials
- `CHANGELOG.md` — user-visible changes organized by application version

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
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" android:usesPermissionFlags="neverForLocation" tools:targetApi="tiramisu" />
```

Fire HD 10 (2021) models use Wi-Fi-based location and do not include a GPS
receiver. Keep both device Location and Wi-Fi enabled before selecting **Use
current location**. If a fresh Wi-Fi fix times out, Draper TAK uses the device's
last-known location when available and labels it before the user saves. Fire OS
can report that Android location services are disabled even while its Wi-Fi
provider is active, so Draper TAK attempts current and last-known acquisition
before presenting disabled-service guidance.

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
<key>NSLocationWhenInUseUsageDescription</key>
<string>Uses your current location to fill in waypoint coordinates when requested.</string>
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

Run the app on two devices, save a waypoint on each, and both should appear in
the **Mesh Device List** section on **Home**. This list contains only devices
with Draper TAK presence records; backend and infrastructure peers are
intentionally excluded. Open **Observability** to view **Mesh Topology** with
SDK-reported peer-to-peer transport links and each device's connection to Ditto
Server (the Big Peer). Every peer and connection reported by the SDK is
preserved, including nodes with multiple neighbors. The responsive graph keeps
nodes within readable size bounds and routes connections through right-angle
paths that avoid other nodes and minimize shared line lanes. Connection labels
sit at the midpoint of their complete routed path. When an SDK connection
briefly disappears, its path remains visible for 15 seconds as a dashed line in
the same protocol color with a **Reconnecting** label; it immediately becomes
solid again if the connection returns, or disappears when the grace period
expires. Select a node to center it, highlight its paths, and open its copyable
connection details; pan or zoom the graph when a larger mesh exceeds the
viewport. Disconnected and isolated nodes appear in a separate section below
the live topology so they cannot obscure active paths. Peers remain identified
even when they have no Draper TAK record or currently mapped transport edge.
Unknown peers use an **Unidentified SDK peer** label and display their stable
peer ID for troubleshooting. The backend advertises the stable device name
`Draper TAK Node backend`. Flutter web syncs through Ditto Server; browser
restrictions prevent direct peer-to-peer transports.

### Browser device identity

The web app stores its generated device UUID in both browser preferences and a
host-scoped `draper_tak_device_id` cookie. The cookie is shared by different
ports on the same hostname, so restarting Flutter on a new `localhost` port
continues using the same Draper TAK device and preloads its previously synced
waypoint. An existing browser-preference ID is migrated into the cookie on the
first launch of this version.

Run the browser application with Flutter's standard Chrome device:

```bash
flutter run \
  -d chrome \
  --dart-define=BACKEND_URL=http://localhost:8080
```

The cookie-backed identity remains consistent when Flutter uses a different
localhost port. Clearing browser data, changing browser profiles, or using a
private browsing session creates a separate device identity.

If a previous localhost origin still contains an older device ID, Draper TAK
now recovers that identity when it owns an active synchronized waypoint and the
cookie's newer ID does not. The recovered ID is written back to both browser
storage mechanisms before the editor is hydrated.

Identity remains separate between `localhost` and `127.0.0.1`, between browser
profiles, and between normal and private browsing. Cookies cleared by the user
will also reset the browser identity. To emulate several devices, use different
browsers or browser profiles. Multiple private windows belonging to the same
browser session may share one private cookie jar and therefore one device ID.

### Demo admin controls

The **Home**, **Observability**, and **Admin** tabs are available on every
supported platform. The Admin tab displays the installed Draper TAK application
version so device
deployments can be verified at a glance. It always shows the full semantic
version and build number, such as `v0.10.0 · build 10`, so `0.10.0` cannot be
mistaken for `0.1.0`. User-visible features increment the minor component;
deployable bug fixes increment the patch component. The major component remains
`0` until a developer explicitly approves promotion to the next major version.
The Flutter package uses the matching `major.minor.patch+build` format. The
Admin tab can permanently delete every synchronized document in Draper TAK's
`user_presence` collection after an explicit confirmation. Resetting demo data
does not reset the persistent identity of each device. The two Cloudflare Worker
buttons are placeholders for future headless Ditto agents and currently display
an explanation instead of launching a worker.

### Cross-platform live connection status

Native devices can participate directly in LAN, Bluetooth, and P2P Wi-Fi mesh
connections, while a browser can only use WebSockets. A web peer can therefore
receive a device's synchronized waypoint without seeing that device directly in
its own presence graph. Draper TAK publishes a lightweight connection heartbeat
with each device's Big Peer and mesh state into that device's `user_presence`
document. The dashboard prefers direct presence data when available, otherwise
uses a synchronized heartbeat observed within the last 15 seconds. Older
heartbeats expire to **Not connected** so a previously connected device is not
shown as live indefinitely.

### Synchronized Live Mesh removal

Expand any Live Mesh row and select **Remove from Live Mesh** to remove that
waypoint after an explicit confirmation. Draper TAK writes `isDeleted: true`
to the presence document, and every peer hides marked documents when the change
syncs. The removed device keeps its persistent UUID and can rejoin by saving a
status or location again, which writes `isDeleted: false` with the updated
waypoint data.

This is intentionally a reversible soft deletion for the demo. Ditto DQL
`DELETE` creates a permanent tombstone and is not appropriate for immediately
reusing the same document ID. The Admin tab's database reset remains the
permanent deletion control.

### Demo connectivity telemetry

Each Live Mesh row can be expanded to show the complete waypoint, device, and sync details. The two connectivity sections intentionally report different facts:

- **Network availability** reports the active connectivity observed by the device: Wi-Fi, Bluetooth adapter status, and cellular. Operating systems do not always expose whether an inactive radio is merely enabled, so Wi-Fi and cellular should be read as active availability rather than a hardware toggle guarantee.
- **Ditto sync transports** comes from Ditto's live Presence Graph. It reports whether that peer is connected to Ditto Server (Big Peer) and the actual peer connections Ditto currently sees, including Bluetooth, LAN/access-point, P2P Wi-Fi, and peer WebSocket links.

For a web demo of a mesh-only device, keep at least one mobile peer connected both to that device and to Ditto Server. That peer bridges the mesh-only device's updates through the Big Peer to the browser. If every mobile peer disconnects from Ditto Server, the web application cannot receive new mesh updates until a server-connected bridge returns.

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
