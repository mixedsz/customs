local Framework = nil
local playerScales = {}

-- ─────────────────────────────────────────────────────────────────────
--  FRAMEWORK INIT
-- ─────────────────────────────────────────────────────────────────────
CreateThread(function()
    if Config.Framework == 'ESX' then
        while GetResourceState('es_extended') ~= 'started' do Wait(500) end
        Framework = exports['es_extended']:getSharedObject()
    elseif Config.Framework == 'QB' then
        while GetResourceState('qb-core') ~= 'started' do Wait(500) end
        Framework = exports['qb-core']:GetCoreObject()
    elseif Config.Framework == 'Qbox' then
        while GetResourceState('qbx_core') ~= 'started' do Wait(500) end
        Framework = exports['qbx_core']:GetCoreObject()
    end
end)

-- ─────────────────────────────────────────────────────────────────────
--  DATABASE ABSTRACTION  (oxmysql & mysql-async supported)
-- ─────────────────────────────────────────────────────────────────────
local function dbExecute(query, params, cb)
    if GetResourceState('oxmysql') == 'started' then
        exports.oxmysql:execute(query, params, cb or function() end)
    elseif GetResourceState('mysql-async') == 'started' then
        exports['mysql-async']:execute(query, params, cb or function() end)
    else
        if Config.SaveToChar then
            print('[ScaleM] ^1No MySQL resource found. Install oxmysql or mysql-async.^0')
        end
        if cb then cb(nil) end
    end
end

local function dbScalar(query, params, cb)
    if GetResourceState('oxmysql') == 'started' then
        exports.oxmysql:scalar(query, params, cb)
    elseif GetResourceState('mysql-async') == 'started' then
        exports['mysql-async']:fetchScalar(query, params, cb)
    else
        cb(nil)
    end
end

