local function dbg(...)
  if Config.Debug then
    print('^3[nord_keys:cl]^7', ...)
  end
end

local function normPlate(plate)
  plate = tostring(plate or ''):upper()
  plate = plate:gsub('%s+', '')
  return plate
end

local function notify(typ, msg)
  if Bridge and Bridge.NotifyClient then
    Bridge.NotifyClient(typ or 'inform', msg)
    return
  end

  lib.notify({ type = typ or 'inform', description = msg })
end

local tempAccess = {} -- [plate] = expireGameTimer
local tempBreakInEntryAccess = {} -- [plate] = expireGameTimer
local accessCache = {} -- [plate] = { state = table, t = gameTimer }
local physicalKeyCache = {} -- [plate] = { value = bool, t = gameTimer }
local unlockedCooldown = {} -- [plate] = expireGameTimer (avoid instant relock)
local tempKeyLoseOnEngineOff = {} -- [plate] = true while temp key should be removed when engine goes off
local tempKeyEngineArmed = {} -- [plate] = true once engine has been running at least once
local carjackCooldown = {} -- [plate] = gameTimer cooldown to avoid spam

local currentPlate = nil
local keyLossPed = nil

local function getClosestPlayer(maxDist)
  local ped = PlayerPedId()
  local myCoords = GetEntityCoords(ped)
  local bestPlayer = nil
  local bestDist = tonumber(maxDist) or (Config.TransferDistance or 3.0)

  for _, player in ipairs(GetActivePlayers()) do
    local targetPed = GetPlayerPed(player)
    if targetPed ~= ped and DoesEntityExist(targetPed) then
      local dist = #(myCoords - GetEntityCoords(targetPed))
      if dist <= bestDist then
        bestDist = dist
        bestPlayer = player
      end
    end
  end

  return bestPlayer, bestDist
end

local function hasTempAccess(plate)
  plate = normPlate(plate)
  local exp = tempAccess[plate]
  if not exp then
    return false
  end

  if GetGameTimer() > exp then
    tempAccess[plate] = nil
    return false
  end

  return true
end

local function grantTempAccess(plate, minutes)
  plate = normPlate(plate)
  local ms = (tonumber(minutes) or 1) * 60 * 1000
  tempAccess[plate] = GetGameTimer() + ms
end

local function hasTempBreakInEntryAccess(plate)
  plate = normPlate(plate)
  local exp = tempBreakInEntryAccess[plate]
  if not exp then
    return false
  end

  if GetGameTimer() > exp then
    tempBreakInEntryAccess[plate] = nil
    return false
  end

  return true
end

local function grantTempBreakInEntryAccess(plate, minutes)
  plate = normPlate(plate)
  local ms = (tonumber(minutes) or 5) * 60 * 1000
  tempBreakInEntryAccess[plate] = GetGameTimer() + ms
end

local function markVehicleTemporarilyUnlocked(plate, seconds)
  plate = normPlate(plate)
  if plate == '' then
    return
  end

  local ms = (tonumber(seconds) or 15) * 1000
  unlockedCooldown[plate] = GetGameTimer() + ms
end

local function isOnUnlockedCooldown(plate)
  plate = normPlate(plate)
  local exp = unlockedCooldown[plate]
  if not exp then
    return false
  end

  if GetGameTimer() > exp then
    unlockedCooldown[plate] = nil
    return false
  end

  return true
end

local function getClosestVehicle()
  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)

  local inVeh = GetVehiclePedIsIn(ped, false)
  if inVeh ~= 0 then
    return inVeh
  end

  local veh = GetClosestVehicle(coords.x, coords.y, coords.z, Config.VehicleSearchRadius or 6.0, 0, 71)
  if veh ~= 0 then
    return veh
  end

  return nil
end

local function getVehicleByPlate(plate)
  plate = normPlate(plate)
  if plate == '' then
    return nil
  end

  local vehicles = GetGamePool('CVehicle')
  for _, veh in ipairs(vehicles) do
    if normPlate(GetVehicleNumberPlateText(veh)) == plate then
      return veh
    end
  end

  return nil
end

local function playKeyAnim()
  local ped = PlayerPedId()
  if IsPedInAnyVehicle(ped, false) then
    return
  end

  local dict = 'anim@mp_player_intmenu@key_fob@'
  RequestAnimDict(dict)
  while not HasAnimDictLoaded(dict) do
    Wait(0)
  end

  TaskPlayAnim(ped, dict, 'fob_click', 8.0, -8.0, 900, 48, 0, false, false, false)
end

local function flashLights(veh, times)
  if not veh or veh == 0 or not DoesEntityExist(veh) then
    return
  end

  CreateThread(function()
    for _ = 1, (times or 1) do
      SetVehicleLights(veh, 2)
      Wait(120)
      SetVehicleLights(veh, 0)
      Wait(120)
    end
  end)
