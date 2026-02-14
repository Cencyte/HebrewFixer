# HebrewFixer

**RTL Hebrew typing support for applications that lack native BiDi text handling.**

![Windows](https://img.shields.io/badge/Windows-10%2F11-blue)
![AutoHotkey](https://img.shields.io/badge/AutoHotkey-v2-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

---

## The Problem

Some design applications—most notably **Affinity Designer**, **Affinity Publisher**, and **Affinity Photo**—don't properly support right-to-left (RTL) languages like Hebrew. When you type Hebrew text:

- Characters appear **left-to-right** instead of right-to-left
- Cursor movement is backwards
- Backspace and Delete behave incorrectly
- Mixed Hebrew/English text becomes jumbled

This makes Hebrew typography work frustrating or impossible in these otherwise excellent applications.

## The Solution

**HebrewFixer** is a lightweight Windows utility that intercepts your Hebrew keyboard input and handles RTL text entry correctly. It:

- ✅ **Types Hebrew right-to-left** using cursor-relative insertion
- ✅ **Fixes Backspace/Delete** behavior for RTL context
- ✅ **Reverses arrow key direction** when in Hebrew mode
- ✅ **Handles mixed Hebrew/English paste** with proper BiDi reordering
- ✅ **Auto-detects Hebrew keyboard** using Windows IME state
- ✅ **Shows tray icon status** so you always know when it's active

---

## Installation

### Option 1: Installer (Recommended)

1. Download `HebrewFixer_Setup.exe` from the [Releases](https://github.com/Cencyte/HebrewFixer/releases) page
2. Run the installer
3. Choose your options:
   - **Start with Windows** – launches automatically at login
   - **Start Menu entry** – adds HebrewFixer to your Start Menu
   - **Desktop shortcut** – creates a desktop icon
4. Click Install

The installer places HebrewFixer in `%LOCALAPPDATA%\HebrewFixer` (no admin rights required).

### Option 2: Portable

1. Download `HebrewFixer.exe` from [Releases](https://github.com/Cencyte/HebrewFixer/releases)
2. Place it anywhere you like
3. Run it directly

---

## Usage

1. **Launch HebrewFixer** – a tray icon (ש) appears in your system tray
2. **Open your design application** (Affinity Designer, etc.)
3. **Switch to Hebrew keyboard** in Windows (Win+Space or language bar)
4. **Start typing** – HebrewFixer automatically handles RTL insertion

### Tray Icon States

| Icon | Meaning |
|------|---------|
| ש (black on white) | **Active** – Hebrew mode enabled, RTL typing active |
| ש (gray/dimmed) | **Inactive** – English mode or HebrewFixer paused |

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+Alt+H` | Toggle HebrewFixer on/off |
| `Ctrl+V` | Smart paste (BiDi-aware) |

### Right-Click Tray Menu

- **Enable/Disable** – Toggle Hebrew fixing
- **Auto Mode** – Automatically activate when Hebrew keyboard is detected
- **Exit** – Close HebrewFixer

---

## How It Works

HebrewFixer uses a clever cursor-relative insertion technique:

1. When you press a Hebrew key, it sends **Shift+End** to select text to the right
2. Cuts the selection, inserts your character, then pastes back
3. This effectively inserts characters **to the left** of the cursor (RTL behavior)

For paste operations, it analyzes clipboard content and reorders BiDi text segments appropriately.

---

## Compatibility

### Tested Applications
- ✅ Affinity Designer 1.x / 2.x
- ✅ Affinity Publisher 1.x / 2.x
- ✅ Affinity Photo 1.x / 2.x
- ✅ Other applications lacking native RTL support

### System Requirements
- Windows 10 or Windows 11
- Hebrew keyboard layout installed in Windows

---

## Building from Source

HebrewFixer is written in [AutoHotkey v2](https://www.autohotkey.com/).

### Prerequisites
- AutoHotkey v2.0+
- Ahk2Exe compiler (included with AutoHotkey)

### Compile
```powershell
# From the project root
& "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe" `
    /in "src\Current Version\HebrewFixer_BiDiPaste.ahk" `
    /out "bin\HebrewFixer.exe" `
    /icon "Icon\ICOs\hebrew_fixer_affinity_on.ico" `
    /base "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
```

### Build Installer
Requires [Inno Setup 6](https://jrsoftware.org/isinfo.php):
```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" "Installer\HebrewFixer_Setup.iss"
```

---

## Project Structure

```
HebrewFixer/
├── Icon/
│   ├── ICOs/               # Icon files (.ico)
│   └── Images/             # Source images (.png, .svg)
├── Installer/
│   ├── BuildHebrewFixerExe.ps1
│   ├── HebrewFixer_Setup.iss
│   └── *.ps1               # Installer helper scripts
├── Tests/
│   └── Win11/
│       └── PromoteTrayIconInvisible.ps1  # Input for installer build
├── native/
│   └── HookTray/            # Optional native experiments
├── src/
│   ├── Current Version/
│   │   └── HebrewFixer_BiDiPaste.ahk
│   └── Previous Versions/   # Archived AHK variants
├── .gitignore
└── README.md
```

---

## FAQ

**Q: Does this work with Adobe InDesign?**  
A: InDesign has native RTL/Hebrew support (especially the Middle East edition). You probably don't need HebrewFixer for InDesign.

**Q: Can I use this for Arabic?**  
A: The current version is optimized for Hebrew. Arabic support would require additional character mappings.

**Q: Why does the icon look like Affinity Designer?**  
A: HebrewFixer was originally created to solve Hebrew typing in Affinity apps, so the icon uses Affinity's color scheme. It works with any application.

**Q: Is this free?**  
A: Yes, HebrewFixer is free and open source under the MIT license.

---

## Contributing

Contributions are welcome! Feel free to:
- Report bugs via [Issues](https://github.com/Cencyte/HebrewFixer/issues)
- Submit pull requests for improvements
- Suggest support for additional RTL languages

---

## License

MIT License – see [LICENSE](LICENSE) for details.

---

## Acknowledgments

- Built with [AutoHotkey v2](https://www.autohotkey.com/)
- Icons designed with [Affinity Designer](https://affinity.serif.com/designer/)
