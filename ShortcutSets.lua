LUAGUI_NAME = "Shortcut Sets"
LUAGUI_AUTH = "PaperEdge"
LUAGUI_DESC = "Left and Right DPad switch between 3 pages of Shortcuts"

-- Credits
-- Xendra for the original mod, Secondary Shortcut Menu, that I worked off of
-- camsPatience for helping me to figure out the color system
-- KSX for the color changer scripts
-- TopazTK for giving me guidance through the modding process
-- You: For being yourself <3

debugFlag = true

canExecute = false
installed = false
loadComplete = false
loadFlagLoc = 0
loadFlag = 0xFF

-- Address Signatures
inputSignature = nil
customizeSignature = nil
shortcutSignature = nil
shortcutColorsSignature = nil

-- Input
inputAddress = 0
L1Address = 0
DPadAddress = 0

L1 = 0x04
DPad_L = 0x80
DPad_R = 0x20

inputCooldown = 0

-- Shortcuts
shortcutPageAddress = 0 -- save the page number so it remembers between sessions
extraShortcutAddresses = {0, 0, 0, 0, 0, 0, 0, 0, 0} -- stored in the save data in a *hopefully* unused spot
realShortcutAddresses = {0, 0, 0}
shortcuts = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF} -- FF = blank slot
magicNames = {"Fire", "Blizzard", "Thunder", "Cure", "Gravity", "Stop", "Aero", "-"}

-- HUD Management; Customize Menu and Shortcut Command Menu
customizeSoraAddress = 0
isOnCustomizeSora = 0x01
isChangingShortcut = 0x02
prevMenu = -1
wasEditing = false

currShortcutPageCommand = 0
currShortcutPageCustomize = 0

-- Shortcut Colors
topLeftShortcutColor = 0
botLeftShortcutColor = 0
topRightShortcutColor = 0
botRightShortcutColor = 0
textShortcutColor = 0

function _OnInit()
    if (ENGINE_TYPE == "BACKEND") then 
        customizeSignature = FindSignature(
            "customizeSignature",
            0x280000,
            0x2EBAE40,
            "\x0F\x85\x00\x00\x00\x00\x48\x8B\x05\x00\x00\x00\x00\xC7\x05\x00\x00\x00\x00\x01\x00\x00\x00\x0F\xB6\x88\x8E\x04\x00\x00\x89\x0D\x00\x00\x00\x00",
            "xx????xxx????xx????xxxxxxxxxxxxx????")

        inputSignature = FindSignature(
            "inputSignature",
            0x160000,
            0x2EBAE40,
            "\x48\x89\x5C\x24\x08\x57\x48\x83\xEC\x20\xE8\x00\x00\x00\x00\x83\x3D\x00\x00\x00\x00\x00\x0F\x84\xC4\x00\x00\x00\x0F\x28\x05\x00\x00\x00\x00\x0F\x28\x0D\x00\x00\x00\x00",
            "xxxxxxxxxxx????xx????xxxxxxxxxx????xxx????")

        shortcutSignature = FindSignature(
            "shortcutSignature",
            0x260000,
            0x2EBAE40,
            "\xCC\xCC\xCC\x48\x8B\x05\x00\x00\x00\x00\x4C\x63\xC1\x41\x88\x94\x00\x44\x08\x00\x00\xC3",
            "xxxxxx????xxxxxxxxxxxx")

        shortcutColorsSignature = FindSignature(
            "shortcutColorsSignature",
            0x250000,
            0x2EBAE40,
            "\x48\x89\x44\x24\x30\x48\x89\x5C\x24\x28\x48\x89\x7C\x24\x20\xE8\x00\x00\x00\x00\x4C\x8D\x05\x00\x00\x00\x00\x48\x8D\x0D\x00\x00\x00\x00\x48\x8D\x15\x00\x00\x00\x00",
            "xxxxxxxxxxxxxxxx????xxx????xxx????xxx????")
        
        if (inputSignature == nil or customizeSignature == nil or
            shortcutSignature == nil or shortcutColorsSignature == nil) then
            canExecute = false
        else
            canExecute = true
        end     
    end
end

