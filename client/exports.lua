--=====================================================
-- NORD_KEYS - CLIENT EXPORTS
--=====================================================

local function normalizePlate(plate)
    plate = tostring(plate or ''):upper():gsub('%s+','')
    return plate
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