Config = {}

-- "qb" ou "esx"
Config.Framework = "qb"

Config.Debug = false

-- Keybind
Config.LockKey = 'L'

-- Distâncias
Config.VehicleSearchRadius = 6.0
Config.TransferDistance = 3.0
Config.CarjackDistance = 4.0

-- Engine lock behavior
Config.EngineLock = {
  enabled = true,
  checkIntervalMs = 350,
  allowPassengers = true, -- passageiros não bloqueiam
  blockStartIfNoKey = true,
  driverEjectDelayMs = 3000, -- tempo antes de tirar do banco do condutor sem chave
}

-- Master key (pode abrir/fechar + ligar motor sem item)
-- QBCore: compara PlayerData.job.name
-- ESX: compara xPlayer.getJob().name
Config.MasterKeyJobs = { 'police', 'sheriff', 'mechanic' }

-- Lockpick / Hotwire
Config.Lockpick = {
  enabled = true,
  item = 'lockpick',
  consumeOnFailChance = 35,   -- % chance de consumir em falha
  consumeOnSuccessChance = 10,-- % chance de consumir em sucesso
  successTempMinutes = 20,    -- dá “chave temporária” por X min
  skillcheck = { 'easy', 'easy', 'medium' }, -- ox_lib
  allowIfVehicleLocked = true,
}

-- Carjack (ameaçar condutor -> destranca e dá temp key curta)
Config.Carjack = {
  enabled = true,
  requireWeapon = true,
  tempMinutes = 5
}

-- Discord webhook (opcional)
Config.Discord = {
  enabled = false,
  webhook = '',
  username = 'nord_keys',
}

-- DB owned vehicles integration (opcional; deixo hooks prontos)
-- Se meteres true, tenta registar owner ao entrar num carro que esteja na tabela do teu framework
Config.OwnedVehicles = {
  enabled = false,
  -- "auto" tenta detetar, ou força:
  -- QBCore comum: player_vehicles (plate, citizenid)
  -- ESX comum: owned_vehicles (plate, owner)
  mode = 'auto'
}

Config.KeyLossNPC = {
  enabled = true,
  model = "a_m_m_business_01",
  coords = vec4(-542.0, -206.44, 37.65, 50.7), -- mete onde quiseres
  scenario = "WORLD_HUMAN_CLIPBOARD",
  useOxTarget = true,

  fee = 250,            -- 0 para grátis (se quiseres cobrar depois eu ligo ao dinheiro)
  requireNearVehicle = true,
  maxVehicleDist = 8.0,
}

-- IMPORTANT: precisa de OwnedVehicles para confirmar dono
Config.OwnedVehicles = Config.OwnedVehicles or {}
Config.OwnedVehicles.enabled = true
-- mode pode ficar auto, ou força:
-- Config.OwnedVehicles.mode = 'qb_player_vehicles'
-- Config.OwnedVehicles.mode = 'esx_owned_vehicles'

-- Texto PT
Config.Text = {
  noKey = 'Não tens a chave deste veículo.',
  locked = 'Veículo trancado.',
  unlocked = 'Veículo destrancado.',
  engineBlocked = 'Não tens chave para ligar este veículo.',
  gaveKey = 'Entregaste uma chave.',
  receivedKey = 'Recebeste uma chave.',
  invalidTarget = 'Não há ninguém perto.',
  keyRevoked = 'Chave revogada.',
  lockpickStart = 'A tentar abrir...',
  lockpickSuccess = 'Conseguiste! Chave temporária criada.',
  lockpickFail = 'Falhaste.',
  carjackSuccess = 'Veículo rendido. Chave temporária criada.',
}