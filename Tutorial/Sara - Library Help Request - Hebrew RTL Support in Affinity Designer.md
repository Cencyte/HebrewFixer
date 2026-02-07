#Task #Project #Mission #Library #Software #Code 

## Introduction:
###### *To Rovodev:*
---
*I was at the local library in my town, and overheard an older woman talking with a librarian at a scheduler tech-time 1-on-1 session, and the more I listened, the more I grew confident that I could do precisely and accurately what the    
librarian could only offer compromises for. I actually stood up, introduced myself as a tech-savvy person, and exchanged emails with the woman in a bid to help her in a superior way to the librarian. To put it more modestly, I need the    
confidence boost. Also, I'm tired of being called a weird in my community; I need to actually use my comptuer skills to contribute to this person's life.    
  
*Their actual issue relates to the Affinity Designer program, an app that I have and am very familiar with. Here is the exact qualm the old woman voiced:    
  
*"I want to be able to paste Hebrew letters into Affinity Designer and have them be preserved in format on my Windows 11 machine. I also want to naturally type into Affinity Designer, and have the RTL support for Hebrew letters in that    
same program. I don't want to buy external software such as RTL Fixer. I don't want to use an external program like Word, which does support this."    
  
*I actually really believe in the "uncompromise" as a powerful liberating aspect of computer usage, and I recognize this same want in the request of the old woman. I feel ideologically aligned with her goal in the pursuit of finding the    
solution she is looking for. However, there are some practical considerations for what I believe to be the solution that I think we should discuss before diving into to some random rabbit hole. This can't take too long. We should aim to    
get it done in a single session, although it may very well spill over into two.    
  
*I was thinking of seeing if I could find a free version of RTL Fixer to see how it works. I could not find any, nor on Github. I realized that the premise of the program is simple; it just reorders how text appears, so that the I-beam    
cursor moves backward instead of forward. It is here that I could use some enlightening; I can't really imagine there to be much more nuance in the program than that, yet in RTL Fixer (from a YouTube video I watched about it from the    
authors), there is. However, we can limit our solution only by the needs of the user, which are:    
  
*Affinity Designer support only  
Hebrew only  
Paste text support  
Windows 11 only  
  
*This narrows things down. I am wondering if we should use an AHK approach, or a custom C++ approach so that we can target things at a lower level. I have a Windows laptop in front of me that has Affinity Designer open on it. This    
computer here however is a Linux Manjaro computer. I would be using Vscode and Rovodev as the IDEs. Perhaps we could afford to switch up the developer environment a little bit. I am also running Rovodev on the Windows laptop.    
  
*So, what are you initial thoughts?    
  
*I think we should make a custom solution, instead of decompilng the one that already exists and essentially cracking it. That may become impossible, as some developers make that impossible. Plus, that's a last resort. I think it will be    
the path of least resistance to make our own gadget for her.    
  
*Additionally, any thoughts on best practices to make sure that the person who is receiving custom software (plus a PDF guide on other things, like how to change the keyboard layout on Windows and how to use the custom software) is    
ensured of the safety of the program?    
  
*I want this to be really impactful. Let's get started on the woman's solution fo. 
***

## Setup:
------- 
#### Laptop:
-  Affinity Designer
-  VSCode
-  Rovodev (GPT52-codex)
-  

#### Central:
- s
- s
- s
- s
- s
- s
- s

Steps:

1.  Type "Optional Features" into the start menu, press the **Enter** key.
2.  Click "View Features",
3.  Click "See available features"
4.  Click the search bar and then type into it "Hebrew"
5.  You should see "Hebrew Supplemental Fonts". Click add, and wait for it to fully add. 
	*Note: It may take several minutes to add completely.*

#### Add Hebrew Language to Windows 11
1.  "Language" > Language & region
2.  Preferred languages > Add a language
3.  Type "Hebrew", and click install 

#### Choose The Input Method Keyboard Shortcut
1.  Type in start menu, "Advanced keyboard settings"
2.  Click "Input language hot keys"
3.  

## AI Conversations:
---
-  Windows Optional Features: Hebrew Supplemental Fonts installation stall
https://chatgpt.com/c/69844289-f364-832d-bc3f-f4ea7fe2200f

## Process Notes: 
---
-  Fonts added by the Hebrew Supplemental Fonts package: 
	-- Aharoni Bold
	-- David
	-- FrankRuehl
	-- Gisha
	-- Levenim MT
	-- Miriam
	-- Miriam Fixed
	-- Narkism
	-- Rod

-  Hebrew input method spaces cursor correctly in OS, but not in Affinity Designer. 
-  Paste translates typed Hebrew letters from OS to Affinity Designer when correct IME is chosen.
-  The on screen keyboard will helpfully show a Hebrew alphabetical key overlay when you switch to the Hebrew IME. However, it won't show you typing the keys you press as you press them. This effect only occurs when you click the keys with the mouse.