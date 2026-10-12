# Install and remove Docua

These instructions install Docua for your LibreOffice user account on macOS Apple Silicon.
Docua requires LibreOffice with its bundled Python runtime.
Use test documents for your first installation because this version is experimental.

## Back up LibreOffice settings

The LibreOffice user profile stores preferences, extensions, dictionaries, and other personal settings.
Your document files live separately.

1. Save your open documents.
2. Quit LibreOffice.
3. In Finder, choose **Go > Go to Folder**.
4. Enter `~/Library/Application Support/LibreOffice`.
5. Copy the `4` folder to a separate backup location.

Keep this backup until you finish testing Docua.

## Install the extension

The OXT is LibreOffice's extension installation package. Install the package without extracting it.

1. Open `/Applications/LibreOffice.app`.
2. Choose **Tools > Extensions**.
3. Click **Add**.
4. Select `~/Developer/docua/dist/docua-0.1.0-macos-arm64.oxt`.
5. Complete the extension installation dialog.
6. Quit LibreOffice.
7. Open LibreOffice again.
8. Create a Writer document.

The document displays Docua's pale top bar, ribbon tabs, and right sidebar controls.
The extension list displays **Docua**, version **0.1.0**.
Older LibreOffice releases label the extension dialog **Extension Manager**.

Install Docua for your account when LibreOffice offers an installation scope choice.
Do not install the earlier experimental extension alongside Docua.
Remove **Custom LibreOffice interface · experimental** before installing Docua.

## Change Docua settings

Click the gear button or press **Command+,** to open Docua settings.
Changes apply immediately to open Docua document windows.

Appearance options include colour, interface font, icon weight, and native title-bar visibility.
Ribbon options include row density, control scale, separators, button corners, tab styling, style previews, and search width.
Editing options include focus return, tab persistence, quick-access placement, and status information.
Document zoom changes the document view. Control scale changes Docua's controls.

## Update LibreOffice

Save your work and quit LibreOffice before updating the application.
Install the new LibreOffice version using its normal installer.
Keep your existing user profile to retain extensions and settings.

The earlier interface package survived a 25.8.7.3 to 26.8.1.1 upgrade without extension reinstallation.
That result does not guarantee compatibility with every future release.
Docua checks native attachment capabilities before hiding the standard interface.

If an update prevents Docua from attaching, disable Docua through **Tools > Extensions**.
Restart LibreOffice to use its standard interface.

## Update Docua

Save your work before updating Docua.
Add the new Docua OXT through **Tools > Extensions**.
Accept LibreOffice's replacement prompt when the package uses the same extension identifier.
Restart LibreOffice after installation.

Docua's extension identifier is `org.docua.extension`.
Keep this identifier for future Docua releases.

## Remove Docua

The immediate restore command affects the current document window.
The extension removal command affects future document windows.

1. Open Docua settings.
2. Select **Compatibility**.
3. Click **Use native LibreOffice interface**.
4. Save your documents.
5. Close the document windows.
6. Choose **Tools > Extensions**.
7. Select **Docua**.
8. Click **Remove**.
9. Restart LibreOffice.

Docua restores the original layout and appearance during normal document closure.
It also restores the original Calc sheet-tab setting before saving a workbook.

## Recover appearance after a crash

Docua records the original application appearance in `user/docua-backup.json` inside the LibreOffice user profile.
The recovery script changes only this recorded appearance setting.
It does not restore documents or reset the entire profile.

Quit every LibreOffice application before running the recovery script.
To preview recovery from the Docua project root, run:

```sh
python3 scripts/recover.py --profile "$HOME/Library/Application Support/LibreOffice/4"
```

To apply recovery, run:

```sh
python3 scripts/recover.py --profile "$HOME/Library/Application Support/LibreOffice/4" --apply
```

The script backs up the profile XML and appearance journal before writing.
It refuses recovery while a LibreOffice process runs.