end

local function playSimpleAnim(dict, clip, duration, flag)
  if not (Config.Animations and Config.Animations.enabled) then
    return
  end

  local ped = PlayerPedId()
  if not ped or ped == 0 then
    return
  end

  if not dict or dict == '' or not clip or clip == '' then
    return
  end

  RequestAnimDict(dict)
  local timeout = GetGameTimer() + 1500
  while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do
    Wait(0)
  end

  if not HasAnimDictLoaded(dict) then
    return
  end

  TaskPlayAnim(ped, dict, clip, 8.0, -8.0, duration or -1, flag or 49, 0, false, false, false)
end

local function playLockSound(veh, locked)
  if not veh or veh == 0 or not DoesEntityExist(veh) then
    return
  end

  if locked then
    PlaySoundFromEntity(-1, 'Remote_Control_Close', veh, 'PI_Menu_Sounds', true, 0)
  else
    PlaySoundFromEntity(-1, 'Remote_Control_Open', veh, 'PI_Menu_Sounds', true, 0)
  end
end

local function hasAnySeatedIdentity(veh)
  if not veh or veh == 0 or not DoesEntityExist(veh) then
    return false
  end

  local seats = GetVehicleModelNumberOfSeats(GetEntityModel(veh))
  for seat = -1, (seats - 2) do
    if GetPedInVehicleSeat(veh, seat) ~= 0 then
      return true
    end
  end

  return false
end

local function fetchServerAccessState(plate, cb)
  plate = normPlate(plate)
  if plate == '' then
    cb({ hasAccess = false, isOwned = false, isOwner = false, isMaster = false })
    return
  end

  if hasTempAccess(plate) then
    cb({ hasAccess = true, isOwned = true, isOwner = false, isMaster = false, isTemp = true })
    return
  end

  local now = GetGameTimer()
  local cached = accessCache[plate]
  if cached and (now - cached.t) <= 1000 then
    cb(cached.state)
    return
  end

  lib.callback('nord_keys:sv:hasAccess', false, function(hasAccess, isOwned, isOwner, isMaster)
    local state = {
      hasAccess = hasAccess and true or false,
      isOwned = isOwned and true or false,
      isOwner = isOwner and true or false,
      isMaster = isMaster and true or false,
      isTemp = false,
    }
    accessCache[plate] = { state = state, t = GetGameTimer() }
    cb(state)
  end, plate)
end

local function fetchServerHasPhysicalKey(plate, cb)
  plate = normPlate(plate)
  if plate == '' then
    cb(false)
    return
  end

  local now = GetGameTimer()
  local cached = physicalKeyCache[plate]
  if cached and (now - cached.t) <= 1000 then
    cb(cached.value and true or false)
    return
  end

  lib.callback('nord_keys:sv:hasPhysicalKey', false, function(hasPhysicalKey)
    local value = hasPhysicalKey and true or false
    physicalKeyCache[plate] = { value = value, t = GetGameTimer() }
    cb(value)
  end, plate)
end

local function isBreakInEntryAllowed(veh, plate)
  if hasAnySeatedIdentity(veh) then
    return false
  end

  if hasTempBreakInEntryAccess(plate) then
    return true
  end

  if not veh or veh == 0 then
    return false
  end

  if (not IsVehicleWindowIntact(veh, 0) or not IsVehicleWindowIntact(veh, 1))
    and GetEntitySpeed(veh) < 0.5
    and not GetIsVehicleEngineRunning(veh)
  then
    return true
  end

  return false
end

local function isVehicleParked(veh)
  if not veh or veh == 0 or not DoesEntityExist(veh) then
    return false
  end

  return GetEntitySpeed(veh) < 0.5 and not GetIsVehicleEngineRunning(veh)
end

local function toggleLockOnVehicle(veh, plate)
  local status = GetVehicleDoorLockStatus(veh)
  local shouldLock = (status == 1 or status == 0)

  playKeyAnim()

  if shouldLock then
    SetVehicleDoorsLocked(veh, 2)
    SetVehicleDoorsLockedForAllPlayers(veh, true)
    flashLights(veh, 2)
    playLockSound(veh, true)
    notify('success', Config.Text.locked)
    TriggerServerEvent('nord_keys:sv:syncVehicleLock', plate, true)
  else
    SetVehicleDoorsLocked(veh, 1)
    SetVehicleDoorsLockedForAllPlayers(veh, false)
    markVehicleTemporarilyUnlocked(plate, 18)
    flashLights(veh, 1)
    playLockSound(veh, false)
    notify('success', Config.Text.unlocked)
    TriggerServerEvent('nord_keys:sv:syncVehicleLock', plate, false)
  end
