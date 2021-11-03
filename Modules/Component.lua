local box = ...

local eepromCode = [[
local init
do
  local component_invoke = component.invoke
  local component_list = component.list
  local function boot_invoke(address, method, ...)
    local result = table.pack(pcall(component_invoke, address, method, ...))
    if not result[1] then
      return nil, result[2]
    else
      return table.unpack(result, 2, result.n)
    end
  end

  -- backwards compatibility, may remove later
  computer.getBootAddress = function()
    return boot_invoke(component_list("eeprom")(), "getData", address)
  end
  computer.setBootAddress = function(address)
    return boot_invoke(component_list("eeprom")(), "setData", address)
  end

  do
    local screen = component.list("screen")()
    local gpu = component.list("gpu")()
    if gpu and screen then
      boot_invoke(gpu, "bind", screen)
    end
  end
  local function tryLoadFrom(address)
    local handle, reason = boot_invoke(address, "open", "/init.lua")
    if not handle then
      return nil, reason
    end
    local buffer = ""
    repeat
      local data, reason = boot_invoke(address, "read", handle, math.huge)
      if not data and reason then
        return nil, reason
      end
      buffer = buffer .. (data or "")
    until not data
    boot_invoke(address, "close", handle)
    return load(buffer, "=init")
  end
  local reason
  if computer.getBootAddress() then
    init, reason = tryLoadFrom(computer.getBootAddress())
  end
  if not init then
    error("no bootable medium found" .. (reason and (": " .. tostring(reason)) or ""), 0)
  end
end
init()
]]

local function createEEPROM(address, getData)
    return box.createComponent{
        address = address,
        type = "eeprom",
        callback = {
            get = function() return eepromCode end,
            set = function() end,
            getLabel = function() return "Box BIOS" end,
            setLabel = function() end,
            getSize = function() return -1 end,
            getDataSize = function() return -1 end, 
            getData = function() return getData end,
            setData = function() end,
            getChecksum = function() return "8e38c115" end, 
            makeReadonly = function() return false end
        }
    }
end

local function createScreen(address, container)
    return box.createComponent{
        address = address,
        type = "screen",
        callback = {
            isOn = function() return true end,
            turnOn = function() return false end,
            turnOff = function() return false end,
            getAspectRatio = function() return 3.0, 2.0 end,
            getKeyboards = function() local keyboards = container.libcomponent.list("keyboard") local n = 0 for address in pairs(keyboards) do n = n + 1 end keyboards.n = n return keyboards end,
            setPrecise = function() return false end,
            isPrecise = function() return false end,
            setTouchModeEnabled = function() return false end,
            isTouchModeInverted = function() return false end
        }
    }
end

local function createFilesystem(address, proxy, relativeDirectory)
    return box.createComponent{
        address = address,
        type = "filesystem",
        callback = {
            spaceUsed = proxy.spaceUsed,
            open = function(path, mode) proxy.makeDirectory(relativeDirectory) checkArg(1, path, "string") return proxy.open(relativeDirectory .. path, mode) end,
            seek = proxy.seek,
            makeDirectory = function(path) proxy.makeDirectory(relativeDirectory) checkArg(1, path, "string") return proxy.makeDirectory(relativeDirectory .. path) end,
            exists = function(path) checkArg(1, path, "string") return proxy.exists(relativeDirectory .. path) end,
            isReadOnly = proxy.isReadOnly,
            write = proxy.write,
            spaceTotal = proxy.spaceTotal,
            isDirectory = function(path) checkArg(1, path, "string") return proxy.isDirectory(relativeDirectory .. path) end,
            rename = function(from, to) checkArg(1, from, "string") checkArg(2, to, "string") return proxy.rename(relativeDirectory .. from, relativeDirectory .. to) end,
            list = function(path) proxy.makeDirectory(relativeDirectory) checkArg(1, path, "string") return proxy.list(relativeDirectory .. path) end,
            lastModified = function(path) return proxy.lastModified(relativeDirectory .. path) end,
            getLabel = proxy.getLabel,
            remove = function(path) return proxy.remove(relativeDirectory .. path) end,
            close = proxy.close, 
            size = function(path) return proxy.size(relativeDirectory .. path) end,
            read = proxy.read,
            setLabel = proxy.getLabel
        }
    }
