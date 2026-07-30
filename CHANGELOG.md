# Changelog

All notable changes to Draper TAK are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
while remaining on major version `0` until a developer explicitly approves a
promotion.

## [Unreleased]

## [0.19.1] - 2026-07-30

### Fixed

- Disabled cleartext HTTP traffic in Android release builds while preserving
  local HTTP backend access for debug builds.

## [0.19.0] - 2026-07-23

### Added

- Added a 15-second reconnecting state for topology connections that briefly
  disappear from SDK telemetry. Reconnecting paths retain their protocol color,
  use a dashed line, and display the protocol with a **Reconnecting** label.
- Kept temporarily missing SDK-only endpoint nodes visible while their
  connections are reconnecting, with automatic recovery or expiry.

## [0.18.0] - 2026-07-23

### Changed

- Replaced the Mesh Topology device total with the number of displayed nodes
  and unique connections, positioned immediately beside the section title.

## [0.17.2] - 2026-07-23

### Fixed

- Moved the Mesh Topology **Last updated** badge into a dedicated row above the
  graph so it cannot overlap nodes, connection lines, or transport labels.

## [0.17.1] - 2026-07-23

### Fixed

- Kept the Mesh Topology **Last updated** badge fully contained within the
  graph on 320-pixel-wide mobile screens.

## [0.17.0] - 2026-07-23

### Added

- Added a **Last updated** timestamp to the top-left corner of the Mesh
  Topology graph.

### Changed

- Corrected the top-level navigation order to **Home**, **Observability**, then
  **Admin**.
- Reduced the application-side topology observation interval from three seconds
  to one second and added event-triggered heartbeat publication when displayed
  mesh connectivity changes.

## [0.16.0] - 2026-07-23

### Added

- Added an **Observability** tab between **Home** and **Admin** with a dedicated
  monitoring icon.

### Changed

- Moved **Mesh Topology** into the Observability tab.
- Simplified the Home page to show **Mesh Device List** as a fixed titled
  section without a second tab switcher.

## [0.15.0] - 2026-07-23

### Changed

- Removed the mesh-device count from the authenticated header so it displays
  only the current authentication status.
- Renamed **Live Mesh Topology** to **Mesh Topology**.
- Updated the topology description to emphasize real-time Ditto mesh
  connectivity updates.

## [0.14.0] - 2026-07-22

### Added

- Added selectable topology nodes that center in the viewport, receive a clear
  visual highlight, emphasize their paths, and show a copyable connection
  detail panel.
- Added pan and zoom support to the topology viewport for larger meshes.

### Changed

- Routed connections with right-angle paths that score and avoid node
  collisions, shared line lanes, and unnecessary crossings.
- Distributed connections across separate node ports so nodes with several
  neighbors remain traceable.
- Bounded device node widths between 190 and 280 logical pixels and centered
  the responsive grid to preserve readability without oversized cards.

## [0.13.1] - 2026-07-22

### Fixed

- Moved disconnected and isolated topology nodes into a separate section below
  the live graph so they cannot overlap or obscure active connection lines.
- Made inactive device and isolated SDK-peer states consistently display a red
  **Not connected** status.

## [0.13.0] - 2026-07-22

### Changed

- Centered transport labels at the midpoint of each visible topology edge.
- Stopped connection lines at node boundaries and increased node spacing so
  short connections and their labels remain readable.
- Rendered label plates after connection lines so crossing edges cannot cut
  through label text.
- Preserved and displayed every connection when a node has multiple neighbors.

## [0.12.0] - 2026-07-22

### Added

- Displayed every peer reported by Ditto's Presence Graph, even when the peer
  has no mapped connection edge or Draper TAK presence record.
- Added `Unidentified SDK peer` labels and complete, selectable peer IDs for
  troubleshooting unknown topology nodes.
- Displayed Big Peer connections for unidentified SDK peers when reported by
  Ditto.

## [0.11.0] - 2026-07-22

### Changed

- Renamed **Live Mesh List** to **Mesh Device List**.
- Kept backend and infrastructure SDK peers out of the device list while
  retaining them in **Live Mesh Topology**.
- Updated list counts and empty-state language to refer to devices rather than
  implementation-level peers.

## [0.10.0] - 2026-07-22

### Added

- Added backend and infrastructure SDK peers to the topology, even when they do
  not have Draper TAK presence records.
- Synchronized native peer descriptors so the browser can display device name,
  operating system, SDK version, transport, and Big Peer connectivity observed
  by native devices.