function _OnFrame()
    if (canExecute == false) then
        goto done
    end

    if(installed == false) then
        ConsolePrint("Shortcut Sets - installed")
        installed = true
    end

    if (inputCooldown > 0) then
        inputCooldown = inputCooldown - 1
    end

    customizeSoraAddress = FetchRelativePointerWithSig(customizeSignature, 0x0F) + 0x04

    inputAddress = FetchRelativePointerWithSig(inputSignature, 0x1F)     
    L1Address = inputAddress + 0x05
    DPadAddress = inputAddress + 0x04

    realShortcutAddresses[1] = FetchRelativePointerWithSig(shortcutSignature, 0x06)
    realShortcutAddresses[1] = (ReadLong(realShortcutAddresses[1]) + 0x00000844) - BASE_ADDR
    realShortcutAddresses[2] = realShortcutAddresses[1] + 1
    realShortcutAddresses[3] = realShortcutAddresses[1] + 2

    extraShortcutAddresses[1] = realShortcutAddresses[1] - 41
    for i=2, 9 do    
        extraShortcutAddresses[i] = extraShortcutAddresses[1] + (i - 1)
    end
    loadFlagLoc = realShortcutAddresses[1] - 1
    shortcutPageAddress = extraShortcutAddresses[9] + 1

    -- colors for Shortcut HUD are 4 bytes per channel. No one knows why
    local shortcutColorRelativePointer = FetchRelativePointerWithSig(shortcutColorsSignature, 0x25)
    topLeftShortcutColor = shortcutColorRelativePointer + 0x20
    botLeftShortcutColor = topLeftShortcutColor + 16
    topRightShortcutColor = botLeftShortcutColor + 16
    botRightShortcutColor = topRightShortcutColor + 16
    textShortcutColor = topLeftShortcutColor + 192

    -- let it load once before letting this run. Order of events here is important
    if(inputAddress ~= 0 and loadComplete) then
        checkInputGame()
        checkInputMenu()
    end

    if(loadFlagLoc ~= 0) then
        checkLoadFlag()
        loadComplete = loadShortcuts()
    end

    -- Style~~~
    if(topLeftShortcutColor ~= 0) then
        changeShortcutMenuColors()
    end

    :: done ::
end

function checkInputGame()
    if (pressed_L1()) then
        if(isPageEmpty(currShortcutPageCommand)) then
            currShortcutPageCommand = findNextPage(currShortcutPageCommand, 1)
            showShortcutPage(currShortcutPageCommand)       
            currShortcutPageCustomize = currShortcutPageCommand
            WriteByte(shortcutPageAddress, currShortcutPageCommand)
        end
        if(isPageEmpty(currShortcutPageCommand)) then -- all pages are empty
            currShortcutPageCommand = 0
            currShortcutPageCustomize = 0
            WriteByte(shortcutPageAddress, currShortcutPageCommand)
        end

        if (inputCooldown == 0) then -- avoid spamming
            if (pressed_DPad_R()) then
                inputCooldown = 10
                currShortcutPageCommand = findNextPage(currShortcutPageCommand, 1)
                showShortcutPage(currShortcutPageCommand)
                currShortcutPageCustomize = currShortcutPageCommand -- reflect change in Customize Menu
                WriteByte(shortcutPageAddress, currShortcutPageCommand)
            elseif (pressed_DPad_L()) then
                inputCooldown = 10
                currShortcutPageCommand = findNextPage(currShortcutPageCommand, -1)
                showShortcutPage(currShortcutPageCommand)
                currShortcutPageCustomize = currShortcutPageCommand
                WriteByte(shortcutPageAddress, currShortcutPageCommand)
            end
        end
    end
end

