--[[
    FREE-GANGS: QBox Framework Bridge
    
    This file provides an abstraction layer for QBox (qbx_core) integration.
    All framework-specific calls go through this bridge, making it easier
    to migrate to other frameworks in the future if needed.
    
    Uses QBox exports instead of the legacy core object pattern.
]]

FreeGangs.Bridge = {}

local isServer = IsDuplicityVersion()

-- ============================================================================
-- SERVER-SIDE BRIDGE FUNCTIONS
-- ============================================================================

if isServer then
    
    -- ========================================================================
    -- PLAYER DATA
    -- ========================================================================
    
    ---Get player object from source
    ---@param source number
    ---@return table|nil
    function FreeGangs.Bridge.GetPlayer(source)
        return exports.qbx_core:GetPlayer(source)
    end
    
    ---Get player from citizenid
    ---@param citizenid string
    ---@return table|nil
    function FreeGangs.Bridge.GetPlayerByCitizenId(citizenid)
        return exports.qbx_core:GetPlayerByCitizenId(citizenid)
    end
    
    ---Get player's citizenid
    ---@param source number
    ---@return string|nil
    function FreeGangs.Bridge.GetCitizenId(source)
        local player = FreeGangs.Bridge.GetPlayer(source)
        return player and player.PlayerData.citizenid or nil
    end
    
    ---Get player's name
    ---@param source number
    ---@return string
    function FreeGangs.Bridge.GetPlayerName(source)
        local player = FreeGangs.Bridge.GetPlayer(source)
        if player then
            return player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
        end
        return 'Unknown'
    end
    
    ---Check if player is loaded
    ---@param source number
    ---@return boolean
    function FreeGangs.Bridge.IsPlayerLoaded(source)
        local player = FreeGangs.Bridge.GetPlayer(source)
        return player ~= nil
    end
    
    ---Get all online players
    ---@return table<number, table>
    function FreeGangs.Bridge.GetPlayers()
        return exports.qbx_core:GetQBPlayers()
    end
    
    -- ========================================================================
    -- GANG MANAGEMENT (QBox Native)
    -- ========================================================================
    
    ---Create a new gang in QBox
    ---@param gangName string
    ---@param gangLabel string
    ---@param grades table
    ---@return boolean
    function FreeGangs.Bridge.CreateGang(gangName, gangLabel, grades)
        local gangData = {
            [gangName] = {
                label = gangLabel,
                grades = grades
            }
        }
        
        local success = pcall(function()
            exports.qbx_core:CreateGangs(gangData)
        end)
        
        return success
    end
    
    ---Add player to gang
    ---@param citizenid string
    ---@param gangName string
    ---@param grade number
    ---@return boolean
    function FreeGangs.Bridge.AddPlayerToGang(citizenid, gangName, grade)
        local success = pcall(function()
            exports.qbx_core:AddPlayerToGang(citizenid, gangName, grade or 0)
        end)
        return success
    end
    
    ---Remove player from gang
    ---@param citizenid string
    ---@param gangName string
    ---@return boolean
    function FreeGangs.Bridge.RemovePlayerFromGang(citizenid, gangName)
        local success = pcall(function()
            exports.qbx_core:RemovePlayerFromGang(citizenid, gangName)
        end)
        return success
    end
    
    ---Set player's gang grade
    ---@param citizenid string
    ---@param gangName string
    ---@param grade number
    ---@return boolean
    function FreeGangs.Bridge.SetPlayerGangGrade(citizenid, gangName, grade)
        -- QBox handles this through AddPlayerToGang with the new grade
        return FreeGangs.Bridge.AddPlayerToGang(citizenid, gangName, grade)
    end
    
    ---Set player's primary gang
    ---@param citizenid string
    ---@param gangName string
    ---@return boolean
    function FreeGangs.Bridge.SetPrimaryGang(citizenid, gangName)
        local success = pcall(function()
            exports.qbx_core:SetPlayerPrimaryGang(citizenid, gangName)
        end)
        return success
    end
    
    ---Get gang members from QBox
    ---@param gangName string
    ---@return table<string, number> citizenid -> grade
    function FreeGangs.Bridge.GetGangMembers(gangName)
        local success, members = pcall(function()
            return exports.qbx_core:GetGroupMembers(gangName, 'gang')
        end)
        return success and members or {}
    end
    
    ---Check if player has gang
    ---@param source number
    ---@param gangName string
    ---@param minGrade number|nil
    ---@return boolean
    function FreeGangs.Bridge.HasGang(source, gangName, minGrade)
        if minGrade then
            return exports.qbx_core:HasPrimaryGroup(source, { [gangName] = minGrade })
        else
            return exports.qbx_core:HasPrimaryGroup(source, gangName)
        end
    end
    
    ---Check if grade is boss
    ---@param gangName string
    ---@param grade number
    ---@return boolean
    function FreeGangs.Bridge.IsGradeBoss(gangName, grade)
        local success, isBoss = pcall(function()
            return exports.qbx_core:IsGradeBoss(gangName, grade)
        end)
        return success and isBoss or false
    end
    
    -- ========================================================================
    -- MONEY MANAGEMENT
    -- ========================================================================
    
    ---Add money to player
    ---@param source number
    ---@param amount number
    ---@param moneyType string|nil ('cash', 'bank', 'crypto')
    ---@param reason string|nil
    ---@return boolean
    function FreeGangs.Bridge.AddMoney(source, amount, moneyType, reason)
        local player = FreeGangs.Bridge.GetPlayer(source)
        if not player then return false end
        
        moneyType = moneyType or 'cash'
        return player.Functions.AddMoney(moneyType, amount, reason or 'free-gangs')
    end
    
    ---Remove money from player
    ---@param source number
    ---@param amount number
    ---@param moneyType string|nil
    ---@param reason string|nil
    ---@return boolean
    function FreeGangs.Bridge.RemoveMoney(source, amount, moneyType, reason)
        local player = FreeGangs.Bridge.GetPlayer(source)
        if not player then return false end
        
        moneyType = moneyType or 'cash'
        return player.Functions.RemoveMoney(moneyType, amount, reason or 'free-gangs')
    end
    
    ---Get player money
    ---@param source number
    ---@param moneyType string|nil
    ---@return number
    function FreeGangs.Bridge.GetMoney(source, moneyType)
        local player = FreeGangs.Bridge.GetPlayer(source)
        if not player then return 0 end
        
        moneyType = moneyType or 'cash'
        return player.PlayerData.money[moneyType] or 0
    end
    
    -- ========================================================================
    -- INVENTORY INTEGRATION (ox_inventory)
    -- ========================================================================
    
    ---Check if player has item
    ---@param source number
    ---@param item string
    ---@param amount number|nil
    ---@return boolean
    function FreeGangs.Bridge.HasItem(source, item, amount)
        amount = amount or 1
        local count = exports.ox_inventory:Search(source, 'count', item)
        return count >= amount
    end
    
    ---Get item count
    ---@param source number
    ---@param item string
    ---@return number
    function FreeGangs.Bridge.GetItemCount(source, item)
        return exports.ox_inventory:Search(source, 'count', item) or 0
    end
    
    ---Add item to player
    ---@param source number
    ---@param item string
    ---@param amount number
    ---@param metadata table|nil
    ---@return boolean
    function FreeGangs.Bridge.AddItem(source, item, amount, metadata)
        return exports.ox_inventory:AddItem(source, item, amount, metadata)
    end
    
    ---Remove item from player
    ---@param source number
    ---@param item string
    ---@param amount number
    ---@return boolean
    function FreeGangs.Bridge.RemoveItem(source, item, amount)
        return exports.ox_inventory:RemoveItem(source, item, amount)
    end
    
    ---Register a stash
    ---@param stashId string
    ---@param label string
    ---@param slots number
    ---@param weight number
    ---@param owner string|boolean
    ---@param groups table|nil
    ---@param coords vector3|nil
    ---@return boolean
    function FreeGangs.Bridge.RegisterStash(stashId, label, slots, weight, owner, groups, coords)
        local success = pcall(function()
            exports.ox_inventory:RegisterStash(stashId, label, slots, weight, owner, groups, coords)
        end)
        return success
    end
    
    ---Open stash for player
    ---@param source number
    ---@param stashId string
    function FreeGangs.Bridge.OpenStash(source, stashId)
        TriggerClientEvent('ox_inventory:openInventory', source, 'stash', stashId)
    end
    
    -- ========================================================================
    -- METADATA MANAGEMENT
    -- ========================================================================
    
    ---Set player metadata
    ---@param source number
    ---@param key string
    ---@param value any
    function FreeGangs.Bridge.SetMetadata(source, key, value)
        exports.qbx_core:SetMetadata(source, key, value)
    end
    
    ---Get player metadata
    ---@param source number
    ---@param key string
    ---@return any
    function FreeGangs.Bridge.GetMetadata(source, key)
        local player = FreeGangs.Bridge.GetPlayer(source)
        if player and player.PlayerData.metadata then
            return player.PlayerData.metadata[key]
        end
        return nil
    end
    
    -- ========================================================================
    -- NOTIFICATIONS
    -- ========================================================================
    
    ---Send notification to player
    ---@param source number
    ---@param message string
    ---@param notifyType string|nil ('success', 'error', 'warning', 'inform')
    ---@param duration number|nil
    function FreeGangs.Bridge.Notify(source, message, notifyType, duration)
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Gang System',
            description = message,
            type = notifyType or 'inform',
            duration = duration or 5000,
        })
    end
    
    ---Send notification to all gang members online
    ---@param gangName string
    ---@param message string
    ---@param notifyType string|nil
    function FreeGangs.Bridge.NotifyGang(gangName, message, notifyType)
        local players = FreeGangs.Bridge.GetPlayers()
        for source, player in pairs(players) do
            if player.PlayerData.gang and player.PlayerData.gang.name == gangName then
                FreeGangs.Bridge.Notify(source, message, notifyType)
            end
        end
    end
    
    -- ========================================================================
    -- UTILITY FUNCTIONS
    -- ========================================================================
    
    ---Get player's current gang data
    ---@param source number
    ---@return table|nil {name: string, label: string, grade: number, gradeName: string, isBoss: boolean}
    function FreeGangs.Bridge.GetPlayerGangData(source)
        local player = FreeGangs.Bridge.GetPlayer(source)
        if not player then return nil end
        
        local gang = player.PlayerData.gang
        if not gang or gang.name == 'none' then
            return nil
        end
        
        return {
            name = gang.name,
            label = gang.label,
            grade = gang.grade.level,
            gradeName = gang.grade.name,
            isBoss = gang.isboss or false,
        }
    end
    
    ---Check if player is in any gang
    ---@param source number
    ---@return boolean
    function FreeGangs.Bridge.IsInAnyGang(source)
        local gangData = FreeGangs.Bridge.GetPlayerGangData(source)
        return gangData ~= nil
    end
    
    ---Get player's ped
    ---@param source number
    ---@return number
    function FreeGangs.Bridge.GetPlayerPed(source)
        return GetPlayerPed(source)
    end
    
    ---Get player's coordinates
    ---@param source number
    ---@return vector3
    function FreeGangs.Bridge.GetPlayerCoords(source)
        local ped = GetPlayerPed(source)
        return GetEntityCoords(ped)
    end
    
