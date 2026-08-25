# Draper TAK Agent Instructions

## Scope

These instructions apply to the entire repository. Add a nested `AGENTS.md`
only when a directory needs more specific rules. A nested file should extend or
override this file as narrowly as possible.

## Project overview

Draper TAK is a cross-platform Flutter application backed by Ditto. It shares
device identity, GPS coordinates, user status, connectivity, and live mesh
topology across Android, iOS, and Flutter Web. The TypeScript/Node service in
`backend/` joins the same Ditto database and provides local configuration and
REST inspection endpoints.

Keep these responsibilities distinct:

- The Flutter application owns the user experience and device participation.
- The Node service is an application backend and Ditto peer.
- Ditto Server, also called the Big Peer in this demo, is synchronization
  infrastructure. It is not the Node application backend.

Preserve support for Android, iOS, and Flutter Web unless a task explicitly
targets one platform. Validate Bluetooth and local-network behavior on physical
hardware; browser and simulator behavior is not a substitute for native mesh
testing.

## Demo application version

Use the complete three-component semantic version everywhere, such as
`0.10.0`. Never shorten it to `0.10`; versions are integer components, not
decimal numbers, so `0.10.0` is distinct from `0.1.0` and follows `0.9.0`.

Keep Draper TAK on major version `0` until a developer or maintainer explicitly
instructs the AI to promote it. Do not infer a major-version change when the
minor component reaches `10` or any other value.

After every user-visible feature or behavior change:

1. Increment the minor component by one and reset the patch component to zero.
   For example, `0.9.0` becomes `0.10.0`.
2. Increment the internal build number by one. For example, `0.9.0+9` becomes
   `0.10.0+10`.
3. Update `appDisplayVersion` and `appBuildNumber` in
   `lib/config/app_version.dart`.
4. Update the matching `major.minor.patch+build` value in `pubspec.yaml`.
5. Update tests that assert the displayed version or build number.
6. Add the user-visible change to the matching version section in
   `CHANGELOG.md`. Create the version section from `[Unreleased]` when the
   release is introduced.
7. State the new public version and build number in the final implementation
   summary.

For a deployable bug-fix release without a new feature, increment the patch and
build components, such as `0.10.0+10` to `0.10.1+11`. Do not bump the version
for documentation-only, test-only, formatting-only, or internal refactoring
changes unless the user explicitly requests it.

Flutter uses `major.minor.patch+build` syntax. The integer after `+` is the
internal build number; it is not a fourth public version component and does not
represent mathematical addition. Do not reset the build number during a major
or minor change unless explicitly instructed.

## Changelog maintenance

Treat `CHANGELOG.md` as part of every user-visible feature or release. Whenever
an AI agent builds a new feature, changes observable behavior, or ships a
deployable bug fix, it must update the changelog in the same task.

- Record changes under the complete public version, such as `0.14.0` or
  `0.13.1`, using `Added`, `Changed`, `Fixed`, or `Removed` headings as
  appropriate.
- Keep newest versions first and include the release date in `YYYY-MM-DD`
  format when the version is introduced.
- Use `[Unreleased]` for meaningful user-visible work that has not yet received
  a release version, then move those entries into the new version section when
  the version is assigned.
- Describe user-visible outcomes concisely; do not turn the changelog into a
  commit log or list documentation-only, formatting-only, test-only, or
  internal refactoring work unless it materially affects users.
- Preserve existing historical entries. Correct factual mistakes when found,
  but do not silently rewrite prior release history.

## Required validation

Format every changed Dart file. After changing Flutter code, run:

```bash
flutter analyze
flutter test
```

For user-visible features, deployment changes, platform integration, or release
handoff, also run:

```bash
flutter build web
flutter build apk --debug
```

After changing the Node backend, run:

```bash
cd backend
npm run typecheck
npm test
npm run build
```

Run `git diff --check` before completing an implementation. Resolve relevant
failures rather than reporting success with known regressions. Do not treat
dependency-update notices or documented non-blocking toolchain warnings as test
failures, but mention material warnings in the final summary.

## Testing expectations

- Add or update tests for every new behavior.
- Cover connected, disconnected, empty, stale, malformed, and transition states
  when they apply.
