local values=require('data/foods')
local M={}
function M.caption(objectID,name,options)
    if type(name)~='string' or name:lower():match('^burnt ') then return end
    local eat,drink=false,false
    for _,option in pairs(options or {}) do
        if type(option)=='string' then
            local op=option:lower()
            eat=eat or op=='eat' or op=='bite' or op=='consume'
            drink=drink or op=='drink'
        end
    end
    local value=values[objectID]
    if eat then return value~=nil and tostring(value) or '?' end
    if drink and value~=nil then return tostring(value) end
end
return M