-- ============================================================================
-- CLIENT-SIDE BRIDGE FUNCTIONS
-- ============================================================================

else
    
    -- ========================================================================
    -- PLAYER DATA (Auto-synced via statebag)
    -- ========================================================================
    
    ---Get local player data
    ---@return table|nil
    function FreeGangs.Bridge.GetPlayerData()
        return QBX.PlayerData
    end
    
    ---Get local player's citizenid
    ---@return string|nil
    function FreeGangs.Bridge.GetCitizenId()
        local playerData = FreeGangs.Bridge.GetPlayerData()
        return playerData and playerData.citizenid or nil
    end
    
    ---Get local player's name
    ---@return string
    function FreeGangs.Bridge.GetPlayerName()
        local playerData = FreeGangs.Bridge.GetPlayerData()
        if playerData and playerData.charinfo then
            return playerData.charinfo.firstname .. ' ' .. playerData.charinfo.lastname
        end
        return 'Unknown'
    end
    
    ---Check if local player is loaded
    ---@return boolean
    function FreeGangs.Bridge.IsPlayerLoaded()
        local playerData = FreeGangs.Bridge.GetPlayerData()
        return playerData ~= nil and playerData.citizenid ~= nil
    end
    
    -- ========================================================================
    -- GANG DATA (Client-side checks)
    -- ========================================================================
    
    ---Get local player's gang data
    ---@return table|nil
    function FreeGangs.Bridge.GetPlayerGangData()
        local playerData = FreeGangs.Bridge.GetPlayerData()
        if not playerData then return nil end
        
        local gang = playerData.gang
        if not gang or gang.name == 'none' then
            return nil
        end
        
        return {
            name = gang.name,
            label = gang.label,
            grade = gang.grade.level,
            gradeName = gang.grade.name,
            isBoss = gang.isboss or false,
        }
    end
    
    ---Check if local player is in any gang
    ---@return boolean
    function FreeGangs.Bridge.IsInAnyGang()
        local gangData = FreeGangs.Bridge.GetPlayerGangData()
        return gangData ~= nil
    end
    
    ---Check if local player has specific gang
    ---@param gangName string
    ---@return boolean
    function FreeGangs.Bridge.HasGang(gangName)
        return exports.qbx_core:HasPrimaryGroup(gangName)
    end
    
    ---Get all groups (jobs + gangs) for local player
    ---@return table
    function FreeGangs.Bridge.GetGroups()
        return exports.qbx_core:GetGroups()
    end
    
    -- ========================================================================
    -- INVENTORY (Client-side)
    -- ========================================================================
    
    ---Check if local player has item
    ---@param item string
    ---@param amount number|nil
    ---@return boolean
    function FreeGangs.Bridge.HasItem(item, amount)
        amount = amount or 1
        local count = exports.ox_inventory:Search('count', item)
        return count >= amount
    end
    
    ---Get item count for local player
    ---@param item string
    ---@return number
    function FreeGangs.Bridge.GetItemCount(item)
        return exports.ox_inventory:Search('count', item) or 0
    end
    
    -- ========================================================================
    -- NOTIFICATIONS
    -- ========================================================================
    
    ---Show notification
    ---@param message string
    ---@param notifyType string|nil
    ---@param duration number|nil
    function FreeGangs.Bridge.Notify(message, notifyType, duration)
        lib.notify({
            title = 'Gang System',
            description = message,
            type = notifyType or 'inform',
            duration = duration or 5000,
        })
    end
    
    -- ========================================================================
    -- UTILITY FUNCTIONS
    -- ========================================================================
    
    ---Get local player's ped
    ---@return number
    function FreeGangs.Bridge.GetPlayerPed()
        return PlayerPedId()
    end
    
    ---Get local player's coordinates
    ---@return vector3
    function FreeGangs.Bridge.GetPlayerCoords()
        return GetEntityCoords(PlayerPedId())
    end
    
    ---Get local player's heading
    ---@return number
    function FreeGangs.Bridge.GetPlayerHeading()
        return GetEntityHeading(PlayerPedId())
    end
    
    -- ========================================================================
    -- PROGRESS BAR
    -- ========================================================================
    
    ---Show progress bar
    ---@param options table
    ---@return boolean completed
    function FreeGangs.Bridge.ProgressBar(options)
        return lib.progressBar({
            duration = options.duration or 5000,
            label = options.label or 'Processing...',
            useWhileDead = options.useWhileDead or false,
            canCancel = options.canCancel or true,
            disable = options.disable or {
                car = true,
                move = true,
                combat = true,
            },
            anim = options.anim,
            prop = options.prop,
        })
    end
    
    ---Show progress circle
    ---@param options table
    ---@return boolean completed
    function FreeGangs.Bridge.ProgressCircle(options)
        return lib.progressCircle({
            duration = options.duration or 5000,
            label = options.label or 'Processing...',
            useWhileDead = options.useWhileDead or false,
            canCancel = options.canCancel or true,
            disable = options.disable or {
                car = true,
                move = true,
                combat = true,
            },
            anim = options.anim,
            prop = options.prop,
        })
    end
    
end

return FreeGangs.Bridge
