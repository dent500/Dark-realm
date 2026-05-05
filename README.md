# Dark Realm — Project Manifest & Dev Guide

## 🕵️ Analysis: Project Audit (2D vs 3D)
The current workspace is a high-fidelity **3D RPG**. I have identified several files currently "cluttering" the root that likely belong to your 2D project or should be reorganized into the 3D asset pipeline.

### The "Muddle" (Identified Issues)
- **Root Bloat**: 40+ `.fbx` and `.png` files are sitting in the root directory.
- **2D Residue**: Numbered sequences like `idle_0.png` through `idle_2.png` (nearly 15MB total) are likely baked frames from a different 2D project.
- **Asset Placement**: 3D animations are currently separate from the models they control.

---

## 📁 Standardized Project Structure (3D RPG)

### 🎬 Scenes & World
- `scenes/main_menu.tscn`: The 3D Hall of Heroes introduction.
- `scenes/world.tscn`: The main exploration and combat zone.
- `scenes/player.tscn`: The modular player character (3D).

### ⚙️ Core Systems (`scripts/`)
- `autoloads/GameManager.gd`: Controls scene flow and game state.
- `autoloads/PlayerData.gd`: The central database for your hero's progress.
- `autoloads/AIDungeonMaster.gd`: Narrates your journey using OpenAI/Gemini.
- `utils/CharacterBuilder.gd`: Dynamically assembles weapons and gear onto 3D models.

### 🎨 Assets Pipeline
- `assets/equipment/`: 3D models for swords, axes, and shields.
- `assets/appearance/`: Materials and textures for skin, hair, and armor.
- `assets/ui/`: Game logo, icons, and HUD elements.

---

## 🛠️ Proposed Cleanup Plan
*Note: I will not run these moving commands until you confirm you are ready.*

| File Type | Current Location | Proposed Move | Project |
| :--- | :--- | :--- | :--- |
| **FBX Animations** | `/ (Root)` | `assets/animations/player/` | 3D Project |
| **2D Frame Sequences** | `/ (Root)` | `legacy/2d_game_assets/` | 2D Project |
| **JSON Data** | `/ (Root)` | `scripts/data/raw/` | 3D Project |

---

## 🚀 Dev Workflow
1. **Engine**: Use **Godot 4.3+** with **Forward+** rendering.
2. **Narration**: Ensure an API key is set in `user://api_config.json` for the AI DM to function.
3. **Execution**: Press **F5** to launch. All menu systems and pedestals are automatically built via script at runtime.

---

## 📜 Next Steps
Would you like me to move the loose root files into this structure to keep your **3D RPG** workspace clean and separate from the 2D assets?