end

local function toggleLock()
  local veh = getClosestVehicle()
  if not veh then
    return
  end

  local plate = normPlate(GetVehicleNumberPlateText(veh))
  if plate == '' then
    return
  end

  fetchServerAccessState(plate, function(state)
    if not state.isOwned then
      notify('error', 'Este veículo não tem chave remota associada.')
      return
    end

    if not state.hasAccess then
      notify('error', Config.Text.noKey)
      return
    end

    if not (Config.LockKeybindRequirePhysicalKey == true) then
      toggleLockOnVehicle(veh, plate)
      return
    end

    fetchServerHasPhysicalKey(plate, function(hasPhysicalKey)
      if not hasPhysicalKey then
        notify('error', Config.Text.noKey)
        return
      end

      toggleLockOnVehicle(veh, plate)
    end)
  end)
end

RegisterCommand('lock', toggleLock)
RegisterKeyMapping('lock', 'Trancar / Destrancar veículo', 'keyboard', Config.LockKey)

local function forceDriverExitRealistic(ped, veh, plate)
  if not ped or ped == 0 or not veh or veh == 0 then
    return
  end

  if not DoesEntityExist(ped) or not DoesEntityExist(veh) then
    return
  end

  SetVehicleEngineOn(veh, false, true, true)
  SetVehicleUndriveable(veh, true)
  TaskLeaveVehicle(ped, veh, 0)
  markVehicleTemporarilyUnlocked(plate, 2)

  CreateThread(function()
    local timeout = GetGameTimer() + 2500
    while DoesEntityExist(ped) and IsPedInVehicle(ped, veh, false) and GetGameTimer() < timeout do
      Wait(50)
      TaskLeaveVehicle(ped, veh, 0)
    end

    if DoesEntityExist(veh) then
      SetVehicleUndriveable(veh, false)
      SetVehicleDoorsLocked(veh, 2)
      SetVehicleDoorsLockedForAllPlayers(veh, true)
    end
  end)
end

CreateThread(function()
  if not (Config.EngineLock and Config.EngineLock.enabled) then
    return
  end

  local pendingDriverEject = {} -- [vehicle] = firstNoKeyGameTimer
  local driverEjectDelayMs = (Config.EngineLock and Config.EngineLock.driverEjectDelayMs) or 3000

  while true do
    Wait(Config.EngineLock.checkIntervalMs or 350)

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)

    if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
      local plate = normPlate(GetVehicleNumberPlateText(veh))
      if plate ~= '' then
        if hasTempAccess(plate) then
          pendingDriverEject[veh] = nil
        else
          fetchServerHasPhysicalKey(plate, function(hasPhysicalKey)
            -- Conduzir exige item físico OU hotwire concluído
            if hasPhysicalKey then
              pendingDriverEject[veh] = nil
              return
            end

            if Config.EngineLock.blockStartIfNoKey then
              SetVehicleEngineOn(veh, false, true, true)
            end

            local now = GetGameTimer()
            if not pendingDriverEject[veh] then
              pendingDriverEject[veh] = now
              return
            end

            if (now - pendingDriverEject[veh]) >= driverEjectDelayMs then
              pendingDriverEject[veh] = nil
              notify('error', Config.Text.engineBlocked or Config.Text.noKey)
              forceDriverExitRealistic(ped, veh, plate)
            end
          end)
        end
      end
    end
  end
end)

CreateThread(function()
  -- qb-like behavior: empty NPC vehicles are locked by default
  while true do
    Wait(1500)

    local ped = PlayerPedId()
    local pcoords = GetEntityCoords(ped)
    local vehicles = GetGamePool('CVehicle')

    for _, veh in ipairs(vehicles) do
      if DoesEntityExist(veh) then
        local dist = #(pcoords - GetEntityCoords(veh))
        if dist <= 80.0 then
          local driver = GetPedInVehicleSeat(veh, -1)
          if driver == 0 then
            local plate = normPlate(GetVehicleNumberPlateText(veh))
            if plate ~= '' and not isOnUnlockedCooldown(plate) then
              local status = GetVehicleDoorLockStatus(veh)
              if status == 0 or status == 1 then
                SetVehicleDoorsLocked(veh, 2)
                SetVehicleDoorsLockedForAllPlayers(veh, true)
              end
            end
          end
        end
      end
    end
  end
end)

