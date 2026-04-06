local function dbg(...)
  if Config.Debug then
    print('^3[nord_keys:sv]^7', ...)
  end
end

local function normPlate(plate)
  plate = tostring(plate or ''):upper()
  plate = plate:gsub('%s+', '')
  return plate
end

local function normalizeTheme(input)
  input = tostring(input or ''):lower()

  if input == 'audi' or input == 'bmw' then
    return input
  end

  if input:find('adder', 1, true) then
    return 'audi'
  end

  if input:find('vapid', 1, true) then
    return 'bmw'
  end

  return 'bmw'
end

local function getThemeFromModelOrMake(modelOrMake)
  return normalizeTheme(modelOrMake)
end

local function discordLog(msg)
  if not (Config.Discord and Config.Discord.enabled and Config.Discord.webhook and Config.Discord.webhook ~= '') then
    return
  end

  PerformHttpRequest(
    Config.Discord.webhook,
    function() end,
    'POST',
    json.encode({
      username = Config.Discord.username or 'nord_keys',
      content = msg,
    }),
    { ['Content-Type'] = 'application/json' }
  )
end

local function addLog(action, plate, actor, target, details)
  plate = normPlate(plate)

  MySQL.insert.await(
    [[
      INSERT INTO nord_vehicle_key_logs (action, plate, actor, target, details)
      VALUES (?, ?, ?, ?, ?)
    ]],
    { action, plate, actor, target, details }
  )

  discordLog(('[%s] plate=%s actor=%s target=%s %s'):format(action, plate, actor or '-', target or '-', details or ''))
end

local function nowUnix()
  return os.time()
end

local function isExpiredKeyMetadata(metadata)
  metadata = metadata or {}
  local expiresAt = tonumber(metadata.expiresAt)
  if not expiresAt then
    return false
  end

  return nowUnix() >= expiresAt
end

local function hasKeyInInventory(src, plate)
  plate = normPlate(plate)
  if plate == '' then
    return false
  end

  local items = exports.ox_inventory:Search(src, 'slots', 'vehicle_key')
  if not items then
    return false
  end

  for _, item in pairs(items) do
    local metadata = item.metadata or {}
    if normPlate(metadata.plate) == plate then
      if isExpiredKeyMetadata(metadata) then
        exports.ox_inventory:RemoveItem(src, 'vehicle_key', 1, nil, item.slot)
      else
        return true
      end
    end
  end

  return false
end

local function buildKeyMetadata(plate, theme, battery, tempMinutes)
  local metadata = {
    plate = normPlate(plate),
    theme = normalizeTheme(theme),
    battery = tonumber(battery) or 100,
  }

  local mins = tonumber(tempMinutes)
  if mins and mins > 0 then
    mins = math.floor(mins)
    metadata.temporary = true
    metadata.expiresAt = nowUnix() + (mins * 60)
    metadata.temporaryMinutes = mins
  end

  return metadata
end

local function giveVehicleKeyItem(src, plate, theme, battery, tempMinutes)
  local added, response = exports.ox_inventory:AddItem(src, 'vehicle_key', 1, buildKeyMetadata(plate, theme, battery, tempMinutes))
  return added and true or false, response
end

local function addItemErrorMessage(response)
  local reason = tostring(response or '')
  if reason == 'invalid_item' then
    return 'Item vehicle_key não existe no ox_inventory.'
  end

  if reason == 'inventory_full' then
    return 'Sem espaço no inventário para receber a chave.'
  end

  if reason ~= '' then
    return ('Não foi possível criar a chave (%s).'):format(reason)
  end

  return 'Não foi possível criar a chave agora. Tenta novamente.'
end

local function hasDBKeyByIdentifier(identifier, plate)
  plate = normPlate(plate)
  if not identifier or identifier == '' or plate == '' then
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
end

local function getOwnerByPlate(plate)
  plate = normPlate(plate)
  if plate == '' then
    return nil
  end

  if not (Config.OwnedVehicles and Config.OwnedVehicles.enabled) then
    return nil
  end

  if NRKeysOwned and NRKeysOwned.GetOwnerIdentifierByPlate then
    return NRKeysOwned.GetOwnerIdentifierByPlate(plate)
  end

  return nil
