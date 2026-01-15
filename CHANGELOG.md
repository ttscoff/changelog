# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.5] - 2026-01-15

### Changed

- When git version matches changelog version, merge new changes with existing entry instead of raising an error
- Version detection now ignores date when checking for existing entries in keepachangelog format
- Date is automatically updated to current date when updating existing changelog entries
- Better handling of empty changelog entries when merging changes
- Prevent duplicate version entries when updating existing changelog entries
- Remove duplicate keepachangelog link definitions and ensure they're sorted correctly
- Ensure keepachangelog links are always placed at the bottom of the file in correct version order
- Respect document order (ascending/descending) when inserting new changelog entries

## [1.0.4] - 2026-01-14

## [1.0.2] - 2026-01-14

### Fixed

- Gsub on nil in update_changelog

## [1.0.0] - 2026-01-14

### New
- Added VERSION file for version tracking

### Changed
- Improved changelog script to better detect version from VERSION file and Rust projects

### Improved
- Enhanced header logic for changelog output

Other changes:
- Updated logic for version detection and changelog formatting

[1.0.5]: https://github.com/ttscoff/changelog/releases/tag/v1.0.5
[1.0.4]: https://github.com/ttscoff/changelog/releases/tag/v1.0.4
[1.0.2]: https://github.com/ttscoff/changelog/releases/tag/v1.0.2
[1.0.0]: https://github.com/ttscoff/changelog/releases/tag/v1.0.0
