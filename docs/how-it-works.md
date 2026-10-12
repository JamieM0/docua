# How Docua works

This explanation assumes no LibreOffice knowledge.
It describes which application owns your documents and how Docua changes the controls around them.

## LibreOffice and its editors

LibreOffice is a collection of applications for office documents.
Writer handles text documents, Calc handles spreadsheets, Impress handles presentations, and Draw handles drawings.
Math handles formulas, and Base handles databases. Docua currently targets Writer, Calc, Impress, and Draw.

LibreOffice contains several parts that work together.
The document engine stores text, formulas, styles, drawings, and other content.
The document canvas displays that content and handles editing.
The interface provides menus, toolbars, panels, and buttons that tell the engine what to do.

When you click LibreOffice's Bold button, the interface sends a formatting command to the engine.
The engine changes the selected text, and the canvas displays the result.
The interface does not perform the text layout or save the document itself.

## The parts Docua replaces

Docua replaces the document ribbon, application menus, right sidebar controls, and status bar.
For Calc, it also supplies the formula bar and sheet controls.
Docua supplies its own settings panel for interface and interaction preferences.

LibreOffice keeps the document canvas, document engine, import and export filters, Undo history, and file-saving logic.
Typing, selecting text, dragging objects, and editing cells still operate inside LibreOffice.
Some commands open LibreOffice's original dialogs. Context menus and Draw layer tabs remain native.
The start centre also remains native.

Docua does not turn LibreOffice into Microsoft Word or change its document compatibility rules.
A Word file still opens through LibreOffice's Word import filter.
An Excel file still saves through LibreOffice's Excel export filter.
Existing LibreOffice limitations for those formats still apply.

## The extension package

An extension adds functionality to an existing application.
LibreOffice installs extensions from files ending in `.oxt`.
An OXT is a ZIP archive with registration metadata, configuration, code, and resources.

LibreOffice reads Docua's metadata and registers its Python adapter.
Docua's configuration asks LibreOffice to run the adapter when a document opens or a new document appears.
The adapter checks the editor, platform, and native window capabilities before attaching the interface.

LibreOffice stores the installed extension inside your user profile.
Docua does not replace files in `LibreOffice.app`.
You can remove Docua through LibreOffice's extension dialog.

## How the interface attaches

Docua's Python adapter asks LibreOffice for the document's window and layout manager.
The layout manager controls the space around the document canvas.
Docua reserves space for its controls and hides the standard controls temporarily.
The document canvas continues to occupy the remaining space.

A small native macOS library creates views inside the existing LibreOffice window.
Those views use Apple's WebKit component to display local HTML, CSS, and JavaScript.
These are interface files bundled with Docua. They do not load an online editor.

HTML describes the controls, CSS defines their appearance, and JavaScript handles interface interactions.
The native library also creates macOS application menus and connects accessibility information.
The resulting window contains Docua controls around a real LibreOffice document canvas.

## What happens when you click a control

Consider the Bold control in a Writer document.
Docua's JavaScript sends a message to the native macOS library.
The library passes the command to the Python adapter.
The adapter sends LibreOffice's own Bold command to the active document.

LibreOffice changes the selected text and updates its Undo history.
Docua reads the current formatting state and updates the Bold control.
The same command path connects many other ribbon controls.
Special adapter commands handle tasks such as sheet selection and document navigation.

LibreOffice exposes this connection through UNO, its application programming interface.
UNO allows extensions to work with documents, commands, windows, settings, and events.
Docua uses public UNO interfaces for document operations and layout reservation.

## Document and preference storage

LibreOffice saves your documents through its existing file-saving code.
Docua does not create a separate document database or convert files into its own format.
Interface preferences do not change the font in your documents.

Docua stores interface preferences under the `DocuaInterface` key in macOS application defaults.
It stores an appearance recovery journal in the LibreOffice user profile.
For Calc saves, Docua restores the original native sheet-tab setting before LibreOffice writes the workbook.
This prevents the hidden native controls from changing the saved workbook's tab visibility.

## Updates and compatibility

Replacing the LibreOffice application normally preserves the user profile and its installed extensions.
That separation allows Docua to survive application updates without modifying the new application bundle.
The earlier interface package passed an actual 25.8 to 26.8 upgrade with the same extension registration.

The private macOS accessibility integration remains the most fragile connection.
It inspects a LibreOffice native view detail after checking that the required capability exists.
LibreOffice could change that detail in a future release.
Capability checks preserve the standard interface when the bridge cannot attach.
They cannot guarantee compatibility with every future application change.

Docua therefore needs release testing against supported LibreOffice versions.
A normal extension package improves update compatibility, but it does not eliminate that testing requirement.