end

local function getAccessState(src, plate)
  plate = normPlate(plate)
  local state = {
    hasAccess = false,
    isOwned = false,
    isOwner = false,
    isMaster = false,
    plate = plate,
  }

  if plate == '' then
    return state
  end

  local ownerIdentifier = getOwnerByPlate(plate)
  if ownerIdentifier and ownerIdentifier ~= '' then
    state.isOwned = true
  else
    -- Veículo não pertencente a player: não aplicar bloqueio do sistema.
    state.hasAccess = true
    return state
  end

  local identifier = Bridge.GetIdentifier(src)
  if not identifier then
    return state
  end

  state.isOwner = tostring(ownerIdentifier) == tostring(identifier)
  state.isMaster = Bridge.IsMasterKey(src)

  if state.isOwner or state.isMaster then
    state.hasAccess = true
    return state
  end

  if hasKeyInInventory(src, plate) then
    state.hasAccess = true
    return state
  end

  if hasDBKeyByIdentifier(identifier, plate) then
    state.hasAccess = true
    return state
  end

  return state
end

function ensureDBKey(holderIdentifier, plate, grantedBy)
  plate = normPlate(plate)
  if not holderIdentifier or holderIdentifier == '' or plate == '' then
    return false
  end

  local ok = MySQL.insert.await(
    [[
      INSERT IGNORE INTO nord_vehicle_keys (plate, holder, granted_by)
      VALUES (?, ?, ?)
    ]],
    { plate, holderIdentifier, grantedBy }
  )

  return ok ~= nil
end

function removeDBKey(holderIdentifier, plate)
  plate = normPlate(plate)
  if not holderIdentifier or holderIdentifier == '' or plate == '' then
    return false
  end

  local res = MySQL.update.await(
    [[
      DELETE FROM nord_vehicle_keys
      WHERE plate = ? AND holder = ?
    ]],
    { plate, holderIdentifier }
  )

  return (res or 0) > 0
end

local function removePhysicalKeyFromPlayer(src, plate)
  local items = exports.ox_inventory:Search(src, 'slots', 'vehicle_key')
  if not items then
    return false
  end

  for _, item in pairs(items) do
    local metadata = item.metadata or {}
    if normPlate(metadata.plate) == plate then
      exports.ox_inventory:RemoveItem(src, 'vehicle_key', 1, nil, item.slot)
      return true
    end
  end

  return false
end

local function getFirstItemSlotByName(src, itemName)
  if not src or src <= 0 or not itemName or itemName == '' then
    return nil
  end

  local items = exports.ox_inventory:Search(src, 'slots', itemName)
  if not items then
    return nil
  end

  for _, item in pairs(items) do
    if item and item.slot then
      return item
    end
  end

  return nil
end

local function getItemUsesLeft(item, maxUses)
  if not item then
    return maxUses
  end

  local metadata = item.metadata or {}
  local usesLeft = tonumber(metadata.nordLockpickUsesLeft)
  if not usesLeft then
    usesLeft = tonumber(metadata.usesLeft)
  end
  if not usesLeft then
    usesLeft = maxUses
  end

  usesLeft = math.floor(usesLeft)
  if usesLeft < 0 then usesLeft = 0 end
  if usesLeft > maxUses then usesLeft = maxUses end
  return usesLeft
end

local function setItemUsesLeft(src, item, usesLeft)
  if not item or not item.slot then
    return false
  end

  local value = math.max(0, math.floor(tonumber(usesLeft) or 0))
  local metadata = item.metadata or {}
  metadata.nordLockpickUsesLeft = value
  metadata.usesLeft = value

  local okSetMetadata = pcall(function()
    exports.ox_inventory:SetMetadata(src, item.slot, metadata)
  end)

  return okSetMetadata and true or false
end

local function findOnlineSourceByIdentifier(identifier)
  if not identifier or identifier == '' then
    return nil
  end

  for _, id in ipairs(GetPlayers()) do
    local p = tonumber(id)
    if p then
      local pid = Bridge.GetIdentifier(p)
      if pid and tostring(pid) == tostring(identifier) then
        return p
      end
    end
  end

  return nil
