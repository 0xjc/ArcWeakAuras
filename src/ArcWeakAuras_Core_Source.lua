-- ArcWeakAuras Core 2.0.0 (https://github.com/0xjc/ArcWeakAuras)

-- Initialize the TSU dispatcher.
-- * The WeakAura must use a single TSU Event trigger with the stub:
--   `function(...) return aura_env:TSU(...) end`
-- * `tsuMode` can be either "basic" or "multi".
--     * "basic": For WeakAuras that don't need multiple clones. Uses `aura_env` itself as the primary TSU state.
--                Event handlers should set `self.show`, `self.changed`, etc.
--     * "multi": For WeakAuras that need multiple clones. Provides `self.allStates`.
--                Event handlers should manipulate `self.allStates` and return whether any state was changed.
function aura_env:InitArcTSU(tsuMode)
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
        error("invalid tsuMode")
    end
end

-- End of ArcWeakAuras Core
