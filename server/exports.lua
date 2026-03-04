--=====================================================
-- NORD_KEYS - SERVER EXPORTS
--=====================================================

local function safePlate(plate)
    if not plate then return '' end
    plate = tostring(plate):upper():gsub('%s+', '')
    return plate
end

--=====================================================
-- 🔐 HasKey
--=====================================================
exports('HasKey', function(src, plate)
    plate = safePlate(plate)
    if plate == '' then return false end
    return hasAnyAccess(src, plate)
end)

--=====================================================
-- 🚗 HasVehicleAccess (alias)
--=====================================================
exports('HasVehicleAccess', function(src, plate)
    plate = safePlate(plate)
    if plate == '' then return false end
    return hasAnyAccess(src, plate)
end)

--=====================================================
-- 🎨 GetVehicleTheme
--=====================================================
exports('GetVehicleTheme', function(plate)
    plate = safePlate(plate)
    if plate == '' then return 'bmw' end
    return getThemeForPlate(plate)
end)

--=====================================================
-- 🔑 GiveVehicleKey
--=====================================================
exports('GiveVehicleKey', function(src, plate)
    plate = safePlate(plate)
    if plate == '' then return false end

    local identifier = Bridge.GetIdentifier(src)
    if not identifier then return false end

    local theme = getThemeForPlate(plate)

    ensureDBKey(identifier, plate, 'external_export')

    exports.ox_inventory:AddItem(src, 'vehicle_key', 1, {
        plate = plate,
        theme = theme
    })

    return true
end)

--=====================================================
-- ❌ RemoveVehicleKey
--=====================================================
exports('RemoveVehicleKey', function(src, plate)
    plate = safePlate(plate)
    if plate == '' then return false end

    local identifier = Bridge.GetIdentifier(src)
    if not identifier then return false end

    removeDBKey(identifier, plate)

    local items = exports.ox_inventory:Search(src, 'slots', 'vehicle_key')
    if items then
        for _, item in pairs(items) do
            if item.metadata and safePlate(item.metadata.plate) == plate then
                exports.ox_inventory:RemoveItem(src, 'vehicle_key', 1, item.metadata)
                break
            end
        end
    end

    return true
end)

--=====================================================
-- 🧠 GetVehicleModelFromPlate (QBCore)
--=====================================================
exports('GetVehicleModelFromPlate', function(plate)
    plate = safePlate(plate)
    if plate == '' then return nil end

    local row = MySQL.single.await(
        "SELECT vehicle FROM player_vehicles WHERE plate = ? LIMIT 1",
        { plate }
    )

    if not row or not row.vehicle then return nil end

    local ok, props = pcall(json.decode, row.vehicle)
    if not ok or not props or not props.model then return nil end

    local modelHash = tonumber(props.model)
    if not modelHash then return nil end

    return GetDisplayNameFromVehicleModel(modelHash)
end)

--=====================================================
-- 🏭 GetVehicleMakeFromPlate
--=====================================================
exports('GetVehicleMakeFromPlate', function(plate)
    plate = safePlate(plate)
    if plate == '' then return nil end

    local row = MySQL.single.await(
        "SELECT vehicle FROM player_vehicles WHERE plate = ? LIMIT 1",
        { plate }
    )

    if not row or not row.vehicle then return nil end

    local ok, props = pcall(json.decode, row.vehicle)
    if not ok or not props or not props.model then return nil end

    local modelHash = tonumber(props.model)
    if not modelHash then return nil end

    return GetMakeNameFromVehicleModel(modelHash)
end)

--=====================================================
-- 🔎 HasDBKey (Direct DB Check)
--=====================================================
exports('HasDBKey', function(src, plate)
    plate = safePlate(plate)
    if plate == '' then return false end

    local identifier = Bridge.GetIdentifier(src)
    if not identifier then return false end

    local row = MySQL.single.await([[
        SELECT id FROM nord_vehicle_keys
        WHERE plate = ? AND holder = ?
        LIMIT 1
    ]], { plate, identifier })

    return row ~= nil
end)

exports("GiveKeyByPlate", function(src, plate)
    plate = tostring(plate or ''):upper():gsub('%s+','')
    if plate == '' then return false end

    local identifier = Bridge.GetIdentifier(src)
    if not identifier then return false end

    ensureDBKey(identifier, plate, identifier)

    exports.ox_inventory:AddItem(src, 'vehicle_key', 1, {
        plate = plate,
        theme = getThemeForPlate(plate)
    })

    return true
end)

exports("RemoveKeyByPlate", function(src, plate)
    plate = tostring(plate or ''):upper():gsub('%s+','')
    if plate == '' then return false end

    local identifier = Bridge.GetIdentifier(src)
    if not identifier then return false end

    removeDBKey(identifier, plate)

    local items = exports.ox_inventory:Search(src, 'slots', 'vehicle_key')

    if items then
        for _, item in pairs(items) do
            local metadata = item.metadata or {}
            if metadata.plate and metadata.plate:upper():gsub('%s+','') == plate then
                exports.ox_inventory:RemoveItem(src, 'vehicle_key', 1, nil, item.slot)
                break
            end
        end
    end

    return true
end)