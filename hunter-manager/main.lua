-- Hunter Manager 0.1.10
-- Keep track of your traps with clear highlights and colours for their different states.

local HT=require('hunter_traps')
local Types=require('hunter_types')
local catalogue=require('hunter_catalogue')
local tracker=HT.new()
local types=Types.new(catalogue)
local captures=require('hunter_catches').new(types)
local session=require('hunter_session').new(types,tracker)
local observer=require('observe').new(types,session)
local ground=require('ground').new(types,tracker)
local pickup=require('pickup').new(types,tracker,ground)
local renderer=require('render').new()
local now,tick,stopped,lastError=0,0,false,nil
local settingsUI,settingsDirty

local saved=PersistentDB:GetStructuredData('settings')
if type(saved)~='table' then saved={} end
if saved.theme then tracker:setTheme(saved.theme) end
if type(saved.colors)=='table' then
  for _,role in ipairs(HT.ROLES) do tracker:setColor(role,saved.colors[role]) end
end
-- Upgrade the old default purple only. Personal colours and accessibility palettes stay as chosen.
local oldCollapse=type(saved.colors)=='table' and saved.colors.collapsed
local migrateColour=saved.colourVersion==nil and (saved.theme==nil or saved.theme=='dusk') and oldCollapse=='D8B4FE'
if migrateColour then tracker:setColor('collapsed','FF4D40') end
tracker.opts.blink=saved.blink==true
tracker.opts.countdown=saved.countdown==true
tracker:setTimes(saved.times or {})
local function save()
  settingsDirty=true
  local colors={}
  for _,role in ipairs(HT.ROLES) do colors[role]=HT.colorText(tracker.colors[role]) end
  local times={}
  for _,key in ipairs({'catch_secs','warn_secs','danger_secs','flash_secs'}) do times[key]=tracker.opts[key] end
  local ok,result=pcall(function()
    return PersistentDB:SetStructuredData('settings',{
      theme=tracker.theme,colors=colors,times=times,blink=tracker.opts.blink,
      countdown=tracker.opts.countdown,colourVersion=2,
    })
  end)
  if ok and result~=false then
    settingsDirty=false
    if settingsUI then settingsUI.saved() end
    return true
  end
  return false
end
if migrateColour then save() end
local function tile()
  local me=Player.GetEntity()
  if not me then return nil end
  local p=me.coordGrid
  return {x=p.x,z=p.z,plane=p.level},p
end
local function guard(fn)
  return function(event)
    if stopped then return end
    local ok,problem=pcall(fn,event)
    if not ok and problem~=lastError then log('Hunter Manager: '..tostring(problem)) end
    lastError=ok and nil or problem
  end
end

local menu=require('menu').new(session,tile,function() return now end,observer)
Event.SettingsLayerReady.Subscribe('hunterSettings',guard(function(event)
  if settingsUI then settingsUI.stop() end
  settingsUI=require('settings').new(event.component,tracker,session,{roles=HT.ROLES,save=save,colourText=HT.colorText})
end))
Event.GameStateChanged.Subscribe('hunterContext',guard(function()
  session.context=(session.context or 0)+1
  session.clear();session.rows={};session.seen={};captures.pending=nil;pickup.clear();ground.clear();renderer.hide()
  session.limited=false
end))

Event.MiniMenuEntrySelected.Subscribe('hunterPlacement',guard(function(event)
  local entry=event.entry
  local p=tile()
  if not p then return end
  local verb=(entry.verbText or ''):lower()
  pickup.tick(now,p)
  if entry.actionEntryType~=MiniMenuEntryType.OBJ or verb~='take' then pickup.clear() end
  if entry.actionEntryType~=MiniMenuEntryType.NPC or not (verb:find('catch',1,true) or verb=='capture') then captures.pending=nil end
  if entry.actionEntryType==MiniMenuEntryType.INTERFACE then
    local data=entry.componentData
    local item=data and data.objConfig and types.item(data.objConfig.id)
    if item and Types.FAMILIES[item.family] and (verb=='lay' or verb=='activate' or verb=='place') then
      session.intent(item.family,p,now)
    end
  elseif entry.actionEntryType==MiniMenuEntryType.OBJ then
    local data=entry.objData
    if verb=='take' then pickup.take(data,now,p)
    elseif verb=='lay' then
      local item=data and data.config and types.item(data.config.id)
      local stack=data and data.entity
      if item and Types.FAMILIES[item.family] and stack and stack.isValid then
        local t=stack.coordGrid
        session.intent(item.family,p,now,{x=t.x,z=t.z,plane=t.level})
      end
    end
  elseif entry.actionEntryType==MiniMenuEntryType.LOC and (verb=='build' or verb=='set-trap' or verb=='trap' or verb=='set' or verb=='lay' or verb=='reset' or verb=='rebuild') then
    local data=entry.locData
    local target=data and data.coordGridX and {x=data.coordGridX,z=data.coordGridZ,plane=p.plane}
    local config=data and data.config
    local info=config and types.classify({id=config.id,name=config.name,ops=config.opNames})
    local family=info and info.family
    if family and target then session.intent(family,p,now,target) end
  elseif entry.actionEntryType==MiniMenuEntryType.NPC and (verb:find('catch',1,true) or verb=='capture') then
    local data=entry.npcData
    local npc=data and data.entity
    if npc and npc.isValid then captures.intent(npc.displayName,npc.configID,now) end
  end
end))
Event.ChatMessage.Subscribe('hunterOwnChat',guard(function(event)
  if event.chatType~=ChatType.GENERAL and event.chatType~=ChatType.SPAM then return end
  if event.senderNameUnfiltered and event.senderNameUnfiltered~='' then return end
  local p=tile()
  if not p then return end
  local before=tracker.pend
  tracker:chat(event.chatMessage,now,p)
  captures.chat(event.chatMessage,now)
  if tracker.pend~=before and not session.pending then session.intent(nil,p,now) end
end))
Event.ServerLogic.Subscribe('hunterScan',guard(function()
  now=now+600;tick=tick+1
  if tick%2~=0 then return end
  if settingsDirty then save() end
  local p,grid=tile()
  if not p or not World.IsAvailable() then ground.clear();renderer.hide();return end
  local rows,limited=observer.near(grid)
  local deferred=ground.before(rows,now,p,limited)
  session.scan(rows,now,p,limited,deferred)
  ground.after(now,p)
  pickup.tick(now,p)
  local view={}
  for _,mark in ipairs(tracker:view(now,p)) do
    if mark.plane==p.plane and math.max(math.abs(mark.x-p.x),math.abs(mark.z-p.z))<=session.range then
      view[#view+1]=mark
    end
  end
  renderer.draw(view,now)
end))
function PluginShutdown()
  stopped=true
  Event.MiniMenuEntrySelected.Unsubscribe('hunterPlacement')
  Event.ChatMessage.Unsubscribe('hunterOwnChat')
  Event.ServerLogic.Unsubscribe('hunterScan')
  Event.SettingsLayerReady.Unsubscribe('hunterSettings')
  Event.GameStateChanged.Unsubscribe('hunterContext')
  menu.stop();pickup.clear();ground.clear();save();renderer.stop();if settingsUI then settingsUI.stop() end
end
log('Hunter Manager 0.1.10: overlays only; stale pickups and unreadable equipment are handled safely. Colours are in the Plugin Hub cog.')
