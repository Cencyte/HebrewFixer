# AutoHotkey v2 Complete Reference

**Purpose:** Comprehensive reference for AHK v2 syntax, functions, and patterns.  
**Generated:** 2026-02-05  
**Source:** https://www.autohotkey.com/docs/v2/  
**Scraped via:** Firecrawl MCP Server

---

## Table of Contents

1. [Concepts & Fundamentals](#concepts--fundamentals)
2. [Variables & Expressions](#variables--expressions)
3. [Functions](#functions)
4. [Objects & Classes](#objects--classes)
5. [Hotkeys](#hotkeys)
6. [#HotIf Directive](#hotif-directive)
7. [InputHook](#inputhook)
8. [Send & Keyboard](#send--keyboard)
9. [Clipboard](#clipboard)
10. [Quick Reference Index](#quick-reference-index)

---

## Concepts & Fundamentals

### Values
Every value is one of the following types:
- **String** - text (a sequence of characters)
- **Integer** - 64-bit signed integer
- **Float** - 64-bit double-precision floating-point number

Related concepts: **Objects** are the fourth "type" but are more complex.

### Strings
- Text is enclosed in quote marks (single or double): `"hello"` or `'hello'`
- Escape sequences use backtick: `` `n `` (newline), `` `r `` (carriage return), `` `t `` (tab)
- Concatenation uses dot operator: `"Hello" . " " . "World"`
- Raw strings use `{Raw}` or backtick-r

### Numbers
- Integers can be decimal or hex: `123`, `0x7B`
- Floats: `3.14`, `1.5e10`
- Scientific notation supported

### Objects
Objects are either:
1. **References** to data (most objects)
2. **Primitive values** wrapped as objects (numbers, strings)

### Boolean
- **True** = non-zero numbers, non-empty strings
- **False** = `0`, `""` (empty string), unset variables

### Variables
- Variables are **untyped** - can hold any value
- Names: start with letter/underscore, contain letters/numbers/underscores
- Case-insensitive: `MyVar` = `myvar` = `MYVAR`
- **Global** variables visible everywhere
- **Local** variables visible only in function

### Nothing vs Empty
- **Unset** = variable has no value assigned
- **Empty string** `""` = variable has a value (empty text)

---

## Variables & Expressions

### Assignment Operators
```ahk
x := 5          ; Assign
x += 1          ; Add and assign
x -= 1          ; Subtract and assign
x *= 2          ; Multiply and assign
x /= 2          ; Divide and assign
x //= 2         ; Integer divide and assign
x .= "text"     ; Concatenate and assign
```

### Comparison Operators
```ahk
x = y           ; Equal (case-insensitive for strings)
x == y          ; Equal (case-sensitive)
x != y          ; Not equal
x !== y         ; Not equal (case-sensitive)
x < y           ; Less than
x > y           ; Greater than
x <= y          ; Less than or equal
x >= y          ; Greater than or equal
```

### Logical Operators
```ahk
x and y         ; Logical AND
x or y          ; Logical OR
not x           ; Logical NOT
x && y          ; Short-circuit AND
x || y          ; Short-circuit OR
!x              ; NOT (unary)
```

### Math Operators
```ahk
x + y           ; Addition
x - y           ; Subtraction
x * y           ; Multiplication
x / y           ; Division
x // y          ; Integer division (floor)
Mod(x, y)       ; Modulo
x ** y          ; Power/exponent
```

### Bitwise Operators
```ahk
x & y           ; Bitwise AND
x | y           ; Bitwise OR
x ^ y           ; Bitwise XOR
~x              ; Bitwise NOT
x << n          ; Left shift
x >> n          ; Right shift (arithmetic)
x >>> n         ; Right shift (logical)
```

### Ternary Operator
```ahk
result := condition ? value_if_true : value_if_false
```

### Maybe/Coalescing Operator
```ahk
result := maybeUnset ?? "default"   ; Use default if unset
```

### Built-in Variables (Common)
```ahk
A_ScriptDir          ; Directory of the script
A_ScriptName         ; Name of the script file
A_WorkingDir         ; Current working directory
A_Now                ; Current date/time (YYYYMMDDHH24MISS)
A_TickCount          ; Milliseconds since system start
A_ScreenWidth        ; Screen width in pixels
A_ScreenHeight       ; Screen height in pixels
A_Clipboard          ; Clipboard contents
A_ThisHotkey         ; Most recently triggered hotkey
A_PriorHotkey        ; Previously triggered hotkey
A_Index              ; Current loop iteration
A_LoopField          ; Current field in Loop Parse
```

---

## Functions

### Defining Functions
```ahk
; Basic function
MyFunc(param1, param2) {
    return param1 + param2
}

; Optional parameters (with defaults)
MyFunc(required, optional := "default") {
    ; ...
}

; Variadic function (accepts any number of params)
MyFunc(fixed, rest*) {
    for item in rest
        ; process item
}

; Fat arrow (single expression)
Add(a, b) => a + b

; Nested function
Outer() {
    Inner() {
        ; can access Outer's locals
    }
}
```

### ByRef Parameters
```ahk
; Pass by reference - function can modify caller's variable
Swap(&a, &b) {
    temp := a
    a := b
    b := temp
}

x := 1, y := 2
Swap(&x, &y)  ; Now x=2, y=1
```

### Closures
```ahk
MakeCounter() {
    count := 0
    return () => ++count  ; Captures 'count'
}

counter := MakeCounter()
counter()  ; Returns 1
counter()  ; Returns 2
```

### Static Variables
```ahk
MyFunc() {
    static callCount := 0  ; Persists between calls
    callCount++
    return callCount
}
```

### Built-in Functions (Selection)

#### String Functions
```ahk
StrLen(str)                    ; Length of string
SubStr(str, start, length?)    ; Extract substring
InStr(haystack, needle)        ; Find position of substring
StrReplace(str, search, replace) ; Replace text
StrSplit(str, delimiters)      ; Split into array
StrLower(str)                  ; Lowercase
StrUpper(str)                  ; Uppercase
Trim(str)                      ; Remove whitespace
LTrim(str)                     ; Remove left whitespace
RTrim(str)                     ; Remove right whitespace
RegExMatch(str, pattern)       ; Regex search
RegExReplace(str, pattern, replace) ; Regex replace
Format(formatStr, values...)   ; Format string
```

#### Math Functions
```ahk
Abs(n)        ; Absolute value
Ceil(n)       ; Round up
Floor(n)      ; Round down
Round(n, d?)  ; Round to d decimals
Max(n...)     ; Maximum value
Min(n...)     ; Minimum value
Mod(x, y)     ; Modulo
Sqrt(n)       ; Square root
Log(n)        ; Logarithm base 10
Ln(n)         ; Natural logarithm
Exp(n)        ; e^n
Sin/Cos/Tan   ; Trigonometry
Random(min?, max?) ; Random number
```

#### Type Functions
```ahk
Type(value)       ; Get type name ("String", "Integer", etc.)
IsObject(value)   ; Is it an object?
IsSet(var)        ; Is variable set?
IsSetRef(&var)    ; Is referenced variable set?
Integer(value)    ; Convert to integer
Float(value)      ; Convert to float
String(value)     ; Convert to string
Number(value)     ; Convert to number
```

---

## Objects & Classes

### Object Basics
```ahk
; Object literal
obj := {name: "John", age: 30}

; Access properties
obj.name           ; "John"
obj["name"]        ; "John" (dynamic)

; Add/modify properties
obj.city := "NYC"
obj["zip"] := 10001

; Check if property exists
obj.HasOwnProp("name")  ; true
```

### Arrays
```ahk
; Create array
arr := [1, 2, 3, 4, 5]
arr := Array(1, 2, 3)

; Access elements (1-based index!)
arr[1]             ; First element
arr[-1]            ; Last element

; Properties
arr.Length         ; Number of elements

; Methods
arr.Push(value)         ; Add to end
arr.Pop()               ; Remove from end
arr.InsertAt(index, val) ; Insert at position
arr.RemoveAt(index)     ; Remove at position
arr.Has(index)          ; Check if index exists
arr.Clone()             ; Shallow copy

; Loop through
for index, value in arr {
    ; ...
}
for value in arr {
    ; index not needed
}
```

### Maps (Associative Arrays)
```ahk
; Create map
m := Map()
m := Map("key1", "value1", "key2", "value2")

; Access
m["key"]           ; Get value
m["key"] := "val"  ; Set value

; Properties
m.Count            ; Number of items
m.Default := val   ; Default for missing keys

; Methods
m.Set(key, value)
m.Get(key, default?)
m.Has(key)
m.Delete(key)
m.Clear()
m.Clone()

; Loop through
for key, value in m {
    ; ...
}
```

### Classes
```ahk
class Animal {
    ; Instance variable
    name := ""
    
    ; Constructor
    __New(name) {
        this.name := name
    }
    
    ; Method
    Speak() {
        return "..."
    }
    
    ; Static property
    static count := 0
    
    ; Static method
    static GetCount() => Animal.count
    
    ; Property with getter/setter
    Name {
        get => this.name
        set => this.name := value
    }
}

; Inheritance
class Dog extends Animal {
    __New(name) {
        super.__New(name)
        Animal.count++
    }
    
    Speak() {
        return "Woof!"
    }
}

; Usage
dog := Dog("Rex")
dog.Speak()  ; "Woof!"
```

### Meta-Functions
```ahk
class MyClass {
    ; Called when undefined property accessed
    __Get(name, params) {
        return "Property " name " not found"
    }
    
    ; Called when undefined property set
    __Set(name, params, value) {
        ; ...
    }
    
    ; Called when object used as function
    __Call(name, params) {
        ; ...
    }
}
```

---

## Hotkeys

### Basic Syntax
```ahk
; Key modifiers
^  ; Ctrl
!  ; Alt
+  ; Shift
#  ; Win

; Examples
^c::Send("Custom Ctrl+C behavior")   ; Single line
^!s::{                                ; Multi-line
    ; code here
}

; Hotkey with function
^j::MyFunction
MyFunction() {
    MsgBox("Ctrl+J pressed")
}
```

### Key Combinations
```ahk
; Modifier + key
^a::          ; Ctrl+A
!a::          ; Alt+A
+a::          ; Shift+A
#a::          ; Win+A
^!a::         ; Ctrl+Alt+A
^+a::         ; Ctrl+Shift+A
^!+a::        ; Ctrl+Alt+Shift+A

; Custom combinations
a & b::       ; A+B (A becomes prefix key)
```

### Special Keys
```ahk
; Named keys
Enter::
Tab::
Space::
Backspace::
Escape::
Delete::
Insert::
Home::
End::
PgUp::
PgDn::
Up::
Down::
Left::
Right::
F1:: through F24::

; Mouse
LButton::     ; Left click
RButton::     ; Right click
MButton::     ; Middle click
WheelUp::
WheelDown::
XButton1::
XButton2::
```

### Hotkey Options
```ahk
; Wildcard - trigger even if extra modifiers held
*^a::

; Passthrough - don't block original key
~^a::

; Up event - trigger on release
a up::

; Combine options
*~^a up::
```

### Dynamic Hotkeys
```ahk
; Enable/disable at runtime
Hotkey("^a", MyFunc)           ; Create/enable
Hotkey("^a", MyFunc, "On")     ; Enable
Hotkey("^a", MyFunc, "Off")    ; Disable
Hotkey("^a", MyFunc, "Toggle") ; Toggle
```

---

## #HotIf Directive

Context-sensitive hotkeys - only active when condition is true.

### Basic Usage
```ahk
; Only in Notepad
#HotIf WinActive("ahk_exe notepad.exe")
^a::MsgBox("Ctrl+A in Notepad!")
#HotIf  ; End context

; Only when NOT in Notepad
#HotIf !WinActive("ahk_exe notepad.exe")
^a::MsgBox("Ctrl+A outside Notepad!")
#HotIf
```

### Window Matching
```ahk
; By window title (partial match)
#HotIf WinActive("Untitled")

; By executable
#HotIf WinActive("ahk_exe chrome.exe")

; By window class
#HotIf WinActive("ahk_class Notepad")

; By window ID
#HotIf WinActive("ahk_id " myHwnd)

; Multiple conditions
#HotIf WinActive("ahk_exe code.exe") or WinActive("ahk_exe notepad.exe")
```

### Custom Functions
```ahk
; Define condition function
IsEditFocused() {
    try {
        return ControlGetFocus("A") ~= "Edit"
    }
    return false
}

#HotIf IsEditFocused()
^a::Send("^a")  ; Select all only in edit controls
#HotIf
```

### HotIf Function (Dynamic)
```ahk
; Programmatic context-sensitive hotkeys
HotIf(() => WinActive("ahk_exe notepad.exe"))
Hotkey("^a", (*) => MsgBox("Dynamic hotkey!"))
HotIf()  ; Reset
```

---

## InputHook

Intercepts keyboard input. Critical for HebrewFixer-type applications.

### Creating an InputHook
```ahk
ih := InputHook(options?)
```

### Options String
- `B` - Backspace removes the last character
- `C` - Case-sensitive
- `I` - Ignore input generated by SendLevel > 0
- `L#` - Max length (# = number)
- `M` - Modified keystrokes (Ctrl+A, etc.) are recognized
- `T#` - Timeout (# = seconds)
- `V` - Visible - keystrokes reach active window

### Key Properties
```ahk
ih.Input              ; Text collected so far
ih.Match              ; Matched end key/string
ih.EndKey             ; Key that ended input
ih.EndMods            ; Modifier state at end
ih.EndReason          ; Why input ended ("Max", "Timeout", etc.)
ih.InProgress         ; Is hook still running?
ih.BackspaceIsUndo    ; Does BS remove chars from buffer?
ih.VisibleText        ; Are text keys sent to window?
ih.VisibleNonText     ; Are non-text keys sent to window?
ih.MinSendLevel       ; Minimum SendLevel to capture
```

### Callbacks
```ahk
; Called when character added to buffer
ih.OnChar := (ih, char) => {
    ; char = the character typed
}

; Called on key down
ih.OnKeyDown := (ih, vk, sc) => {
    ; vk = virtual key code
    ; sc = scan code
    ; Return false to suppress key
}

; Called on key up
ih.OnKeyUp := (ih, vk, sc) => {
    ; ...
}

; Called when input ends
ih.OnEnd := (ih) => {
    ; ih.EndReason tells you why
}
```

### Methods
```ahk
ih.Start()                    ; Start capturing
ih.Stop()                     ; Stop capturing
ih.Wait(timeout?)             ; Wait until ended
ih.KeyOpt(keys, options)      ; Set per-key options
```

### KeyOpt Options
```ahk
ih.KeyOpt("{All}", "N")       ; Notify on all keys
ih.KeyOpt("{Enter}", "E")     ; Enter ends input
ih.KeyOpt("a-z", "I")         ; Ignore a-z
ih.KeyOpt("{BS}", "S")        ; Suppress backspace
```

Options:
- `+` or `-` prefix: Add/remove option
- `E` - End key (ends input)
- `I` - Ignore (don't add to buffer)
- `N` - Notify (trigger OnKeyDown)
- `S` - Suppress (don't send to window)
- `V` - Visible (send to window)

### Example: Custom Input
```ahk
; Capture text until Enter
ih := InputHook("V")
ih.OnChar := (ih, char) => ToolTip("Typed: " ih.Input)
ih.KeyOpt("{Enter}", "E")  ; Enter ends
ih.Start()
ih.Wait()
MsgBox("You typed: " ih.Input)
```

### Example: Hebrew-style Character Interception
```ahk
; Intercept and process each character
ih := InputHook("V I1")
ih.VisibleText := false    ; Block text from reaching app
ih.NotifyNonText := true   ; Get notified about special keys
ih.OnChar := ProcessChar
ih.OnKeyDown := ProcessKeyDown
ih.Start()

ProcessChar(ih, char) {
    ; Add to buffer, reverse, send to app
    global myBuffer
    myBuffer .= char
    SendText(ReverseString(myBuffer))
}

ProcessKeyDown(ih, vk, sc) {
    ; Handle backspace, arrows, etc.
    if vk = 0x08 {  ; Backspace
        ; Handle specially
    }
    return true  ; Let key through
}
```

---

## Send & Keyboard

### Send Functions
```ahk
Send(keys)          ; Send keystrokes (default mode)
SendText(text)      ; Send raw text (no special interpretation)
SendInput(keys)     ; Fast, reliable method
SendEvent(keys)     ; Traditional method
SendPlay(keys)      ; For games that block other methods
```

### Special Keys Syntax
```ahk
Send("{Enter}")      ; Enter key
Send("{Tab}")        ; Tab
Send("{Space}")      ; Space
Send("{Backspace}")  ; or {BS}
Send("{Delete}")     ; or {Del}
Send("{Escape}")     ; or {Esc}
Send("{Up}")         ; Arrow keys
Send("{Down}")
Send("{Left}")
Send("{Right}")
Send("{Home}")
Send("{End}")
Send("{PgUp}")
Send("{PgDn}")
Send("{Insert}")     ; or {Ins}
Send("{F1}")         ; Function keys F1-F24
```

### Modifier Syntax
```ahk
Send("^a")           ; Ctrl+A
Send("!{Tab}")       ; Alt+Tab
Send("+{End}")       ; Shift+End
Send("^!{Delete}")   ; Ctrl+Alt+Del
```

### Repeat Keys
```ahk
Send("{Left 5}")     ; Press Left 5 times
Send("{BS 10}")      ; 10 backspaces
Send("{a 20}")       ; 20 letter 'a's
```

### Key Down/Up
```ahk
Send("{Ctrl down}")  ; Hold Ctrl
Send("c")
Send("{Ctrl up}")    ; Release Ctrl

Send("{Shift down}hello{Shift up}")  ; HELLO
```

### Blind Mode
```ahk
; Don't release modifiers user is holding
Send("{Blind}^c")

; Or prefix the keys
Send("{Blind}{Ctrl down}c{Ctrl up}")
```

### Text Mode
```ahk
Send("{Text}Hello!")      ; Send as raw text
SendText("Special: ^!+#") ; No special interpretation
```

### Send Settings
```ahk
SendMode("Input")         ; Use SendInput (default, fastest)
SendMode("Event")         ; Use SendEvent
SendMode("Play")          ; Use SendPlay

SetKeyDelay(delay, pressDuration?, mode?)
; delay = ms between keystrokes (-1 = no delay)
; pressDuration = ms each key is held
```

---

## Clipboard

### A_Clipboard Variable
```ahk
; Read clipboard
text := A_Clipboard

; Write to clipboard
A_Clipboard := "New content"

; Append to clipboard
A_Clipboard .= " more text"

; Clear clipboard
A_Clipboard := ""

; Check if clipboard has data
ClipWait(timeout?, waitForType?)
; timeout = seconds to wait
; waitForType = 1 (any data) or blank/0 (text only)
```

### ClipboardAll
```ahk
; Save entire clipboard (including formats)
saved := ClipboardAll()

; Restore
A_Clipboard := saved

; Or save to file
FileAppend(ClipboardAll(), "clip.bin")
```

### Wait for Clipboard
```ahk
A_Clipboard := ""  ; Clear first
Send("^c")         ; Copy
ClipWait(2)        ; Wait up to 2 seconds
if ErrorLevel
    MsgBox("Clipboard didn't change")
else
    MsgBox("Copied: " A_Clipboard)
```

### OnClipboardChange
```ahk
OnClipboardChange(ClipChanged)

ClipChanged(dataType) {
    ; dataType: 0=empty, 1=text, 2=non-text
    if dataType = 1
        ToolTip("Clipboard: " SubStr(A_Clipboard, 1, 50))
}
```

---

## Quick Reference Index

### Common Directives
```ahk
#Requires AutoHotkey v2.0   ; Require specific version
#SingleInstance Force       ; Only one instance
#NoTrayIcon                 ; Hide tray icon
#Warn                       ; Enable warnings
#Include file.ahk           ; Include another script
#HotIf condition            ; Context-sensitive hotkeys
```

### Virtual Key Codes (Common)
```
0x08  Backspace       0x0D  Enter          0x1B  Escape
0x09  Tab             0x10  Shift          0x20  Space
0x21  PageUp          0x22  PageDown       0x23  End
0x24  Home            0x25  Left           0x26  Up
0x27  Right           0x28  Down           0x2D  Insert
0x2E  Delete          0x70-0x87  F1-F24
```

### Hebrew Unicode Range
```
0x0590 - 0x05FF : Hebrew block
  0x05D0 - 0x05EA : Hebrew letters (Aleph to Tav)
```

### Control Flow
```ahk
if condition { }
else if condition { }
else { }

switch value {
    case 1: ; ...
    case 2, 3: ; multiple values
    default: ; ...
}

Loop count { }
Loop Parse, string, delimiters { }
Loop Files, pattern { }
Loop Read, filename { }
Loop Reg, keyname { }

while condition { }
for key, value in collection { }

Break       ; Exit loop
Continue    ; Next iteration
Return      ; Exit function
```

### Error Handling
```ahk
try {
    ; risky code
}
catch Error as e {
    MsgBox("Error: " e.Message)
}
finally {
    ; always runs
}

throw Error("Something went wrong")
```

---

*End of AHK v2 Reference Document*
