-- ArcWeakAuras Full 2.0.0 (https://github.com/0xjc/ArcWeakAuras)
do
    local _aura_env, _C_Timer_After, _error, _GetTime, _max, _random, _WeakAuras
    =      aura_env,  C_Timer.After,  error,  GetTime,  max,  random,  WeakAuras
    local _WeakAuras_ScanEvents, _WeakAuras_IsPaused
    =     _WeakAuras.ScanEvents, _WeakAuras.IsPaused

    -- Initialize the TSU dispatcher.
    -- * The WeakAura must use a single TSU Event trigger with the stub:
    --   `function(...) return aura_env:TSU(...) end`
    -- * `tsuMode` can be either "basic" or "multi".
    --     * "basic": For WeakAuras that don't need multiple clones. Uses `aura_env` itself as the primary TSU state.
    --                Event handlers should set `self.show`, `self.changed`, etc.
    --     * "multi": For WeakAuras that need multiple clones. Provides `self.allStates`.
    --                Event handlers should manipulate `self.allStates` and return whether any state was changed.
    function _aura_env:InitArcTSU(tsuMode)
        if tsuMode == "basic" then
            self.TSU = function(_self, allStates, event, ...)
                local handler = _self[event]
                if handler then
                    handler(_self, ...)
                    allStates[""] = _self
                    return _self.changed
                end
            end
        elseif tsuMode == "multi" then
            self.TSU = function(_self, allStates, event, ...)
                local handler = _self[event]
                if handler then
                    _self.allStates = allStates
                    return handler(_self, ...)
                end
            end
        else
            _error("invalid tsuMode")
        end
    end

    -- Initialize the event framework needed for periodic and timer callbacks.
    -- The trigger event list must include an event starting with "ARC_EVENT_" followed by a random suffix.
    -- The suffix should ideally be unique across WeakAuras; otherwise, a small performance overhead is incurred.
    function _aura_env:InitArcEvents()
        local oldArcEvents, arcEventUnderlying, data, trigger
        -- Cancel old timer callbacks after re-initialization.
        oldArcEvents = self.region.arcEvents
        if oldArcEvents then
            for arcEventId, ctx in pairs(oldArcEvents) do
                ctx[1] = nil
            end
            self.region.arcEvents = nil
        end
        -- Auto-detect the event name. Hopefully WeakAuras doesn't break this in the future.
        data = _WeakAuras.GetData(self.id)
        for _, triggerData in ipairs(data.triggers) do
            trigger = triggerData.trigger
            if trigger and trigger.type == "custom" and trigger.events and (trigger.check ~= "update" or trigger.custom_type == "event") then
                arcEventUnderlying = trigger.events:match("ARC_EVENT_%w+")
                if arcEventUnderlying then
                    break
                end
            end
        end
        self.arcEventUnderlying = assert(arcEventUnderlying, "missing ARC_EVENT_")
        self.arcEvents = {}
        -- Use `self.region` as a persistent store to allow cleanup after re-initialization.
        self.region.arcEvents = self.arcEvents
        -- Filter out any cross-triggering, then dispatch the underlying event to logical `arcEventId` handlers.
        self[arcEventUnderlying] = function(_self, id, arcEventId, ...)
            if id == _self.id then
                local handler = _self[arcEventId]
                if handler then
                    return handler(_self, ...)
                else
                    _error("missing handler for arcEventId: "..tostring(arcEventId))
                end
            end
        end
    end

    local _MISSING_INIT_ARC_EVENTS_CALL = "missing InitArcEvents() call"

    -- Schedule a repeating periodic callback.
    -- `aura_env[arcEventId](aura_env)` will be invoked approximately every `interval +/- noise/2` seconds.
    -- Does not fire immediately. Replaces existing callback if called again for the same `arcEventId`.
    -- `noise` helps stagger callbacks for different WeakAuras. Defaults to `min(0.05, 0.05 * interval)`.
    function _aura_env:SetArcPeriodic(arcEventId, interval, noise)
        local arcEventUnderlying, arcEvents, id, ctx, seqnum, callback = self.arcEventUnderlying, self.arcEvents
        if not arcEvents then
            _error(_MISSING_INIT_ARC_EVENTS_CALL)
        end
        noise = noise or min(0.05, 0.05 * interval)
        id = self.id
        ctx = arcEvents[arcEventId] or {0}  -- seqnum
        arcEvents[arcEventId] = ctx
        seqnum = ctx[1] + 1
        ctx[1] = seqnum
        callback = function()
            if ctx[1] == seqnum then
                if not _WeakAuras_IsPaused() then
                    _WeakAuras_ScanEvents(arcEventUnderlying, id, arcEventId)
                end
                _C_Timer_After(interval + (_random() - 0.5) * noise, callback)
            end
        end
        _C_Timer_After(interval + (_random() - 0.5) * noise, callback)
    end

    -- Schedule a timed callback.
    -- `aura_env[arcEventId](aura_env, arg1, arg2, arg3)` will be invoked at approximately `scheduledTime`.
    -- Replaces pending callback if called again for the same `arcEventId`.
    -- If `scheduledTime == nil`, cancels any pending callback without scheduling a new one.
    function _aura_env:SetArcTimer(arcEventId, scheduledTime, arg1, arg2, arg3)
        local arcEventUnderlying, arcEvents, id, ctx, seqnum = self.arcEventUnderlying, self.arcEvents
        if not arcEvents then
            _error(_MISSING_INIT_ARC_EVENTS_CALL)
        end
        id = self.id
        ctx = arcEvents[arcEventId] or {0, nil}  -- seqnum, scheduledTime
        arcEvents[arcEventId] = ctx
        if ctx[2] ~= scheduledTime then
            seqnum = ctx[1] + 1
            ctx[1] = seqnum
            ctx[2] = scheduledTime
            if scheduledTime ~= nil then
                _C_Timer_After(_max(0, scheduledTime - _GetTime() + 1e-6), function()
                    if ctx[1] == seqnum then
                        ctx[2] = nil
                        if not _WeakAuras_IsPaused() then
                            _WeakAuras_ScanEvents(arcEventUnderlying, id, arcEventId, arg1, arg2, arg3)
                        end
                    end
                end)
            end
        end
    end

    -- Get the current `scheduledTime` set by `SetArcTimer`, if pending.
    function _aura_env:GetArcTimer(arcEventId)
        local arcEvents, ctx = self.arcEvents
        if not arcEvents then
            _error(_MISSING_INIT_ARC_EVENTS_CALL)
        end
        ctx = arcEvents[arcEventId]
        return ctx and ctx[2]
    end

    -- Schedule a timed callback, with multiple callbacks allowed for the same `arcEventId`.
    -- `aura_env[arcEventId](aura_env, arg1, arg2, arg3)` will be invoked at approximately `scheduledTime`.
    -- Returns a handle that can be used to cancel the callback.
    function _aura_env:SetArcMultiTimer(arcEventId, scheduledTime, arg1, arg2, arg3)
        local arcEventUnderlying, arcEvents, id, ctx, handle = self.arcEventUnderlying, self.arcEvents
        if not arcEvents then
            _error(_MISSING_INIT_ARC_EVENTS_CALL)
        end
        id = self.id
        ctx = arcEvents[arcEventId] or {1, 2}  -- isActive, nextHandleMinus1, isHandleActive...
        arcEvents[arcEventId] = ctx
        handle = ctx[2] + 1
        ctx[2] = handle
        ctx[handle] = 1
        _C_Timer_After(_max(0, scheduledTime - _GetTime() + 1e-6), function()
            if ctx[1] and ctx[handle] and not _WeakAuras_IsPaused() then
                _WeakAuras_ScanEvents(arcEventUnderlying, id, arcEventId, arg1, arg2, arg3)
            end
            ctx[handle] = nil
        end)
        return handle
    end

    -- Cancel a callback scheduled by `SetArcMultiTimer`, if pending.
    function _aura_env:CancelArcMultiTimer(arcEventId, handle)
        local arcEvents = self.arcEvents
        if not arcEvents then
            _error(_MISSING_INIT_ARC_EVENTS_CALL)
        end
        arcEvents[arcEventId][handle] = nil
    end
end
-- End of ArcWeakAuras Full
