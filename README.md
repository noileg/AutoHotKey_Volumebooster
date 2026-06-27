# AutoHotkey_Volumebooster

This program controls the Windows sound-mixer's property to boost the volume. It'll store the volume settings and automatically apply the change to the Windows sound-mixer.

## Files
* **`VolumeBoost.ahk`**: The background script (AutoHotkey v2).
* **`VolumeBoostSettings.hta`**: The GUI settings panel(JP).
* **`VolumeBoostSettings-EN.hta`**: The GUI settings panel(EN).

## How to Use
1. Download `VolumeBoost.ahk` and `VolumeBoostSettings.hta` into the same folder.
2. Run `VolumeBoost.ahk`first to make setting file.
3. Open `VolumeBoostSettings.hta` to add target apps (e.g., `Microsoft.Media.Player.exe`), set a boost factor, and configure a hotkey.
4. Press your setted hotkey to toggle the volume boost on/off.

## Windows Startup
To run the script automatically when Windows starts:
1. Right-click `VolumeBoost.ahk` and select **"Create shortcut"**.
2. Press `Win + R`, type `shell:startup`, and hit Enter.
3. Move the shortcut file into that folder.

## Antivirus Flag
If your antivirus blocks the script, please restore the file from quarantine and add it to the exclusion list. It is a false positive caused by low-level Windows API calls.