CreateThread(function()
  local enterBlockMs = 800
  local lastCheckTime = 0
  local checkCooldown = 250
  local lastNotifyTime = 0
  local notifyCooldown = 3000

  while true do
    Wait(0)

    local ped = PlayerPedId()
    local tryingVeh = GetVehiclePedIsTryingToEnter(ped)

    if tryingVeh and tryingVeh ~= 0 then
      local now = GetGameTimer()
      if (now - lastCheckTime) >= checkCooldown then
        lastCheckTime = now

        local plate = normPlate(GetVehicleNumberPlateText(tryingVeh))
        if plate ~= '' and not hasTempAccess(plate) then
          fetchServerHasPhysicalKey(plate, function(hasPhysicalKey)
            if hasPhysicalKey then
              return
            end

            -- Janela partida/entrada por arrombamento temporário
            if isBreakInEntryAllowed(tryingVeh, plate) then
              return
            end

            -- Sem chave válida no banco do condutor: bloqueia antes de entrar
            if GetSeatPedIsTryingToEnter(ped) ~= -1 then
              return
            end

            DisableControlAction(0, 23, true)
            ClearPedTasksImmediately(ped)
            TaskStandStill(ped, enterBlockMs)
            local nowNotify = GetGameTimer()
            if (nowNotify - lastNotifyTime) >= notifyCooldown then
              lastNotifyTime = nowNotify
              notify('error', Config.Text.noKey)
            end
          end)
        end
      end
    end
  end
end)

local function canSmashWindowOnVehicle(veh)
  if not veh or veh == 0 or not DoesEntityExist(veh) then
    return false
  end

  if hasAnySeatedIdentity(veh) then
    return false
  end

  -- Roubo de carros estacionados: só com lockpick.
  if not isVehicleParked(veh) then
    return false
  end

  return true
end

local function canLockpickVehicle(veh, plate)
  if not canSmashWindowOnVehicle(veh) then
    return false
  end

  local hasLockpick = exports.ox_inventory:Search('count', Config.Lockpick.item) or 0
  return hasLockpick > 0
end

local function canCarjackWithLockpick(veh)
  if not veh or veh == 0 or not DoesEntityExist(veh) then
    return false
  end

  local driver = GetPedInVehicleSeat(veh, -1)
  if driver == 0 or not DoesEntityExist(driver) then
    return false
  end

  if IsPedAPlayer(driver) then
    return false
  end

  if GetEntitySpeed(veh) > 1.5 then
    return false
  end

  local hasLockpick = exports.ox_inventory:Search('count', Config.Lockpick.item) or 0
  return hasLockpick > 0
end

local function isPistolEquipped(ped)
  if not ped or ped == 0 then
    return false
  end

  local weapon = GetSelectedPedWeapon(ped)
  if not weapon or weapon == 0 then
    return false
  end

  local allowed = {
    joaat('WEAPON_PISTOL'),
    joaat('WEAPON_COMBATPISTOL'),
    joaat('WEAPON_PISTOL_MK2'),
    joaat('WEAPON_APPISTOL'),
    joaat('WEAPON_HEAVYPISTOL'),
    joaat('WEAPON_VINTAGEPISTOL'),
    joaat('WEAPON_SNSPISTOL'),
    joaat('WEAPON_SNSPISTOL_MK2'),
    joaat('WEAPON_CERAMICPISTOL'),
    joaat('WEAPON_PISTOL50'),
  }

  for i = 1, #allowed do
    if weapon == allowed[i] then
      return true
    end
  end

  return false
end

local function canCarjackByAiming(veh, driver)
  if not (Config.Carjack and Config.Carjack.enabled) then
    return false
  end

  if not veh or veh == 0 or not DoesEntityExist(veh) then
    return false
  end

  if not driver or driver == 0 or not DoesEntityExist(driver) or IsPedAPlayer(driver) then
    return false
  end

  if GetPedInVehicleSeat(veh, -1) ~= driver then
    return false
  end

  local ped = PlayerPedId()
  local dist = #(GetEntityCoords(ped) - GetEntityCoords(veh))
  if dist > (Config.CarjackDistance or 4.0) then
    return false
  end

  if GetEntitySpeed(veh) > 4.0 then
    return false
  end

  if Config.Carjack.requireWeapon and not IsPedArmed(ped, 6) then
    return false
  end

  if Config.Carjack.requirePistol and not isPistolEquipped(ped) then
    return false
  end

  local plate = normPlate(GetVehicleNumberPlateText(veh))
  if plate == '' then
    return false
  end

  local cd = carjackCooldown[plate]
  if cd and GetGameTimer() < cd then
    return false
  end

  return true
end

local function hasLockpickItem()
  local ok, count = pcall(function()
    return exports.ox_inventory:Search('count', Config.Lockpick.item)
  end)

  if not ok then
    return false
  end

  return (count or 0) > 0
end

