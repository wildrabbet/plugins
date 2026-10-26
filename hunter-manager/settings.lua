-- Optional Plugin Hub settings. Nothing is attached to the gameplay layer.
local M={}
function M.new(parent,tracker,session,actions)
  local panel=ui.Layer.new(parent)
  panel:SetPos(8,8);panel:SetSize(360,350)
  local stopped=false
  local font=id.Font.MUSEO_SANS_15PT_REGULAR
  local function text(content,y)
    local t=ui.Text.new(panel)
    t:SetPos(0,y);t:SetSize(350,40);t.font=font;t.content=content;t.clickthrough=true
    return t
  end
  text('Hunter Manager: world overlays only',0)
  local status=text('Click a state to cycle colours, or enter RGB then Apply.',25)
  local waitingMessage
  local function persist(message)
    if actions.save() then
      waitingMessage=nil
      status.content=message
    else
      waitingMessage=message
      status.content='Changes applied; waiting to save settings.'
    end
  end
  local function button(label,x,y,w,fn)
    local b=ui.Button.new(panel)
    b:SetPos(x,y);b:SetSize(w,24);b.label=label;b.text.font=font;b.stylesheetID=id.StyleSheet.BUTTON_DEFAULT
    b:Subscribe(ui.Hook.ONBUTTONPRESSED,function() if not stopped then fn() end end)
    return b
  end
  local function input(x,y,w,mode,length)
    local field=ui.InputField.new(panel)
    field:SetPos(x,y);field:SetSize(w,25);field.stylesheetID=id.StyleSheet.INPUT_DEFAULT
    field:Setup(ui.TextContentVisibilityMode.VISIBLE,mode,length);field.text.font=font
    return field
  end
  local palettes={'dusk','red_green','blue_yellow','high_contrast','classic'}
  local palette,blink,reminder
  local stateFields={}
  local extraRoles={'warn','danger'} -- All other visible state colours have a direct row below.
  local extraLabels={'Low time','Urgent'}
  local field=input(110,215,105,ui.InputFieldFilterMode.ALPHANUMERIC,6)
  local role,roleButton=1
  local function refreshColour()
    field.content=actions.colourText(tracker.colors[extraRoles[role]])
    for key,control in pairs(stateFields) do control.content=actions.colourText(tracker.colors[key]) end
  end
  palette=button(tracker.theme,0,60,105,function()
    for i,name in ipairs(palettes) do if name==tracker.theme then tracker:setTheme(palettes[i%#palettes+1]);break end end
    palette.label=tracker.theme
    refreshColour()
    persist('Palette saved.')
  end)
  blink=button(tracker.opts.blink and 'Blink on' or 'Blink off',110,60,105,function()
    tracker.opts.blink=not tracker.opts.blink
    blink.label=tracker.opts.blink and 'Blink on' or 'Blink off'
    persist('Blink preference saved.')
  end)
  reminder=button(tracker.opts.countdown and 'Reminder on' or 'Reminder off',220,60,125,function()
    tracker.opts.countdown=not tracker.opts.countdown
    reminder.label=tracker.opts.countdown and 'Reminder on' or 'Reminder off'
    persist('Reminder preference saved.')
  end)
  local quick={'68A9FF','5CE0C3','FF4D40','F1C66A','B68CFF','FFFFFF','CBD5E1'}
  for i,entry in ipairs({{'set','Set'},{'caught','Caught'},{'collapsed','Collapsed'},{'unknown','Unknown'}}) do
    local key,label=entry[1],entry[2]
    local y=91+(i-1)*31
    local control=input(110,y,105,ui.InputFieldFilterMode.ALPHANUMERIC,6)
    stateFields[key]=control
    button(label,0,y,105,function()
      local current,index=actions.colourText(tracker.colors[key]),0
      for n,colour in ipairs(quick) do if current==colour then index=n;break end end
      tracker:setColor(key,quick[index%#quick+1])
      refreshColour()
      persist(label..' colour saved.')
    end)
    button('Apply '..label,220,y,125,function()
      if tracker:setColor(key,control.content) then
        refreshColour()
        persist(label..' colour saved.')
      else status.content='Enter six RGB colour digits, for example FF4D40.' end
    end)
  end
  roleButton=button(extraLabels[role],0,215,105,function()
    role=role%#extraRoles+1;roleButton.label=extraLabels[role];refreshColour()
  end)
  refreshColour()
  button('Apply colour',220,215,125,function()
    if tracker:setColor(extraRoles[role],field.content) then
      persist('Colour saved.')
    else status.content='Enter six RGB colour digits.' end
  end)
  local seconds=input(0,246,215,ui.InputFieldFilterMode.NONE,24)
  seconds.content=tracker.opts.catch_secs..' '..tracker.opts.warn_secs..' '..tracker.opts.danger_secs..' '..tracker.opts.flash_secs
  button('Apply seconds',220,246,125,function()
    local a,b,c,d=seconds.content:match('^(%d+)%s+(%d+)%s+(%d+)%s+(%d+)$')
    if a and tracker:setTimes({catch_secs=a,warn_secs=b,danger_secs=c,flash_secs=d}) then
      persist('Reminder seconds saved.')
    else status.content='Seconds: reminder >= low >= urgent >= blink.' end
  end)
  text('Seconds: reminder / low / urgent / blink.\nPersonal reminder; not an escape prediction.',277)
  button('Clear marks',0,321,105,function() session.clear();status.content='Local trap marks cleared.' end)
  local function saved()
    if waitingMessage and not stopped then
      pcall(function() status.content=waitingMessage end)
      waitingMessage=nil
    end
  end
  return {saved=saved,stop=function() stopped=true;pcall(function() panel:Destroy() end) end}
end
return M