- Added the stable `Draper TAK Node backend` identity and peer-ID fallbacks for
  unnamed processes.
- Added responsive support for SDK-only topology nodes at 320-pixel widths.

## [0.9.0] - 2026-07-22

### Fixed

- Stopped treating Fire OS's incorrect disabled-location-service response as a
  hard failure when permissions and a Wi-Fi location provider are available.
- Attempted a fresh location before falling back to the last-known Wi-Fi fix.
- Displayed disabled-service guidance only after both current and last-known
  acquisition fail.
- Clearly identified last-known coordinates before the user saves them.

## [0.8.0] - 2026-07-22

### Added

- Added Fire HD 10 Wi-Fi-location support with a last-known-location fallback
  when a fresh fix times out.
- Added disabled-location dialogs and inline actions for opening location or
  application settings.
- Added Fire-tablet-specific guidance explaining that Wi-Fi is required because
  supported Fire HD 10 hardware does not contain a GPS receiver.
- Kept detailed location errors selectable and copyable.

## [0.7.0] - 2026-07-22

### Changed

- Removed the glow and shadow from topology legend indicators, leaving flat,
  solid-color circles for better readability.

## [0.6.0] - 2026-07-22

### Changed

- Consolidated the topology explanation and legend into a bordered information
  card above the graph.
- Added explicit **Description** and **Legend** headings.
- Enlarged legend markers and text and improved their contrast on mobile.

### Fixed

- Protected topology connection labels with opaque, padded plates so Android
  connection lines do not pass through their text.

## [0.5.0] - 2026-07-22

### Changed

- Moved each connection-status badge directly beside the device identity name
  instead of placing it at the far-right edge of the row.
- Kept a narrow-screen fallback that moves the badge below the name rather than
  allowing it to clip.

## [0.4.0] - 2026-07-22

### Added

- Added switchable **Live Mesh List** and **Live Mesh Topology** views.
- Added a responsive topology graph with device nodes, saved status, transport
  labels, and a synthetic Ditto Server/Big Peer node.
- Built Big Peer edges from `Peer.isConnectedToDittoServer` and device edges
  from Ditto's actual connection endpoint keys and transport types.
- Synchronized topology snapshots so the browser can visualize BLE, LAN,
  P2P Wi-Fi, and WebSocket links observed by native devices.
- Kept disconnected devices visible as red nodes with their last-known status
  while removing expired live edges.

## [0.3.0] - 2026-07-22

### Added

- Added synchronized connection heartbeats that publish each device's Big Peer,
  mesh-transport, and network-availability state every three seconds.
- Added independent multi-device connection resolution for Big Peer + mesh,
  mesh-only, server-only, and disconnected states.

### Fixed

- Fixed the browser showing a synchronized Android device as **Not connected**
  merely because browsers cannot observe native LAN or Bluetooth peers in their
  local Presence Graph.
- Preferred direct SDK presence when available, otherwise used synchronized
  telemetry that expires after 15 seconds.

## [0.2.0] - 2026-07-22

### Changed

- Hardened host-scoped cookie-backed UUID persistence for Flutter Web so one
  browser profile retains its identity across changing `localhost` ports.
- Added recovery of an older origin-specific identity when it owns an active
  synchronized waypoint, then mirrored the recovered UUID into both cookie and
  browser preferences.
- Preloaded the recovered device's previously synchronized waypoint into the
  editor.
- Preserved intentionally separate identities across hostnames, browser
  profiles, different browsers, and private browsing contexts.

## [0.1.0] - 2026-07-22

### Added

- Established the Flutter application, TypeScript/Node backend peer, and Ditto
  synchronization for device identity, username, GPS coordinates, status, and
  live presence records.
- Added the Draper TAK waypoint editor, synchronized map, username validation,
  and explicit **Use current location** flow.
- Added Android and cross-platform permission recovery with retry, application
  settings, platform guidance, and selectable error details.
- Added expandable Live Mesh rows showing current connection, network
  availability, Ditto transports, last-known waypoint data, and device details,
  including useful offline and empty states.
- Added Wi-Fi, Bluetooth, and cellular connectivity telemetry and red
  **Not connected** indicators.
- Added persistent per-device UUIDs and initial cookie-backed web identity.
- Added **Home** and **Admin** tabs, confirmed database-reset controls, and two
  documented Cloudflare Worker placeholders.
- Added synchronized, reversible **Remove from Live Mesh** soft deletion so a
  device can rejoin with the same persistent identity.
- Added the application-version card to the Admin tab and aligned the first
  package build at `0.1.0+1`.
