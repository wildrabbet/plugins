local Scrollbar = {}

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function round(value)
    return math.floor(value + 0.5)
end

function Scrollbar.new(control, bounds, onPage)
    if not control or not control.area or type(control.callback) ~= "function"
        or type(bounds) ~= "table" or type(onPage) ~= "function" then
        return nil
    end
    for _, key in ipairs({ "x", "y", "width", "height", "thumb", "pixel", "arrowHeight" }) do
        if not finite(bounds[key]) then
            return nil
        end
    end
    if bounds.width <= 0 or bounds.thumb <= 0 or bounds.height <= bounds.thumb
        or bounds.pixel <= 0 or bounds.arrowHeight <= 0 then
        return nil
    end

    local area = control.area
    local originalClick = control.callback
    local self = {
        area = area,
        page = 1,
        pages = 1,
        hidden = true,
        dragging = false,
        destroyed = false,
    }
    local pending
    local startY
    local startPage
    local travel = bounds.height - bounds.thumb

    local function pointer()
        local ok, y = pcall(function()
            return Mouse.GetY() - area.xyGlobal.y
        end)
        return ok and finite(y) and y or nil
    end

    local function cancelDrag()
        self.dragging = false
        startY = nil
        startPage = nil
    end

    local function request(page)
        page = math.max(1, math.min(self.pages, page))
        if page ~= self.page then
            self.page = page
            pending = page
        end
    end

    local function follow()
        if self.destroyed or self.hidden or not self.dragging then
            return
        end
        local y = pointer()
        if y then
            request(startPage + round((y - startY) * (self.pages - 1) / travel))
        end
    end

    area:SetPos(bounds.x, bounds.y)
    area:SetSize(bounds.width, bounds.height + bounds.arrowHeight)
    control.callback = function()
        if self.destroyed or self.hidden then
            return
        end
        local y = pointer()
        -- The original down arrow still pages by one, including when Mouse
        -- is temporarily unavailable. The wheel handler remains the view's.
        if not y or y >= bounds.height then
            pending = nil
            cancelDrag()
            originalClick()
            return
        end
        if self.pages <= 1 then
            return
        end
        local top = math.floor(travel * (self.page - 1) / (self.pages - 1) / bounds.pixel)
            * bounds.pixel
        if y < top or y > top + bounds.thumb then
            request(round((y - bounds.thumb / 2) / travel * (self.pages - 1)) + 1)
        end
        startY = y
        startPage = self.page
        self.dragging = true
    end
    area:Subscribe(ui.Hook.ONHOLD, function()
        follow()
        return false
    end)
    area:Subscribe(ui.Hook.ONRELEASE, function()
        follow()
        cancelDrag()
        return false
    end)

    function self:tick()
        if self.destroyed or self.hidden then
            return
        end
        local target = pending
        pending = nil
        if target then
            onPage(target)
        end
    end

    function self:set(page, pages, hidden)
        if self.destroyed or not finite(page) or not finite(pages)
            or page ~= math.floor(page) or pages ~= math.floor(pages)
            or page < 1 or pages < page or type(hidden) ~= "boolean" then
            return false
        end
        if hidden or pages <= 1 or pages ~= self.pages or page ~= self.page then
            pending = nil
            cancelDrag()
        end
        self.page = page
        self.pages = pages
        self.hidden = hidden
        area.hidden = hidden
        return true
    end

    function self:destroy()
        if self.destroyed then
            return
        end
        self.destroyed = true
        pending = nil
        cancelDrag()
        control.callback = originalClick
        -- The view destroys its own rectangle with the parent window.
        -- Do not destroy a borrowed component or unregister a named hook.
    end

    return self
end

return Scrollbar
