# ArcWeakAuras

A small convenience library that can be embedded in the Init section of custom WeakAuras.

- `ArcWeakAuras_Core.lua`: Provides TSU dispatch.
- `ArcWeakAuras_Full.lua`: Provides TSU dispatch and periodic/timed events.

The unminified source files are provided in `src` for reference and debugging purposes.

## TSU stub

The library expects the WeakAura to use a single Custom TSU Event trigger, with the following trigger stub:

```
function(...) return aura_env:TSU(...) end
```

This stub allows the Init section to be the central place for custom logic.

## TSU dispatch

The library provides two TSU modes, `"basic"` and `"multi"`.

### Basic mode

TSU dispatcher for WeakAuras that don't use clones. For convenience, uses `aura_env` itself as the primary TSU state. Event handlers should set `self.show`, `self.changed`, etc.

```
function aura_env:Init()
    self:InitArcTSU("basic")
end

function aura_env:EXAMPLE_EVENT(arg1, arg2)
    self.show = true
    self.changed = true
end

aura_env:Init()
```

### Multi mode

TSU dispatcher for WeakAuras that need multiple clones.

Event handlers should manipulate `self.allStates`, and return whether any state was changed.

```
function aura_env:Init()
    self:InitArcTSU("multi")
end

function aura_env:EXAMPLE_EVENT(arg1, arg2)
    self.allStates["key"] = {
        show = true,
        changed = true,
    }
    return true
end

aura_env:Init()
```

## WeakAura-local events

To use the periodic and timer callbacks, an event name starting with `ARC_EVENT_` must be present in the TSU event list. The suffix can be any random string. (You must also be using one of the above TSU dispatch methods.)

### Periodic callbacks

```
function aura_env:Init()
    self:InitArcTSU("basic")
    self:InitArcEvents()
end

function aura_env:STATUS()
    self:SetArcPeriodic("EXAMPLE_PERIODIC", 0.2)
end

function aura_env:EXAMPLE_PERIODIC()
    self.show = true
    self.changed = true
end

aura_env:Init()
```

### Timer callbacks

```
function aura_env:Init()
    self:InitArcTSU("basic")
    self:InitArcEvents()
end

function aura_env:STATUS()
    self:SetArcTimer("EXAMPLE_TIMER", nil)
end

function aura_env:EXAMPLE_EVENT()
    self:SetArcTimer("EXAMPLE_TIMER", GetTime() + 1)
end

function aura_env:EXAMPLE_TIMER()
    self.show = true
    self.changed = true
end

aura_env:Init()
```

### Design of `ARC_EVENT_`

The periodic and timer callbacks rely on the ability to fire WeakAura-local events.

WeakAuras does not provide a built-in way for a WeakAura to dispatch events only to itself.
Instead, one can only call `WeakAuras.ScanEvents()` with a hopefully unique event name,
insert `aura_env.id` as the first argument, and manually filter out collisions in the event handler.

If the event name is not unique, any cross-triggering will incur the overhead of activating
the aura environment. This overhead is generally small, but scales quadratically with the number of
WeakAuras sharing an event name, so it is best to use unique event names if possible.

This library provides `self:InitArcEvents()` to standardize this handling.
- All logical custom events will be multiplexed through the underlying `ARC_EVENT_` event,
  so that the user only needs to choose the name once per WeakAura.
- In previous iterations, the library was able to automatically modify the TSU event list if
  collisions were detected. However, the WeakAuras maintainers removed the ability for WeakAuras
  to modify their own data, so this is no longer possible.
- `self:InitArcEvents()` will handle everything else (auto-detecting the event name, filtering out
  cross-triggers, and dispatching to logical `arcEventId`s).
