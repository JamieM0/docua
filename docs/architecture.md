# Architecture reference

Docua hosts custom controls inside existing LibreOffice document windows.
The document model and canvas remain under LibreOffice control.

## Registration

`extension/description.xml` declares identifier `org.docua.extension`, version `0.1.0`, and platform `macosx_aarch64`.
`META-INF/manifest.xml` registers the Python component and configuration data.
`Jobs.xcu` connects `org.docua.StartupJob` to the `OnNew` and `OnLoad` document events.

`StartupJob` ignores unsupported platforms and documents without an active controller.
The adapter prevents duplicate hosts for the same frame.

## Layout and command adapter

`extension/adapter.py` implements document listeners, command status listeners, and a docking-area wrapper.
The wrapper reserves space through `XDockingAreaAcceptor`.
The adapter obtains the native view through `XSystemDependentWindowPeer.getWindowHandle`.

The adapter sends standard commands through LibreOffice's dispatch interfaces.
It reads document selection, styles, formatting, and editor-specific properties through UNO.
Custom adapter commands validate values before changing document properties.

## Native bridge

`native/bridge.mm` compiles into an ARM64 Cocoa and WebKit dynamic library.
The existing internal library filename is `lo365-web-ribbon.dylib`.
Docua loads this library from its own installed resources.

The bridge creates local WKWebView controls, native menus, and document-window navigation.
It restricts navigation to the extension resource directory.
The packaged HTML disables network connections through its Content Security Policy.
Docua contains no telemetry or remote editor service.

The accessibility bridge inspects the private `mpChildWrapper` view member after capability checks.
This integration is specific to LibreOffice's macOS implementation.
Public UNO interfaces do not provide the complete accessibility attachment used here.

## Restoration and saving

The adapter records the original layout visibility, docking-area acceptor, sidebar visibility, and application appearance.
Calc also records the original `HasSheetTabs` property.
Normal closure restores these values and removes document listeners.

Before Calc save events, the adapter restores `HasSheetTabs` to its original value.
After save completion or failure, it hides native tabs again while the custom controls remain active.
The adapter preserves the document's modified state when changing this display property.

## Packaging

`scripts/build.py` compiles and signs the native library, copies extension resources, and writes the OXT.
It uses fixed archive timestamps and sorted files to support reproducible builds with the same toolchain.
Apple toolchain or SDK changes can change the compiled binary and package checksum.

The OXT includes `source/build.py`, `source/bridge.mm`, the adapter, frontend source, recovery script, and documentation.
Extracting the OXT and running `python3 source/build.py` rebuilds an installation package.
Building Docua requires no LibreOffice checkout or source modification.