local function triggerLockpickAlarmAndDispatch(veh, plate)
  if math.random(1, 100) > (Config.Lockpick.alarmChance or 100) then
    return
  end

  StartVehicleAlarm(veh)

  local coords = GetEntityCoords(veh)
  local streetHash, _ = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
  local streetName = GetStreetNameFromHashKey(streetHash)
  TriggerServerEvent('nord_keys:sv:dispatchCarTheft', { x = coords.x, y = coords.y, z = coords.z }, plate, streetName)
end

local function smashVehicleWindowWithElbow(veh, plate)
  local smashAnim = Config.Animations and Config.Animations.lockpick and Config.Animations.lockpick.smash or nil

  triggerLockpickAlarmAndDispatch(veh, plate)

  lib.progressBar({
    duration = 1800,
    label = 'A partir o vidro com o cotovelo...',
    useWhileDead = false,
    canCancel = false,
    disable = { move = true, car = true, combat = true },
    anim = smashAnim and {
      dict = smashAnim.dict,
      clip = smashAnim.clip,
      flag = smashAnim.flag or 49,
    } or nil,
  })

  local windowIndex = IsVehicleWindowIntact(veh, 0) and 0 or 1

  NetworkRequestControlOfEntity(veh)
  local timeout = GetGameTimer() + 1000
  while not NetworkHasControlOfEntity(veh) and GetGameTimer() < timeout do
    Wait(0)
  end

  SmashVehicleWindow(veh, windowIndex)
  SetVehicleDoorsLocked(veh, 1)
  SetVehicleDoorsLockedForAllPlayers(veh, false)
  SetVehicleDoorsLockedForPlayer(veh, PlayerId(), false)
end

local function executeParkedLockpick(veh)
  if not veh or not DoesEntityExist(veh) then
    return
  end

  local plate = normPlate(GetVehicleNumberPlateText(veh))
  if plate == '' then
    return
  end

  if not canLockpickVehicle(veh, plate) then
    notify('error', 'Só podes arrombar veículos estacionados e vazios.')
    return
  end

  fetchServerHasPhysicalKey(plate, function(hasPhysicalKey)
    if hasPhysicalKey then
      notify('inform', 'Já tens chave deste veículo.')
      return
    end

    smashVehicleWindowWithElbow(veh, plate)

    grantTempBreakInEntryAccess(plate, 5)
    markVehicleTemporarilyUnlocked(plate, 40)

    lib.progressBar({
      duration = 6000,
      label = 'A fazer ligação direta...',
      useWhileDead = false,
      canCancel = false,
      disable = { move = true, car = true, combat = true },
      anim = (Config.Animations and Config.Animations.lockpick and Config.Animations.lockpick.hotwire) and {
        dict = Config.Animations.lockpick.hotwire.dict,
        clip = Config.Animations.lockpick.hotwire.clip,
        flag = Config.Animations.lockpick.hotwire.flag or 49,
      } or nil,
    })

    local success = lib.skillCheck(Config.Lockpick.skillcheck or { 'easy', 'easy', 'medium' })
    if success then
      grantTempAccess(plate, Config.Lockpick.successTempMinutes or 20)
      tempKeyLoseOnEngineOff[plate] = true
      tempKeyEngineArmed[plate] = false

      local successAnim = Config.Animations and Config.Animations.lockpick and Config.Animations.lockpick.success or nil
      if successAnim then
        playSimpleAnim(successAnim.dict, successAnim.clip, successAnim.duration or 900, successAnim.flag or 48)
      end

      notify('success', Config.Text.lockpickSuccess)
      flashLights(veh, 2)

      TriggerServerEvent('nord_keys:sv:consumeLockpick', 'success')

      TriggerServerEvent('nord_keys:sv:lockpickSuccess', plate)
    else
      local failAnim = Config.Animations and Config.Animations.lockpick and Config.Animations.lockpick.fail or nil
      if failAnim then
        playSimpleAnim(failAnim.dict, failAnim.clip, failAnim.duration or 900, failAnim.flag or 48)
      end

      notify('error', Config.Text.lockpickFail)

      TriggerServerEvent('nord_keys:sv:consumeLockpick', 'fail')

      TriggerServerEvent('nord_keys:sv:lockpickFail', plate)
    end
  end)
end

local function tryLockpickClosestVehicle()
  if not Config.Lockpick.enabled then
    return
  end

  local veh = getClosestVehicle()
  if not veh or not DoesEntityExist(veh) then
    notify('error', 'Nenhum veículo próximo.')
    return
  end

  local plate = normPlate(GetVehicleNumberPlateText(veh))
  if plate ~= '' and canLockpickVehicle(veh, plate) then
    executeParkedLockpick(veh)
    return
  end

  notify('error', 'Precisas de lockpick e de um carro válido para arrombar.')
