local GUI = require("GUI")
local system = require("System")
local filesystem = require("Filesystem")
local keyboard = require("Keyboard")
local text = require("Text")
local screen = require("Screen")
local color = require("Color")
local getUserSettings = system.getUserSettings

local config = {
    width = 70,
    height = 21,
    shadow = true,
    title = true,
    
    colorScheme = {
        {"Background", GUI.WINDOW_BACKGROUND_PANEL_COLOR},
        {"Foreground", 0x1E1E1E},
        {"Title background", GUI.WINDOW_TITLE_BACKGROUND_COLOR},
        {"Title foreground", GUI.WINDOW_TITLE_TEXT_COLOR}
    },

    titleLabel = "OpenOS",
    backgroundTransparency = 0,
    titleTransparency = 0,
}

local componentAddresses = {
    screen = "e04934fb-10a8-417e-918f-5e67ff1013c8",
    filesystem = "f55c495e-2b53-403c-844b-90f20a0c085a",
    eeprom = "4c276989-f178-4b7f-9132-2bfaaa4b0563",
    gpu = "5a5b2521-0a54-4fd0-b170-8d231f67649e",
    tmpfs = "ef489a28-5418-4375-8142-f8948992415e"
}

local currentScriptPath = filesystem.path(system.getCurrentScript())
local configPath = currentScriptPath .. "Config.cfg"

--------------------------------------------------------------------------------

local function bootstrap()
    filesystem.remove(currentScriptPath .. "rootfs")
    local workspace = system.getWorkspace()
    local container = GUI.addBackgroundContainer(workspace, true, true, "Downloading")
    local progressBar = container.layout:addChild(GUI.progressBar(1, 1, 40, 0x66DB80, 0x0, 0xE1E1E1, 0, true, true, "", "%"))
    workspace:draw()

    if not component.list("internet")() then
        return GUI.alert("No component internet available"), container:remove()
    end

    local function download(url, path, progressHandler)
        filesystem.makeDirectory(filesystem.path(path))
        local handle, reason = filesystem.open(path, "w")

        if handle then
            local request, reason = component.internet.request(url, nil, {["User-Agent"]="Wget/OpenComputers"}), 0

            if request then
                while not request.finishConnect() do
                    require("Event").sleep(0.1)
                end

                local headers = select(3, request.response())
                local contentLength, downloaded = headers["Content-Length"] and headers["Content-Length"][1] or headers["content-length"] and headers["content-length"][1] or math.huge, 0

                while true do
                    local chunk = request.read(math.huge)

                    if chunk then
                        local success, reason = handle:write(chunk)

                        if success then
                            downloaded = downloaded + #chunk
                            if progressHandler then
                                progressHandler(math.min(100, math.ceil(downloaded / contentLength * 100)))
                            end
                        else
                            handle:close()
                            return false, "Write failed: " .. reason
                        end
                    else
                        handle:close()
                        return true
                    end
                end
            end

            return false, "Download failed: " .. reason
        end
        
        return false, "Open failed: " .. reason
    end

    local result, reason = download("https://github.com/BrightYC/OpenOS-mineos/blob/master/rootfs.pkg?raw=true", currentScriptPath .. "Temp.pkg", function(progress)
        progressBar.value = progress
        workspace:draw()
    end)

    if not result then
        GUI.alert(reason)
        container:remove()
        return false
    end
    
    progressBar:remove()
    container.label.text = "Almost done"
    workspace:draw()
    local result, reason = require("Compressor").unpack(currentScriptPath .. "Temp.pkg", currentScriptPath)
    filesystem.remove(currentScriptPath .. "Temp.pkg")

    if not result then
        GUI.alert(reason)
        container:remove()
        workspace:draw()
        return false
    end
    container:remove()
    workspace:draw()

    return true
end

if not filesystem.exists(currentScriptPath .. "rootfs") then
    bootstrap()
end

if filesystem.exists(configPath) then
    config = filesystem.readTable(configPath)
end