end

local function getThemeForPlateInternal(plate)
  plate = normPlate(plate)
  if plate == '' then
    return 'bmw'
  end

  if NRKeysOwned and NRKeysOwned.GetVehicleModelByPlate then
    local model = NRKeysOwned.GetVehicleModelByPlate(plate)
    if model and model ~= '' then
      return getThemeFromModelOrMake(model)
    end
  end

  if NRKeysOwned and NRKeysOwned.GetVehicleMakeByPlate then
    local make = NRKeysOwned.GetVehicleMakeByPlate(plate)
    if make and make ~= '' then
      return getThemeFromModelOrMake(make)
    end
  end

  return 'bmw'
end

function getThemeForPlate(plate)
  return getThemeForPlateInternal(plate)
end

local function canManageKeys(src, plate)
  local state = getAccessState(src, plate)
  return state.isOwner or state.isMaster
end

lib.callback.register('nord_keys:sv:hasAccess', function(src, plate)
  local state = getAccessState(src, plate)
  return state.hasAccess, state.isOwned, state.isOwner, state.isMaster
end)

lib.callback.register('nord_keys:sv:hasPhysicalKey', function(src, plate)
  plate = normPlate(plate)
  if plate == '' then
    return false
  end

  return hasKeyInInventory(src, plate)
end)

RegisterNetEvent('nord_keys:sv:grantSelfOwner', function(plate)
  local src = source
  local identifier = Bridge.GetIdentifier(src)
  plate = normPlate(plate)

  if not identifier or plate == '' then
    return
  end

  -- Security: block if another player already owns this vehicle in the DB
  local ownerId = getOwnerByPlate(plate)
  if ownerId and tostring(ownerId) ~= tostring(identifier) then
    addLog('GRANT_SELF_OWNER_BLOCKED', plate, identifier, tostring(ownerId), 'caller is not vehicle owner')
    return
  end

  -- Don't give duplicate key items if player already carries one
  if hasKeyInInventory(src, plate) then
    Bridge.Notify(src, 'inform', 'Já tens a chave desse carro.')
    return
  end

  ensureDBKey(identifier, plate, identifier)

  local added, reason = giveVehicleKeyItem(src, plate, getThemeForPlateInternal(plate), 100)

  if not added then
    Bridge.Notify(src, 'error', addItemErrorMessage(reason))
    return
  end

  addLog('REGISTER_OWNER', plate, identifier, identifier, 'owner registered + key item granted')

  TriggerClientEvent('nord_keys:cl:syncVehicleLocked', -1, plate, true)

  Bridge.Notify(src, 'success', 'Chave criada para o teu veículo.')
end)

RegisterNetEvent('nord_keys:sv:transferKey', function(plate, targetSrc)
  local src = source
  local plateN = normPlate(plate)
  if plateN == '' then
    return
  end

  targetSrc = tonumber(targetSrc)
  if not targetSrc then
    Bridge.Notify(src, 'error', Config.Text.invalidTarget)
    return
  end

  local actorIdentifier = Bridge.GetIdentifier(src)
  local targetIdentifier = Bridge.GetIdentifier(targetSrc)
  if not actorIdentifier or not targetIdentifier then
    Bridge.Notify(src, 'error', Config.Text.invalidTarget)
    return
  end

  if not canManageKeys(src, plateN) then
    Bridge.Notify(src, 'error', 'Só o proprietário pode entregar chaves deste veículo.')
    return
  end

  if ensureDBKey(targetIdentifier, plateN, actorIdentifier) then
    local added, reason = giveVehicleKeyItem(targetSrc, plateN, getThemeForPlateInternal(plateN), 100)

    if not added then
      removeDBKey(targetIdentifier, plateN)
      Bridge.Notify(src, 'error', ('Falha ao entregar a chave: %s'):format(addItemErrorMessage(reason)))
      Bridge.Notify(targetSrc, 'error', addItemErrorMessage(reason))
      return
    end

    addLog('TRANSFER_KEY', plateN, actorIdentifier, targetIdentifier, 'granted db key + item key')
    Bridge.Notify(src, 'success', Config.Text.gaveKey)
    Bridge.Notify(targetSrc, 'success', Config.Text.receivedKey)
  end
end)

