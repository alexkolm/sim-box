# Changelog

## v1.2.0 — Monthly SIM keep-alive

### Added
- Monthly keep-alive SMS service
- systemd service + timer for SIM activity
- Configurable target number and message text via simbox.conf

### Improved
- SMS daemon resilience to modem/SIM disappearance
- Unified configuration and secrets handling

## v1.1.0 — 2025-12-20

### Improvements
- SMS daemon (`simbox-smsd`) made resilient to:
  - modem disappearance
  - SIM not ready state
  - read errors from TTY device
- Added controlled startup delay until SIM becomes READY
- Eliminated busy-loops, improved long-term stability

### Internal
- Unified configuration via simbox.conf + secrets.env
- Code structure cleanup and safety improvements

## [1.0.0] — 2025-12-20

### Added
- Unified configuration file `simbox.conf`
- Unified secrets file `secrets.env` (excluded from repository)
- `secrets.env.example` template for safe setup
- Persistent SIM state tracking via `sim.state`
- Robust SIM initialization with retries and SIM-busy handling
- Daily heartbeat with system, modem, SIM and signal diagnostics
- Automatic modem initialization on boot (systemd)
- SMS receiving daemon with RAW SMS forwarding
- Full systemd integration (services + timers)

### Changed
- Removed legacy `telegram.env` and `modem.env`
- All scripts now load configuration from `simbox.conf`
- All secrets are loaded from `secrets.env`
- Improved logging and fault tolerance
- Project structure cleaned and standardized

### Security
- No secrets stored in repository
- `.gitignore` protects all sensitive files

### Status
- Fully functional on real hardware
- Tested with ZTE MF112 USB modem
