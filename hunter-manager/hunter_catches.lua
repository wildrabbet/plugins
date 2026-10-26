-- Client-side capture log for netting, barehanding and other Hunter methods without a persistent trap.
-- Only the player's own success text confirms a capture; NPC disappearance, item gains and XP never prove one.
local M={}
function M.new(types)
  local C={counts={},total=0}
  function C.intent(name,id,now)
    local species=types.species(name,id)
    C.pending=species and {species=species,at=now} or nil
  end
  function C.chat(text,now)
    if type(text)~='string' then return false end
    local line=text:sub(1,1024):gsub('<[^>]*>',''):lower()
    local prey=line:match('^you catch (.+)') or line:match('^you caught (.+)')
      or line:match('^you successfully catch (.+)') or line:match('^you have caught (.+)')
    if not prey then return false end
    prey=prey:gsub('[.!].*$',''):gsub(' barehanded$',''):gsub(' with your bare hands$','')
    local quantity=tonumber(prey:match('^(%d+)%s+')) or 1
    if quantity<1 or quantity>1000 then return false end
    prey=prey:gsub('^%d+%s+',''):gsub('^an?%s+',''):gsub('^the%s+','')
    local species=types.species(prey)
    -- Generic success text can identify the last creature the player explicitly chose, for ten seconds.
    if not species and C.pending and now-C.pending.at<=10000 then
      for _,kind in ipairs({'impling','butterfly','moth','whirligig','kebbit','jadinko','chinchompa','tortle','creature'}) do
        if (prey==kind or prey==kind..'s') and types.kind(C.pending.species,kind) then species=C.pending.species;break end
      end
    end
    if not species then return false end
    C.counts[species]=math.min(1000000,(C.counts[species] or 0)+quantity)
    C.total=math.min(1000000,C.total+quantity)
    C.last,C.pending=species,nil
    return true
  end
  return C
end
return M