RegisterNetEvent('nord_keys:sv:transferTempKey', function(plate, targetSrc, minutes)
  local src = source
  if not (Config.TempKeys and Config.TempKeys.enabled) then
    Bridge.Notify(src, 'error', 'Sistema de chaves temporárias está desativado.')
    return
  end

  local plateN = normPlate(plate)
  if plateN == '' then
    return
  end

  targetSrc = tonumber(targetSrc)
  if not targetSrc then
    Bridge.Notify(src, 'error', Config.Text.invalidTarget)
    return
  end

  local actorIdentifier = Bridge.GetIdentifier(src)
  local targetIdentifier = Bridge.GetIdentifier(targetSrc)
  if not actorIdentifier or not targetIdentifier then
    Bridge.Notify(src, 'error', Config.Text.invalidTarget)
    return
  end

  if not canManageKeys(src, plateN) then
    Bridge.Notify(src, 'error', 'Só o proprietário pode entregar chaves deste veículo.')
    return
  end

  local minCfg = math.max(1, tonumber((Config.TempKeys and Config.TempKeys.minMinutes) or 5) or 5)
  local maxCfg = math.max(minCfg, tonumber((Config.TempKeys and Config.TempKeys.maxMinutes) or 240) or 240)
  local defaultCfg = math.max(minCfg, tonumber((Config.TempKeys and Config.TempKeys.defaultMinutes) or 30) or 30)

  local duration = tonumber(minutes) or defaultCfg
  duration = math.floor(duration)
  if duration < minCfg then duration = minCfg end
  if duration > maxCfg then duration = maxCfg end

  local added, reason = giveVehicleKeyItem(targetSrc, plateN, getThemeForPlateInternal(plateN), 100, duration)
  if not added then
    Bridge.Notify(src, 'error', ('Falha ao entregar chave temporária: %s'):format(addItemErrorMessage(reason)))
    Bridge.Notify(targetSrc, 'error', addItemErrorMessage(reason))
    return
  end

  addLog('TRANSFER_TEMP_KEY', plateN, actorIdentifier, targetIdentifier, ('duration=%s min'):format(duration))
  Bridge.Notify(src, 'success', (Config.Text.tempKeyGiven or 'Chave temporária entregue por %s minutos.'):format(duration))
  Bridge.Notify(targetSrc, 'success', (Config.Text.tempKeyReceived or 'Recebeste uma chave temporária por %s minutos.'):format(duration))
end)

RegisterNetEvent('nord_keys:sv:revokeKey', function(plate, targetIdentifier)
  local src = source
  local plateN = normPlate(plate)
  if plateN == '' then
    return
  end

  local actorIdentifier = Bridge.GetIdentifier(src)
  if not actorIdentifier then
    return
  end

  local targetId = tostring(targetIdentifier or '')
  if targetId == '' then
    targetId = actorIdentifier
  end

  if not canManageKeys(src, plateN) and targetId ~= tostring(actorIdentifier) then
    Bridge.Notify(src, 'error', 'Sem permissão para revogar esta chave.')
    return
  end

  local ok = removeDBKey(targetId, plateN)
  if not ok then
    Bridge.Notify(src, 'error', 'Nada para revogar.')
    return
  end

  -- Revoga item físico se o jogador alvo estiver online.
  for _, player in ipairs(GetPlayers()) do
    local p = tonumber(player)
    if p then
      local id = Bridge.GetIdentifier(p)
      if id and tostring(id) == targetId then
        removePhysicalKeyFromPlayer(p, plateN)
      end
    end
  end

  addLog('REVOKE_KEY', plateN, actorIdentifier, targetId, 'db key revoked')
  Bridge.Notify(src, 'success', Config.Text.keyRevoked)
end)

