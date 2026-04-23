local addonName, ns = ...

ns.aura = {}

-- Walk the player's buff list and mark which tracked auras are present.
-- Returns true when the set of active tracked keys changed since the
-- previous call — callers use that as a signal to refresh UI; without it
-- every proc of an untracked buff would trigger a full re-render.
function ns.aura:RefreshActiveBuffs()
    local active = {}
    local meta   = {}

    for i = 1, 40 do
        local name, _, _, _, _, expirationTime, source, _, _, spellId = UnitAura("player", i, "HELPFUL")
        if not name then break end
        local tracked = ns.trackedAuras[spellId]
        if tracked then
            local key = tracked.key
            active[key] = true
            meta[key]   = {
                expirationTime = expirationTime,
                source         = source,
                spellId        = spellId,
                label          = tracked.label,
            }
        end
    end

    -- Fingerprint: sorted list of active keys. Cheap compare, stable across
    -- ticks, and we only pay the sort when something actually changed.
    local keys = {}
    for k in pairs(active) do keys[#keys + 1] = k end
    table.sort(keys)
    local fingerprint = table.concat(keys, "|")

    local changed = fingerprint ~= ns.state.activeBuffsFingerprint
    ns.state.activeBuffs            = active
    ns.state.activeBuffsMeta        = meta
    ns.state.activeBuffsFingerprint = fingerprint
    return changed
end

function ns.aura:IsActive(key)
    return ns.state.activeBuffs[key] == true
end

function ns.aura:IsPlanned(key)
    local planned = UncrushableHelperPerCharDB and UncrushableHelperPerCharDB.plannedBuffs
    if not planned then return false end
    return planned[key] == true
end

function ns.aura:SetPlanned(key, value)
    UncrushableHelperPerCharDB.plannedBuffs = UncrushableHelperPerCharDB.plannedBuffs or {}
    UncrushableHelperPerCharDB.plannedBuffs[key] = value and true or nil
end

function ns.aura:TogglePlanned(key)
    local next = not self:IsPlanned(key)
    self:SetPlanned(key, next)
    return next
end

-- Stable ordered view for UI rendering. Returns one row per tracked key
-- with `active`/`planned`/`label` already resolved.
function ns.aura:ListTrackedForUI()
    local rows = {}
    for _, key in ipairs(ns.trackedAurasOrder) do
        rows[#rows + 1] = {
            key     = key,
            label   = ns.trackedAurasLabels[key] or key,
            active  = self:IsActive(key),
            planned = self:IsPlanned(key),
        }
    end
    return rows
end