function checkInputMenu()
    local currMenu = ReadByte(customizeSoraAddress)
    if (currMenu == isChangingShortcut) then
        wasEditing = true
        prevMenu = currMenu
    elseif(prevMenu ~= currMenu and currMenu == isOnCustomizeSora) then
        if (wasEditing) then
            readShortcutPage(currShortcutPageCustomize)
            saveShortcuts()
            wasEditing = false
        end
        prevMenu = currMenu
    end

    if(currMenu == isOnCustomizeSora) then
        if (inputCooldown == 0) then
            if (pressed_DPad_L()) then
                currShortcutPageCustomize = currShortcutPageCustomize - 1
                if (currShortcutPageCustomize < 0) then
                    currShortcutPageCustomize = 2
                end 
                showShortcutPage(currShortcutPageCustomize)              
                inputCooldown = 10
                currShortcutPageCommand = currShortcutPageCustomize
                WriteByte(shortcutPageAddress, currShortcutPageCustomize)
            elseif (pressed_DPad_R()) then
                currShortcutPageCustomize = currShortcutPageCustomize + 1
                if (currShortcutPageCustomize > 2) then
                    currShortcutPageCustomize = 0
                end     
                showShortcutPage(currShortcutPageCustomize)          
                inputCooldown = 10
                currShortcutPageCommand = currShortcutPageCustomize
                WriteByte(shortcutPageAddress, currShortcutPageCustomize)
            end
        end
    end
end

function findNextPage(page, inc)
    page = incPage(page, inc)
    local attempts = 0
    while (isPageEmpty(page) and attempts < 2) do
        page = incPage(page, inc)
        attempts = attempts + 1
    end
    return page
end

function incPage(page, inc)
    page = page + inc
    if (page > 2) then
        page = 0
    elseif (page < 0) then
        page = 2
    end
    return page
end

function isPageEmpty(page)
    local i = page * 3 + 1
    return (shortcuts[i] == 0xFF and 
        shortcuts[i + 1] == 0xFF and
        shortcuts[i + 2] == 0xFF)
end

function readShortcutPage(page)
    DebugPrint("Reading Page: " .. page)
    local i = page * 3 + 1
    shortcuts[i] = ReadByte(realShortcutAddresses[1])
    shortcuts[i+1] = ReadByte(realShortcutAddresses[2])
    shortcuts[i+2] = ReadByte(realShortcutAddresses[3])

    DebugPrint("Slot ".. i .. " - "..shortcuts[i])
    DebugPrint("Slot ".. (i+1).. " - "..shortcuts[i+1])
    DebugPrint("Slot ".. (i+2).. " - "..shortcuts[i+2])
end

function showShortcutPage(page)
    local i = page * 3 + 1
    WriteByte(realShortcutAddresses[1], shortcuts[i])
    WriteByte(realShortcutAddresses[2], shortcuts[i+1])
    WriteByte(realShortcutAddresses[3], shortcuts[i+2])
end

function saveShortcuts()
    DebugPrint("Saving Shortcuts")
    for i=1, #shortcuts do
        WriteByte(extraShortcutAddresses[i], shortcuts[i])
        DebugPrint(string.format("Slot %i: %X -> "..numToMagic(shortcuts[i]), i, extraShortcutAddresses[i]))
    end
    DebugPrint("======================")
end

function checkLoadFlag()
    if (ReadByte(loadFlagLoc) ~= loadFlag) then
        initializeNewSaveData()
        DebugPrint("1 "..ReadByte(loadFlagLoc))
        DebugPrint("2 "..string.format("%X",loadFlagLoc))
        DebugPrint("3 "..loadFlag)
        WriteByte(loadFlagLoc, loadFlag)
        DebugPrint("4 "..ReadByte(loadFlagLoc))
    end
end

function loadShortcuts()
    for i=1, #shortcuts do
        shortcuts[i] = ReadByte(extraShortcutAddresses[i])
    end
    currShortcutPageCustomize = ReadByte(shortcutPageAddress)
    if(currShortcutPageCustomize > 2) then
        currShortcutPageCustomize = 0
    elseif(currShortcutPageCustomize < 0) then
        currShortcutPageCustomize = 2
    end  
    currShortcutPageCommand = currShortcutPageCustomize

    return true
end

function initializeNewSaveData()
    DebugPrint("Adding Shortcut Sets Save Data")
    for i=1, #shortcuts do
        if(i < 4) then
            WriteByte(extraShortcutAddresses[i], ReadByte(realShortcutAddresses[i]))
        else
            WriteByte(extraShortcutAddresses[i], 0xFF) -- Add empty slots
        end
    end
    WriteByte(shortcutPageAddress, 0x00) -- probably uneccessary, but just in case
