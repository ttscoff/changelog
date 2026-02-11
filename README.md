# Changelog Generator

A Ruby script that automatically generates changelog entries from Git commit messages. It scans commits since the last tag (or a specified tag) and extracts changelog entries formatted with specific keywords.

## Overview

This tool is designed for git-flow workflows. It extracts changelog entries from commit messages that contain specific keywords (`NEW:`, `FIXED:`, `IMPROVED:`, etc.) and formats them into organized Markdown release notes.

## Installation

To use the `changelog` script from anywhere, symlink it to a directory in your `$PATH`:

```bash
# For Homebrew on Apple Silicon (M1/M2/M3 Macs)
ln -s "$(pwd)/changelog" /opt/homebrew/bin/changelog

# For Homebrew on Intel Macs or Linux
ln -s "$(pwd)/changelog" /usr/local/bin/changelog

# Or use any directory in your PATH
# Check your PATH: echo $PATH
# Then symlink to a directory you have write access to
ln -s "$(pwd)/changelog" ~/bin/changelog  # if ~/bin is in your PATH
```

After symlinking, you can run `changelog` from any directory instead of `./changelog`.

## Writing Compatible Git Commits

To have your commits included in the changelog, format your commit messages using one of these patterns:

### Format 1: Bullet Points with Keywords

```
Commit message summary

- NEW: New feature description
- FIXED: Bug fix description
- IMPROVED: Improvement description
- CHANGED: Change description
- REMOVED: Removed feature description
```

### Format 2: @-prefixed Keywords

```
Commit message summary
@new New feature description
@fixed Bug fix description
@improved Improvement description
@changed Change description
@removed Removed feature description
```

### Format 3: Single-Line Format

You can also use single-line commit messages formatted like:

```
NEW: New feature description
```

or

```
@new New feature description
```

### Supported Keywords

The script recognizes two families of keywords: its original markers and Conventional Commits style markers. Both are case-sensitive.

#### Original markers

These are the existing `NEW:` / `@new` style tags:

| Keyword | Variations | Output Section |
|---------|-----------|----------------|
| `NEW:` / `@new` | `NEW`, `ADD`, `ADDED` | **NEW** |
| `FIXED:` / `@fixed` | `FIX`, `FIXED` | **FIXED** |
| `IMPROVED:` / `@improved` | `IMP`, `IMPROVEMENT`, `IMPROVED`, `UPD`, `UPDATE`, `UPDATED` | **IMPROVED** |
| `CHANGED:` / `@changed` | `CHANGED`, `CHANGE` | **CHANGED** |
| `REMOVED:` / `@removed` | `DEPRECATED`, `DEP`, `REMOVED`, `REM` | **REMOVED** |

Use uppercase for the colon format (`NEW:`) and lowercase for the @ format (`@new`).

#### Conventional Commits markers

The script also understands Conventional Commits style prefixes and will map them into the appropriate sections. It matches lines like:

```
feat: add user authentication
fix: resolve login redirect issue
docs: update API reference
style: adjust button spacing
refactor: simplify controller logic
test: add coverage for edge cases
chore: bump dependencies
```

or the same with list markers or `@` prefixes:

```
- feat: add user authentication
* @fix: resolve login redirect issue
```

The mapping is:

| Conventional type | Output Section |
|-------------------|----------------|
| `feat`            | **NEW**        |
| `fix`             | **FIXED**      |
| `docs` / `doc`    | **DOCS**       |
| `test`            | **TEST**       |
| `style`           | **CHANGED**    |
| `refactor`        | **CHANGED**    |
| `chore`           | *(ignored or treated as non‑user‑facing)* |

If any of these types are followed by `!` (for example `feat!:` or `fix!:`), the entry is also added to the **BREAKING** section in addition to its normal section.

### Examples

**Example 1: Multi-line commit**
```
Add user authentication

- NEW: User login functionality
- NEW: Password reset feature
- IMPROVED: Session management
- FIXED: Token expiration bug
```

**Example 2: @-format commit**
```
Refactor API endpoints
@changed API response format
@breaking Removed deprecated endpoints
@improved Error handling
```

**Example 3: Single-line commit**
```
FIXED: Memory leak in image processing
```

## Version Detection

The script automatically detects the version number using the following methods (in order of priority):

1. **Forced version** (`--version` option)
2. **Ruby Gem** - Reads from `lib/**/version.rb` files (looks for `VERSION = "x.y.z"`)
3. **macOS Xcode projects** - Uses `agvtool` to read version from `Info.plist`
4. **Plain text files** - Reads from `VERSION`, `VERSION.txt`, or `VERSION.md`
5. **Git version command** - Uses `git ver` if available
6. **YAML config** - Reads from `config.yml` or `config.yaml` (expects `version` key)
7. **Rakefile** - Executes `rake ver` if available
8. **Makefile** - Executes `make version` or `make ver` if available
9. **Binary executables** - Checks `bin/` or `build/` directories for executables with `--version` flag
10. **Special project handling** - Custom logic for specific project paths (nvUltra, Marked, PopClip Extensions, etc.)

