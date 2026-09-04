# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and follows [Semantic Versioning](https://semver.org/).

## [0.1.3+bird3.3.2] - 2026-09-04

### Added ✨

- Build BIRD 3.3.2

## [0.1.2+bird2.19.2] - 2026-08-27

### Changed 🔧

- Build BIRD unmodified, drop the local patch

### Documentation 📚

- State the GPL obligation the image actually carries

### Miscellaneous 🧹

- Move markdownlint config to the cli2 file

## [0.1.1+bird2.19.2] - 2026-08-26

### CI/CD ⚙️

- Build each arch on a runner of its own architecture

### Documentation 📚

- State the facts, drop how they were found
- Inline what the linked issue said

### Miscellaneous 🧹

- Add the standard markdownlint ignore list

## [0.1.0+bird2.19.2] - 2026-08-07

### Added ✨

- Static bird/birdc build for router's sidecar container
- Encode the packaged BIRD version in the release tag

### Fixed 🐛

- Clone from the CZ-NIC/bird GitHub mirror, not gitlab.nic.cz directly
