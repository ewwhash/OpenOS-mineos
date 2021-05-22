local GUI = require("GUI")
local screen = require("Screen")
local system = require("System")
local filesystem = require("Filesystem")
local color = require("Color")
local keyboard = require("Keyboard")
local internet = component.internet

local config = {
    width = 80,
    height = 24,
    transparency = 0.3,
}

local currentScriptPath = filesystem.path(system.getCurrentScript())
local realFS = filesystem.get(currentScriptPath)
local workingDirectory = currentScriptPath .. "rootfs/"

--------------------------------------------------------------------------------

local function windowCheck(window, x, y)
	local child
	for i = #window.children, 1, -1 do
		child = window.children[i]
		
		if
			not child.hidden and
			not child.disabled and
			child:isPointInside(x, y)
		then
			if not child.passScreenEvents and child.eventHandler then
				return true
			elseif child.children then
				local result = windowCheck(child, x, y)
				if result == true then
					return true
				elseif result == false then
					return false
				end
			end
		end
	end
end

local function windowEventHandler(workspace, window, e1, e2, e3, e4, ...)
	if window.movingEnabled then
		if e1 == "touch" then
			if not windowCheck(window, e3, e4) then
				window.lastTouchX, window.lastTouchY = e3, e4
			end

			if window ~= window.parent.children[#window.parent.children] then
				window:moveToFront()
				
				if window.onFocus then
					window.onFocus(workspace, window, e1, e2, e3, e4, ...)
				end

				workspace:draw()
			end
		elseif e1 == "drag" and window.lastTouchX and not windowCheck(window, e3, e4) then
			local xOffset, yOffset = e3 - window.lastTouchX, e4 - window.lastTouchY
			if xOffset ~= 0 or yOffset ~= 0 then
				window.localX, window.localY = window.localX + xOffset, window.localY + yOffset
				window.lastTouchX, window.lastTouchY = e3, e4
				
				workspace:draw()
			end
		elseif e1 == "drop" then
			window.lastTouchX, window.lastTouchY = nil, nil
		end
	end
end

local function windowResize(window, width, height, ignoreOnResizeFinished)
	window.width, window.height = width, height
	
	if window.onResize then
		window.onResize(width, height)
	end

	if window.onResizeFinished and not ignoreOnResizeFinished then
		window.onResizeFinished()
	end

	return window
end

--------------------------------------------------------------------------------

local gpuImage = {bg = 0x0, fg = 0xffffff}

for y = 1, config.height do
    gpuImage[y] = {}
    for x = 1, config.width do
        gpuImage[y][x] = {" ", 0x0, 0x0} -- symbol, background, foreground
    end
end

local window = GUI.container(20, 10, config.width, config.height + 1)

window.passScreenEvents = false
window.resize = windowResize
window.maximize = GUI.windowMaximize
window.minimize = GUI.windowMinimize
window.eventHandler = windowEventHandler
window.movingEnabled = true

window.backgroundPanel = window:addChild(GUI.panel(1, 1, window.width, window.height, 0x0))
window.backgroundPanel.colors.transparency = config.transparency
window:addChild(GUI.label(1, 1, window.width, 1, 0xE1E1E1, "OpenOS")):setAlignment(GUI.ALIGNMENT_HORIZONTAL_CENTER, GUI.ALIGNMENT_VERTICAL_CENTER)
window:addChild(GUI.button(1, 1, 1, 1, nil, 0xFF4940, nil, 0x992400, "⬤")).onTouch = function()
    window:remove()
end
window:addChild(GUI.button(3, 1, 1, 1, nil, 0xFFB640, nil, 0x996D00, "⬤")).onTouch = function()
    window:minimize()
end

local workspace = system.addWindow(window)
local gpuObject = window:addChild(GUI.object(1, 2, config.width, config.height))
gpuObject.draw = function()
	local bufferWidth = screen.getWidth()
	local bufferIndex, indexStepOnReachOfSquareWidth = screen.getIndex(gpuObject.x, gpuObject.y), bufferWidth - gpuObject.width
	local newFrameBackgrounds, newFrameForegrounds, newFrameSymbols = screen.getNewFrameTables()

	for y = 1, config.height do
		if (window.y + y - 1) >= workspace.y and (window.y + y) <= workspace.y + workspace.height - 1 then
			for x = 1, config.width do
				if (gpuObject.x + x - 1) >= workspace.x and (gpuObject.x + x - 1) <= workspace.x + workspace.width - 1 then
					local emptySymbol = gpuImage[y][x][1] == " "
					newFrameSymbols[bufferIndex] = emptySymbol and gpuImage[y][x][2] == 0x0 and newFrameSymbols[bufferIndex] or gpuImage[y][x][1]
					newFrameBackgrounds[bufferIndex] = gpuImage[y][x][2] == 0x0 and color.blend(newFrameBackgrounds[bufferIndex], gpuImage[y][x][2], 1) or gpuImage[y][x][2]
					newFrameForegrounds[bufferIndex] = emptySymbol and newFrameForegrounds[bufferIndex] or gpuImage[y][x][3] 
				end
				
				bufferIndex = bufferIndex + 1
			end
			
			bufferIndex = bufferIndex + indexStepOnReachOfSquareWidth
		else
			bufferIndex = bufferIndex + bufferWidth
		end
	end
end

------------------------------------------------------------------------------

local container = dofile(currentScriptPath .. "Box.lua").createContainer()

container.onBootstrap = function()
    container.temp.sandbox.MINEOS_ROOTFS = realFS
end

for address, type in pairs(component.list()) do
    if type ~= "gpu" and type ~= "screen" and type ~= "eeprom" and address ~= realFS.address then
        container:passComponent(address)
    end
end

container:addComponent("eeprom", container:uuid(), {
    get = function()        
        return 'local a;do local b=component.invoke;local function c(d,e,...)local f=table.pack(pcall(b,d,e,...))if not f[1]then return nil,f[2]else return table.unpack(f,2,f.n)end end;local g=component.list("eeprom")()computer.getBootAddress=function()return c(g,"getData")end;computer.setBootAddress=function(d)return c(g,"setData",d)end;do local h=component.list("screen")()local i=component.list("gpu")()if i and h then c(i,"bind",h)end end;local function j(d)local k,l=c(d,"open","/init.lua")if not k then return nil,l end;local m=""repeat local n,l=c(d,"read",k,math.huge)if not n and l then return nil,l end;m=m..(n or"")until not n;c(d,"close",k)return load(m,"=init")end;local l;if computer.getBootAddress()then a,l=j(computer.getBootAddress())end;if not a then error("no bootable medium found"..(l and": "..tostring(l)or""),0)end end;a()'
    end,
    set = function() end,
    getLabel = function()
        return "Box BIOS"
    end,
    setLabel = function() end,
    getSize = function()
        return 4096
    end,
    getDataSize = function()
        return 256
    end,
    getData = function()
        return "f55c495e-2b53-403c-844b-90f20a0c085a"
    end,
    setData = function()
    end,
    getChecksum = function()
        return "checksum, i suppose? what do you expect?"
    end,
    makeReadonly = function(self)
        return false
    end
})

local virtualScreen = container:addComponent("screen", container:uuid(), {
    isOn = function()
        return true
    end,
    turnOn = function()
        return
    end,
    turnOff = function()
        return
    end,
    getAspectRatio = function()
        return 3.0, 2.0
    end,
    getKeyboards = function()
        local keyboards = container.libcomponent.list("keyboard")
        keyboards.n = 0

        for address in pairs(keyboards) do
            keyboards.n = keyboards.n + 1
        end

        return keyboards
    end,
    setPrecise = function()
        return false
    end,
    isPrecise = function()
        return false
    end,
    setTouchModeEnabled = function()
        return false
    end,
    isTouchModeInverted = function()
        return false
    end
})

local virtualGPU = container:addComponent("gpu", container:uuid(), {
    bind = function()
        return true
    end,
    getScreen = function()
        return virtualScreen.address
    end,
    getBackground = function()
        return gpuImage.bg
    end,
    setBackground = function(background)
        checkArg(1, background, "number")
        gpuImage.bg = background
        return background, 0
    end,
    getForeground = function(...)
        return gpuImage.fg
    end,
    setForeground = function(foreground)
        checkArg(1, foreground, "number")
        gpuImage.fg = foreground
        return foreground, 0
    end,
    getPaletteColor = function(...)
        return 0
    end,
    setPaletteColor = function()
        return 0
    end,
    maxDepth = function(self)
        return 8
    end,
    getDepth = function(self)
        return 8
    end,
    setDepth = function()
        return false
    end,
    maxResolution = function()
        return config.width, config.height
    end,
    getResolution = function()
        return config.width, config.height
    end,
    setResolution = function()
        return config.width, config.height
    end,
    getViewport = function()
        return config.width, config.height
    end,
    setViewport = function()
        return false
    end,
    get = function(x, y)
		checkArg(1, x, "number")
		checkArg(2, y, "number")

        if not gpuImage[y] or not gpuImage[y][x]then
            error("index out of bounds")
        end

        return gpuImage[y][x][1], gpuImage[y][x][3], gpuImage[y][x][2]
    end,
    set = function(x, y, value, vertical)
		checkArg(1, x, "number")
		checkArg(2, y, "number")

        for i = 1, unicode.len(value) do
            local X, Y = vertical and x or x + i - 1, vertical and y + i - 1 or y

            if gpuImage[Y] and gpuImage[Y][X] then
                gpuImage[Y][X] = {unicode.sub(value, i, i), gpuImage.bg, gpuImage.fg}
            end
        end
    end,
    copy = function(x, y, w, h, tx, ty)
		checkArg(1, x, "number")
		checkArg(2, y, "number")
		checkArg(3, w, "number")
		checkArg(4, h, "number")
		checkArg(5, tx, "number")
		checkArg(6, ty, "number")

        for Y = 1, h do
            for X = 1, w do
                local copyX, copyY = x + X - 1, y + Y - 1

                if gpuImage[copyY] and gpuImage[copyY][copyX] then
                    local tX, tY = copyX + tx, copyY + ty

                    if gpuImage[tY] and gpuImage[tY][tX] then
                        gpuImage[tY][tX] = gpuImage[copyY][copyX]
                    end
                end
            end
        end
    end,
    fill = function(x, y, w, h, char)
		checkArg(1, x, "number")
		checkArg(2, y, "number")
		checkArg(3, w, "number")
		checkArg(4, h, "number")
		checkArg(5, char, "string")

        for Y = 1, h do
            for X = 1, w do
                local setX, setY = x + X - 1, y + Y - 1

                if gpuImage[setY] and gpuImage[setY][setX] then
                    gpuImage[setY][setX] = {char, gpuImage.bg, gpuImage.fg}
                end
            end
        end
    end
})  

local virtualFS = container:addComponent("filesystem", "f55c495e-2b53-403c-844b-90f20a0c085a", {
    spaceUsed = realFS.spaceUsed,
    open = function(path, mode)
        checkArg(1, path, "string")
        return realFS.open(workingDirectory .. path, mode)
    end,
    seek = realFS.seek,
    makeDirectory = function(path)
        checkArg(1, path, "string")
        return realFS.makeDirectory(workingDirectory .. path)
    end,
    exists = function(path)
        checkArg(1, path, "string")
        return realFS.exists(workingDirectory .. path)
    end,
    isReadOnly = realFS.isReadOnly,
    write = realFS.write,
    spaceTotal = realFS.spaceTotal,
    isDirectory = function(path)
        checkArg(1, path, "string")
        return realFS.isDirectory(workingDirectory .. path)
    end,
    rename = function(from, to)
        checkArg(1, from, "string")
        checkArg(2, to, "string")
        return realFS.rename(workingDirectory .. from, workingDirectory .. to)
    end,
    list = function(path)
        checkArg(1, path, "string")
        return realFS.list(workingDirectory .. path)
    end,
    lastModified = function(path)
        return realFS.lastModified(workingDirectory .. path)
    end,
    getLabel = realFS.getLabel,
    remove = function(path)
        return realFS.remove(workingDirectory .. path)
    end,
    close = realFS.close,
    size = function(path)
        return realFS.size(workingDirectory .. path)
    end,
    read = realFS.read,
    setLabel = realFS.getLabel
})

if not virtualFS.callback.exists("/init.lua") then
    local function centrize(len)
        return math.ceil(config.width / 2 - len / 2)
    end
    
    local function centrizedSet(y, text)
        virtualGPU.callback.set(centrize(unicode.len(text)), y, text)
        workspace:draw()
    end
    
    local function drawProgressBar(percent)
        virtualGPU.callback.setForeground(0x1E1E1E)
        virtualGPU.callback.set(centrize(30), config.height / 2 + 1, ("━"):rep(30))
        virtualGPU.callback.setForeground(0xFFFFFF)
        virtualGPU.callback.set(centrize(30), config.height / 2 + 1, ("━"):rep(math.floor(math.min(percent, 100) / 100 * 30)))
        workspace:draw()
    end

    centrizedSet(config.height / 2 - 1, "Downloading")
    virtualGPU.callback.setForeground(0xE1E1E1)
    centrizedSet(config.height / 2 + 6, "Tip: use ALT to pass touch events to the OpenOS")
    virtualGPU.callback.setForeground(0xFFFFFF)
    drawProgressBar(0)
    local handle, reason = filesystem.open(currentScriptPath .. "Temp.pkg", "w")

    local request, reason, chunk = internet.request("http://localhost:8080/RootFS.pkg", nil, {
        ["User-Agent"]="Box/OpenComputers",
    })

    if request then
        repeat
            require("event").sleep(.5)
        until request.finishConnect()

        local headers = select(3, request.response())
        local contentLength, downloaded = headers["Content-Length"] and headers["Content-Length"][1] or headers["content-length"] and headers["content-length"][1], 0

        while true do
            local chunk = request.read(math.huge)

            if chunk then
                handle:write(chunk)
                downloaded = downloaded + #chunk
                drawProgressBar(math.ceil(downloaded / contentLength * 100))
            else
                break
            end
        end

        handle:close()
        virtualGPU.callback.fill(1, 1, config.width, config.height, " ")
        centrizedSet(config.height / 2, "Extracting")

        require("Compressor").unpack(currentScriptPath .. "Temp.pkg", currentScriptPath)
        filesystem.remove(currentScriptPath .. "Temp.pkg")

        virtualGPU.callback.fill(1, 1, config.width, config.height, " ")
        centrizedSet(config.height / 2, "Done")
    else
        GUI.alert("Download failed: " .. reason)
        window:remove()
    end
end

local nextResume = computer.uptime()

local function resume(...)
    local signal = {...}

    if keyboard.isAltDown() then
        gpuObject.disabled = false
        gpuObject.passScreenEvents = false

        if signal[1] == "touch" or signal[1] == "drag" or signal[1] == "drop" or signal[1] == "scroll" or signal[1] == "walk" then
            container:pushSignal(signal)
        end
    else
        gpuObject.disabled = true
        gpuObject.passScreenEvents = true
    end

    if container.temp.signalQueue[1] or computer.uptime() >= nextResume or container:passSignal(signal) then
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
    gpuObject.eventHandler = function(workspace, container, ...)
        resume(...)
    end

    workspace:draw()    
    container.startUptime = computer.uptime()
    resume()
else
    GUI.alert(reason)
end