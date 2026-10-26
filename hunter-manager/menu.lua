-- Local ownership declaration on the exact trap selected. Never invokes a native trap action.
local M={}
function M.new(session,tile,clock,observer)
  local stopped,lastError=false,nil
  local function key(r) return r.x..','..r.z..','..r.plane end
  local function label(entry) return entry.overrideText and entry.overrideText~='' and entry.overrideText or entry.fullText end
  local function current(target)
    local p=tile()
    if not p or not World.IsAvailable() or p.plane~=target.plane then return end
    if math.max(math.abs(p.x-target.x),math.abs(p.z-target.z))>20 then return end
    local row=observer.at(target,target.sourceID)
    if row and row.id==target.id then return row end
  end
  local function choose(target,remove,context)
    if stopped or context~=(session.context or 0) then return end
    local row=current(target)
    if not row then return end
    if remove then
      local owned=session.tracker.traps[key(row)]
      if owned and owned.family==row.family then session.tracker.traps[key(row)]=nil end
    else session.tracker:observe(row,clock(),true) end
  end
  local function ready(event)
    if stopped then return end
    local menu=event.miniMenu
    local count=menu.entryCount
    if count<2 or count>64 then return end
    local reverse=menu.entries[1].actionType==MiniMenuActionType.CANCEL
    if not reverse and menu.entries[count].actionType~=MiniMenuActionType.CANCEL then return end
    local target,anchor
    local p=tile()
    if not p or not World.IsAvailable() then return end
    for i=1,count do
      local entry=menu.entries[i]
      local data=entry.actionEntryType==MiniMenuEntryType.LOC and entry.locData
      if data and data.config and entry.actionVerbType==MiniMenuActionVerbType.EXAMINE then
        local r=observer.at({x=data.coordGridX,z=data.coordGridZ,plane=p.plane},data.config.id)
        if r and math.max(math.abs(p.x-r.x),math.abs(p.z-r.z))<=20 then target,anchor=r,entry end
      end
      if target then break end
    end
    if not target then return end
    local owned=session.tracker.traps[key(target)]
    local remove=owned~=nil and owned.family==target.family
    local text=remove and 'Untrack this trap' or 'Track this trap'
    local anchorText=label(anchor)
    menu:Swap(1,1) -- Fail before Add if this client does not support reordering.
    menu:Add(text,choose,target,remove,session.context or 0)
    local added,beside
    for i=1,count+1 do
      local entry=menu.entries[i]
      if entry.actionEntryType==MiniMenuEntryType.PLUGIN and label(entry)==text then added=i end
      if entry==anchor or (label(entry)==anchorText and entry.locData and entry.locData.config
        and entry.locData.config.id==target.sourceID and entry.locData.coordGridX==target.x and entry.locData.coordGridZ==target.z) then beside=i end
    end
    if not added or not beside then return end
    local destination=beside
    if not reverse and added<beside then destination=beside-1 end
    if reverse and added>beside then destination=beside+1 end
    local step=added<destination and 1 or -1
    for i=added,destination-step,step do menu:Swap(i,i+step) end
  end
  Event.MiniMenuReady.Subscribe('hunterMarks',function(event)
    local ok,problem=pcall(ready,event)
    if not ok and problem~=lastError then log('Hunter menu: '..tostring(problem)) end
    lastError=ok and nil or problem
  end)
  return {stop=function() stopped=true;Event.MiniMenuReady.Unsubscribe('hunterMarks') end}
end
return M