RegisterNetEvent('nord_keys:sv:recoverLostKey', function(plate)
  local src = source
  local plateN = normPlate(plate)
  if plateN == '' then
    return
  end

  local identifier = Bridge.GetIdentifier(src)
  if not identifier then
    return
  end

  local ownerId = getOwnerByPlate(plateN)
  if not ownerId or tostring(ownerId) ~= tostring(identifier) then
    Bridge.Notify(src, 'error', 'Não és o proprietário deste veículo.')
    return
  end

  if hasKeyInInventory(src, plateN) then
    Bridge.Notify(src, 'inform', 'Já tens a chave desse carro.')
    return
  end

  local fee = math.max(0, tonumber((Config.KeyLossNPC and Config.KeyLossNPC.fee) or 0) or 0)
  if fee > 0 then
    local paid = Bridge.TryCharge and Bridge.TryCharge(src, fee, 'nord_keys_recover_lost_key')
    if not paid then
      Bridge.Notify(src, 'error', Config.Text.keyRecoverNoMoney or 'Não tens dinheiro suficiente para recuperar a chave.')
      return
    end
  end

  local alreadyHadDBKey = hasDBKeyByIdentifier(identifier, plateN)
  ensureDBKey(identifier, plateN, 'keyloss_npc')

  local added, reason = giveVehicleKeyItem(src, plateN, getThemeForPlateInternal(plateN), 100)

  if not added then
    if not alreadyHadDBKey then
      removeDBKey(identifier, plateN)
    end
    if fee > 0 and Bridge.GiveMoney then
      Bridge.GiveMoney(src, fee, 'nord_keys_recover_lost_key_refund')
    end
    Bridge.Notify(src, 'error', addItemErrorMessage(reason))
    return
  end

  addLog('RECOVER_LOST_KEY', plateN, identifier, identifier, ('npc issued duplicate key fee=%s'):format(fee))

  if fee > 0 then
    Bridge.Notify(src, 'success', (Config.Text.keyRecoverPaid or 'Chave recuperada (%s). Custo: $%s'):format(plateN, fee))
  else
    Bridge.Notify(src, 'success', ('Chave recuperada (%s).'):format(plateN))
  end
end)

RegisterNetEvent('nord_keys:sv:lockpickSuccess', function(plate)
  local src = source
  local plateN = normPlate(plate)
  local identifier = Bridge.GetIdentifier(src)
  if not identifier or plateN == '' then
    return
  end

  addLog('LOCKPICK_SUCCESS', plateN, identifier, nil, 'temporary access granted')
end)

RegisterNetEvent('nord_keys:sv:lockpickFail', function(plate)
  local src = source
  local plateN = normPlate(plate)
  local identifier = Bridge.GetIdentifier(src)
  if not identifier or plateN == '' then
    return
  end

  addLog('LOCKPICK_FAIL', plateN, identifier, nil, 'failed')
end)

RegisterNetEvent('nord_keys:sv:consumeLockpick', function(mode)
  local src = source
  if not Config.Lockpick.enabled then
    return
  end

  local item = Config.Lockpick.item
  if not item then
    return
  end

  local durabilityCfg = (Config.Lockpick and Config.Lockpick.durability) or {}
  local durabilityEnabled = durabilityCfg.enabled == true

  if durabilityEnabled then
    local lockpickItem = getFirstItemSlotByName(src, item)
    if not lockpickItem then
      return
    end

    local maxUses = math.max(1, math.floor(tonumber(durabilityCfg.maxUses) or 8))
    local loss = (tostring(mode) == 'fail') and (tonumber(durabilityCfg.lossOnFail) or 2)
      or (tonumber(durabilityCfg.lossOnSuccess) or 1)
    loss = math.max(1, math.floor(loss))

    local currentUses = getItemUsesLeft(lockpickItem, maxUses)
    local newUses = math.max(0, currentUses - loss)
    setItemUsesLeft(src, lockpickItem, newUses)

    if newUses <= 0 and durabilityCfg.removeWhenBroken ~= false then
      exports.ox_inventory:RemoveItem(src, item, 1, nil, lockpickItem.slot)
      Bridge.Notify(src, 'error', Config.Text.lockpickBroken or 'O lockpick partiu-se.')
      addLog('LOCKPICK_BREAK', 'N/A', Bridge.GetIdentifier(src), nil, ('mode=%s'):format(tostring(mode or 'unknown')))
      return
    end

    if durabilityCfg.notifyWear then
      Bridge.Notify(src, 'inform', (Config.Text.lockpickWear or 'Usos do lockpick restantes: %s.'):format(newUses))
    end

    addLog(
      'LOCKPICK_WEAR',
      'N/A',
      Bridge.GetIdentifier(src),
      nil,
      ('mode=%s before=%s after=%s loss=%s'):format(tostring(mode or 'unknown'), currentUses, newUses, loss)
    )
    return
  end

  local chance = (tostring(mode) == 'fail') and (Config.Lockpick.consumeOnFailChance or 35)
    or (Config.Lockpick.consumeOnSuccessChance or 10)

  if math.random(1, 100) <= chance then
    exports.ox_inventory:RemoveItem(src, item, 1)
    addLog('LOCKPICK_CONSUME', 'N/A', Bridge.GetIdentifier(src), nil, tostring(mode or 'unknown'))
  end
end)

