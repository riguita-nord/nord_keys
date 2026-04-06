Config = {}

-- "qb" ou "esx"
Config.Framework = "qb"

Config.Debug = false

-- Keybind
Config.LockKey = 'L'
Config.LockpickKey = 'H'

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

-- Jobs que recebem alertas de arrombamento (lockpick)
Config.PoliceJobs = { 'police', 'sheriff', 'ranger', 'bcso', 'sasp' }

-- Lockpick / Hotwire
Config.Lockpick = {
  enabled = true,
  item = 'lockpick',
  consumeOnFailChance = 35,   -- % chance de consumir em falha
  consumeOnSuccessChance = 10,-- % chance de consumir em sucesso
  alarmChance = 100,          -- % chance de disparar alarme + dispatch ao fazer lockpick (0-100)
  successTempMinutes = 20,    -- dá “chave temporária” por X min
  skillcheck = { 'easy', 'easy', 'medium' }, -- ox_lib
  allowIfVehicleLocked = true,
  durability = {
    enabled = true,
    maxUses = 2,              -- usos totais de um lockpick novo
    lossOnSuccess = 1,        -- usos gastos em sucesso
    lossOnFail = 1,           -- usos gastos em falha
    notifyWear = true,        -- mostra feedback com usos restantes
    removeWhenBroken = true,  -- remove item quando usos chegarem a 0
  },
}

Config.Animations = {
  enabled = true,
  lockpick = {
    smash = { dict = 'veh@break_in@0h@p_m_one@', clip = 'low_force_entry_ds', flag = 49 },
    hotwire = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer', flag = 49 },
    success = { dict = 'anim@mp_player_intcelebrationmale@thumbs_up', clip = 'thumbs_up', duration = 900, flag = 48 },
    fail = { dict = 'amb@code_human_wander_texting@male@base', clip = 'static', duration = 900, flag = 48 },
  },
  carjack = {
    intimidateDriverMs = 1200,
  },
}

-- Carjack (ameaçar condutor -> destranca e dá temp key curta)
Config.Carjack = {
  enabled = true,
  requireWeapon = true,
  requirePistol = true,
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
  enabled = true,
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

Config.TempKeys = {
  enabled = true,
  defaultMinutes = 30,
  minMinutes = 5,
  maxMinutes = 240,
}

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
  keyRecoverNoMoney = 'Não tens dinheiro suficiente para recuperar a chave.',
  keyRecoverPaid = 'Chave recuperada (%s). Custo: $%s',
  tempKeyGiven = 'Chave temporária entregue por %s minutos.',
  tempKeyReceived = 'Recebeste uma chave temporária por %s minutos.',
  tempKeyExpired = 'Esta chave temporária expirou.',
  lockpickStart = 'A tentar abrir...',
  lockpickSuccess = 'Conseguiste! Chave temporária criada.',
  lockpickFail = 'Falhaste.',
  lockpickWear = 'Usos do lockpick restantes: %s.',
  lockpickBroken = 'O lockpick partiu-se.',
  carjackSuccess = 'Veículo rendido. Chave temporária criada.',
  carjackTempExpiredOnEngineOff = 'Motor desligado: perdeste a chave temporária.',
}