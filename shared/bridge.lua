Bridge = {}

local function dbg(...)
  if Config.Debug then
    print("^3[nord_keys:bridge]^7", ...)
  end
end

local function GetQB()
  local ok, qb = pcall(function()
    return exports['qb-core']:GetCoreObject()
  end)
  if ok and qb then return qb end
  return nil
end

function Bridge.Notify(src, typ, msg, title)
  TriggerClientEvent('ox_lib:notify', src, {
    type = typ or 'inform',
    title = title,
    description = msg or ''
  })
end

function Bridge.NotifyClient(typ, msg, title)
  if IsDuplicityVersion() then
    return
  end

  if lib and lib.notify then
    lib.notify({
      type = typ or 'inform',
      title = title,
      description = msg or ''
    })
    return
  end

  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(tostring(msg or ''))
  EndTextCommandThefeedPostTicker(false, false)
end

function Bridge.GetIdentifier(src)
  if Config.Framework == 'qb' then
    local QBCore = GetQB()
    if not QBCore then return nil end
    local ply = QBCore.Functions.GetPlayer(src)
    return ply and ply.PlayerData and ply.PlayerData.citizenid or nil
  end

  if Config.Framework == 'esx' then
    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer and xPlayer.identifier or nil
  end

  return nil
end

function Bridge.GetJobName(src)
  if Config.Framework == 'qb' then
    local QBCore = GetQB()
    if not QBCore then return nil end
    local ply = QBCore.Functions.GetPlayer(src)
    return ply and ply.PlayerData and ply.PlayerData.job and ply.PlayerData.job.name or nil
  end

  if Config.Framework == 'esx' then
    local xPlayer = ESX.GetPlayerFromId(src)
    local job = xPlayer and xPlayer.getJob and xPlayer.getJob() or nil
    return job and job.name or nil
  end

  return nil
end

function Bridge.IsMasterKey(src)
  local job = Bridge.GetJobName(src)
  if not job then return false end
  for _, j in ipairs(Config.MasterKeyJobs or {}) do
    if j == job then return true end
  end
  return false
end

function Bridge.IsPolice(src)
  local job = Bridge.GetJobName(src)
  if not job then return false end
  for _, j in ipairs(Config.PoliceJobs or {}) do
    if j == job then return true end
  end
  return false
end

function Bridge.TryCharge(src, amount, reason)
  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then
    return true
  end

  reason = reason or 'nord_keys'

  if Config.Framework == 'qb' then
    local QBCore = GetQB()
    if not QBCore then return false end
    local ply = QBCore.Functions.GetPlayer(src)
    if not ply then return false end

    if ply.Functions.RemoveMoney('cash', amount, reason) then
      return true
    end

    return ply.Functions.RemoveMoney('bank', amount, reason)
  end

  if Config.Framework == 'esx' then
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false end

    local cash = xPlayer.getMoney and xPlayer.getMoney() or 0
    if cash >= amount then
      xPlayer.removeMoney(amount)
      return true
    end

    local bank = 0
    if xPlayer.getAccount then
      local account = xPlayer.getAccount('bank')
      bank = account and account.money or 0
    end

    if bank >= amount then
      if xPlayer.removeAccountMoney then
        xPlayer.removeAccountMoney('bank', amount)
      end
      return true
    end

    return false
  end

  return false
end

function Bridge.GiveMoney(src, amount, reason)
  amount = math.floor(tonumber(amount) or 0)
  if amount <= 0 then
    return true
  end

  reason = reason or 'nord_keys'

  if Config.Framework == 'qb' then
    local QBCore = GetQB()
    if not QBCore then return false end
    local ply = QBCore.Functions.GetPlayer(src)
    if not ply then return false end
    return ply.Functions.AddMoney('cash', amount, reason)
  end

  if Config.Framework == 'esx' then
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false end
    if xPlayer.addMoney then
      xPlayer.addMoney(amount)
      return true
    end
  end

  return false
end