end

RegisterCommand('carlockpick', function()
  tryLockpickClosestVehicle()
end, false)

RegisterKeyMapping('carlockpick', 'Arrombar veículo com lockpick', 'keyboard', Config.LockpickKey or 'H')

CreateThread(function()
  if not Config.Lockpick.enabled then
    return
  end

  exports.ox_target:addGlobalVehicle({
    {
      name = 'nord_lockpick_parked_only',
      icon = 'fa-solid fa-car-burst',
      label = 'Roubar carro estacionado',
      distance = 2.5,
      canInteract = function(entity)
        if not entity or entity == 0 or not DoesEntityExist(entity) then
          return false
        end

        local plate = normPlate(GetVehicleNumberPlateText(entity))
        if plate == '' then
          return false
        end

        return hasLockpickItem() and canLockpickVehicle(entity, plate)
      end,
      onSelect = function(data)
        local veh = data.entity
        if not veh or not DoesEntityExist(veh) then
          return
        end

        executeParkedLockpick(veh)
      end,
    },
  })
end)

CreateThread(function()
  while true do
    Wait(150)

    if not (Config.Carjack and Config.Carjack.enabled) then
      goto continue_carjack_loop
    end

    local ped = PlayerPedId()
    if not IsPlayerFreeAiming(PlayerId()) then
      goto continue_carjack_loop
    end

    local aiming, entity = GetEntityPlayerIsFreeAimingAt(PlayerId())
    if not aiming or not entity or not DoesEntityExist(entity) or not IsEntityAPed(entity) then
      goto continue_carjack_loop
    end

    local driver = entity
    local veh = GetVehiclePedIsIn(driver, false)
    if veh == 0 then
      goto continue_carjack_loop
    end

    if not canCarjackByAiming(veh, driver) then
      goto continue_carjack_loop
    end

    local plate = normPlate(GetVehicleNumberPlateText(veh))
    if plate == '' then
      goto continue_carjack_loop
    end

    carjackCooldown[plate] = GetGameTimer() + 15000

    TaskHandsUp(driver, (Config.Animations and Config.Animations.carjack and Config.Animations.carjack.intimidateDriverMs) or 1200, ped, -1, false)
    Wait(300)

    TaskLeaveVehicle(driver, veh, 256)
    SetVehicleDoorsLocked(veh, 1)
    SetVehicleDoorsLockedForAllPlayers(veh, false)
    SetVehicleDoorsLockedForPlayer(veh, PlayerId(), false)

    grantTempBreakInEntryAccess(plate, 2)
    grantTempAccess(plate, (Config.Carjack and Config.Carjack.tempMinutes) or 2)
    markVehicleTemporarilyUnlocked(plate, 12)
    tempKeyLoseOnEngineOff[plate] = true
    tempKeyEngineArmed[plate] = false

    notify('success', Config.Text.carjackSuccess or 'Carjacking concluído.')

    ::continue_carjack_loop::
  end
end)

CreateThread(function()
  while true do
    Wait(350)

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
      local plate = normPlate(GetVehicleNumberPlateText(veh))
      if plate ~= '' and tempKeyLoseOnEngineOff[plate] then
        if GetIsVehicleEngineRunning(veh) then
          tempKeyEngineArmed[plate] = true
        elseif tempKeyEngineArmed[plate] then
          tempKeyLoseOnEngineOff[plate] = nil
          tempKeyEngineArmed[plate] = nil
          tempAccess[plate] = nil
          tempBreakInEntryAccess[plate] = nil
          SetVehicleEngineOn(veh, false, true, true)
          notify('error', Config.Text.carjackTempExpiredOnEngineOff or 'Motor desligado: chave temporária perdida.')
        end
      end
    end
  end
end)

local function trunkToggle(veh)
  if not DoesEntityExist(veh) then
    return
  end

  NetworkRequestControlOfEntity(veh)
  local timeout = GetGameTimer() + 1000
  while not NetworkHasControlOfEntity(veh) and GetGameTimer() < timeout do
    Wait(0)
  end

  local trunkDoor = 5
  if not DoesVehicleHaveDoor(veh, 5) then
    if DoesVehicleHaveDoor(veh, 4) then
      trunkDoor = 4
    else
      notify('error', 'Este veículo não tem mala.')
      return
    end
  end

  SetVehicleDoorsLocked(veh, 1)
  SetVehicleDoorsLockedForAllPlayers(veh, false)

  if GetVehicleDoorAngleRatio(veh, trunkDoor) > 0.1 then
    SetVehicleDoorShut(veh, trunkDoor, false)
  else
    SetVehicleDoorOpen(veh, trunkDoor, false, false)
  end
