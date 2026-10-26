local M={}
local marks={S={{0,0},{2,0},{2,1},{0,1},{0,2},{2,2}},C={{2,0},{0,0},{0,2},{2,2}},
  R={{0,2},{0,0},{2,0},{2,1},{0,1},{2,2}},U={{0,0},{0,2},{2,2},{2,0}}}
local function geometry(letter)
  local positions,colours,lines={},{},{}
  local function point(x,z,colour)
    local index=#positions
    positions[index+1]=Vector3.new(x,0,z);colours[index+1]=colour
    return index
  end
  -- Solid edge and letter, with a separate low-opacity fill that leaves the item visible.
  local corners={{-220,-220},{220,-220},{220,220},{-220,220}}
  for _,p in ipairs(corners) do point(p[1],p[2],0xFFFFFFFF) end
  for i=0,3 do lines[#lines+1]=i;lines[#lines+1]=(i+1)%4 end
  for _,p in ipairs(corners) do point(p[1],p[2],0xFFFFFF28) end
  local previous
  for _,p in ipairs(marks[letter]) do
    local current=point((p[1]-1)*90,(p[2]-1)*90,0xFFFFFFFF)
    if previous then lines[#lines+1]=previous;lines[#lines+1]=current end
    previous=current
  end
  local data=ShapeData.new()
  data.positions,data.rgba,data.lines,data.tris=positions,colours,lines,{4,5,6,4,6,7}
  return data
end
function M.new()
  local shapes,entities={},{}
  for letter in pairs(marks) do shapes[letter]=geometry(letter) end
  local reported=false
  local R={}
  function R.hide() for _,slot in pairs(entities) do slot.entity.visible=false end end
  function R.draw(view,now)
    local seen={}
    for i=1,math.min(#view,64) do
      local t=view[i]
      local key=t.plane..':'..t.x..':'..t.z
      seen[key]=true
      local slot=entities[key]
      if not slot then
        local entity=assert(ShapeList.CreateEntity('hunterTrap-'..key),'Could not create Hunter tile mark')
        entity.coordGrid=CoordGrid.new(t.plane,math.floor(t.x/64),math.floor(t.z/64),t.x%64,t.z%64)
        entity.alignType=ShapeEntityAlignType.MODEL
        entity.heightOffset=24;entity.ignoreDepth=false;entity.lineWidth=3
        entity:SetDrawDistance(24*512)
        slot={entity=entity};entities[key]=slot
      end
      local entity=slot.entity
      local letter=t.state=='caught' and 'C' or t.state=='collapsed' and 'R' or t.state=='set' and 'S' or 'U'
      -- Rebuilding a tile entity every scan would make it flicker while the client rebuilds its visual.
      if slot.letter~=letter or not entity.hasData then entity:SetShapeData(shapes[letter]);slot.letter=letter end
      local c=t.color
      entity.colour=math.floor(c[1]*255+.5)*16777216+math.floor(c[2]*255+.5)*65536+math.floor(c[3]*255+.5)*256+255
      entity.visible=entity.hasData==true and (not t.flash or math.floor(now/1200)%2==0)
      if not reported then
        log('Hunter draw: tile entity '..key..' data='..tostring(entity.hasData)..' visible='..tostring(entity.visible))
        reported=true
      end
    end
    for key,slot in pairs(entities) do if not seen[key] then slot.entity:Destroy();entities[key]=nil end end
  end
  function R.stop() for _,slot in pairs(entities) do slot.entity:Destroy() end;entities={} end
  return R
end
return M
