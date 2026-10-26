-- Client-side Hunter classification from visible names, actions and the public Wiki catalogue. No game calls.
-- A creature name identifies content, never who owns it; unfamiliar changes remain unknown instead of becoming catches.
local M = {}
M.FAMILIES = {bird='Bird snare', box='Box trap', clockwork='Clockwork box trap', rabbit='Rabbit snare',
  net='Net trap', deadfall='Deadfall', pitfall='Pitfall', magic='Magic box', plant='Marasamaw plant',
  tortle='Tortle trap', protean='Protean trap', birdhouse='Birdhouse', big_game='Large Hunter trap'}

local function plain(s)
  return type(s)=='string' and s:sub(1,256):gsub('<[^>]*>',''):lower():gsub('%s+',' '):gsub('^%s+',''):gsub('%s+$','') or ''
end

function M.family(name)
  local n=plain(name)
  for _,pair in ipairs({{'giant box','big_game'},{'giant deadfall','big_game'},{'spike trap','big_game'},
    {'log trap','big_game'},{'clockwork','clockwork'},{'birdhouse','birdhouse'},{'bird house','birdhouse'},
    {'marasamaw','plant'},{'tortle trap','tortle'},{'protean','protean'},{'bird snare','bird'},
    {'rabbit snare','rabbit'},{'magic box','magic'},{'deadfall','deadfall'},{'net trap','net'},
    {'young tree','net'},{'spiked pit','pitfall'},{'collapsed trap','pitfall'},
    {'box trap','box'},{'shaking box','box'},{'shaking crate','box'}}) do
    if n:find(pair[1],1,true) then return pair[2] end
  end
end

function M.new(catalogue)
  local aliases={}
  local function alias(name,title)
    name=plain(name)
    if aliases[name]==nil then aliases[name]=title elseif aliases[name]~=title then aliases[name]=false end
  end
  for title,creature in pairs(catalogue.creatures) do
    alias(title:gsub(' %(Hunter%)',''),title)
    for _,name in ipairs(creature.names) do alias(name,title) end
  end
  local C={}
  function C.species(name,npcID)
    local n=plain(name)
    local value=aliases[n]
    if value==nil and n:sub(-1)=='s' then value=aliases[n:sub(1,-2)] end
    return catalogue.npc_ids[npcID] or value or nil
  end
  function C.kind(species,kind)
    local record=catalogue.creatures[species]
    if kind=='creature' then return true end
    local name=plain(species)
    for _,group in ipairs({'impling','moth','whirligig','kebbit','jadinko','chinchompa','tortle'}) do
      if name:find(group,1,true) then return kind==group end
    end
    return record and plain(species..' '..record.method):find(kind,1,true)~=nil
  end
  function C.item(id) return catalogue.items[id] end
  function C.classify(row,hint)
    local name=plain(row.name)
    local record=catalogue.scenery[row.id]
    local species=aliases[name] or nil
    local family=M.family(name)
    if not family and species then family=M.family(catalogue.creatures[species].method) end
    if not family and record and plain(record.name)==name and M.FAMILIES[record.family] then family=record.family end
    if not family and hint and (name=='trap' or name=='snare') then family=hint end
    if not M.FAMILIES[family] then return nil end
    local ops={}
    local n=0
    for _,op in pairs(row.ops or {}) do
      n=n+1; if n>10 then break end
      ops[plain(op)]=true
    end
    local state=record and record.family==family and record.state or 'unknown'
    local detail=record and record.family==family and record.detail or nil
    if family=='birdhouse' then
      -- Empty is available even while filling: only a published full-state ID proves the birdhouse is ready.
      if not record or record.family~=family then state='unknown' end
    elseif ops.check or ops.retrieve or ops.collect then state='caught'
    elseif ops.lay or ops.rebuild or ops.reset then state='collapsed'
    elseif name:find('wilted',1,true) or name:find('failed',1,true) or name:find('broken',1,true) then state='collapsed'
    elseif family=='pitfall' and name=='collapsed trap' then
      state=record and record.family==family and record.state or 'unknown'
    elseif state=='unknown' then
      if ops.dismantle or ops.investigate or ops.deactivate or ops.pick then state='set'
      elseif ops.build or ops.trap or name=='young tree' then state='idle' end
    end
    return {family=family,state=state,species=species,label=M.FAMILIES[family],detail=detail}
  end
  return C
end
return M