end

RegisterNUICallback('closeFob', function(_, cb)
  SetNuiFocus(false, false)
  currentPlate = nil
  SendNUIMessage({ action = 'outOfRange', state = false })
  cb(true)
end)

CreateThread(function()
  local isOutOfRange = false

  while true do
    Wait(500)

    if not currentPlate then
      if isOutOfRange then
        isOutOfRange = false
        SendNUIMessage({ action = 'outOfRange', state = false })
      end
    else
      local veh = getVehicleByPlate(currentPlate)
      local out = true

      if veh and veh ~= 0 then
        local ped = PlayerPedId()
        local dist = #(GetEntityCoords(ped) - GetEntityCoords(veh))
        out = dist > 15.0
      end

      if out ~= isOutOfRange then
        isOutOfRange = out
        SendNUIMessage({ action = 'outOfRange', state = isOutOfRange })
      end
    end
  end
end)

RegisterNetEvent('nord_keys:cl:syncVehicleLocked', function(plate, isLocked)
  plate = normPlate(plate)
  if plate == '' then
    return
  end

  local veh = getVehicleByPlate(plate)
  if veh and veh ~= 0 and DoesEntityExist(veh) then
    if isLocked then
      SetVehicleDoorsLocked(veh, 2)
    else
      SetVehicleDoorsLocked(veh, 1)
    end
    SetVehicleDoorsLockedForAllPlayers(veh, isLocked)
  end
end)

RegisterNetEvent('nord_keys:client:useKeyFob', function(item)
  if not item or not item.slot then
    return
  end

  TriggerServerEvent('nord_keys:sv:openKeyFobFromSlot', item.slot)
end)

RegisterNetEvent('nord_keys:client:openKeyFob', function(plate, battery, theme)
  plate = normPlate(plate)
  if plate == '' then
    notify('error', 'Chave inválida.')
    return
  end

  currentPlate = plate
  SetNuiFocus(true, true)

  SendNUIMessage({
    action = 'openFob',
    plate = plate,
    battery = tonumber(battery) or 100,
    theme = theme or 'bmw',
  })

  local veh = getVehicleByPlate(plate)
  if veh and veh ~= 0 then
    local doorLockStatus = GetVehicleDoorLockStatus(veh)
    local isLocked = (doorLockStatus == 2)
    SendNUIMessage({
      action = 'syncLockState',
      locked = isLocked,
    })
  end
end)

RegisterNUICallback('fobAction', function(data, cb)
  local action = data and data.action
  if not action or not currentPlate then
    cb(true)
    return
  end

  local plate = currentPlate

  fetchServerAccessState(plate, function(state)
    if not state.hasAccess then
      notify('error', Config.Text.noKey)
      return
    end

    if action == 'lock' or action == 'unlock' then
      fetchServerHasPhysicalKey(plate, function(hasPhysicalKey)
        if not hasPhysicalKey then
          notify('error', Config.Text.noKey)
          return
        end

        local veh = getVehicleByPlate(plate)
        if not veh then
          notify('error', 'Sem sinal do veículo.')
          return
        end

        playKeyAnim()

        if action == 'lock' then
          SetVehicleDoorsLocked(veh, 2)
          SetVehicleDoorsLockedForAllPlayers(veh, true)
          flashLights(veh, 2)
          playLockSound(veh, true)
          notify('success', Config.Text.locked)
          TriggerServerEvent('nord_keys:sv:syncVehicleLock', plate, true)
        else
          SetVehicleDoorsLocked(veh, 1)
          SetVehicleDoorsLockedForAllPlayers(veh, false)
          markVehicleTemporarilyUnlocked(plate, 18)
          flashLights(veh, 1)
          playLockSound(veh, false)
          notify('success', Config.Text.unlocked)
          TriggerServerEvent('nord_keys:sv:syncVehicleLock', plate, false)
        end
      end)

      return
    end

    local veh = getVehicleByPlate(plate)
    if not veh then
      notify('error', 'Sem sinal do veículo.')
      return
    end

    playKeyAnim()

    if action == 'trunk' then
      trunkToggle(veh)
    end
  end)

  cb(true)
end)

RegisterNetEvent('nord_keys:cl:updateNUILockState', function(plate, isLocked)
  plate = normPlate(plate)
  if not currentPlate or plate ~= currentPlate then
    return
  end

  SendNUIMessage({
    action = 'syncLockState',
    locked = isLocked,
  })
end)

