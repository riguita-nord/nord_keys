--=====================================================
-- NORD_KEYS - CLIENT EXPORTS
--=====================================================

exports("GiveKeyByPlate", function(plate)
    TriggerServerEvent("nord_keys:sv:exportGiveKey", plate)
end)

exports("RemoveKeyByPlate", function(plate)
    plate = tostring(plate or ''):upper():gsub('%s+','')
    if plate == '' then return false end

    TriggerServerEvent("nord_keys:sv:exportRemoveKey", plate)
    return true
end)