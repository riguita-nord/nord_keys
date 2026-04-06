--=====================================================
-- NORD_KEYS - SERVER EXPORTS (clean wrappers)
--=====================================================

local function safePlate(plate)
  if not plate then
    return ''
  end

  return tostring(plate):upper():gsub('%s+', '')
end

local function safeSource(src)
  src = tonumber(src)
  if not src or src <= 0 then
    return nil
  end

  return src
end

local function removePhysicalKey(src, plate)
  local items = exports.ox_inventory:Search(src, 'slots', 'vehicle_key')
  if not items then
    return false
  end

  for _, item in pairs(items) do
    local metadata = item.metadata or {}
    local itemPlate = safePlate(metadata.plate)
    if itemPlate == plate then
      exports.ox_inventory:RemoveItem(src, 'vehicle_key', 1, nil, item.slot)
      return true
    end
  end

  return false
end

exports('GetVehicleTheme', function(plate)
  plate = safePlate(plate)
  if plate == '' then
    return 'bmw'
  end

  return getThemeForPlate(plate)
end)

exports('GiveVehicleKey', function(src, plate)
  src = safeSource(src)
  if not src then
    return false
  end

  plate = safePlate(plate)
  if plate == '' then
    return false
  end

  local identifier = Bridge.GetIdentifier(src)
  if not identifier then
    return false
  end

  ensureDBKey(identifier, plate, 'external_export')

  local added = exports.ox_inventory:AddItem(src, 'vehicle_key', 1, {
    plate = plate,
    theme = getThemeForPlate(plate),
    battery = 100,
  })

  if not added then
    removeDBKey(identifier, plate)
    return false
  end

  return true
end)

exports('RemoveVehicleKey', function(src, plate)
  src = safeSource(src)
  if not src then
    return false
  end

  plate = safePlate(plate)
  if plate == '' then
    return false
  end

  local identifier = Bridge.GetIdentifier(src)
  if not identifier then
    return false
  end

  removeDBKey(identifier, plate)
  removePhysicalKey(src, plate)

  return true
end)

exports('HasDBKey', function(src, plate)
  src = safeSource(src)
  if not src then
    return false
  end

  plate = safePlate(plate)
  if plate == '' then
    return false
  end

  local identifier = Bridge.GetIdentifier(src)
  if not identifier then
    return false
  end

  local row = MySQL.single.await(
    [[
      SELECT id
      FROM nord_vehicle_keys
      WHERE plate = ? AND holder = ?
      LIMIT 1
    ]],
    { plate, identifier }
  )

  return row ~= nil
end)

exports('GiveKeyByPlate', function(src, plate)
  src = safeSource(src)
  if not src then
    return false
  end

  plate = safePlate(plate)
  if plate == '' then
    return false
  end

  local identifier = Bridge.GetIdentifier(src)
  if not identifier then
    return false
  end

  ensureDBKey(identifier, plate, identifier)

  local added = exports.ox_inventory:AddItem(src, 'vehicle_key', 1, {
    plate = plate,
    theme = getThemeForPlate(plate),
    battery = 100,
  })

  if not added then
    removeDBKey(identifier, plate)
    return false
  end

  return true
end)

exports('RemoveKeyByPlate', function(src, plate)
  src = safeSource(src)
  if not src then
    return false
  end

  plate = safePlate(plate)
  if plate == '' then
    return false
  end

  local identifier = Bridge.GetIdentifier(src)
  if not identifier then
    return false
  end

  removeDBKey(identifier, plate)
  removePhysicalKey(src, plate)

  return true
end)

-- Backward-compatible aliases
exports('HasKeyByPlate', function(src, plate)
  return exports['nord_keys']:HasKey(src, plate)
end)

exports('RemoveKey', function(src, plate)
  return exports['nord_keys']:RemoveKeyByPlate(src, plate)
end)