- Add multi-device tests for Ditto synchronization and topology behavior.
- Test responsive UI changes at narrow mobile widths, including a 320-pixel
  viewport.
- Preserve tests for selectable and copyable error details.
- Keep tests deterministic. Do not require live credentials or external
  services for unit and widget tests.

## Git workflow

Every change lands on its own branch and merges with its own merge commit, so
`git log --graph` reads as a list of what each update contained. Draper TAK
changes in small increments over a long period, and the branch shape is the
record of which change was which.

**Never commit directly to `main`.**

### One branch per change

A branch is one coherent change: one thing a reader would name in a sentence,
and one entry in `CHANGELOG.md`. Two unrelated improvements are two branches,
even when they are small and even when they are already sitting in the same
worktree. Splitting them afterwards is much harder than starting them apart.

If work in progress turns out to contain two changes, land the first, then
branch again for the second.

### Branch names

`<type>/<short-kebab-slug>`, where type is one of:

| Type | For |
| --- | --- |
| `feat` | new behavior a user or API client can observe |
| `fix` | a defect in existing behavior |
| `docs` | documentation, comments, or runbooks only |
| `test` | tests only |
| `chore` | dependencies, CI, tooling, formatting |
| `refactor` | internal structure with no behavior change |

The type is chosen for what the branch changes, not for how much work it was.
A one-line change that alters observable behavior is still `feat` or `fix`; a
large internal rewrite that changes nothing a device does is `refactor`.

Examples matching this repository's history:

```
feat/live-map-and-waypoint-validation
feat/mesh-topology-reconnecting-state
fix/android-cleartext-release-traffic
docs/tak-workflows-and-release-history
chore/harden-repo-for-public-release
```

### The sequence

```bash
# 1. start from a current main
git switch main
git pull --ff-only

# 2. branch
git switch -c feat/my-change

# 3. work, committing in logical units
git add -A
git commit            # message conventions below

# 4. run the gate for this repository (see "Before you merge")

# 5. push the branch
git push -u origin feat/my-change

# 6. open a pull request
gh pr create --fill

# 7. merge, keeping the branch visible in history
gh pr merge --merge --delete-branch

# 8. return to a current main and confirm the shape
git switch main
git pull --ff-only
git log --graph --oneline -12
```

### Merge with a merge commit, never a squash

`gh pr merge --merge`. Not `--squash`, not `--rebase`.

A squash flattens the branch out of history, which is precisely the thing this
workflow exists to preserve.

### Commit messages

Match what is already in the log: an imperative, sentence-case subject naming
the outcome, not the mechanism.

```
Add persistent identity and mesh telemetry
Build Draper TAK observability and admin experience
```

No type prefix in the subject — the branch name already carries that. Use the
body to explain *why*, including what was considered and rejected, because that
is the part nobody can reconstruct later. Keep the `Co-Authored-By` trailer on
agent-authored commits.

### Before you merge

The pre-merge gate is the same one described under **Required validation**
above; keep the two in step if either changes.

```bash
flutter analyze
flutter test

cd backend
npm run typecheck
npm test
npm run build
cd ..

git diff --check
```

For user-visible features, deployment changes, platform integration, or release
handoff, also run the release builds named under **Required validation**:

```bash
flutter build web
flutter build apk --debug
```

Also required, per branch type:

- A branch that changes observable behavior carries the version bump described
  under **Demo application version** and the `CHANGELOG.md` entry described
  under **Changelog maintenance**, saying what a device now does differently.
- Branches that only touch documentation, tests, formatting, or internal
  refactoring skip both the bump and the changelog entry — they change nothing
  a device can observe.
- A branch that claims a presence, topology, or convergence improvement states
  the evidence, including which platforms it was validated on. Native mesh
  claims require physical hardware; simulator and browser results do not
  qualify.

## Ditto presence and topology rules

- Determine Big Peer connectivity from the Ditto SDK
  `Peer.isConnectedToDittoServer` value.
- Determine device-to-device topology from SDK connection endpoints and
  connection types. Do not infer physical mesh edges solely from synchronized
  application records.
