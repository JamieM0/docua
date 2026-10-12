# Release Docua

This procedure prepares an experimental open-source Docua release.
It does not publish a repository or upload assets automatically.

## Review the release scope

Docua currently supports macOS Apple Silicon only.
Publish version 0.1.0 as an experimental preview.
State the supported LibreOffice versions and remaining native interface surfaces in the release description.
Do not promise compatibility with untested future releases.

The source uses MPL 2.0. Keep the licence and asset notices with source and binary distributions.
The public source repository is [JamieM0/docua](https://github.com/JamieM0/docua).

## Build and inspect the package

Install Apple's Command Line Tools and Python 3 before building on macOS.
From the Docua project root, run:

```sh
python3 scripts/build.py
python3 scripts/check_package.py dist/docua-0.1.0-macos-arm64.oxt
```

The build creates `dist/docua-0.1.0-macos-arm64.oxt` and its checksum file.
The package validator checks registration, source inclusion, resource hashes, and prohibited bundled fonts.
It does not replace live application testing.

## Test a release

Use a separate LibreOffice profile and copies of documents for release testing.

- Install through LibreOffice's extension dialog on each supported version.
- Test Writer formatting, styles, clipboard commands, Undo, search, and document saving.
- Test Calc formulas, sheet controls, XLSX saving, and saved sheet-tab visibility.
- Test Impress and Draw editing, native dialogs, and document export.
- Test keyboard access, accessibility labels, focus return, and multiple document windows.
- Test light and dark appearance, control scales, ribbon densities, and narrow windows.
- Test disabling, removing, crash recovery, and upgrading LibreOffice with the extension already installed.

Historical verification records describe the earlier interface package.
Record the actual Docua package checksum and application versions for each release check.

## Publish source and assets

Upload the project source to your chosen public repository.
Keep generated build directories and local user profiles out of version control.
The `.gitignore` excludes `dist`, `.build`, Python caches, and macOS Finder metadata.

Attach the OXT and checksum file to the release.
Include the installation instructions and experimental support scope.
The OXT includes rebuildable source for its native library.

The current native library has an ad-hoc signature.
Test distribution on a clean Mac and document its installation behavior.
Prepare distribution signing and notarization before describing the release as ready for general use.

## Version updates

Change the version in `extension/description.xml` for a new release.
Keep the identifier `org.docua.extension` so LibreOffice recognizes replacement packages.
Update package filenames in user documentation and repeat release checks.
