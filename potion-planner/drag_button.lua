-- Click to open; hold and move to place the collapsed button.
-- Reuse the native button. A drag never activates its normal click action.
local DragButton = {}

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

function DragButton.new(button, parent, position, onMove, onClick)
    local current = { x = position.x, y = position.y }
    local gesture
    local completed
    local pendingClick = false
    local destroyed = false
    local self = {}

    local function pointer()
        local ok, x, y = pcall(function()
            return Mouse.GetX(), Mouse.GetY()
        end)
        if ok and finite(x) and finite(y) then
            return x, y
        end
    end

    local function follow()
        if not gesture then
            return
        end
        local x, y = pointer()
        if not x then
            return
        end
        local dx = x - gesture.mouseX
        local dy = y - gesture.mouseY
        if dx * dx + dy * dy >= 16 then
            gesture.moved = true
        end
        if gesture.moved then
            local width = parent.width or 1920
            local height = parent.height or 1080
            current.x = math.floor(math.max(0, math.min(width - 142, gesture.x + dx)))
            current.y = math.floor(math.max(0, math.min(height - 30, gesture.y + dy)))
            button:SetPos(current.x, current.y)
        end
    end

    local function finish()
        if gesture then
            follow()
            completed = { moved = gesture.moved }
            gesture = nil
            if completed.moved then
                onMove(current.x, current.y)
            end
        end
        if not completed or not completed.moved then
            pendingClick = true
        end
    end

    -- ONRELEASE avoids activating the button at the start of a drag. Component
    -- release and button activation can arrive in either order; finish is
    -- idempotent within that gesture, and activation is deferred to Logic.
    -- Retain the completed drag until the next press so delayed activation
    -- cannot open the window after the release frame has already finished.
    button.mode = ui.TriggerMode.ONRELEASE
    button:Subscribe(ui.Hook.ONCLICK, function()
        if destroyed or button.hidden then
            return false
        end
        pendingClick = false
        completed = nil
        local x, y = pointer()
        if x then
            gesture = { mouseX = x, mouseY = y, x = current.x, y = current.y, moved = false }
        end
        return false
    end)
    button:Subscribe(ui.Hook.ONHOLD, function()
        if not destroyed and not button.hidden then
            follow()
        end
        return false
    end)
    button:Subscribe(ui.Hook.ONRELEASE, function()
        if not destroyed and not button.hidden then
            finish()
        end
        return false
    end)
    button:Subscribe(ui.Hook.ONBUTTONPRESSED, function()
        if not destroyed and not button.hidden then
            finish()
        end
    end)

    function self:tick()
        if destroyed then
            return
        end
        if button.hidden then
            gesture = nil
            completed = nil
            pendingClick = false
            return
        end
        follow()
        local activate = pendingClick
        pendingClick = false
        if activate then
            onClick()
        end
    end

    function self:setPosition(x, y)
        gesture = nil
        completed = nil
        pendingClick = false
        current.x = x
        current.y = y
        button:SetPos(x, y)
    end

    function self:destroy()
        destroyed = true
        gesture = nil
        completed = nil
        pendingClick = false
        -- The controller owns the button and destroys it after this helper.
    end

    return self
end

return DragButton