local function spawnKeyLossPed()
  if not (Config.KeyLossNPC and Config.KeyLossNPC.enabled) then
    return
  end

  local hash = joaat(Config.KeyLossNPC.model)
  RequestModel(hash)
  while not HasModelLoaded(hash) do
    Wait(0)
  end

  local c = Config.KeyLossNPC.coords
  keyLossPed = CreatePed(0, hash, c.x, c.y, c.z - 1.0, c.w, false, true)

  SetEntityInvincible(keyLossPed, true)
  SetBlockingOfNonTemporaryEvents(keyLossPed, true)
  FreezeEntityPosition(keyLossPed, true)

  if Config.KeyLossNPC.scenario and Config.KeyLossNPC.scenario ~= '' then
    TaskStartScenarioInPlace(keyLossPed, Config.KeyLossNPC.scenario, 0, true)
  end

  if Config.KeyLossNPC.useOxTarget then
    local fee = math.max(0, tonumber((Config.KeyLossNPC and Config.KeyLossNPC.fee) or 0) or 0)
    local label = fee > 0 and ('Recuperar chave ($%s)'):format(fee) or 'Recuperar chave (perdida)'

    exports.ox_target:addLocalEntity(keyLossPed, {
      {
        label = label,
        icon = 'fa-solid fa-key',
        onSelect = function()
          TriggerEvent('nord_keys:cl:recoverLostKey')
        end,
      },
      {
        label = 'Dar chave temporária',
        icon = 'fa-solid fa-user-clock',
        onSelect = function()
          TriggerEvent('nord_keys:cl:npcGiveTempKey')
        end,
      },
    })
  end
end

CreateThread(function()
  Wait(1500)
  spawnKeyLossPed()
end)

RegisterNetEvent('nord_keys:cl:recoverLostKey', function()
  local veh = getClosestVehicle()

  if Config.KeyLossNPC.requireNearVehicle then
    if not veh then
      notify('error', 'Aproxima-te do veículo para recuperar a chave.')
      return
    end

    local ped = PlayerPedId()
    local dist = #(GetEntityCoords(ped) - GetEntityCoords(veh))
    if dist > (Config.KeyLossNPC.maxVehicleDist or 8.0) then
      notify('error', 'Estás demasiado longe do veículo.')
      return
    end
  end

  if not veh then
    notify('error', 'Nenhum veículo encontrado perto.')
    return
  end

  local plate = normPlate(GetVehicleNumberPlateText(veh))
  if plate == '' then
    return
  end

  lib.progressBar({
    duration = 2500,
    label = 'A verificar propriedade...',
    useWhileDead = false,
    canCancel = false,
    disable = { move = true, car = true, combat = true },
  })

  TriggerServerEvent('nord_keys:sv:recoverLostKey', plate)
end)

RegisterNetEvent('nord_keys:cl:npcGiveTempKey', function()
  local closestPlayer = getClosestPlayer(Config.TransferDistance or 3.0)
  if not closestPlayer then
    notify('error', 'Nenhum jogador próximo para receber a chave temporária.')
    return
  end

  local veh = getClosestVehicle()
  if not veh then
    notify('error', 'Nenhum veículo próximo para gerar chave temporária.')
    return
  end

  local plate = normPlate(GetVehicleNumberPlateText(veh))
  if plate == '' then
    notify('error', 'Matrícula inválida.')
    return
  end

  local input = lib.inputDialog('Dar Chave Temporária', {
    {
      type = 'number',
      label = 'Minutos',
      description = 'Duração da chave temporária',
      default = (Config.TempKeys and Config.TempKeys.defaultMinutes) or 30,
      min = (Config.TempKeys and Config.TempKeys.minMinutes) or 5,
      max = (Config.TempKeys and Config.TempKeys.maxMinutes) or 240,
      required = true,
    },
  })

  if not input then
    return
  end

  local minutes = tonumber(input[1])
  local targetSrc = GetPlayerServerId(closestPlayer)
  if not targetSrc then
    notify('error', 'Jogador alvo inválido.')
    return
  end

  TriggerServerEvent('nord_keys:sv:transferTempKey', plate, targetSrc, minutes)
end)

RegisterCommand('recoverkey', function()
  TriggerEvent('nord_keys:cl:recoverLostKey')
end, false)

RegisterCommand('tempkey', function(args)
  local targetSrc = tonumber(args[1])
  local minutes = tonumber(args[2])

  if not targetSrc then
    notify('error', 'Uso: /tempkey [id] [minutos]')
    return
  end

  local veh = getClosestVehicle()
  if not veh then
    notify('error', 'Nenhum veículo próximo para gerar chave temporária.')
    return
  end

  local plate = normPlate(GetVehicleNumberPlateText(veh))
  if plate == '' then
    notify('error', 'Matrícula inválida.')
    return
  end

  TriggerServerEvent('nord_keys:sv:transferTempKey', plate, targetSrc, minutes)
end, false)
