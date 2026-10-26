local Ambient = {}
Ambient.__index = Ambient

local DB_KEY = "muffler.ambienceRecovery"
local LEGACY_KEY = "ambienceBefore"
local MODES = { normal = true, muffled = true, blocked = true }
local EPSILON = 0.0000001

local function finite(value)
    return type(value) == "number" and value == value
       and value ~= math.huge and value ~= -math.huge
end

local function same(a, b)
    return finite(a) and finite(b) and math.abs(a - b) <= EPSILON
end

local function isObject(value)
    local kind = type(value)
    return kind == "table" or kind == "userdata"
end

local function member(object, name)
    if not isObject(object) then
        return nil, "object is unavailable"
    end
    local ok, value = pcall(function()
        return object[name]
    end)
    if not ok then
        return nil, "object member read failed"
    end
    return value
end

local function copy(record)
    if type(record) ~= "table" then
        return nil
    end
    return {
        active = record.active,
        baseline = record.baseline,
        lastApplied = record.lastApplied,
        pending = record.pending,
        legacyMigration = record.legacyMigration == true,
    }
end

local function sameRecord(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    if a.active ~= b.active then
        return false
    end
    if a.active == false then
        return true
    end
    return same(a.baseline, b.baseline)
       and ((a.lastApplied == nil and b.lastApplied == nil) or same(a.lastApplied, b.lastApplied))
       and ((a.pending == nil and b.pending == nil) or same(a.pending, b.pending))
       and (a.legacyMigration == true) == (b.legacyMigration == true)
end

local function recordFitsBounds(record, bounds)
    return record.baseline >= bounds.min and record.baseline <= bounds.max
       and (record.lastApplied == nil
            or record.lastApplied >= bounds.min and record.lastApplied <= bounds.max)
       and (record.pending == nil
            or record.pending >= bounds.min and record.pending <= bounds.max)
end

function Ambient.new(option, db)
    local self = setmetatable({
        option = option,
        db = db,
        record = nil,
        mode = "normal",
        enabled = false,
        externalBaselineAdopted = false,
        lastError = nil,
        legacyPending = false,
        recoveryLoaded = false,
    }, Ambient)

    -- A saved recovery record means a previous run may have stopped between
    -- intent and completion. Recover immediately before the parent reapplies
    -- its saved mode. External volume changes are kept intact.
    local ok, loadErr = self:_loadRecovery()
    if not ok then
        self.lastError = loadErr
        self.startupRecoveryFailed = true
    end
    return self
end

function Ambient:_loadRecovery()
    if self.recoveryLoaded then
        return true
    end
    local record, err = self:_readRecord()
    if err then
        return false, err
    end
    self.record = record
    if record then
        local ok, recoveryErr = self:_recoverAtStartup()
        if not ok then
            return false, recoveryErr
        end
    else
        local ok, migrationErr = self:_migrateLegacy()
        if not ok then
            return false, migrationErr
        end
    end
    self.recoveryLoaded = true
    return true
end

function Ambient:_readLegacy()
    local getString = member(self.db, "GetString")
    if type(getString) ~= "function" then
        return nil
    end
    local ok, value = pcall(getString, self.db, LEGACY_KEY)
    if not ok then
        return nil, "legacy ambient recovery read failed"
    end
    if value == nil or value == "" then
        return nil
    end
    if type(value) ~= "string" then
        return nil, "legacy ambient recovery value is invalid"
    end
    local number = tonumber(value)
    if not finite(number) then
        return nil, "legacy ambient recovery value is invalid"
    end
    return number
end

function Ambient:_clearLegacy()
    local setString = member(self.db, "SetString")
    local getString = member(self.db, "GetString")
    if type(setString) ~= "function" or type(getString) ~= "function" then
        return false, "legacy ambient recovery cannot be cleared"
    end
    local ok, result = pcall(setString, self.db, LEGACY_KEY, "")
    if not ok or result == false then
        return false, "legacy ambient recovery clear failed"
    end
    local readOk, value = pcall(getString, self.db, LEGACY_KEY)
    if not readOk or (value ~= nil and value ~= "") then
        return false, "legacy ambient recovery clear could not be verified"
    end
    return true
end

function Ambient:_migrateLegacy()
    local legacy, readErr = self:_readLegacy()
    if readErr then
        self.legacyPending = true
        return false, readErr
    end
    if legacy == nil then
        self.legacyPending = false
        return true
    end
    self.legacyPending = true
    local bounds, boundsErr = self:_readBoundsAndValue()
    if not bounds then
        return false, boundsErr
    end
    if legacy < bounds.min or legacy > bounds.max then
        return false, "legacy ambient recovery value is outside current option bounds"
    end

    -- Save the old baseline before touching the option. The legacy format has
    -- no last-applied value, so its documented purpose is to restore the
    -- original value even when the current value is already at the old target.
    local recovery = { active = true, baseline = legacy,
                      lastApplied = bounds.value, pending = legacy,
                      legacyMigration = true }
    local saved, saveErr = self:_writeRecord(recovery)
    if not saved then
        return false, saveErr
    end
    local restored, restoreErr = self:_restore(recovery)
    if not restored then
        return false, restoreErr
    end
    local cleared, clearErr = self:_clearLegacy()
    if cleared then
        self.legacyPending = false
    end
    return cleared, clearErr
end

function Ambient:_readBoundsAndValue()
    if not isObject(self.option) then
        return nil, "ambient option is unavailable"
    end
    local ok, minimum, maximum, value = pcall(function()
        return self.option.min, self.option.max, self.option.setting
    end)
    if not ok then
        return nil, "ambient option read failed"
    end
    if not finite(minimum) or not finite(maximum) or minimum > maximum then
        return nil, "ambient option bounds are invalid"
    end
    if not finite(value) or value < minimum or value > maximum then
        return nil, "ambient option setting is invalid or outside its bounds"
    end
    return { min = minimum, max = maximum, value = value }
end

function Ambient:_readRecord()
    local getData = member(self.db, "GetStructuredData")
    if type(getData) ~= "function" then
        return nil, "recovery database is unavailable"
    end
    local ok, value = pcall(getData, self.db, DB_KEY)
    if not ok then
        return nil, "recovery database read failed"
    end
    if value == nil or (type(value) == "table" and value.active == false) then
        return nil
    end
    if type(value) ~= "table" or value.active ~= true or not finite(value.baseline) then
        return nil, "saved ambient recovery record is invalid"
    end
    if value.lastApplied ~= nil and not finite(value.lastApplied) then
        return nil, "saved ambient last-applied value is invalid"
    end
    if value.pending ~= nil and not finite(value.pending) then
        return nil, "saved ambient pending value is invalid"
    end
    return copy(value)
end

function Ambient:_writeRecord(record)
    local setData = member(self.db, "SetStructuredData")
    if type(setData) ~= "function" then
        return false, "recovery database is unavailable"
    end
    local ok, result = pcall(setData, self.db, DB_KEY, copy(record))
    if not ok or result == false then
        return false, "recovery database write failed"
    end
    local saved, err = self:_readRecord()
    if record.active == false then
        if err or saved ~= nil then
            return false, "recovery database clear could not be verified"
        end
    elseif err or not sameRecord(saved, record) then
        return false, "recovery database write could not be verified"
    end
    if record.active == false then
        self.record = nil
    else
        self.record = copy(record)
    end
    return true
end

function Ambient:_setAndVerify(value)
    local bounds, boundsErr = self:_readBoundsAndValue()
    if not bounds then
        return false, boundsErr
    end
    if not finite(value) or value < bounds.min or value > bounds.max then
        return false, "requested ambient value is outside its bounds"
    end
    local setValue = member(self.option, "Set")
    if type(setValue) ~= "function" then
        return false, "ambient Set method is unavailable"
    end
    local ok, result = pcall(setValue, self.option, value)
    if not ok or result == false then
        return false, "ambient Set failed"
    end
    local after, readErr = self:_readBoundsAndValue()
    if not after then
        return false, readErr
    end
    if not same(after.value, value) then
        return false, "ambient Set readback did not match"
    end
    return true
end

function Ambient:_isControlled(record, current)
    return (record.pending ~= nil and same(current, record.pending))
        or (record.lastApplied ~= nil and same(current, record.lastApplied))
end

function Ambient:_restore(record)
    local bounds, err = self:_readBoundsAndValue()
    if not bounds then
        return false, err
    end
    if not recordFitsBounds(record, bounds) then
        return false, "saved ambient recovery values are outside current option bounds"
    end
    local intent = { active = true, baseline = record.baseline,
                     lastApplied = bounds.value, pending = record.baseline,
                     legacyMigration = record.legacyMigration }
    local saved, saveErr = self:_writeRecord(intent)
    if not saved then
        return false, saveErr
    end
    local applied, applyErr = self:_setAndVerify(record.baseline)
    if not applied then
        return false, applyErr
    end
    local cleared, clearErr = self:_writeRecord({ active = false })
    if not cleared then
        return false, clearErr
    end
    return true
end

function Ambient:_recoverAtStartup()
    local bounds, err = self:_readBoundsAndValue()
    if not bounds then
        return false, err
    end
    local record = self.record
    if not recordFitsBounds(record, bounds) then
        return false, "saved ambient recovery value is outside current option bounds"
    end
    if record.legacyMigration then
        local restored, restoreErr = self:_restore(record)
        if not restored then
            return false, restoreErr
        end
        return self:_clearLegacy()
    end
    if same(bounds.value, record.baseline) then
        local ok, clearErr = self:_writeRecord({ active = false })
        return ok, clearErr
    end
    if self:_isControlled(record, bounds.value) then
        return self:_restore(record)
    end
    -- The player changed the setting while the plugin was stopped. Preserve
    -- that value rather than restoring the stale baseline over it.
    self.externalBaselineAdopted = true
    local ok, clearErr = self:_writeRecord({ active = false })
    return ok, clearErr
end

function Ambient:_restoreOrAdopt()
    if not self.record then
        return true
    end
    local bounds, err = self:_readBoundsAndValue()
    if not bounds then
        return false, err
    end
    local record = self.record
    if not recordFitsBounds(record, bounds) then
        return false, "saved ambient recovery values are outside current option bounds"
    end
    if record.legacyMigration then
        local restored, restoreErr = self:_restore(record)
        if not restored then
            return false, restoreErr
        end
        return self:_clearLegacy()
    end
    if same(bounds.value, record.baseline) then
        return self:_writeRecord({ active = false })
    end
    if self:_isControlled(record, bounds.value) then
        return self:_restore(record)
    end
    self.externalBaselineAdopted = true
    return self:_writeRecord({ active = false })
end

function Ambient:_activeBaseline()
    local bounds, err = self:_readBoundsAndValue()
    if not bounds then
        return nil, nil, err
    end
    if not self.record then
        return bounds.value, bounds, nil
    end
    local record = self.record
    if not recordFitsBounds(record, bounds) then
        return nil, nil, "saved ambient recovery values are outside current option bounds"
    end
    if self:_isControlled(record, bounds.value) then
        if record.pending == nil and same(record.lastApplied, bounds.value) then
            return record.baseline, bounds, nil
        end
        local settled = { active = true, baseline = record.baseline, lastApplied = bounds.value }
        local ok, saveErr = self:_writeRecord(settled)
        if not ok then
            return nil, nil, saveErr
        end
        return record.baseline, bounds, nil
    end
    if same(bounds.value, record.baseline) then
        local ok, clearErr = self:_writeRecord({ active = false })
        if not ok then
            return nil, nil, clearErr
        end
        return bounds.value, bounds, nil
    end
    -- Treat a different live volume as the player's new baseline. The next
    -- change will store it durably before touching the option again.
    self.externalBaselineAdopted = true
    local ok, clearErr = self:_writeRecord({ active = false })
    if not ok then
        return nil, nil, clearErr
    end
    return bounds.value, bounds, nil
end

function Ambient:apply(mode, enabled)
    if not MODES[mode] then
        return false, "unknown ambience mode"
    end
    if type(enabled) ~= "boolean" then
        return false, "enabled must be boolean"
    end
    if not self.recoveryLoaded then
        local loaded, loadErr = self:_loadRecovery()
        if not loaded then
            self.lastError = loadErr
            return false, loadErr
        end
        if self.startupRecoveryFailed then
            self.startupRecoveryFailed = false
            self.lastError = "startup recovery was retried; apply the requested mode again"
            return false, self.lastError
        end
    end
    if self.legacyPending then
        local migrated, migrationErr = self:_migrateLegacy()
        if not migrated then
            self.lastError = migrationErr
            return false, migrationErr
        end
    end
    self.mode, self.enabled = mode, enabled
    self.lastError = nil
    if not enabled or mode == "normal" then
        local ok, err = self:_restoreOrAdopt()
        if not ok then
            self.lastError = err
        end
        return ok, err
    end

    local baseline, bounds, err = self:_activeBaseline()
    if not baseline then
        self.lastError = err
        return false, err
    end
    local target = mode == "blocked" and bounds.min
        or (bounds.min + math.floor((baseline - bounds.min) * 0.3 + 0.5))
    if target < bounds.min or target > bounds.max then
        self.lastError = "computed ambience target is outside current option bounds"
        return false, self.lastError
    end
    if same(bounds.value, target) then
        if self.record and same(self.record.baseline, target) then
            local ok, clearErr = self:_writeRecord({ active = false })
            if not ok then
                self.lastError = clearErr
            end
            return ok, clearErr
        end
        return true
    end

    local intent = { active = true, baseline = baseline,
                     lastApplied = self.record and bounds.value or nil, pending = target }
    local saved, saveErr = self:_writeRecord(intent)
    if not saved then
        self.lastError = saveErr
        return false, saveErr
    end
    local applied, applyErr = self:_setAndVerify(target)
    if not applied then
        self.lastError = applyErr
        return false, applyErr
    end

    local finalized = { active = true, baseline = baseline, lastApplied = target }
    local committed, commitErr = self:_writeRecord(finalized)
    if not committed then
        self.lastError = commitErr
        return false, commitErr
    end
    return true
end

function Ambient:shutdown()
    if not self.recoveryLoaded then
        local loaded, loadErr = self:_loadRecovery()
        if not loaded then
            self.lastError = loadErr
            return false, loadErr
        end
    end
    if self.legacyPending then
        local migrated, migrationErr = self:_migrateLegacy()
        if not migrated then
            self.lastError = migrationErr
            return false, migrationErr
        end
    end
    self.enabled = false
    self.mode = "normal"
    local ok, err = self:_restoreOrAdopt()
    if not ok then
        self.lastError = err
    end
    return ok, err
end

function Ambient:status()
    local bounds = self:_readBoundsAndValue()
    return {
        mode = self.mode,
        enabled = self.enabled,
        available = bounds ~= nil,
        current = bounds and bounds.value or nil,
        min = bounds and bounds.min or nil,
        max = bounds and bounds.max or nil,
        recoveryPending = self.record ~= nil or self.legacyPending,
        baseline = self.record and self.record.baseline or nil,
        lastApplied = self.record and self.record.lastApplied or nil,
        externalBaselineAdopted = self.externalBaselineAdopted,
        error = self.lastError,
    }
end

return Ambient
