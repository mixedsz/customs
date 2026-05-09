local isMenuOpen          = false
local currentScale        = Config.DefaultScale
local savedScale          = Config.DefaultScale
local previewScale        = nil
local weaponNotifCooldown = false

local scaledPlayers = {}
local previewCam    = nil

-- ─────────────────────────────────────────────────────────────────────
--  SCALE HELPERS
-- ─────────────────────────────────────────────────────────────────────
local function RawScale(ped, scale)
    if not ped or not DoesEntityExist(ped) then return end

    local ok, forward, right, up, pos = pcall(GetEntityMatrix, ped)
    if not ok or not forward or #forward == 0 or not right or #right == 0 or not up or #up == 0 then
        return
    end

    local sf = (forward / #forward) * scale
    local sr = (right   / #right)   * scale
    local su = (up      / #up)      * scale

    -- Ground clamp: keep feet on ground.
    -- This matches the proven approach in flake-pedscale.
    local adjustedPos = vector3(pos.x, pos.y, pos.z)
    local heightAbove = GetEntityHeightAboveGround(ped)

    if heightAbove and heightAbove <= 1.5 then
        local adjustedZ = pos.z - heightAbove + (1.0 * scale)
        adjustedPos = vector3(pos.x, pos.y, adjustedZ)
    end

    pcall(SetEntityMatrix, ped, sf, sr, su, adjustedPos)
end

local function AddScaledPlayer(serverId, scale)
    for _, entry in ipairs(scaledPlayers) do
        if entry.id == serverId then
            entry.scale = scale
            entry.ped   = nil
            return
        end
    end
    table.insert(scaledPlayers, { id = serverId, scale = scale, ped = nil })
end

local function RemoveScaledPlayer(serverId)
    for i = #scaledPlayers, 1, -1 do
        if scaledPlayers[i].id == serverId then
            table.remove(scaledPlayers, i)
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────
--  CAMERA  (frozen in world space, never updates after open)
-- ─────────────────────────────────────────────────────────────────────
local camTargetPos = nil

local function SetupPreviewCamera()
    local ped = PlayerPedId()
    if not previewCam or not DoesCamExist(previewCam) then
        previewCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    end

    -- Distance far enough to see max-height peds fully
    local dist  = 4.2
    local hgt   = 1.4
    local left  = -1.2

    -- Front-left of player
    local camOffset = GetOffsetFromEntityInWorldCoords(ped, left, dist, hgt)
    SetCamCoord(previewCam, camOffset.x, camOffset.y, camOffset.z)

    -- Lock look-at target to the player's chest position AT OPEN TIME
    -- so scaling later doesn't shift the camera view
    local boneCoords = GetPedBoneCoords(ped, 24818, 0.0, 0.0, 0.0)
    camTargetPos = vector3(boneCoords.x, boneCoords.y, boneCoords.z)
    PointCamAtCoord(previewCam, camTargetPos.x, camTargetPos.y, camTargetPos.z)

    SetCamFov(previewCam, 48.0)
    SetCamActive(previewCam, true)
    RenderScriptCams(true, true, 800, true, true)

    -- Keep ped standing still without freezing physics.
    -- FreezeEntityPosition + SetEntityMatrix position change launches the player.
    ClearPedTasksImmediately(ped)
    TaskStandStill(ped, -1)
end

local function DestroyPreviewCamera()
    if previewCam and DoesCamExist(previewCam) then
        SetCamActive(previewCam, false)
        RenderScriptCams(false, true, 500, true, true)
        DestroyCam(previewCam, false)
        previewCam = nil
    end
    camTargetPos = nil
    ClearPedTasks(PlayerPedId())
end

-- ─────────────────────────────────────────────────────────────────────
--  NOTIFICATION
-- ─────────────────────────────────────────────────────────────────────
local function Notify(msg, notifType)
    if Config.Framework == 'ESX' then
        local ESX = exports['es_extended']:getSharedObject()
        ESX.ShowNotification((notifType == 'error' and '~r~' or '~g~') .. msg)
    elseif Config.Framework == 'QB' then
        local QBCore = exports['qb-core']:GetCoreObject()
        QBCore.Functions.Notify(msg, notifType or 'primary')
    elseif Config.Framework == 'Qbox' then
        local QBX = exports['qbx_core']:GetCoreObject()
        QBX.Functions.Notify(msg, notifType or 'inform')
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(msg)
        EndTextCommandThefeedPostTicker(false, true)
    end
end

-- ─────────────────────────────────────────────────────────────────────
--  SERVER EVENTS
-- ─────────────────────────────────────────────────────────────────────

RegisterNetEvent('ScaleM:SyncScale', function(serverId, scale)
    scale = tonumber(scale)
    if not scale then return end

    if serverId == GetPlayerServerId(PlayerId()) then
        currentScale = scale
        savedScale   = scale
        -- Local player is handled by the enforcement thread directly.
        -- Don't add to scaledPlayers to avoid double-processing.
        if scale == Config.DefaultScale then
            RemoveScaledPlayer(serverId)
        end
    else
        if scale == Config.DefaultScale then
            RemoveScaledPlayer(serverId)
        else
            AddScaledPlayer(serverId, scale)
        end
        for _, player in ipairs(GetActivePlayers()) do
            if GetPlayerServerId(player) == serverId then
                local ped = GetPlayerPed(player)
                if DoesEntityExist(ped) then RawScale(ped, scale) end
                break
            end
        end
    end
end)

RegisterNetEvent('ScaleM:SyncAllScales', function(scales)
    local localPed    = PlayerPedId()
    local localCoords = GetEntityCoords(localPed)
    scaledPlayers = {}

    for id, s in pairs(scales) do
        s  = tonumber(s)
        id = tonumber(id)
        if s and s ~= Config.DefaultScale and id ~= GetPlayerServerId(PlayerId()) then
            table.insert(scaledPlayers, { id = id, scale = s, ped = nil })

            local targetPlayer = GetPlayerFromServerId(id)
            if targetPlayer and NetworkIsPlayerActive(targetPlayer) then
                local ped = GetPlayerPed(targetPlayer)
                if DoesEntityExist(ped) then
                    local dist = #(localCoords - GetEntityCoords(ped))
                    if dist <= 30.0 then
                        RawScale(ped, s)
                    end
                end
            end
        end
    end
end)

RegisterNetEvent('ScaleM:Notify', function(msg, notifType)
    Notify(msg, notifType)
end)

RegisterNetEvent('ScaleM:OpenMenu', function(scale)
    if Config.GenderRestriction then
        local ped    = PlayerPedId()
        local isMale = IsPedMale(ped)
        if Config.GenderRestriction == 'male' and not isMale then
            Notify('Only male characters can use the Scale Menu.', 'error')
            return
        end
        if Config.GenderRestriction == 'female' and isMale then
            Notify('Only female characters can use the Scale Menu.', 'error')
            return
        end
    end

    currentScale = scale
    savedScale   = scale
    previewScale = nil
    isMenuOpen   = true

    SetupPreviewCamera()
    SetNuiFocus(true, true)
    SendNUIMessage({
        type         = 'openMenu',
        scale        = currentScale,
        minScale     = Config.MinScale,
        maxScale     = Config.MaxScale,
        defaultScale = Config.DefaultScale,
        themeColor   = Config.ThemeColor,
    })
end)

-- ─────────────────────────────────────────────────────────────────────
--  NUI CALLBACKS
-- ─────────────────────────────────────────────────────────────────────

-- Live preview: apply scale immediately but do NOT save.
RegisterNUICallback('preview', function(data, cb)
    cb({})
    local scale = tonumber(data.scale)
    if not scale then
        print('[ScaleM] preview: invalid scale')
        return
    end
    scale = math.max(Config.MinScale, math.min(Config.MaxScale, scale))
    previewScale = scale
    print(('[ScaleM] preview → scale=%.3f  isMenuOpen=%s'):format(scale, tostring(isMenuOpen)))
    RawScale(PlayerPedId(), scale)
end)

RegisterNUICallback('confirm', function(data, cb)
    isMenuOpen = false
    SetNuiFocus(false, false)
    DestroyPreviewCamera()
    cb({})

    local scale = tonumber(data.scale)
    if not scale then return end
    scale = math.max(Config.MinScale, math.min(Config.MaxScale, scale))
    currentScale = scale
    savedScale   = scale
    previewScale = nil

    RawScale(PlayerPedId(), scale)
    TriggerServerEvent('ScaleM:SaveScale', scale)
    print(('[ScaleM] confirm → scale=%.3f'):format(scale))
end)

RegisterNUICallback('reset', function(_, cb)
    isMenuOpen = false
    SetNuiFocus(false, false)
    DestroyPreviewCamera()
    cb({})

    currentScale = Config.DefaultScale
    savedScale   = Config.DefaultScale
    previewScale = nil
    RemoveScaledPlayer(GetPlayerServerId(PlayerId()))
    RawScale(PlayerPedId(), Config.DefaultScale)
    TriggerServerEvent('ScaleM:ResetScale')
end)

RegisterNUICallback('close', function(_, cb)
    isMenuOpen = false
    SetNuiFocus(false, false)
    DestroyPreviewCamera()
    cb({})

    currentScale = savedScale
    previewScale = nil
    RawScale(PlayerPedId(), savedScale)
end)

-- ─────────────────────────────────────────────────────────────────────
--  DISABLE MOVEMENT WHILE MENU OPEN
-- ─────────────────────────────────────────────────────────────────────
CreateThread(function()
    while true do
        if isMenuOpen then
            DisableControlAction(0, 30, true) -- A / D
            DisableControlAction(0, 31, true) -- W / S
            DisableControlAction(0, 21, true) -- Shift (sprint)
            DisableControlAction(0, 22, true) -- Space (jump)
            DisableControlAction(0, 23, true) -- F (enter vehicle)
            DisableControlAction(0, 44, true) -- Q (cover)
            DisableControlAction(0, 140, true) -- Melee
            DisableControlAction(0, 141, true) -- Melee
            DisableControlAction(0, 142, true) -- Melee
            DisableControlAction(0, 143, true) -- Melee
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ─────────────────────────────────────────────────────────────────────
--  COMMANDS
-- ─────────────────────────────────────────────────────────────────────
RegisterCommand(Config.Commands.menu.name, function()
    if isMenuOpen then return end
    TriggerServerEvent('ScaleM:RequestOpen')
end, false)

RegisterCommand(Config.Commands.give.name, function(_, args)
    local targetId = tonumber(args[1])
    if not targetId then
        Notify('Usage: /' .. Config.Commands.give.name .. ' [player id]', 'error')
        return
    end
    TriggerServerEvent('ScaleM:GiveMenu', targetId)
end, true)

RegisterCommand(Config.Commands.reset.name, function(_, args)
    local targetId = tonumber(args[1])
    if targetId then
        TriggerServerEvent('ScaleM:AdminReset', targetId)
    else
        currentScale = Config.DefaultScale
        savedScale   = Config.DefaultScale
        previewScale = nil
        RemoveScaledPlayer(GetPlayerServerId(PlayerId()))
        RawScale(PlayerPedId(), Config.DefaultScale)
        TriggerServerEvent('ScaleM:ResetScale')
        Notify('Your scale has been reset.', 'success')
    end
end, false)

-- ─────────────────────────────────────────────────────────────────────
--  WEAPON BLOCKING
-- ─────────────────────────────────────────────────────────────────────
if Config.BlockWeapons then
    CreateThread(function()
        while true do
            Wait(0)
            local ped = PlayerPedId()
            local activeScale = previewScale or currentScale
            if math.abs(activeScale - Config.DefaultScale) > 0.005 then
                if GetSelectedPedWeapon(ped) ~= GetHashKey('WEAPON_UNARMED') then
                    SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
                    if not weaponNotifCooldown then
                        weaponNotifCooldown = true
                        Notify('Weapons are disabled while your character is scaled.', 'error')
                        SetTimeout(5000, function() weaponNotifCooldown = false end)
                    end
                end
            else
                Wait(500)
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────
--  PED CHANGE DETECTION  (respawn / model swap)
-- ─────────────────────────────────────────────────────────────────────
CreateThread(function()
    local lastPed = PlayerPedId()
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        if ped ~= lastPed then
            lastPed = ped
            Wait(800)
            local activeScale = previewScale or currentScale
            if activeScale ~= Config.DefaultScale then
                RawScale(ped, activeScale)
            end
        end
    end
end)

-- ─────────────────────────────────────────────────────────────────────
--  SCALE MATRIX ENFORCEMENT  (self + nearby scaled players)
-- ─────────────────────────────────────────────────────────────────────
CreateThread(function()
    while true do
        local waitTime = 500
        local activeScale = previewScale or currentScale

        -- Always enforce our own scale every frame.
        -- SetEntityMatrix does NOT persist — GTA resets it each tick.
        -- previewScale is used while the menu is open; currentScale when closed.
        if activeScale ~= Config.DefaultScale then
            RawScale(PlayerPedId(), activeScale)
            waitTime = 0
        end

        -- Enforce visible scaled players
        if #scaledPlayers > 0 then
            waitTime = 0
            local localPed    = PlayerPedId()
            local localCoords = GetEntityCoords(localPed)

            for i = #scaledPlayers, 1, -1 do
                local entry = scaledPlayers[i]
                if not entry then goto continue end

                -- Skip local player; their scale is handled by the direct call above
                if entry.id == GetPlayerServerId(PlayerId()) then
                    goto continue
                end

                if not entry.ped or not DoesEntityExist(entry.ped) then
                    local targetPlayer = GetPlayerFromServerId(entry.id)
                    if targetPlayer and NetworkIsPlayerActive(targetPlayer) then
                        entry.ped = GetPlayerPed(targetPlayer)
                    end
                end

                local ped = entry.ped
                if ped and DoesEntityExist(ped) then
                    local dist = #(localCoords - GetEntityCoords(ped))
                    if dist <= 30.0 then
                        RawScale(ped, entry.scale)
                    end
                end
                ::continue::
            end
        end

        Wait(waitTime)
    end
end)

-- ─────────────────────────────────────────────────────────────────────
--  STALE ENTRY CLEANUP
-- ─────────────────────────────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(30000)
        for i = #scaledPlayers, 1, -1 do
            local entry = scaledPlayers[i]
            local player = GetPlayerFromServerId(entry.id)
            if not player or not NetworkIsPlayerActive(player) then
                table.remove(scaledPlayers, i)
            end
        end
    end
end)

-- ─────────────────────────────────────────────────────────────────────
--  ESX PLAYER LOADED  (restore saved scale on join)
-- ─────────────────────────────────────────────────────────────────────
if Config.Framework == 'ESX' then
    RegisterNetEvent('esx:playerLoaded', function()
        CreateThread(function()
            Wait(3000)
            TriggerServerEvent('ScaleM:RequestSavedScale')
        end)
    end)
end

-- ─────────────────────────────────────────────────────────────────────
--  STARTUP
-- ─────────────────────────────────────────────────────────────────────
CreateThread(function()
    Wait(5000)
    TriggerServerEvent('ScaleM:RequestSavedScale')
    Wait(100)
    TriggerServerEvent('ScaleM:RequestAllScales')
end)
