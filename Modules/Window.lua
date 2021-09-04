local GUI = require("GUI")
local screen = require("Screen")
local text = require("Text")

local function windowCheck(window, x, y)
    local child
    for i = #window.children, 1, -1 do
        child = window.children[i]
        
        if
            not child.hidden and
            not child.disabled and
            child:isPointInside(x, y)
        then
            if child.children then
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

local function drawWindow(window)
    window.transparencyEnabled = GUI.WINDOW_SHADOW_TRANSPARENCY and true or false
    window:overrideDraw()

    if window.drawShadow and not window.maximized then
        GUI.drawShadow(window.x, window.y, window.width, window.height - (window.titleBar.hidden and 1 or 0), GUI.WINDOW_SHADOW_TRANSPARENCY, true)
    end

    return window
end

local function drawTitleBar(object)
    local trimmedText, xText = object.text

    if unicode.len(object.text) >= object.width - 7 then
        trimmedText = text.limit(object.text, object.width - 8)
    end
        
    xText = math.floor(object.width / 2 - unicode.len(trimmedText) / 2)
    if object.parent.transparencyEnabled then
        screen.drawRectangle(object.x, object.y, object.width, 1, object.colors.background, 0x0, " ", object.colors.transparency)
    else
        screen.drawRectangle(object.x, object.y, object.width, 1, object.colors.background, 0x0, " ")
    end
    screen.drawText(xText + 1 < 7 and object.x + 7 or object.x + xText - 1, object.y, object.colors.text, trimmedText)
    object:overrideDraw()
end

local function createWindow(x, y, width, height, shadow, title, titleTransparency, titleBackground, titleForeground)
    local window = GUI.container(x, y, width, height + 1)

    window.passScreenEvents = false
    window.resize = windowResize
    window.maximize = GUI.windowMaximize
    window.minimize = GUI.windowMinimize
    window.focus = GUI.windowFocus
    window.eventHandler = windowEventHandler
    window.movingEnabled = true
    window.drawShadow = shadow

    window.titleBar = window:addChild(GUI.container(1, 1, window.width, 1))
    window.titleBar.colors = {
        background = titleBackground,
        text = titleForeground,
        transparency = titleTransparency
    }

    window.titleBar.text = title
    window.titleBar.passScreenEvents = false
    window.titleBar.close = window.titleBar:addChild(GUI.button(1, 1, 1, 1, nil, 0xFF4940, nil, 0x992400, "⬤"))
    window.titleBar.minimize = window.titleBar:addChild(GUI.button(3, 1, 1, 1, nil, 0xFFB640, nil, 0x996D00, "⬤"))
    window.titleBar.maximize = window.titleBar:addChild(GUI.button(5, 1, 1, 1, nil, 0x00B640, nil, 0x006D40, "⬤"))

    window.titleBar.close.onTouch = function()
        window:remove()
    end
    window.titleBar.minimize.onTouch = function()
        window:minimize()
    end
    window.titleBar.maximize.onTouch = function()
        window:maximize()
    end

    window.overrideDraw = window.draw
    window.draw = drawWindow
    window.titleBar.overrideDraw = window.titleBar.draw
    window.titleBar.draw = drawTitleBar

    window.titleBar.hide = function()
        if not window.maximized then
            window.localY = window.localY + 1
        end

        window.titleBar.hidden = true
        window.titleBar.passScreenEvents = true
    end

    window.titleBar.unhide = function()
        if not window.maximized then
            window.localY = window.localY - 1
        end

        window.titleBar.hidden = false
        window.titleBar.passScreenEvents = false
    end

    return window
end

return {
    create = createWindow
}