end

-- RRRRGGGGBBBB
-- Feel free to change the colors if you hate me
function changeShortcutMenuColors()
    if(currShortcutPageCommand == 0) then
        textR = 147
        textG = 0
        textB = 0
        topLeftR = 125
        topLeftG = 125
        topLeftB = 125
        botLeftR = 125
        botLeftG = 0
        botLeftB = 0
        topRightR = 125
        topRightG = 0
        topRightB = 0
        botRightR = 125
        botRightG = 0
        botRightB = 125
    elseif(currShortcutPageCommand == 1) then
        textR = 0
        textG = 147
        textB = 0
        topLeftR = 125
        topLeftG = 125
        topLeftB = 125
        botLeftR = 0
        botLeftG = 125
        botLeftB = 0
        topRightR = 0
        topRightG = 125
        topRightB = 0
        botRightR = 125
        botRightG = 0
        botRightB = 125
    elseif(currShortcutPageCommand == 2) then
        textR = 0
        textG = 64
        textB = 147
        topLeftR = 125
        topLeftG = 125
        topLeftB = 125
        botLeftR = 0
        botLeftG = 0
        botLeftB = 125
        topRightR = 0
        topRightG = 0
        topRightB = 125
        botRightR = 125
        botRightG = 0
        botRightB = 125
    end

    WriteColor(topLeftShortcutColor, topLeftR, topLeftG, topLeftB)
    WriteColor(botLeftShortcutColor, botLeftR, botLeftG, botLeftB)
    WriteColor(topRightShortcutColor, topRightR, topRightG, topRightB)
    WriteColor(botRightShortcutColor, botRightR, botRightG, botRightB)
    WriteColor(textShortcutColor, textR, textG, textB)
end

function WriteColor(address, colorR, colorG, colorB)
    WriteInt(address + 0, colorR)
    WriteInt(address + 4, colorG)
    WriteInt(address + 8, colorB)
end

function pressed_L1()
    return ReadByte(L1Address) & L1 == L1
end

function pressed_DPad_R()
    return ReadByte(DPadAddress) & DPad_R == DPad_R
end

function pressed_DPad_L()
    return ReadByte(DPadAddress) & DPad_L == DPad_L
end

function numToMagic(n)
    if (n >= 0 and n <= 6) then
        return magicNames[n+1]
    elseif n == 255 then
        return "-"
    else
        return "Error"
    end
end

--------------------------
--Agnostic Function Finders
--------------------------
function FetchRelativePointerWithSig(fetchSignature, relOffset)
    if (fetchSignature == nil) then
        return nil
    end

    local fetchValue = ReadInt(fetchSignature + relOffset)
    if(once) then
        ConsolePrint(string.format("fetchValue: %X", fetchValue))
        ConsolePrint(string.format("finalValue: %X", fetchSignature + fetchValue + relOffset + 0x04))
    end
    return fetchSignature + fetchValue + relOffset + 0x04
end

function FindSignature(sigName, startOffset, endOffset, pattern, mask)
    local bytes = BytesFromEscapedPattern(pattern)
    local length = #pattern

    if (#mask ~= length) then
        ConsolePrint("Pattern and mask length do not match for "..sigName)
        return nil
    end

    for offset = startOffset, endOffset - length do
        local found = true

        for i = 1, length do
            if (string.sub(mask, i, i) == "x") then
                local actual = ReadByte(offset + i - 1)
                if actual ~= bytes[i] then
                    found = false
                    break
                end
            end
        end

        if (found) then
            DebugPrint(string.format("Found "..sigName.." at %X", offset))
            return offset        
        end
    end

    ConsolePrint("Unable to find "..sigName..". Report bug or check for mod update")
    return nil
end

function BytesFromEscapedPattern(pattern)
    local bytes = {}

    for i = 1, #pattern do
        bytes[i] = string.byte(pattern, i)
    end

    return bytes
end

function DebugPrint(message)
    if(debugFlag) then
        ConsolePrint(message)
    end
end