- Native peers may use Bluetooth, access-point/LAN, P2P Wi-Fi, or peer
  WebSockets. Browser peers use WebSockets and cannot directly observe native
  Bluetooth or LAN links.
- The web dashboard may use fresh synchronized native heartbeat data when a
  native peer is not directly visible in the browser's presence graph.
- Prefer direct SDK presence data over synchronized heartbeat data.
- Treat a heartbeat older than the configured freshness window as disconnected.
- Keep a disconnected device visible with its last known GPS location and user
  status. When an active topology edge first disappears, retain it for the
  reconnect grace period as a dashed line in its protocol color with a
  Reconnecting label; remove it after expiry and show a red Not Connected
  state.
- Deduplicate SDK connections by their deterministic connection identity.
- A mesh-only device reaches the browser through a native peer that is connected
  to both the local mesh and the Big Peer.

## Persistent device identity

- A physical device should keep the same UUID across application restarts.
- Flutter Web identity must persist across localhost port changes by using the
  host-scoped identity cookie together with browser preferences.
- Do not use a MAC address as application identity.
- Keep identities separate across different hostnames, browser profiles, and
  private browsing contexts so the demo can emulate multiple devices.
- Preserve and preload the current device's previously synchronized waypoint
  when its persistent UUID already owns a record.

## Live Mesh UX invariants

- Keep `Mesh Device List` as a fixed section on the Home tab and keep
  `Mesh Topology` in the top-level Observability tab between Home and Admin.
- Keep backend and infrastructure SDK peers out of `Mesh Device List`; show
  peers without Draper TAK presence records only in the topology view.
- Show every peer reported by the SDK in the topology, even without a mapped
  transport edge. Give unidentified peers a visible, stable peer ID.
- Draw every SDK-reported connection, place its transport label at the midpoint
  of the visible line between node boundaries, and preserve enough spacing for
  the boxed label to remain readable.
- Keep the connection-status badge immediately beside the identity name on
  normal-width list rows. On very narrow rows it may move below the name to
  prevent clipping, but it must not be pushed to the far-right edge.
- Expanded rows must retain the last known status and GPS location for offline
  devices.
- Current Connection should appear before historical waypoint and device data.
- Keep the Not Connected indicator red.
- Ensure long values and expansion content do not overflow on mobile screens.
- Keep error messages selectable and copyable.

## Location permissions

- Keep Android manifest and iOS usage-description permissions aligned with the
  location feature.
- Request permission when the user selects Use current location.
- If permission is denied, allow the user to request it again.
- If permission is permanently denied, explain how to open application settings.
- Keep permission behavior cross-platform where the platform supports it, with
  platform-specific handling isolated behind services.

## Demo data controls

- Removing a Live Mesh item is a synchronized, reversible soft deletion using
  `isDeleted`; the same persistent device can rejoin by publishing again.
- The Admin reset action is the permanent database-clearing control and must
  require explicit confirmation.
- Do not reset device identity when resetting synchronized demo data.
- Cloudflare Worker controls remain clearly labeled placeholders until their
  headless Ditto agents are implemented.

## Repository safeguards

- Preserve unrelated working-tree changes. The repository may already contain
  user changes or unfinished work.
- Never commit credentials, playground tokens, generated secrets, `.env` files,
  or browser profiles.
- Avoid adding production dependencies unless they are necessary for the task.
- Keep credentials and deployment-specific values in environment variables or
  `--dart-define` configuration.
- Update `README.md` when setup, deployment, permissions, identity behavior, or
  user-facing workflows change.
- Prefer the simplest working cross-platform implementation suitable for the
  demo.
- Do not commit, push, delete data, reset the database, or install an application
  on a device unless the user's request authorizes that action.
- When a request does authorize committing, follow **Git workflow** above: branch
  with a `<type>/<slug>` name, never commit to `main`, and merge with a merge
  commit rather than a squash.

## Completion summary

Lead with the implemented outcome. Include:

- The user-visible behavior that changed.
- The resulting application version when it was bumped.
- Tests and builds that were run and their results.
- The debug APK path when an Android artifact was built.
- Any remaining limitation or material warning.