end

local function rawFlushGPU(gpu, width, height)
    gpu.temp = {
        width = width,
        height = height,
        background = gpu.background,
        foreground = gpu.foreground,
        symbols = {},
        backgrounds = {},
        foregrounds = {}
    }

    for i = 1, gpu.temp.width * gpu.temp.height do
        table.insert(gpu.temp.symbols, " ")
        table.insert(gpu.temp.backgrounds, gpu.temp.background)
        table.insert(gpu.temp.foregrounds, gpu.temp.foreground)
    end
end

local function flushGPU(gpu, width, height, runtime, oldBackground, oldForeground, newBackground, newForeground)
    width = width or gpu.temp.width
    height = height or gpu.temp.height

    if runtime then
        local oldSymbols, oldBackgrounds, oldForegrounds, oldWidth, oldHeight, index, newIndex = gpu.temp.symbols, gpu.temp.backgrounds, gpu.temp.foregrounds, gpu.temp.width, gpu.temp.height, 1, 1
        gpu.background = newBackground or gpu.background
        gpu.foreground = newForeground or gpu.background
        rawFlushGPU(gpu, width, height)

        for y = 1, oldHeight do
            for x = 1, oldWidth do
                gpu.temp.symbols[newIndex] = oldSymbols[index]
                gpu.temp.backgrounds[newIndex] = oldBackgrounds[index] == oldBackground and newBackground or oldBackgrounds[index]
                gpu.temp.foregrounds[newIndex] = oldForegrounds[index] == oldForeground and newForeground or oldForegrounds[index]

                index = index + 1
                newIndex = newIndex + 1
            end

            newIndex = newIndex + gpu.temp.width - oldWidth
        end

        if gpu.container then
            gpu.container:pushSignal{"screen_resized", gpu.callback.getScreen(), width, height}
        end
    else
        rawFlushGPU(gpu, width, height)
    end
end

local function getIndex(gpu, x, y)
    return gpu.temp.width * (y - 1) + x
end

local function setResolution(gpu, width, height)
    width = math.floor(width)
    height = math.floor(height)

    if width == gpu.temp.width and height == gpu.temp.height then return end

    if width >= 1 and width <= gpu.maxWidth() and height >= 1 and height <= gpu.maxHeight() then
        flushGPU(gpu, width, height, true, nil, nil, gpu.background, gpu.foreground) 

        if gpu.onResolutionChange then
            gpu.onResolutionChange(width, height)
        end
    else
        error("unsupported resolution")
    end
end

local function get(gpu, x, y)
    checkArg(1, x, "number")
    checkArg(2, y, "number")
    x = math.floor(x)
    y = math.floor(y)
    local index = gpu:getIndex(x, y)

    if not gpu.temp.symbols[index] then
        error("index out of bounds")
    end

    return gpu.temp.symbols[index], gpu.temp.foregrounds[index], gpu.temp.backgrounds[index]
end

local function set(gpu, x, y, value, vertical)
    checkArg(1, x, "number")
    checkArg(2, y, "number")
    checkArg(3, value, "string")
    x = math.floor(x)
    y = math.floor(y)

    if x >= 1 and y >= 1 and y <= gpu.temp.height then
        local index = gpu:getIndex(x, y)

        if vertical then
            for i = 1, unicode.len(value) do
                if y + i - 1 <= gpu.temp.height then
                    gpu.temp.symbols[index] = unicode.sub(value, i, i)
                    gpu.temp.backgrounds[index] = gpu.temp.background
                    gpu.temp.foregrounds[index] = gpu.temp.foreground
                end

                index = index + gpu.temp.width
            end
        else
            for i = 1, unicode.len(value) do
                if x + i - 1 <= gpu.temp.width then
                    gpu.temp.symbols[index] = unicode.sub(value, i, i)
                    gpu.temp.backgrounds[index] = gpu.temp.background
                    gpu.temp.foregrounds[index] = gpu.temp.foreground
                end

                index = index + 1
            end
        end
    end
end