local box = dofile(currentScriptPath .. "Modules/Box.lua")
local windows = dofile(currentScriptPath .. "Modules/Window.lua")
local components = dofile(currentScriptPath .. "Modules/Component.lua", box)
local updateColors, resizeWindow

--------------------------------------------------------------------------------

local workspace, window, menu = system.addWindow(windows.create(
    1, 
    1, 
    config.width, 
    config.height, 
    config.shadow,  
    config.titleLabel, 
    config.titleTransparency, 
    config.colorScheme[3][2], -- Title background 
    config.colorScheme[4][2] -- Title foreground
))

if not config.title then
    window.titleBar:hide()
end

window.maximize = function()
    window.movingEnabled = window.maximized
    GUI.windowMaximize(window, true)
end

window.onResizeFinished = function()
    window.titleBar.width = window.width
end

local windowsContainer = system.getWindowsContainer()

local properties = menu:addContextMenuItem("Properties")
properties:addItem("Color scheme").onTouch = function()
    local container = GUI.addBackgroundContainer(workspace, true, false)
    local pickerWidth, separatorWidth = math.floor(container.width / #config.colorScheme * 0.6), 3
    local startX, startY = math.floor(container.width / 2 - ((pickerWidth + separatorWidth) * #config.colorScheme) / 2) + separatorWidth, math.floor(container.height / 2 - 3)
    container:addChild(GUI.label(1, startY, container.width, 1, 0xFFFFFF, "Color scheme")):setAlignment(GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_TOP)
    startY = startY + 3

    for i = 1, #config.colorScheme do
        if i == 1 then
            container:addChild(GUI.slider(startX, startY + 4, pickerWidth, 0x66DB80, 0x1e1e1e, 0xFFFFFF, 0xAAAAAA, 0, 100, config.backgroundTransparency * 100, false, "Transparency ", " %")).onValueChanged = function(workspace, slider)
                config.backgroundTransparency = slider.value / 100
                updateColors()
                filesystem.writeTable(configPath, config)
            end
        elseif i == 3 then
            container:addChild(GUI.slider(startX, startY + 4, pickerWidth, 0x66DB80, 0x1e1e1e, 0xFFFFFF, 0xAAAAAA, 0, 100, config.titleTransparency * 100, false, "Transparency ", " %")).onValueChanged = function(workspace, slider)
                config.titleTransparency = slider.value / 100
                updateColors()
                filesystem.writeTable(configPath, config)
            end
        end

        local colorSelector = container:addChild(GUI.colorSelector(startX, startY, pickerWidth, separatorWidth, config.colorScheme[i][2], config.colorScheme[i][1]))
        colorSelector.onColorSelected = function()
            local oldBackground, oldForeground = config.colorScheme[1][2], config.colorScheme[2][2]
            config.colorScheme[i][2] = colorSelector.color
            updateColors(oldBackground, oldForeground)
            filesystem.writeTable(configPath, config)
        end
        startX = startX + pickerWidth + separatorWidth
    end
end

properties:addItem("Terminal").onTouch = function()
    local container = GUI.addBackgroundContainer(workspace, true, false)
    local startX, startY = math.floor(container.width / 2 - 15), math.floor(container.height / 2 - 3)
    container:addChild(GUI.label(1, startY, container.width, 1, 0xFFFFFF, "Terminal")):setAlignment(GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_TOP)
    startY = startY + 3

    local titleBar = container:addChild(GUI.switchAndLabel(startX, startY, 29, 8, 0x66DB80, 0x2D2D2D, 0xE1E1E1, 0x878787, "Title bar:", config.title))
    titleBar.switch.onStateChanged = function()
        config.title = titleBar.switch.state

        if config.title then
            window.titleBar:unhide()
            window.gpu.context.localY = 2
            if window.maximized then
                window.gpu:flush(windowsContainer.width, windowsContainer.height - 1, true)
            end
        else
            window.titleBar:hide()
            window.gpu.context.localY = 1
            if window.maximized then
                window.gpu:flush(windowsContainer.width, windowsContainer.height, true)
            end
        end

        filesystem.writeTable(configPath, config)
    end
    startY = startY + 2

    local shadow = container:addChild(GUI.switchAndLabel(startX, startY, 29, 8, 0x66DB80, 0x2D2D2D, 0xE1E1E1, 0x878787, "Shadow:", config.shadow))
    shadow.switch.onStateChanged = function()
        config.shadow = shadow.switch.state
        window.drawShadow = config.shadow
        filesystem.writeTable(configPath, config)
    end

    startY = startY + 3
    container:addChild(GUI.text(startX, startY, 0x878787, "Resolution: "))
    local width = container:addChild(GUI.input(startX + 13, startY, 6, 1, 0xEEEEEE, 0x555555, 0x999999, 0xFFFFFF, 0x2D2D2D, window.gpu.temp.width, nil, true))
    width.validator = function(text)
        local width = tonumber(text)

        if #text == 0 then
            return
        end

        if #tostring(text) > 0 and width and (width >= 1 and width <= workspace.width) then
            return true
        end
        GUI.alert("Invalid width")
    end
    width.onInputFinished = function()
        local width = math.floor(tonumber(width.text))
        resizeWindow(width, window.gpu.temp.height)
        window.gpu:flush(width, window.gpu.temp.height, true)
        config.width = width
        filesystem.writeTable(configPath, config)
    end

    container:addChild(GUI.text(startX + 20, startY, 0x878787, "x"))
    local height = container:addChild(GUI.input(startX + 22, startY, 6, 1, 0xEEEEEE, 0x555555, 0x999999, 0xFFFFFF, 0x2D2D2D, window.gpu.temp.height, nil, true))
    height.validator = function(text)
        local height = tonumber(text)

        if #text == 0 then
            return
        end

        if #tostring(text) > 0 and height and (height >= 1 and height <= windowsContainer.height - (window.titleBar.hidden and 0 or 1)) then
            return true
        end
        GUI.alert("Invalid height")
    end
    height.onInputFinished = function()
        local height = math.floor(tonumber(height.text))
        resizeWindow(window.width, height)
        window.gpu:flush(window.gpu.temp.width, height, true)
        config.height = height
        filesystem.writeTable(configPath, config)
    end
end
properties:addSeparator()

menu:addItem("Hotkeys").onTouch = function()
    local container = GUI.addBackgroundContainer(workspace, true, true, "Hotkeys")
    
    local help = {
        "ALT - pass 'drag' event",
        " ",
        "CTRL+E - close editor",
        " ",
        "CTRL+SHIFT+C - interrupt"
    }

    local textBox = container.layout:addChild(GUI.textBox(1, 1, 60, #help, nil, 0xB4B4B4, help, 1, 0, 0, false, false))
    textBox:setAlignment(GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_TOP)
    textBox.eventHandler = nil

    workspace:draw()
end

------------------------------------------------------------------------------

local container = box.createContainer()

properties:addItem("Reset OpenOS").onTouch = function()
    if bootstrap() then
        local success, reason = container:bootstrap()

        if not success then
            GUI.alert(reason)
            window:remove()
        end
    else
        filesystem.remove(currentScriptPath .. "rootfs")
        window:remove()
    end
end

container.libcomputer.tmpAddress = function()
    return componentAddresses.tmpfs
end

container.libcomputer.users = function()
    return computer.users()
end

container.libcomputer.addUser = function(user)
    return computer.addUser(user)
end

container.libcomputer.removeUser = function(user)
    return computer.removeUser(user)
end

container.libcomputer.energy = function()
    return computer.energy()
end

container.libcomputer.maxEnergy = function()
    return computer.maxEnergy()
end

container.libcomputer.uptime = function()
    return computer.uptime()
end

window.address = container.address

container:attachComponent(components.createScreen(componentAddresses.screen, container))
container:attachComponent(components.createFilesystem(componentAddresses.filesystem, filesystem.get(currentScriptPath), currentScriptPath .. "rootfs/"))
container:attachComponent(components.createFilesystem(componentAddresses.tmpfs, component.proxy(computer.tmpAddress()), "/OpenOS/"))
window.gpu = container:attachComponent(components.createGPU(componentAddresses.gpu, config.colorScheme[1][2], config.colorScheme[2][2], function() return windowsContainer.width end, function() return windowsContainer.height - (window.titleBar.hidden and 0 or 1) end, container.libcomponent.list("screen")()))
window.gpu.context = window:addChild(GUI.object(1, 1, config.width, config.height))
window.gpu.context.draw = function()
    local bufferWidth = screen.getWidth()
    local bufferIndex, indexStepOnReachOfSquareWidth, gpuIndex = screen.getIndex(window.gpu.context.x, window.gpu.context.y), bufferWidth - window.gpu.temp.width, 1
    local newFrameBackgrounds, newFrameForegrounds, newFrameSymbols = screen.getNewFrameTables()

    for y = 1, window.gpu.temp.height do
        if (window.gpu.context.y + y - 1) >= 1 and (window.gpu.context.y + y - 1) <= workspace.height then
            for x = 1, window.gpu.temp.width do
                if (window.gpu.context.x + x - 1) >= workspace.x and (window.gpu.context.x + x - 1) <= workspace.x + workspace.width - 1 then
                    if config.backgroundTransparency > 0 and window.transparencyEnabled then
                        local emptySymbol = window.gpu.temp.symbols[gpuIndex] == " "
                        newFrameSymbols[bufferIndex] = emptySymbol and window.gpu.temp.backgrounds[gpuIndex] == config.colorScheme[1][2] and newFrameSymbols[bufferIndex] or window.gpu.temp.symbols[gpuIndex]
                        newFrameBackgrounds[bufferIndex] = window.gpu.temp.backgrounds[gpuIndex] == config.colorScheme[1][2] and color.blend(newFrameBackgrounds[bufferIndex], config.colorScheme[1][2], config.backgroundTransparency) or window.gpu.temp.backgrounds[gpuIndex]
                        newFrameForegrounds[bufferIndex] = emptySymbol and color.blend(newFrameForegrounds[bufferIndex], config.colorScheme[1][2], config.backgroundTransparency) or window.gpu.temp.foregrounds[gpuIndex]
                    else
                        newFrameSymbols[bufferIndex] = window.gpu.temp.symbols[gpuIndex]
                        newFrameBackgrounds[bufferIndex] = window.gpu.temp.backgrounds[gpuIndex]
                        newFrameForegrounds[bufferIndex] = window.gpu.temp.foregrounds[gpuIndex]
                    end
                end
                
                gpuIndex = gpuIndex + 1
                bufferIndex = bufferIndex + 1
            end
            
            bufferIndex = bufferIndex + indexStepOnReachOfSquareWidth
        else
            bufferIndex = bufferIndex + bufferWidth
            gpuIndex = gpuIndex + window.gpu.temp.width
        end
    end
end

if window.titleBar.hidden then
    window.gpu.context.localY = 1
else
    window.gpu.context.localY = 2
end

resizeWindow = function(width, height)
    if not (window.width == width and window.height == height + 1) then
        if window.maximized then
            window:maximize()
        end
        window:resize(width, height + 1)
        window.localX = math.floor(workspace.width / 2 - window.width / 2)
        window.localY = math.floor(workspace.height / 2 - window.height / 2)
        window.localX = window.localX < 1 and 1 or window.localX
        window.localY = window.localY < 1 and 1 or window.localY
        window.gpu.context.width = width
        window.gpu.context.height = height
    end
end

window.gpu:flush(config.width, config.height)
window.gpu.onResolutionChange = resizeWindow

window.titleBar.maximize.onTouch = function()
    window:maximize()
    window.gpu:flush(window.width, window.height - 1, true)
    window.gpu.context.width = window.width
    window.gpu.context.height = window.height - 1
end

for address, type in pairs(component.list()) do
    if type ~= "screen" and type ~= "gpu" and type ~= "eeprom" and address ~= filesystem.get(currentScriptPath).address and address ~= computer.tmpAddress() then
        container:passComponent(address, true) -- weak passthrough
    end
end

container.beforeBootstrap = function()
    for address in pairs(container.libcomponent.list("eeprom")) do
        container.components[address]:remove()
    end
    container:attachComponent(components.createEEPROM(componentAddresses.eeprom, componentAddresses.filesystem))
end

container.onBootstrap = function()
    container.temp.sandbox.MINEOS_INTEGRATION = {
        COLORS = {
            BACKGROUND = config.colorScheme[1][2],
            FOREGROUND = config.colorScheme[2][2]
        },
        ATTACH_EEPROM = function()
            container.components[componentAddresses.eeprom]:remove()
            local eeprom = component.list("eeprom")()

            if eeprom then
                container:passComponent(eeprom, true)
            end
        end,
        RESOLUTION = {
            WIDTH = config.width,
            HEIGHT = config.height
        },
        ROOTFS = filesystem.get(currentScriptPath),
        CURRENT_PROGRAM = function(name)
            window.titleBar.text = name
        end
    }
end

updateColors = function(oldBackground, oldForeground)
    container.temp.sandbox.MINEOS_INTEGRATION.COLORS.BACKGROUND = config.colorScheme[1][2]
    container.temp.sandbox.MINEOS_INTEGRATION.COLORS.FOREGROUND = config.colorScheme[2][2]

    window.titleBar.colors.background = config.colorScheme[3][2]
    window.titleBar.colors.text = config.colorScheme[4][2]
    window.titleBar.colors.transparency = config.titleTransparency

    window.gpu:flush(nil, nil, true, oldBackground, oldForeground, config.colorScheme[1][2], config.colorScheme[2][2])
end

local nextResume = computer.uptime()

local function resume(...)
    local signal, isKeyboardEvent = {...}

    if signal[1] == "component_added" and not container.components[signal] and signal[3] ~= "screen" and signal[3] ~= "gpu" then
        container:passComponent(signal[2], true)
    end 

    isKeyboardEvent = signal[1] == "key_down" or signal[1] == "key_up" or signal[1] == "clipboard"

    if signal[1] == "drag" then
        if keyboard.isAltDown() then
            window.movingEnabled = false
            signal[2] = componentAddresses.screen
            signal[3] = signal[3] - window.x + 1
            signal[4] = signal[4] - window.y
            container:pushSignal(signal)
        elseif not window.maximized then
            window.movingEnabled = true
            window.eventHandler(workspace, window, ...)
        end
    end
    if signal[1] == "touch" or signal[1] == "drop" or signal[1] == "scroll" then
        signal[2] = componentAddresses.screen
        signal[3] = signal[3] - window.x + 1
        signal[4] = signal[4] - window.y
        container:pushSignal(signal)
    elseif isKeyboardEvent and windowsContainer.children[#windowsContainer.children].address == container.address then    
        if keyboard.isControlDown() and keyboard.isShiftDown() and keyboard.isKeyDown(46) then
            container:pushSignal{"key_down", signal[2], 0, 29, signal[5]}
            container:pushSignal{"key_down", signal[2], 0, 56, signal[5]}
            container:pushSignal{"key_down", signal[2], 99, 46, signal[5]}
        else
            container:passSignal(signal)
        end

        workspace:consumeEvent()
    elseif not isKeyboardEvent then
        container:passSignal(signal)
    end

    if container.temp.signalQueue[1] or computer.uptime() >= nextResume then
        local success, result = container:resume()
        workspace:draw()

        if not success then
            if result ~= "container shutdown" then
                GUI.alert(result)
            end
            return window:remove()
        end

        nextResume = computer.uptime() + result
    end
end

local success, reason = container:bootstrap()

if success then
    window.gpu.context.eventHandler = function(workspace, container, ...)
        resume(...)
    end
else
    GUI.alert(reason)
    window:remove()
end