If no version can be detected, the script will exit with an error (unless `--no_version` is used).

## Usage

### Basic Usage

Generate changelog for commits since the last tag:

```bash
./changelog
```

### Options

- `--since-version VER` / `--sv VER` - Show changelog since tag matching VER (full or partial version)
- `--select` / `-s` - Interactively choose the "since" tag using fzf
- `--split` - Split output by version (requires `--select` or `--since-version`)
- `--order ORDER` - Order of split output: `asc` (oldest first) or `desc` (newest first, default)
- `--format FORMAT` - Output format: `markdown`, `keepachangelog`, `bunch`, or `def_list`
- `--only TYPES` - Only output specific change types (comma-separated: `new,fixed,improved,changed`)
- `--update [FILE]` / `-u [FILE]` - Update changelog file (auto-detects file if not specified)
- `--version=VER` / `-v VER` - Force version (skips version detection)
- `--no_version` / `-n` - Skip version check (prevents header output)
- `--copy` / `-c` - Copy results to clipboard
- `--file PATH` - Read additional commit messages from file (useful for commit-msg hooks)
- `--help` / `-h` - Display help message

### Examples

**Generate changelog since last tag:**
```bash
./changelog
```

**Generate changelog since a specific version:**
```bash
./changelog --since-version 1.0
```

**Update existing changelog file:**
```bash
./changelog --update CHANGELOG.md
```

**Generate changelog in Keep a Changelog format:**
```bash
./changelog --format keepachangelog
```

**Generate changelog split by version:**
```bash
./changelog --select --split
```

**Only show new features and fixes:**
```bash
./changelog --only new,fixed
```

**Copy changelog to clipboard:**
```bash
./changelog --copy
```

## Updating an Existing Changelog

The `--update` option automatically updates an existing changelog file. The script:

1. **Auto-detects the changelog format** by examining the file:
   - **Keep a Changelog** - Detects `## [version]` headers
   - **Markdown** - Detects `## version` or `### version` headers
   - **Bunch** - Detects `{% icon %}` Liquid tags
   - **Definition List** - Detects version numbers followed by `:`

2. **Detects version order** - Determines if versions are listed newest-first (desc) or oldest-first (asc) by comparing the first two versions

3. **Checks for existing version** - If the version already exists in the changelog, it replaces that section

4. **Inserts new entries** - Adds new changelog entries at the top (for desc order) or bottom (for asc order)

5. **Adds Keep a Changelog links** - For Keep a Changelog format, automatically adds or updates footer links

### Changelog File Detection

If you don't specify a file with `--update`, the script automatically searches for files matching `changelog*` (excluding executable files) in the current directory.

## Output Formats

### Markdown (default)
```markdown
### 1.2.3

2024-01-15 10:30

#### NEW

- New feature description

#### FIXED

- Bug fix description
```

### Keep a Changelog
```markdown
## [1.2.3] - 2024-01-15

### Added

- New feature description

### Fixed

- Bug fix description
```

### Bunch
```markdown
{% available 1.2.3 %}

---

1.2.3

: {% icon new %} New feature description
: {% icon fix %} Bug fix description

{% endavailable %}
```

### Definition List
```
1.2.3
: New feature description
: Bug fix description
```

## How It Works

1. **Finds the starting point**: By default, finds the last Git tag. Can be overridden with `--since-version` or `--select`.

2. **Gets commits**: Retrieves all commits since the starting point (or between tags if using `--split`).

3. **Parses commit messages**: Scans each commit message for lines matching the keyword patterns.

4. **Cleans entries**: Removes the keyword markers and capitalizes the first letter of each entry.

5. **Groups by type**: Organizes entries into categories (NEW, FIXED, IMPROVED, CHANGED, REMOVED).

6. **Formats output**: Generates formatted output based on the selected format.

## Tips

- **Use consistent formatting**: Stick to one format (either `- KEYWORD:` or `@keyword`) for consistency
- **Write descriptive entries**: The entry text should be clear and complete without the keyword
- **Tag your releases**: The script relies on Git tags to determine version ranges
- **Test your format**: Run `./changelog` before updating to see what will be generated
- **Use commit-msg hooks**: The `--file` option allows you to read from a file, useful for commit-msg hooks that validate commit message format

## Requirements

- Ruby (with standard libraries: `optparse`, `shellwords`, `yaml`)
- Git repository with tags
- (Optional) `fzf` for interactive tag selection
- (Optional) `pbcopy` for clipboard functionality (macOS)
- (Optional) `agvtool` for Xcode project version detection (macOS)

## Limitations

- Keywords are case-sensitive
- Only processes commits since the last tag (or specified tag)
- Merge commits are automatically excluded
- Non-ASCII characters in commit messages may be stripped or encoded