RegisterNetEvent('nord_keys:sv:openKeyFobFromSlot', function(slot)
  local src = source
  if not slot then
    return
  end

  local item = exports.ox_inventory:GetSlot(src, slot)
  if not item or item.name ~= 'vehicle_key' then
    return
  end

  local metadata = item.metadata or {}
  local plate = normPlate(metadata.plate)
  if plate == '' then
    Bridge.Notify(src, 'error', 'Esta chave não está associada a nenhum veículo.')
    return
  end

  if isExpiredKeyMetadata(metadata) then
    exports.ox_inventory:RemoveItem(src, 'vehicle_key', 1, nil, slot)
    Bridge.Notify(src, 'error', Config.Text.tempKeyExpired or 'Esta chave temporária expirou.')
    return
  end

  local battery = tonumber(metadata.battery) or 100
  local theme = normalizeTheme(metadata.theme)

  local changed = false
  if metadata.battery == nil then
    metadata.battery = battery
    changed = true
  end
  if metadata.theme == nil then
    metadata.theme = theme
    changed = true
  end
  if changed then
    exports.ox_inventory:SetMetadata(src, slot, metadata)
  end

  TriggerClientEvent('nord_keys:client:openKeyFob', src, plate, battery, theme)
end)

RegisterNetEvent('nord_keys:sv:policeAlert', function(_coords)
  local players = GetPlayers()

  for _, id in ipairs(players) do
    local src = tonumber(id)
    if src and Bridge.IsPolice and Bridge.IsPolice(src) then
      TriggerClientEvent('ox_lib:notify', src, {
        type = 'error',
        title = 'Roubo de Veículo',
        description = 'Tentativa de arrombamento detectada.',
      })
    end
  end
end)

RegisterNetEvent('nord_keys:sv:dispatchCarTheft', function(coords, plate, street)
  local src = source
  if not src or src == 0 then return end

  local c = coords or {}
  local payload = {
    street = tostring(street or ''),
    coords = {
      x = tonumber(c.x) or 0.0,
      y = tonumber(c.y) or 0.0,
      z = tonumber(c.z) or 0.0,
    },
    info = {
      placa = tostring(normPlate(plate)),
    },
  }

  local sent = false
  local lastErr = nil

  local okAlias, errAlias = pcall(function()
    local ret, retErr = exports['nord_dispach']:CreateDispatchAlert('car_theft', payload)
    if ret == false then
      lastErr = retErr or 'CreateDispatchAlert retornou false'
      return
    end
    sent = true
  end)

  if not okAlias then
    lastErr = errAlias
  end

  if not sent then
    local okPt, errPt = pcall(function()
      local ret, retErr = exports['nord_dispach']:CriarAlertaDispatch('car_theft', payload)
      if ret == false then
        lastErr = retErr or 'CriarAlertaDispatch retornou false'
        return
      end
      sent = true
    end)

    if not okPt then
      lastErr = errPt
    end
  end

  if not sent then
    print('^1[nord_keys] DispatchCarTheft falhou em nord_dispach: ^7' .. tostring(lastErr))
    return
  end

  dbg('DispatchCarTheft enviado — placa:', plate, 'rua:', street)
end)