-- Auto-create table
if Config.SaveToChar then
    CreateThread(function()
        Wait(1500)
        dbExecute([[
            CREATE TABLE IF NOT EXISTS `player_scales` (
                `identifier` VARCHAR(60) NOT NULL,
                `scale`      FLOAT       NOT NULL DEFAULT 1.0,
                PRIMARY KEY  (`identifier`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ]], {})
    end)
end

-- ─────────────────────────────────────────────────────────────────────
--  HELPERS
-- ─────────────────────────────────────────────────────────────────────
local function GetCharIdentifier(source)
    if Config.Framework == 'ESX' and Framework then
        local player = Framework.GetPlayerFromId(source)
        if player then return player.getIdentifier() end
    elseif (Config.Framework == 'QB' or Config.Framework == 'Qbox') and Framework then
        local player = Framework.Functions.GetPlayer(source)
        if player then return player.PlayerData.citizenid end
    end
    for i = 0, GetNumPlayerIdentifiers(source) - 1 do
        local id = GetPlayerIdentifier(source, i)
        if id and id:sub(1, 8) == 'license:' then return id end
    end
    return nil
end

local function GetDiscordId(source)
    for i = 0, GetNumPlayerIdentifiers(source) - 1 do
        local id = GetPlayerIdentifier(source, i)
        if id and id:sub(1, 8) == 'discord:' then return id:sub(9) end
    end
    return nil
end

local function CheckIdentifiers(source)
    for i = 0, GetNumPlayerIdentifiers(source) - 1 do
        local id = GetPlayerIdentifier(source, i)
        if id then
            for _, allowed in ipairs(Config.Permissions.AllowedIdentifiers) do
                if id == allowed then return true end
            end
        end
    end
    return false
end

local function CheckDiscordRoles(source, cb)
    if #Config.Permissions.AllowedDiscordRoles == 0 then return cb(false) end
    if Config.Discord.Token == '' or Config.Discord.Guild == '' then
        print('[ScaleM] ^3Discord Token or Guild ID not set in config.^0')
        return cb(false)
    end
    local discordId = GetDiscordId(source)
    if not discordId then return cb(false) end

    PerformHttpRequest(
        ('https://discord.com/api/v10/guilds/%s/members/%s'):format(Config.Discord.Guild, discordId),
        function(status, data)
            if status ~= 200 or not data then return cb(false) end
            local ok, member = pcall(json.decode, data)
            if not ok or not member or not member.roles then return cb(false) end
            for _, allowed in ipairs(Config.Permissions.AllowedDiscordRoles) do
                for _, role in ipairs(member.roles) do
                    if role == allowed then return cb(true) end
                end
            end
            cb(false)
        end,
        'GET', '',
        { ['Authorization'] = 'Bot ' .. Config.Discord.Token }
    )
end

local function HasPermission(source, cb)
    if not Config.Permissions.UseWhitelist then return cb(true) end
    if CheckIdentifiers(source) then return cb(true) end
    CheckDiscordRoles(source, cb)
end

-- ─────────────────────────────────────────────────────────────────────
--  NET EVENTS
-- ─────────────────────────────────────────────────────────────────────

-- Player requests to open the menu
RegisterNetEvent('ScaleM:RequestOpen', function()
    local src = source
    HasPermission(src, function(allowed)
        if not allowed then
            TriggerClientEvent('ScaleM:Notify', src, 'You do not have permission to use the Scale Menu.', 'error')
            return
        end

        if Config.SaveToChar then
            local id = GetCharIdentifier(src)
            if id then
                dbScalar(
                    'SELECT `scale` FROM `player_scales` WHERE `identifier` = ?',
                    { id },
                    function(result)
                        TriggerClientEvent('ScaleM:OpenMenu', src, tonumber(result) or Config.DefaultScale)
                    end
                )
                return
            end
        end

        TriggerClientEvent('ScaleM:OpenMenu', src, Config.DefaultScale)
    end)
end)

-- Player confirms their scale selection
RegisterNetEvent('ScaleM:SaveScale', function(scale)
    local src = source
    if type(scale) ~= 'number' then return end
    scale = math.max(Config.MinScale, math.min(Config.MaxScale, scale))

    playerScales[src] = scale
    TriggerClientEvent('ScaleM:SyncScale', -1, src, scale)

    if Config.SaveToChar then
        local id = GetCharIdentifier(src)
        if id then
            dbExecute(
                'INSERT INTO `player_scales` (`identifier`, `scale`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `scale` = ?',
                { id, scale, scale }
            )
        end
    end
end)

-- Player resets to default
RegisterNetEvent('ScaleM:ResetScale', function()
    local src   = source
    local scale = Config.DefaultScale
    playerScales[src] = scale
    TriggerClientEvent('ScaleM:SyncScale', -1, src, scale)
    if Config.SaveToChar then
        local id = GetCharIdentifier(src)
        if id then
            dbExecute(
                'INSERT INTO `player_scales` (`identifier`, `scale`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `scale` = ?',
                { id, scale, scale }
            )
        end
    end
end)

-- Player requests their saved scale on spawn / resource start
RegisterNetEvent('ScaleM:RequestSavedScale', function()
    local src = source
    if not Config.SaveToChar then return end
    local id = GetCharIdentifier(src)
    if not id then return end
    dbScalar(
        'SELECT `scale` FROM `player_scales` WHERE `identifier` = ?',
        { id },
        function(result)
            if result then
                local scale = tonumber(result)
                playerScales[src] = scale
                TriggerClientEvent('ScaleM:SyncScale', -1, src, scale)
            end
        end
    )
end)

-- Client requests all currently scaled players (late joiners)
RegisterNetEvent('ScaleM:RequestAllScales', function()
    local src = source
    TriggerClientEvent('ScaleM:SyncAllScales', src, playerScales)
end)

-- Clean up when a player leaves
AddEventHandler('playerDropped', function()
    local src = source
    playerScales[src] = nil
    TriggerClientEvent('ScaleM:SyncScale', -1, src, Config.DefaultScale)
end)

-- Admin gives menu to another player
RegisterNetEvent('ScaleM:GiveMenu', function(targetId)
    local src = source
    HasPermission(src, function(allowed)
        if not allowed then
            TriggerClientEvent('ScaleM:Notify', src, 'You do not have permission.', 'error')
            return
        end

        local target = tonumber(targetId)
        if not target or not GetPlayerName(target) then
            TriggerClientEvent('ScaleM:Notify', src, 'Invalid player ID.', 'error')
            return
        end

        if Config.SaveToChar then
            local id = GetCharIdentifier(target)
            if id then
                dbScalar(
                    'SELECT `scale` FROM `player_scales` WHERE `identifier` = ?',
                    { id },
                    function(result)
                        TriggerClientEvent('ScaleM:OpenMenu', target, tonumber(result) or Config.DefaultScale)
                    end
                )
                return
            end
        end

        TriggerClientEvent('ScaleM:OpenMenu', target, Config.DefaultScale)
    end)
end)

-- Admin resets another player's scale
RegisterNetEvent('ScaleM:AdminReset', function(targetId)
    local src = source
    HasPermission(src, function(allowed)
        if not allowed then
            TriggerClientEvent('ScaleM:Notify', src, 'You do not have permission.', 'error')
            return
        end

        local target = tonumber(targetId)
        if not target or not GetPlayerName(target) then
            TriggerClientEvent('ScaleM:Notify', src, 'Invalid player ID.', 'error')
            return
        end

        local scale = Config.DefaultScale
        playerScales[target] = scale
        TriggerClientEvent('ScaleM:SyncScale', -1, target, scale)
        if Config.SaveToChar then
            local id = GetCharIdentifier(target)
            if id then
                dbExecute(
                    'INSERT INTO `player_scales` (`identifier`, `scale`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `scale` = ?',
                    { id, scale, scale }
                )
            end
        end
        TriggerClientEvent('ScaleM:Notify', target, 'Your scale has been reset by an admin.', 'inform')
        TriggerClientEvent('ScaleM:Notify', src, ('Reset scale for player %s.'):format(GetPlayerName(target)), 'success')
    end)
end)

-- On resource restart, sync scales for already-connected players
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    Wait(2000)
    for _, src in ipairs(GetPlayers()) do
        src = tonumber(src)
        local id = GetCharIdentifier(src)
        if id then
            dbScalar(
                'SELECT `scale` FROM `player_scales` WHERE `identifier` = ?',
                { id },
                function(result)
                    local scale = tonumber(result) or Config.DefaultScale
                    playerScales[src] = scale
                    if scale ~= Config.DefaultScale then
                        TriggerClientEvent('ScaleM:SyncScale', -1, src, scale)
                    end
                end
            )
        end
    end
end)