local function copy(gpu, x, y, w, h, tx, ty)
    checkArg(1, x, "number")
    checkArg(2, y, "number")
    checkArg(3, w, "number")
    checkArg(4, h, "number")
    checkArg(5, tx, "number")
    checkArg(6, ty, "number")
    x = math.floor(x)
    y = math.floor(y)
    w = math.floor(w)
    h = math.floor(h)
    tx = math.floor(tx)
    ty = math.floor(ty)

    local fromIndex = gpu:getIndex(x, y)
    local toIndex = gpu:getIndex(x + tx, y + ty)

    for j = 1, h do
        if (y + ty + j - 1) >= 1 and (y + ty + j - 1) <= gpu.temp.height then
            for i = 1, w do
                if (x + tx + i - 1) and (x + tx + i - 1) <= gpu.temp.width then
                    gpu.temp.symbols[toIndex] = gpu.temp.symbols[fromIndex]
                    gpu.temp.backgrounds[toIndex] = gpu.temp.backgrounds[fromIndex]
                    gpu.temp.foregrounds[toIndex] = gpu.temp.foregrounds[fromIndex]
                end

                fromIndex = fromIndex + 1
                toIndex = toIndex + 1
            end
        end

        fromIndex = fromIndex + gpu.temp.width - w
        toIndex = toIndex + gpu.temp.width - w
    end
end

local function fill(gpu, x, y, w, h, char)
    checkArg(1, x, "number")
    checkArg(2, y, "number")
    checkArg(3, w, "number")
    checkArg(4, h, "number")
    checkArg(5, char, "string")
    x = math.floor(x)
    y = math.floor(y)
    w = math.floor(w)
    h = math.floor(h)
    local index = gpu:getIndex(x, y)
    
    for j = 1, h do
        if (y + j - 1) >= 1 and (y + j - 1) <= gpu.temp.height then
            for i = 1, w do
                if (x + i - 1) >= 1 and (x + i - 1) <= gpu.temp.width then
                    gpu.temp.symbols[index] = char
                    gpu.temp.backgrounds[index] = gpu.temp.background
                    gpu.temp.foregrounds[index] = gpu.temp.foreground
                end
                
                index = index + 1
            end
        end

        index = index + gpu.temp.width - w
    end
end

local function createGPU(address, background, foreground, maxWidth, maxHeight, screenAddress)
    local gpu
    
    gpu = box.createComponent{
        address = address,
        type = "gpu",
        flush = flushGPU,
        getIndex = getIndex,
        background = background,
        foreground = foreground,
        maxWidth = maxWidth,
        maxHeight = maxHeight,

        temp = {
            width = maxWidth,
            height = maxHeight,
            background = background,
            foreground = foreground,
            symbols = {},
            backgrounds = {},
            foregrounds = {}
        },

        callback = {
            bind = function() return true end,
            getScreen = function() return screenAddress end,
            getBackground = function() return gpu.temp.background end,
            setBackground = function(background) checkArg(1, background, "number") gpu.temp.background = background return background, gpu.temp.background end,
            getForeground = function() return gpu.temp.foreground end,
            setForeground = function(foreground) checkArg(1, foreground, "number") gpu.temp.foreground = foreground return foreground, gpu.temp.foreground end,
            getPaletteColor = function() return 0 end,
            setPaletteColor = function() return 0 end,
            maxDepth = function() return 8 end,
            getDepth = function() return 8 end,
            setDepth = function() return false end,
            maxResolution = function() return maxWidth(), maxHeight() end,
            getResolution = function() return gpu.temp.width, gpu.temp.height end,
            setResolution = function(width, height) return setResolution(gpu, width, height) end,
            getViewport = function() return gpu.temp.width, gpu.temp.height end,
            setViewport = function() return false end,
            get = function(x, y) return get(gpu, x, y) end,
            set = function(x, y, value, vertical) return set(gpu, x, y, value, vertical) end,
            copy = function(x, y, w, h, tx, ty) return copy(gpu, x, y, w, h, tx, ty) end,
            fill = function(x, y, w, h, char) return fill(gpu, x, y, w, h, char) end
        }
    }

    return gpu
end

return {
    createScreen = createScreen,
    createEEPROM = createEEPROM,
    createGPU = createGPU,
    createFilesystem = createFilesystem
}