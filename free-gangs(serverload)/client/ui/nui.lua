--[[
    FREE-GANGS: NUI Handler

    Manages all NUI communication: opening/closing the UI, sending data
    to the browser, and handling callbacks from the JS frontend.

    Access control:
      - BLOCKED: police, ambulance, lawyer (hard-blocked, UI won't open)
      - CIVILIAN: non-gang players see limited view (Dashboard + Territories)
      - GANG MEMBER: full menu minus Contacts and Settings
      - OFFICER: full menu minus Settings
      - BOSS: full menu
]]

FreeGangs = FreeGangs or {}
FreeGangs.Client = FreeGangs.Client or {}
FreeGangs.Client.NUI = FreeGangs.Client.NUI or {}

-- ============================================================================
-- BLOCKED JOBS (hard-blocked: UI will not open at all)
-- ============================================================================

local BLOCKED_JOBS = {
    ['police'] = true,
    ['sheriff'] = true,
    ['ambulance'] = true,
    ['ems'] = true,
    ['doctor'] = true,
    ['lawyer'] = true,
    ['judge'] = true,
    ['bcso'] = true,
    ['sasp'] = true,
    ['ranger'] = true,
    ['highway'] = true,
    ['lspd'] = true,
    ['sahp'] = true,
    ['fib'] = true,
    ['doj'] = true,
}

-- Track NUI open state
local nuiOpen = false

-- ============================================================================
-- ROLE DETECTION
-- ============================================================================

---Get the player's current job name from QBX
---@return string jobName
local function GetPlayerJobName()
    local playerData = QBX and QBX.PlayerData
    if not playerData then return 'unemployed' end
    local job = playerData.job
    if not job then return 'unemployed' end
    return job.name or 'unemployed'
end

---Determine whether the player's current job is blocked
---@return boolean
local function IsJobBlocked()
    local jobName = GetPlayerJobName()
    return BLOCKED_JOBS[jobName] == true
end

---Determine the player's NUI role based on gang membership
---@return string role 'civilian' | 'gang_member' | 'officer' | 'boss'
local function GetPlayerRole()
    local gangData = FreeGangs.Client.PlayerGang
    if not gangData then return 'civilian' end

    local membership = gangData.membership
    if not membership then return 'gang_member' end

    if membership.isBoss then return 'boss' end
    if membership.isOfficer then return 'officer' end
    return 'gang_member'
end

-- ============================================================================
-- NUI SEND HELPERS
-- ============================================================================

---Send a message to the NUI browser
---@param action string
---@param data table|nil
local function SendNUI(action, data)
    data = data or {}
    data.action = action
    SendNUIMessage(data)
end

-- ============================================================================
-- DATA GATHERING (builds payloads for the JS frontend)
-- ============================================================================

---Build gang data payload for the header + dashboard
---@return table|nil
local function BuildGangData()
    local gang = FreeGangs.Client.PlayerGang
    if not gang then return nil end

    return {
        name = gang.name,
        label = gang.label,
        archetype = gang.archetype,
        color = gang.color,
        master_level = gang.master_level or 1,
        master_rep = gang.master_rep or 0,
        treasury = gang.treasury or 0,
        war_chest = gang.war_chest or 0,
        member_count = gang.member_count or 0,
        online_members = gang.online_members or 0,
        controlled_zones = gang.controlled_zones or 0,
        active_rivalries = gang.active_rivalries or 0,
        max_territories = gang.max_territories or 1,
    }
end

---Build territory data payload
---@return table
local function BuildTerritoryData()
    return FreeGangs.Client.Cache.Get('territories') or {}
end

---Build current zone data for the Operations tab
---@return table
local function BuildZoneData()
    local zone = FreeGangs.Client.CurrentZone
    if not zone then
        return { name = 'No Zone', control = 0 }
    end

    local gangName = FreeGangs.Client.PlayerGang and FreeGangs.Client.PlayerGang.name
    local influence = 0
    if gangName and zone.data and zone.data.influence then
        influence = zone.data.influence[gangName] or 0
    end

    return {
        name = zone.data and zone.data.label or zone.name,
        control = influence,
    }
end

---Fetch full data set for a specific tab from server via callbacks
---@param tab string
local function FetchTabData(tab)
    if tab == 'dashboard' then
        -- Refresh gang data from server
        local gangData = lib.callback.await(FreeGangs.Callbacks.GET_PLAYER_GANG, false)
        if gangData then
            FreeGangs.Client.PlayerGang = gangData
            FreeGangs.Client.Cache.Set('playerGang', gangData)
        end
        SendNUI('updateGangData', { gangData = BuildGangData() })

    elseif tab == 'members' then
        local gangData = FreeGangs.Client.PlayerGang
        if not gangData then return end
        local members = lib.callback.await(FreeGangs.Callbacks.GET_GANG_MEMBERS, false)
        local role = GetPlayerRole()
        local canManage = role == 'boss' or role == 'officer'
        if members then
            for _, m in pairs(members) do
                m.canManage = canManage and not m.isBoss
            end
        end
        SendNUI('updateMembers', { members = members or {} })

    elseif tab == 'territories' then
        local territories = lib.callback.await(FreeGangs.Callbacks.GET_TERRITORIES, false)
        if territories then
            FreeGangs.Client.Cache.Set('territories', territories)
        end
        SendNUI('updateTerritories', { territories = territories or {} })

    elseif tab == 'wars' then
        local heat = lib.callback.await(FreeGangs.Callbacks.GET_HEAT_LEVEL, false)
        local wars = lib.callback.await(FreeGangs.Callbacks.GET_ACTIVE_WARS, false)
        SendNUI('updateHeat', { heatData = heat or {} })
        SendNUI('updateWars', { wars = wars or {} })

    elseif tab == 'operations' then
        -- Zone info
        SendNUI('updateOperations', {
            zone = BuildZoneData(),
            -- Protection businesses
            protection = FreeGangs.Client.PlayerGang
                and lib.callback.await(FreeGangs.Callbacks.GET_PROTECTION_BUSINESSES, false)
                or {},
            -- Cooldowns
            cooldowns = lib.callback.await('freegangs:activities:getCooldowns', false) or {},
        })

    elseif tab == 'contacts' then
        local bribes = lib.callback.await(FreeGangs.Callbacks.GET_ACTIVE_BRIBES, false)
        SendNUI('updateContacts', { contacts = bribes or {} })

    elseif tab == 'treasury' then
        -- Refresh gang data for treasury amounts
        local gangData = lib.callback.await(FreeGangs.Callbacks.GET_PLAYER_GANG, false)
        if gangData then
            FreeGangs.Client.PlayerGang = gangData
            FreeGangs.Client.Cache.Set('playerGang', gangData)
        end
        SendNUI('updateGangData', { gangData = BuildGangData() })
        -- TODO: fetch transaction history when server callback is added

    elseif tab == 'settings' then
        SendNUI('updateGangData', { gangData = BuildGangData() })
    end
end

-- ============================================================================
-- OPEN / CLOSE
-- ============================================================================

---Open the NUI gang menu
function FreeGangs.Client.NUI.Open()
    if nuiOpen then return end

    -- Hard block for law enforcement
    if IsJobBlocked() then
        FreeGangs.Bridge.Notify('This network is not accessible to you.', 'error', 3000)
        return
    end

    nuiOpen = true
    SetNuiFocus(true, true)

    local role = GetPlayerRole()
    local gangData = BuildGangData()
    local territories = BuildTerritoryData()

    -- Fetch heat data for gangs
    local heatData = {}
    local wars = {}
    if role ~= 'civilian' then
        heatData = lib.callback.await(FreeGangs.Callbacks.GET_HEAT_LEVEL, false) or {}
        wars = lib.callback.await(FreeGangs.Callbacks.GET_ACTIVE_WARS, false) or {}
    end

    SendNUI('open', {
        playerRole = role,
        gangData = gangData,
        territories = territories,
        heatData = heatData,
        wars = wars,
    })
end

---Close the NUI gang menu
function FreeGangs.Client.NUI.Close()
    if not nuiOpen then return end
    nuiOpen = false
    SetNuiFocus(false, false)
    SendNUI('close')
end

---Toggle the NUI
function FreeGangs.Client.NUI.Toggle()
    if nuiOpen then
        FreeGangs.Client.NUI.Close()
    else
        FreeGangs.Client.NUI.Open()
    end
end

-- ============================================================================
-- NUI CALLBACKS (JS -> Lua)
-- ============================================================================

---Handle close from JS
RegisterNUICallback('close', function(_, cb)
    FreeGangs.Client.NUI.Close()
    cb('ok')
end)

---Handle tab data request
RegisterNUICallback('requestTabData', function(data, cb)
    local tab = data.tab
    if tab then
        CreateThread(function()
            FetchTabData(tab)
        end)
    end
    cb('ok')
end)

---Handle invite member
RegisterNUICallback('inviteMember', function(data, cb)
    local playerId = tonumber(data.playerId)
    if playerId and playerId > 0 then
        TriggerServerEvent(FreeGangs.Events.Server.JOIN_GANG, playerId)
        SendNUI('showToast', { message = 'Invite sent to player #' .. playerId, type = 'success' })
    else
        SendNUI('showToast', { message = 'Invalid player ID', type = 'error' })
    end
    cb('ok')
end)

---Handle promote member
RegisterNUICallback('promoteMember', function(data, cb)
    if data.citizenid then
        TriggerServerEvent(FreeGangs.Events.Server.PROMOTE_MEMBER, data.citizenid)
        SendNUI('showToast', { message = 'Promotion request sent', type = 'success' })
        -- Refresh members after a short delay
        SetTimeout(500, function()
            if nuiOpen then FetchTabData('members') end
        end)
    end
    cb('ok')
end)

---Handle demote member
RegisterNUICallback('demoteMember', function(data, cb)
    if data.citizenid then
        TriggerServerEvent(FreeGangs.Events.Server.DEMOTE_MEMBER, data.citizenid)
        SendNUI('showToast', { message = 'Demotion request sent', type = 'warning' })
        SetTimeout(500, function()
            if nuiOpen then FetchTabData('members') end
        end)
    end
    cb('ok')
end)

---Handle kick member
RegisterNUICallback('kickMember', function(data, cb)
    if data.citizenid then
        TriggerServerEvent(FreeGangs.Events.Server.KICK_MEMBER, data.citizenid)
        SendNUI('showToast', { message = 'Member kicked', type = 'error' })
        SetTimeout(500, function()
            if nuiOpen then FetchTabData('members') end
        end)
    end
    cb('ok')
end)

---Handle deposit
RegisterNUICallback('deposit', function(data, cb)
    local amount = tonumber(data.amount)
    local depositType = data.type

    if not amount or amount <= 0 then
        SendNUI('showToast', { message = 'Invalid amount', type = 'error' })
        cb('ok')
        return
    end

    if depositType == 'warchest' then
        TriggerServerEvent(FreeGangs.Events.Server.DEPOSIT_WARCHEST, amount)
    else
        TriggerServerEvent(FreeGangs.Events.Server.DEPOSIT_TREASURY, amount)
    end

    SendNUI('showToast', { message = string.format('Deposited $%s', FreeGangs.Utils.FormatNumber(amount)), type = 'success' })

    -- Refresh treasury data
    SetTimeout(500, function()
        if nuiOpen then FetchTabData('treasury') end
    end)

    cb('ok')
end)

---Handle withdraw
RegisterNUICallback('withdraw', function(data, cb)
    local amount = tonumber(data.amount)

    if not amount or amount <= 0 then
        SendNUI('showToast', { message = 'Invalid amount', type = 'error' })
        cb('ok')
        return
    end

    TriggerServerEvent(FreeGangs.Events.Server.WITHDRAW_TREASURY, amount)
    SendNUI('showToast', { message = string.format('Withdrew $%s', FreeGangs.Utils.FormatNumber(amount)), type = 'success' })

    SetTimeout(500, function()
        if nuiOpen then FetchTabData('treasury') end
    end)

    cb('ok')
end)

---Handle open stash
RegisterNUICallback('openStash', function(_, cb)
    -- Close NUI first so inventory can open
    FreeGangs.Client.NUI.Close()
    TriggerServerEvent(FreeGangs.Events.Server.OPEN_STASH)
    cb('ok')
end)

-- ============================================================================
-- EVENT HOOKS (update NUI when game state changes)
-- ============================================================================

---When gang data updates, push to NUI if open
RegisterNetEvent(FreeGangs.Events.Client.UPDATE_GANG_DATA, function(data)
    if nuiOpen and data then
        SendNUI('updateGangData', { gangData = BuildGangData() })
    end
end)

---When territory updates, push to NUI if open
RegisterNetEvent(FreeGangs.Events.Client.UPDATE_TERRITORY, function(zoneName, data)
    if nuiOpen then
        SendNUI('updateTerritories', { territories = BuildTerritoryData() })
    end
end)

---When heat updates, push to NUI if open
RegisterNetEvent(FreeGangs.Events.Client.UPDATE_HEAT, function()
    if nuiOpen then
        CreateThread(function()
            local heat = lib.callback.await(FreeGangs.Callbacks.GET_HEAT_LEVEL, false)
            SendNUI('updateHeat', { heatData = heat or {} })
        end)
    end
end)

---When war status changes, push to NUI if open
RegisterNetEvent(FreeGangs.Events.Client.UPDATE_WAR, function()
    if nuiOpen then
        CreateThread(function()
            local wars = lib.callback.await(FreeGangs.Callbacks.GET_ACTIVE_WARS, false)
            SendNUI('updateWars', { wars = wars or {} })
        end)
    end
end)

-- ============================================================================
-- OPEN GANG UI EVENT (replaces ox_lib menu route)
-- ============================================================================

---Override the OPEN_GANG_UI event to open NUI instead of ox_lib menus
---This replaces the handler in client/ui/menus.lua
RegisterNetEvent(FreeGangs.Events.Client.OPEN_GANG_UI, function()
    FreeGangs.Client.NUI.Open()
end)

-- ============================================================================
-- CLEANUP
-- ============================================================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if nuiOpen then
        SetNuiFocus(false, false)
        nuiOpen = false
    end
end)

return FreeGangs.Client.NUI
