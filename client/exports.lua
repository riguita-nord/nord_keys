--=====================================================
-- NORD_KEYS - CLIENT EXPORTS
--=====================================================

local function normalizePlate(plate)
    plate = tostring(plate or ''):upper():gsub('%s+','')
    return plate
end

local function resolvePlate(a, b)
    local p1 = normalizePlate(a)
    if p1 ~= '' and #p1 >= 3 then
        return p1
    end

    local p2 = normalizePlate(b)
    if p2 ~= '' and #p2 >= 3 then
        return p2
    end

    return ''
end

exports("GiveKeyByPlate", function(plate)
    plate = normalizePlate(plate)
    if plate == '' then return false end

    TriggerServerEvent("nord_keys:sv:exportGiveKey", plate)
    return true
end)

exports("RemoveKeyByPlate", function(plate)
    plate = normalizePlate(plate)
    if plate == '' then return false end

    TriggerServerEvent("nord_keys:sv:exportRemoveKey", plate)
    return true
end)

-- Backward-compatible aliases
exports("GiveVehicleKey", function(plate)
    return exports['nord_keys']:GiveKeyByPlate(plate)
end)

exports("RemoveVehicleKey", function(plate)
    return exports['nord_keys']:RemoveKeyByPlate(plate)
end)

exports("GiveKey", function(a, b)
    local plate = resolvePlate(a, b)
    if plate == '' then return false end
    return exports['nord_keys']:GiveKeyByPlate(plate)
end)

exports("RemoveKey", function(a, b)
    local plate = resolvePlate(a, b)
    if plate == '' then return false end
    return exports['nord_keys']:RemoveKeyByPlate(plate)
end)