RegisterNetEvent('nord_keys:sv:syncVehicleLock', function(plate, isLocked)
  local src = source
  local plateN = normPlate(plate)
  if plateN == '' then
    return
  end

  local state = getAccessState(src, plateN)
  if not state.hasAccess then
    return
  end

  if not hasKeyInInventory(src, plateN) then
    return
  end

  TriggerClientEvent('nord_keys:cl:syncVehicleLocked', -1, plateN, isLocked)
  TriggerClientEvent('nord_keys:cl:updateNUILockState', src, plateN, isLocked)
end)

RegisterNetEvent('nord_keys:sv:removePlayerKey', function(plate)
  local src = source
  local plateN = normPlate(plate)
  if plateN == '' then
    return
  end

  local identifier = Bridge.GetIdentifier(src)
  if not identifier then
    return
  end

  removeDBKey(identifier, plateN)
  removePhysicalKeyFromPlayer(src, plateN)

  addLog('REMOVE_KEY', plateN, identifier, identifier, 'removed via integration')
end)

RegisterNetEvent('nord_keys:sv:exportGiveKey', function(plate)
  local src = source
  exports['nord_keys']:GiveKeyByPlate(src, plate)
end)

RegisterNetEvent('nord_keys:sv:exportRemoveKey', function(plate)
  local src = source
  exports['nord_keys']:RemoveKeyByPlate(src, plate)
end)

exports('HasKey', function(src, plate)
  local state = getAccessState(src, plate)
  return state.hasAccess
end)

exports('HasVehicleAccess', function(src, plate)
  local state = getAccessState(src, plate)
  return state.hasAccess
end)

exports('GiveKey', function(src, plate, toIdentifier, grantedBy)
  plate = normPlate(plate)
  if plate == '' or not toIdentifier or toIdentifier == '' then
    return false
  end

  local targetSrc = tonumber(src)
  if not targetSrc or targetSrc <= 0 then
    targetSrc = findOnlineSourceByIdentifier(toIdentifier)
  else
    local targetIdentifier = Bridge.GetIdentifier(targetSrc)
    if not targetIdentifier or tostring(targetIdentifier) ~= tostring(toIdentifier) then
      targetSrc = findOnlineSourceByIdentifier(toIdentifier)
    end
  end

  if not targetSrc then
    return false
  end

  if not ensureDBKey(toIdentifier, plate, grantedBy) then
    return false
  end

  local added = giveVehicleKeyItem(targetSrc, plate, getThemeForPlateInternal(plate), 100)
  if not added then
    removeDBKey(toIdentifier, plate)
    return false
  end

  return true
end)

exports('RevokeKey', function(src, plate, fromIdentifier)
  plate = normPlate(plate)
  if plate == '' or not fromIdentifier or fromIdentifier == '' then
    return false
  end

  local targetSrc = tonumber(src)
  if not targetSrc or targetSrc <= 0 then
    targetSrc = findOnlineSourceByIdentifier(fromIdentifier)
  else
    local targetIdentifier = Bridge.GetIdentifier(targetSrc)
    if not targetIdentifier or tostring(targetIdentifier) ~= tostring(fromIdentifier) then
      targetSrc = findOnlineSourceByIdentifier(fromIdentifier)
    end
  end

  if not targetSrc then
    return false
  end

  local removedDb = removeDBKey(fromIdentifier, plate)
  local removedItem = removePhysicalKeyFromPlayer(targetSrc, plate)

  return removedDb and removedItem
end)

exports('GiveTemporaryKey', function(src, plate, targetSrc, minutes)
  if not (Config.TempKeys and Config.TempKeys.enabled) then
    return false
  end

  plate = normPlate(plate)
  targetSrc = tonumber(targetSrc)
  if plate == '' or not targetSrc then
    return false
  end

  local ownerState = getAccessState(src, plate)
  if not ownerState.isOwner and not ownerState.isMaster then
    return false
  end

  local mins = tonumber(minutes) or ((Config.TempKeys and Config.TempKeys.defaultMinutes) or 30)
  local added = giveVehicleKeyItem(targetSrc, plate, getThemeForPlateInternal(plate), 100, mins)
  return added and true or false
end)
