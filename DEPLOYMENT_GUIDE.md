# Dark Realm - Deployment Guide

This guide outlines the exact steps to release updates to the game. It explains when to perform a **Base Game Update** (requires players to download a new installer) versus an **OTA Patch** (players auto-update invisibly).

---

## 1. When to use which method?

### Option A: Base Game Update (Full Export)
Use this method when:
*   You changed a **Singleton/Autoload** script (like `UpdateManager.gd`, `NetworkManager.gd`, `SaveSystem.gd`).
*   You updated the Godot Engine version.
*   You changed Project Settings (Input map, Display settings, etc.).
*   You added large new assets (3D models, music) that would make an OTA patch too large.
*   *Note: Players must re-download the new `.zip` or `.exe` manually.*

### Option B: OTA Patch (Lightweight `.pck`)
Use this method when:
*   You changed regular Scripts (UI, Combat, Player Controllers, World Logic).
*   You modified existing Scenes (`.tscn`).
*   You made minor balance tweaks to Data files.
*   *Note: Players will automatically download this 200KB patch when launching the game.*

---

## 2. Releasing an OTA Patch (The Fast Way)

1. **Bump Version:** Open `version.txt` and `patch_version.txt` and increment the version (e.g., from `1.0.2` to `1.0.3`).
2. **Build the Patch:** 
   * In Godot, you can run the `build_patch.gd` script, or run this in a terminal:
     `"path/to/Godot.exe" --headless -s build_patch.gd`
   * This will generate `build/patch_v1.0.3.pck`.
3. **Update GitHub Release:**
   * Go to your GitHub repository.
   * Create a new Release (e.g., `v1.0.3`).
   * Upload the `build/patch_v1.0.3.pck` file.
4. **Trigger the Update:**
   * Edit `version.json` in the root of your GitHub `main` branch.
   * Change `"version": "1.0.3"` and update the `"patch_url"` to point to the new `.pck` on GitHub.
   * *Done! The next time players launch, they get the update.*

---

## 3. Releasing a Base Game Update (The Full Way)

1. **Bump Version:** Open `version.txt` and `patch_version.txt` and set the new version (e.g., `1.0.3`).
2. **Export the Game:**
   * In Godot Editor, go to **Project -> Export**.
   * Select your Windows preset.
   * Click **Export Project** (make sure "Export With Debug" is OFF for production).
   * Save it as `Dark Realm.exe` inside your `build/` folder.
3. **Zip the Build:** Select `Dark Realm.exe` and `Dark Realm.pck` and compress them into `Dark_Realm_Setup.zip`.
4. **Update GitHub Release:**
   * Create a new Release on GitHub.
   * Upload the `Dark_Realm_Setup.zip`.
5. **Update Version Tracker:**
   * Edit `version.json` in the root of your GitHub `main` branch to match the new version.
   * Ensure players know they must download the new ZIP file manually.

---

> [!WARNING]
> If you test OTA updates locally, the game caches them in `%APPDATA%\Godot\app_userdata\Dark Realm\updates\`. If you are testing new full builds, **delete this folder first** to prevent old patches from overriding your new base game!
