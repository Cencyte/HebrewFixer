# AI HANDOFF DOCUMENT

**HebrewFixer Manuscripts Series:** Appendix B (handoff; not a volume)

You are picking up an ongoing project for user **FireSongz**. This document contains everything you need to continue the work.

---

## IMMEDIATE CONTEXT

Two projects were worked on in the previous session:

### 1. SSHFS Watchdog Service — COMPLETED ✅
A systemd service that auto-mounts a dual-boot laptop (Manjaro Linux / Windows 11) via SSHFS. It was broken (misdetecting Linux as Windows). It is now fixed and working perfectly.

### 2. HebrewFixer for Affinity Designer — AWAITING TESTING 🔄
A custom AutoHotkey v2 script that enables RTL (Right-to-Left) Hebrew typing in Affinity Designer. The script is written (v2.0) and deployed to the Windows laptop desktop. **User has not yet tested it.**

---

## FILES YOU NEED TO KNOW ABOUT

### HebrewFixer Project
| Path | Description |
|------|-------------|
| `/home/firesongz/Source/HebrewFixer/` | Git repository for the project |
| `/home/firesongz/Source/HebrewFixer/HebrewFixer.ahk` | The v2.0 script (on `cencyte_experimental` branch) |
| `/mnt/Laptop/Desktop/HebrewFixer.ahk` | Copy deployed to Windows laptop for testing |
| `/home/firesongz/Desktop/AHK_V2_Reference.md` | Comprehensive AHK v2 documentation (scraped via Firecrawl) |

### SSHFS Watchdog (for reference, already working)
| Path | Description |
|------|-------------|
| `/usr/local/bin/laptop-sshfs-watchdog` | The watchdog script (v6 final) |
| `/var/log/laptop-sshfs-watchdog.log` | Service logs |
| `/root/.ssh/config` | SSH config mapping hostnames to IP |

### Session Documentation
| Path | Description |
|------|-------------|
| `/home/firesongz/Desktop/HANDOFF_Complete_Session_20260205.md` | Detailed technical handoff from previous session |
| `/home/firesongz/Desktop/AHK_V2_Reference.md` | AHK v2 language reference |

---

## PROJECT BACKGROUND

### HebrewFixer
FireSongz met an elderly woman at the local library who needs to type Hebrew in Affinity Designer. The program doesn't support RTL text natively—Hebrew letters appear backwards. A commercial solution (RTL Fixer) costs $8. FireSongz volunteered to build a free solution.

**How HebrewFixer works:**
- Toggle with `Ctrl+Alt+H`
- Uses AHK v2 `InputHook` to intercept Hebrew keystrokes
- Maintains a buffer of typed characters
- Sends text reversed so it displays correctly (RTL)
- Also intercepts `Ctrl+V` to reverse Hebrew in clipboard before pasting

**Git repository:**
- `master` branch = v1.0 (original, 214 lines)
- `cencyte_experimental` branch = v2.0 (improved, 524 lines) ← current
- Config: email=antiultra2007@gmail.com, name=Cencyte

---

## RECENT EVENTS (What Just Happened)

1. **HebrewFixer v2.0 was created** with major improvements:
   - Smart paste (only reverses Hebrew segments, not English/numbers)
   - Proper punctuation handling
   - Backspace with display rebuild
   - Debug menu in tray
   - Better window detection

2. **AHK v2 Reference was built** by scraping official docs via Firecrawl MCP server with rate-limit-aware pacing.

3. **MCP server research was conducted** to find tools for autonomous GUI testing. Smooth Operator was tried but **does not work** on user's PC.

4. **User has NOT YET TESTED** the HebrewFixer script. This is the immediate next step.

---

## NEXT STEPS

1. **Fix remaining HebrewFixer issues** (see below)
2. **Set up more MCP servers** — user wants to try: computer-use-mcp, Windows CLI, Desktop Commander
3. **Create PDF user guide** for the elderly woman
4. **Package and deliver** the final solution

---

## HEBREWFIXER TESTING RESULTS (Latest)

### What Works ✅
- **Accordion effect FIXED** - O(1) insertion using `{Home}` + single char
- **Physical key mapping** - Maps physical keys (a,b,c) to Hebrew chars
- **Basic RTL flow** - Characters appear left-to-right (RTL reading order)
- **Backspace** - Works correctly

### What Still Needs Fixing ❌

1. **IME Detection Missing (CRITICAL)**
   - Hebrew chars type even when Windows input method is ENGLISH
   - Need to detect IME state via Windows API (`GetKeyboardLayout()` or similar)
   - Only do key replacement when: IME is Hebrew AND toggle is ON

2. **First Character Cursor Bug**
   - First character advances cursor by one position incorrectly
   - After first char, cursor stays put (correct)
   - Fix: First char should NOT move cursor

3. **Delete Key Behavior Wrong**
   - Current: Delete does something weird
   - Expected: Delete should act like normal backspace (delete leftmost/newest char)
   - Backspace seems correct already

4. **Arrow Keys Not Reversed**
   - Left arrow should move right (toward older chars)
   - Right arrow should move left (toward newer chars)
   - Need to swap Left/Right when in RTL mode

### Current Branch
`cencyte_perkey_intercept` on `/home/firesongz/Source/HebrewFixer/`

### Current File
`HebrewFixer_PerKey.ahk` - deployed to `/mnt/Laptop/Desktop/`

---

## TECHNICAL NOTES

### Hebrew Unicode Range
`0x0590` to `0x05FF` (Hebrew block)
`0x05D0` to `0x05EA` (Hebrew letters: Aleph to Tav)

### SSH Configuration
Both laptop hostnames resolve to the same IP via `/root/.ssh/config`:
- `firesongzpc3` → 192.168.68.116 (Linux)
- `firesongzpc3-win` → 192.168.68.116 (Windows)

### Windows Laptop Access
The laptop is mounted via SSHFS at `/mnt/Laptop` when online. The watchdog service handles this automatically.

---

## USER NOTES

FireSongz is technically proficient. They:
- Understand SSH, systemd, Git, AHK
- Will firmly redirect you if you're going down the wrong path
- Value "uncompromise" — finding proper solutions, not workarounds
- Are building this to help a community member (elderly woman from library)

---

*End of Handoff*
