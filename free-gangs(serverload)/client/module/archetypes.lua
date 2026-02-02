--[[
    FREE-GANGS: Client Archetype Module (Phase E Revised)
    
    Client-side implementation for archetype-specific mechanics,
    tier activities, passive bonuses, and prison interactions.
    
    PHASE E REVISIONS:
    - Drive-By Contracts: ox_target on NPCs in opposing territories
    - Prospect Runs: Item delivery, destination ambush, route NPC ambush
    - Club Runs: Scaled-up Prospect Runs for 4+ members
    - Territory Ride: Patrol all territories, 3+ members, proximity/bike checks
    - Convoy Protection: Item delivery, destination ambush only, gang-wide sync
    - Crime Family: Business extortion bonus (passive)
]]

FreeGangs = FreeGangs or {}
FreeGangs.Client = FreeGangs.Client or {}
FreeGangs.Client.Archetypes = {}
FreeGangs.Client.Prison = {}

-- ============================================================================
-- LOCAL STATE
-- ============================================================================

local isInitialized = false
local cachedArchetypeInfo = nil
local cachedPassiveBonuses = nil
local cachedTierActivities = nil
local cachedPrisonData = nil

-- Active activity tracking
local activeActivities = {
    prospectRun = nil,
    clubRun = nil,
    territoryRide = nil,
    driveByContract = nil,
    convoyProtection = nil,
    smuggleMission = nil,
}

-- Halcon Network state
local halconEnabled = false

-- Motorcycle hash cache for MC validation
local motorcycleHashes = {}

-- Spawned entities for cleanup
local spawnedEntities = {
    npcs = {},
    vehicles = {},
    blips = {},
}

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Initialize archetype module
function FreeGangs.Client.Archetypes.Initialize()
    if isInitialized then return end
    
    -- Cache motorcycle hashes for quick lookup
    local bikeModels = FreeGangs.Config.MC and FreeGangs.Config.MC.ProspectRuns and 
                       FreeGangs.Config.MC.ProspectRuns.ValidBikeModels or {}
    for _, model in ipairs(bikeModels) do
        local hash = GetHashKey(model)
        motorcycleHashes[hash] = true
    end
    
    -- Register event handlers
    FreeGangs.Client.Archetypes.RegisterEvents()
    
    isInitialized = true
    FreeGangs.Utils.Debug('[Archetypes] Client module initialized')
end

---Register event handlers
function FreeGangs.Client.Archetypes.RegisterEvents()
    -- ===== STREET GANG EVENTS =====
    
    -- Drive-by contract started
    RegisterNetEvent('free-gangs:client:driveByContract', function(data)
        FreeGangs.Client.Archetypes.HandleDriveByContractStart(data)
    end)
    
    -- Drive-by contract completed
    RegisterNetEvent('free-gangs:client:driveByComplete', function(data)
        FreeGangs.Client.Archetypes.HandleDriveByComplete(data)
    end)
    
    -- Block party started
    RegisterNetEvent('free-gangs:client:blockPartyStarted', function(data)
        FreeGangs.Client.Archetypes.HandleBlockPartyNotification(data)
    end)
    
    -- ===== MC EVENTS =====
    
    -- Prospect run started
    RegisterNetEvent('free-gangs:client:startProspectRun', function(data)
        FreeGangs.Client.Archetypes.HandleProspectRunStart(data)
    end)
    
    -- Club run started (synced to all members)
    RegisterNetEvent('free-gangs:client:clubRunStarted', function(data)
        FreeGangs.Client.Archetypes.HandleClubRunStart(data)
    end)
    
    -- Territory ride started
    RegisterNetEvent('free-gangs:client:territoryRideStarted', function(data)
        FreeGangs.Client.Archetypes.HandleTerritoryRideStart(data)
    end)
    
    -- ===== CARTEL EVENTS =====
    
    -- Halcon Network alerts
    RegisterNetEvent('free-gangs:client:halconAlert', function(data)
        FreeGangs.Client.Archetypes.HandleHalconAlert(data)
    end)
    
    -- Convoy protection started (synced to all members)
    RegisterNetEvent('free-gangs:client:convoyStarted', function(data)
        FreeGangs.Client.Archetypes.HandleConvoyStart(data)
    end)
    
    -- ===== PRISON EVENTS =====
    
    -- Prison contraband ready
    RegisterNetEvent('free-gangs:client:contrabandReady', function()
        FreeGangs.Client.Prison.HandleContrabandReady()
    end)
    
    -- Prison escape initiated
    RegisterNetEvent('free-gangs:client:escapeInitiated', function(data)
        FreeGangs.Client.Prison.HandleEscapeInitiated(data)
    end)
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

---Check if player is on a valid motorcycle
---@return boolean
function FreeGangs.Client.Archetypes.IsOnMotorcycle()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    
    if vehicle == 0 then return false end
    
    local model = GetEntityModel(vehicle)
    return motorcycleHashes[model] == true or GetVehicleClass(vehicle) == 8
end

---Get vehicle model hash
---@return number|nil
function FreeGangs.Client.Archetypes.GetCurrentVehicleModel()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return nil end
    return GetEntityModel(vehicle)
end

---Clean up spawned entities
---@param category string|nil Specific category or all
function FreeGangs.Client.Archetypes.CleanupEntities(category)
    local categories = category and { category } or { 'npcs', 'vehicles', 'blips' }
    
    for _, cat in ipairs(categories) do
        if spawnedEntities[cat] then
            for _, entity in ipairs(spawnedEntities[cat]) do
                if cat == 'blips' then
                    if DoesBlipExist(entity) then
                        RemoveBlip(entity)
                    end
                else
                    if DoesEntityExist(entity) then
                        DeleteEntity(entity)
                    end
                end
            end
            spawnedEntities[cat] = {}
        end
    end
end

---Create a destination blip
---@param coords vector3
---@param sprite number
---@param color number
---@param label string
---@return number blip
function FreeGangs.Client.Archetypes.CreateDestinationBlip(coords, sprite, color, label)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite or 1)
    SetBlipColour(blip, color or 1)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, color or 1)
    SetBlipScale(blip, 1.0)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label or 'Destination')
    EndTextCommandSetBlipName(blip)
    
    table.insert(spawnedEntities.blips, blip)
    return blip
end

---Spawn an NPC
---@param model string
---@param coords vector3
---@param heading number
---@param weapon string|nil
---@return number ped
function FreeGangs.Client.Archetypes.SpawnNPC(model, coords, heading, weapon)
    local hash = GetHashKey(model)
    
    lib.requestModel(hash)
    
    local ped = CreatePed(4, hash, coords.x, coords.y, coords.z, heading or 0.0, true, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAbility(ped, 2)
    
    if weapon then
        local weaponHash = GetHashKey(weapon)
        GiveWeaponToPed(ped, weaponHash, 250, false, true)
    end
    
    table.insert(spawnedEntities.npcs, ped)
    SetModelAsNoLongerNeeded(hash)
    
    return ped
end

---Spawn a vehicle with NPC driver
---@param vehicleModel string
---@param pedModel string
---@param coords vector3
---@param heading number
---@return number vehicle, number driver
function FreeGangs.Client.Archetypes.SpawnVehicleWithDriver(vehicleModel, pedModel, coords, heading)
    local vehHash = GetHashKey(vehicleModel)
    local pedHash = GetHashKey(pedModel)
    
    lib.requestModel(vehHash)
    lib.requestModel(pedHash)
    
    local vehicle = CreateVehicle(vehHash, coords.x, coords.y, coords.z, heading or 0.0, true, true)
    SetEntityAsMissionEntity(vehicle, true, true)
    
    local driver = CreatePedInsideVehicle(vehicle, 4, pedHash, -1, true, true)
    SetEntityAsMissionEntity(driver, true, true)
    SetPedCombatAttributes(driver, 46, true)
    
    table.insert(spawnedEntities.vehicles, vehicle)
    table.insert(spawnedEntities.npcs, driver)
    
    SetModelAsNoLongerNeeded(vehHash)
    SetModelAsNoLongerNeeded(pedHash)
    
    return vehicle, driver
end

-- ============================================================================
-- STREET GANG: DRIVE-BY CONTRACTS (TIER 3)
-- Target NPCs in opposing gang territories via ox_target
-- ============================================================================

---Start a drive-by contract
---@param targetZone string|nil Specific zone to target
---@return boolean, string
function FreeGangs.Client.Archetypes.StartDriveByContract(targetZone)
    -- Get available target zones
    local zones = lib.callback.await('free-gangs:callback:getDriveByTargetZones', false)
    
    if not zones or #zones == 0 then
        FreeGangs.Bridge.Notify('No rival territories available for contracts', 'error')
        return false, 'No targets available'
    end
    
    -- If no zone specified, let player choose
    if not targetZone then
        local options = {}
        for _, zone in ipairs(zones) do
            table.insert(options, {
                title = zone.zoneLabel,
                description = 'Controlled by: ' .. zone.ownerLabel,
                icon = 'crosshairs',
                onSelect = function()
                    FreeGangs.Client.Archetypes.StartDriveByContract(zone.zoneName)
                end,
            })
        end
        
        lib.registerContext({
            id = 'driveby_target_select',
            title = 'Select Target Territory',
            options = options,
        })
        lib.showContext('driveby_target_select')
        return true, 'Selecting target'
    end
    
    -- Accept contract for specific zone
    local result = lib.callback.await('free-gangs:callback:acceptDriveByContract', false, {
        targetZone = targetZone
    })
    
    if result and result.success then
        FreeGangs.Bridge.Notify(result.message or 'Contract accepted', 'success')
    else
        FreeGangs.Bridge.Notify(result and result.message or 'Failed to accept contract', 'error')
    end
    
    return result and result.success or false, result and result.message or 'Unknown error'
end

---Handle drive-by contract start (from server)
---@param data table
function FreeGangs.Client.Archetypes.HandleDriveByContractStart(data)
    -- Store active contract data
    activeActivities.driveByContract = {
        contractId = data.contractId,
        targetZone = data.targetZone,
        targetGang = data.targetGang,
        targetGangLabel = data.targetGangLabel,
        payout = data.payout,
        expiresAt = data.expiresAt,
        timeRemaining = data.timeRemaining,
        kills = 0,
        targetPeds = {},
    }
    
    -- Create destination blip
    if data.targetCoords then
        FreeGangs.Client.Archetypes.CreateDestinationBlip(
            vector3(data.targetCoords.x, data.targetCoords.y, data.targetCoords.z),
            58, -- Crosshair
            1,  -- Red
            'Drive-By Target: ' .. data.targetZone
        )
    end
    
    -- Notify player
    lib.notify({
        title = 'Drive-By Contract Active',
        description = string.format('Target: %s territory\nPayout: $%s\nTime: %d minutes',
            data.targetGangLabel or data.targetZone,
            FreeGangs.Utils.FormatMoney(data.payout),
            math.floor(data.timeRemaining / 60)
        ),
        type = 'inform',
        duration = 10000,
        icon = 'car-burst',
    })
    
    -- Spawn target NPCs in zone via ox_target
    FreeGangs.Client.Archetypes.SpawnDriveByTargets(data)
    
    -- Start timer thread
    CreateThread(function()
        while activeActivities.driveByContract and 
              activeActivities.driveByContract.contractId == data.contractId do
            
            local remaining = activeActivities.driveByContract.expiresAt - os.time()
            
            if remaining <= 0 then
                -- Time expired - server will handle failure
                FreeGangs.Client.Archetypes.EndDriveByContract(false, 'Time expired')
                break
            end
            
            -- Show timer on screen
            if remaining <= 60 then
                FreeGangs.Bridge.Notify('Drive-by time remaining: ' .. remaining .. 's', 'warning')
            end
            
            Wait(10000) -- Check every 10 seconds
        end
    end)
end

---Spawn drive-by target NPCs with ox_target
---@param data table
function FreeGangs.Client.Archetypes.SpawnDriveByTargets(data)
    local targetCoords = data.targetCoords
    if not targetCoords then return end
    
    local coords = vector3(targetCoords.x, targetCoords.y, targetCoords.z)
    
    -- Spawn main target
    local mainTarget = FreeGangs.Client.Archetypes.SpawnNPC(
        data.npcModel or 'g_m_y_ballasout_01',
        coords,
        math.random(0, 360),
        'WEAPON_PISTOL'
    )
    
    -- Add to target list
    table.insert(activeActivities.driveByContract.targetPeds, mainTarget)
    
    -- Setup ox_target on main target
    exports.ox_target:addLocalEntity(mainTarget, {
        {
            name = 'driveby_target_' .. mainTarget,
            icon = 'fa-solid fa-crosshairs',
            label = 'Target - ' .. (data.targetGangLabel or 'Rival'),
            distance = 50.0,
            canInteract = function()
                return activeActivities.driveByContract ~= nil
            end,
            onSelect = function()
                -- This is just for identification - kills are detected via death
            end,
        }
    })
    
    -- Create blip on target
    local targetBlip = AddBlipForEntity(mainTarget)
    SetBlipSprite(targetBlip, 58)
    SetBlipColour(targetBlip, 1)
    SetBlipScale(targetBlip, 0.8)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Drive-By Target')
    EndTextCommandSetBlipName(targetBlip)
    table.insert(spawnedEntities.blips, targetBlip)
    
    -- Spawn escorts if applicable
    if data.hasEscorts and data.escortCount then
        for i = 1, data.escortCount do
            local offset = vector3(
                math.random(-5, 5),
                math.random(-5, 5),
                0
            )
            local escortCoords = coords + offset
            
            local escort = FreeGangs.Client.Archetypes.SpawnNPC(
                data.npcModel or 'g_m_y_ballasout_01',
                escortCoords,
                math.random(0, 360),
                'WEAPON_PISTOL'
            )
            
            table.insert(activeActivities.driveByContract.targetPeds, escort)
            
            -- Escorts protect main target
            TaskCombatPed(escort, mainTarget, 0, 16)
        end
    end
    
    -- Monitor for target deaths
    CreateThread(function()
        while activeActivities.driveByContract do
            for i, ped in ipairs(activeActivities.driveByContract.targetPeds) do
                if DoesEntityExist(ped) and IsEntityDead(ped) then
                    -- Record kill
                    FreeGangs.Client.Archetypes.RecordDriveByKill(ped)
                    table.remove(activeActivities.driveByContract.targetPeds, i)
                end
            end
            
            -- Check if all targets eliminated
            if #activeActivities.driveByContract.targetPeds == 0 then
                FreeGangs.Client.Archetypes.CompleteDriveByContract()
                break
            end
            
            Wait(500)
        end
    end)
end

---Record a drive-by kill
---@param ped number
function FreeGangs.Client.Archetypes.RecordDriveByKill(ped)
    if not activeActivities.driveByContract then return end
    
    activeActivities.driveByContract.kills = activeActivities.driveByContract.kills + 1
    
    -- Remove ox_target
    exports.ox_target:removeLocalEntity(ped, 'driveby_target_' .. ped)
    
    FreeGangs.Bridge.Notify('Target eliminated! (' .. activeActivities.driveByContract.kills .. ')', 'success')
    
    -- Notify server
    TriggerServerEvent('free-gangs:server:recordDriveByKill', activeActivities.driveByContract.contractId)
end

---Complete drive-by contract (all targets eliminated)
function FreeGangs.Client.Archetypes.CompleteDriveByContract()
    if not activeActivities.driveByContract then return end
    
    local contractId = activeActivities.driveByContract.contractId
    
    -- Notify server
    local result = lib.callback.await('free-gangs:callback:completeDriveByContract', false, contractId)
    
    if result and result.success then
        FreeGangs.Bridge.Notify(result.message or 'Contract completed!', 'success')
    end
    
    FreeGangs.Client.Archetypes.EndDriveByContract(true)
end

---End drive-by contract (success or failure)
---@param success boolean
---@param reason string|nil
function FreeGangs.Client.Archetypes.EndDriveByContract(success, reason)
    if not activeActivities.driveByContract then return end
    
    -- Clean up NPCs
    for _, ped in ipairs(activeActivities.driveByContract.targetPeds or {}) do
        if DoesEntityExist(ped) then
            exports.ox_target:removeLocalEntity(ped, 'driveby_target_' .. ped)
            DeleteEntity(ped)
        end
    end
    
    -- Clean up blips
    FreeGangs.Client.Archetypes.CleanupEntities('blips')
    
    if not success then
        FreeGangs.Bridge.Notify('Contract failed: ' .. (reason or 'Unknown'), 'error')
        TriggerServerEvent('free-gangs:server:failDriveByContract', 
            activeActivities.driveByContract.contractId, reason)
    end
    
    activeActivities.driveByContract = nil
end

-- ============================================================================
-- MC: PROSPECT RUNS (TIER 1)
-- Item delivery with ambush mechanics
-- ============================================================================

---Start a prospect run
---@return boolean, string
function FreeGangs.Client.Archetypes.StartProspectRun()
    if not FreeGangs.Client.Archetypes.IsOnMotorcycle() then
        FreeGangs.Bridge.Notify('You must be on a motorcycle', 'error')
        return false, 'Not on motorcycle'
    end
    
    local result = lib.callback.await('free-gangs:callback:startProspectRun', false)
    
    if result and result.success then
        FreeGangs.Bridge.Notify(result.message or 'Prospect run started', 'success')
    else
        FreeGangs.Bridge.Notify(result and result.message or 'Failed to start prospect run', 'error')
    end
    
    return result and result.success or false, result and result.message or 'Unknown error'
end

---Handle prospect run start (from server)
---@param data table
function FreeGangs.Client.Archetypes.HandleProspectRunStart(data)
    activeActivities.prospectRun = {
        runId = data.runId,
        requiredItems = data.requiredItems,
        destination = data.destination,
        trapSpot = data.trapSpot,
        timeLimit = data.timeLimit,
        startTime = GetGameTimer(),
        expiresAt = os.time() + data.timeLimit,
        destinationAmbushChance = data.destinationAmbushChance,
        routeAmbushChance = data.routeAmbushChance,
        routeAmbushNPCCount = data.routeAmbushNPCCount,
        npcAmbushModels = data.npcAmbushModels,
        npcAmbushVehicles = data.npcAmbushVehicles,
        ambushSpawned = false,
        atDestination = false,
    }
    
    -- Show required items
    FreeGangs.Client.Archetypes.ShowRequiredItemsUI(data.requiredItems, 'Prospect Run')
    
    -- Create destination blip
    if data.destination and data.destination.coords then
        local coords = data.destination.coords
        FreeGangs.Client.Archetypes.CreateDestinationBlip(
            vector3(coords.x, coords.y, coords.z),
            501, -- Delivery
            5,   -- Yellow
            'Delivery: ' .. (data.destination.label or 'Drop-off')
        )
    end
    
    -- Start monitoring thread
    CreateThread(function()
        FreeGangs.Client.Archetypes.ProspectRunMonitorThread()
    end)
end

---Show required items UI
---@param items table
---@param title string
function FreeGangs.Client.Archetypes.ShowRequiredItemsUI(items, title)
    local itemList = ''
    for _, item in ipairs(items) do
        itemList = itemList .. string.format('• %s x%d\n', item.label, item.count)
    end
    
    lib.notify({
        title = title .. ' - Required Items',
        description = itemList,
        type = 'inform',
        duration = 15000,
        icon = 'box',
    })
end

---Prospect run monitoring thread
function FreeGangs.Client.Archetypes.ProspectRunMonitorThread()
    local run = activeActivities.prospectRun
    if not run then return end
    
    local playerPed = PlayerPedId()
    local destCoords = run.destination and run.destination.coords
    
    if destCoords then
        destCoords = vector3(destCoords.x, destCoords.y, destCoords.z)
    end
    
    while activeActivities.prospectRun and activeActivities.prospectRun.runId == run.runId do
        local playerCoords = GetEntityCoords(playerPed)
        
        -- Check time remaining
        local remaining = run.expiresAt - os.time()
        if remaining <= 0 then
            FreeGangs.Client.Archetypes.FailProspectRun('Time expired')
            break
        end
        
        -- Check if still on motorcycle
        if not FreeGangs.Client.Archetypes.IsOnMotorcycle() then
            -- Give warning but don't fail immediately
            FreeGangs.Bridge.Notify('Get back on your motorcycle!', 'warning')
        end
        
        -- Check distance to destination
        if destCoords then
            local dist = #(playerCoords - destCoords)
            
            -- Route ambush check (spawn en route)
            if not run.ambushSpawned and dist > 100 and dist < 500 then
                if math.random() < run.routeAmbushChance then
                    FreeGangs.Client.Archetypes.SpawnRouteAmbush(run)
                    run.ambushSpawned = true
                end
            end
            
            -- At destination
            if dist < 20 and not run.atDestination then
                run.atDestination = true
                FreeGangs.Client.Archetypes.HandleProspectRunArrival()
            end
        end
        
        Wait(1000)
    end
end

---Spawn route ambush NPCs (MC biker ambush)
---@param run table
function FreeGangs.Client.Archetypes.SpawnRouteAmbush(run)
    FreeGangs.Bridge.Notify('Ambush! Enemy bikers incoming!', 'error')
    PlaySoundFrontend(-1, 'ENEMY_SPOTTED', 'HUD_FRONTEND_DEFAULT_SOUNDSET', false)
    
    local playerCoords = GetEntityCoords(PlayerPedId())
    local npcCount = run.routeAmbushNPCCount or 2
    local models = run.npcAmbushModels or { 'g_m_y_lost_01' }
    local vehicles = run.npcAmbushVehicles or { 'daemon' }
    
    -- Spawn behind/beside player
    for i = 1, npcCount do
        local angle = math.rad(180 + (i * 30) - (npcCount * 15))
        local distance = 50 + (i * 10)
        
        local spawnCoords = vector3(
            playerCoords.x + math.cos(angle) * distance,
            playerCoords.y + math.sin(angle) * distance,
            playerCoords.z
        )
        
        -- Find road position
        local success, roadCoords, roadHeading = GetClosestVehicleNodeWithHeading(
            spawnCoords.x, spawnCoords.y, spawnCoords.z, 1, 3.0, 0
        )
        
        if success then
            local vehicleModel = vehicles[math.random(#vehicles)]
            local pedModel = models[math.random(#models)]
            
            local vehicle, driver = FreeGangs.Client.Archetypes.SpawnVehicleWithDriver(
                vehicleModel, pedModel, roadCoords, roadHeading
            )
            
            -- Give weapon
            GiveWeaponToPed(driver, GetHashKey('WEAPON_PISTOL'), 100, false, true)
            
            -- Set hostile
            SetPedRelationshipGroupHash(driver, GetHashKey('HATES_PLAYER'))
            
            -- Chase player
            TaskVehicleChase(driver, PlayerPedId())
            SetPedCombatAttributes(driver, 46, true)
            SetPedCombatRange(driver, 2)
        end
    end
end

---Handle arrival at prospect run destination
function FreeGangs.Client.Archetypes.HandleProspectRunArrival()
    local run = activeActivities.prospectRun
    if not run then return end
    
    -- Check for destination ambush/doublecross
    local ambushed = math.random() < run.destinationAmbushChance
    
    if ambushed then
        FreeGangs.Bridge.Notify('It\'s a setup! They\'re waiting for you!', 'error')
        PlaySoundFrontend(-1, 'ENEMY_SPOTTED', 'HUD_FRONTEND_DEFAULT_SOUNDSET', false)
        
        -- Spawn ambush NPCs at destination
        local destCoords = vector3(run.destination.coords.x, run.destination.coords.y, run.destination.coords.z)
        
        for i = 1, 3 do
            local offset = vector3(math.random(-10, 10), math.random(-10, 10), 0)
            local npc = FreeGangs.Client.Archetypes.SpawnNPC(
                'g_m_y_mexgoon_01',
                destCoords + offset,
                math.random(0, 360),
                'WEAPON_MICROSMG'
            )
            
            TaskCombatPed(npc, PlayerPedId(), 0, 16)
        end
        
        -- Player must survive and complete
        FreeGangs.Bridge.Notify('Eliminate the threat and complete the delivery!', 'warning')
    else
        -- Show delivery prompt
        FreeGangs.Client.Archetypes.ShowDeliveryPrompt()
    end
end

---Show delivery prompt
function FreeGangs.Client.Archetypes.ShowDeliveryPrompt()
    local run = activeActivities.prospectRun
    if not run then return end
    
    local confirm = lib.alertDialog({
        header = 'Complete Delivery',
        content = 'Deliver the items to complete the prospect run?',
        centered = true,
        cancel = true,
    })
    
    if confirm == 'confirm' then
        FreeGangs.Client.Archetypes.CompleteProspectRun()
    end
end

---Complete prospect run
function FreeGangs.Client.Archetypes.CompleteProspectRun()
    local run = activeActivities.prospectRun
    if not run then return end
    
    local result = lib.callback.await('free-gangs:callback:completeProspectRun', false, {
        runId = run.runId,
        wasAmbushed = false,
    })
    
    if result and result.success then
        FreeGangs.Bridge.Notify(result.message or 'Prospect run completed!', 'success')
        FreeGangs.Client.Archetypes.EndProspectRun(true)
    else
        FreeGangs.Bridge.Notify(result and result.message or 'Failed to complete delivery', 'error')
    end
end

---Fail prospect run
---@param reason string
function FreeGangs.Client.Archetypes.FailProspectRun(reason)
    local run = activeActivities.prospectRun
    if not run then return end
    
    TriggerServerEvent('free-gangs:server:failProspectRun', run.runId, reason)
    FreeGangs.Client.Archetypes.EndProspectRun(false, reason)
end

---End prospect run
---@param success boolean
---@param reason string|nil
function FreeGangs.Client.Archetypes.EndProspectRun(success, reason)
    if not success then
        FreeGangs.Bridge.Notify('Prospect run failed: ' .. (reason or 'Unknown'), 'error')
    end
    
    FreeGangs.Client.Archetypes.CleanupEntities()
    activeActivities.prospectRun = nil
end

-- ============================================================================
-- MC: CLUB RUNS (TIER 2)
-- Scaled-up Prospect Runs for 4+ members
-- ============================================================================

---Handle club run start (synced to all members)
---@param data table
function FreeGangs.Client.Archetypes.HandleClubRunStart(data)
    activeActivities.clubRun = {
        runId = data.runId,
        startedBy = data.startedBy,
        requiredItems = data.requiredItems,
        destination = data.destination,
        timeLimit = data.timeLimit,
        startTime = GetGameTimer(),
        expiresAt = os.time() + data.timeLimit,
        destinationAmbushChance = data.destinationAmbushChance,
        routeAmbushChance = data.routeAmbushChance,
        routeAmbushNPCCount = data.routeAmbushNPCCount,
        ambushWaves = data.ambushWaves or 1,
        npcAmbushModels = data.npcAmbushModels,
        npcAmbushVehicles = data.npcAmbushVehicles,
        currentWave = 0,
        atDestination = false,
    }
    
    -- Notify
    lib.notify({
        title = 'Club Run Started',
        description = string.format('%s started a club run!\nTime: %d minutes',
            data.startedBy,
            math.floor(data.timeLimit / 60)
        ),
        type = 'inform',
        duration = 10000,
        icon = 'users',
    })
    
    -- Show required items
    FreeGangs.Client.Archetypes.ShowRequiredItemsUI(data.requiredItems, 'Club Run')
    
    -- Create destination blip
    if data.destination and data.destination.coords then
        local coords = data.destination.coords
        FreeGangs.Client.Archetypes.CreateDestinationBlip(
            vector3(coords.x, coords.y, coords.z),
            501,
            5,
            'Club Run Delivery: ' .. (data.destination.label or 'Drop-off')
        )
    end
    
    -- Ask to join
    local confirm = lib.alertDialog({
        header = 'Join Club Run?',
        content = 'A club run has started. Get on your bike and join!',
        centered = true,
        cancel = true,
    })
    
    if confirm == 'confirm' then
        FreeGangs.Client.Archetypes.JoinClubRun()
    end
end

---Join club run
---@return boolean, string
function FreeGangs.Client.Archetypes.JoinClubRun()
    if not FreeGangs.Client.Archetypes.IsOnMotorcycle() then
        FreeGangs.Bridge.Notify('You must be on a motorcycle', 'error')
        return false, 'Not on motorcycle'
    end
    
    local result = lib.callback.await('free-gangs:callback:joinClubRun', false)
    
    if result and result.success then
        FreeGangs.Bridge.Notify(result.message or 'Joined club run', 'success')
    else
        FreeGangs.Bridge.Notify(result and result.message or 'Failed to join', 'error')
    end
    
    return result and result.success or false, result and result.message or 'Unknown error'
end

-- ============================================================================
-- MC: TERRITORY RIDE (TIER 3)
-- Patrol ALL territories with 3+ members in proximity on motorcycles
-- ============================================================================

---Start a territory ride
---@return boolean, string
function FreeGangs.Client.Archetypes.StartTerritoryRide()
    if not FreeGangs.Client.Archetypes.IsOnMotorcycle() then
        FreeGangs.Bridge.Notify('You must be on a motorcycle to lead a territory ride', 'error')
        return false, 'Not on motorcycle'
    end
    
    local result = lib.callback.await('free-gangs:callback:startTerritoryRide', false)
    
    if result and result.success then
        FreeGangs.Bridge.Notify(result.message or 'Territory ride started!', 'success')
    else
        FreeGangs.Bridge.Notify(result and result.message or 'Failed to start territory ride', 'error')
    end
    
    return result and result.success or false, result and result.message or 'Unknown error'
end

---Handle territory ride start (from server)
---@param data table
function FreeGangs.Client.Archetypes.HandleTerritoryRideStart(data)
    activeActivities.territoryRide = {
        rideId = data.rideId,
        startedBy = data.startedBy,
        leaderSource = data.leaderSource,
        minMembers = data.minMembers,
        proximityRadius = data.proximityRadius,
        startTime = GetGameTimer(),
        zonesVisited = {},
        currentZone = nil,
        isLeader = GetPlayerServerId(PlayerId()) == data.leaderSource,
    }
    
    lib.notify({
        title = 'Territory Ride',
        description = string.format('%s started a territory ride!\nMin members: %d | Stay within %dm',
            data.startedBy,
            data.minMembers,
            data.proximityRadius
        ),
        type = 'inform',
        duration = 10000,
        icon = 'motorcycle',
    })
    
    -- Start monitoring thread
    CreateThread(function()
        FreeGangs.Client.Archetypes.TerritoryRideMonitorThread()
    end)
end

---Join territory ride
---@return boolean, string
function FreeGangs.Client.Archetypes.JoinTerritoryRide()
    if not FreeGangs.Client.Archetypes.IsOnMotorcycle() then
        FreeGangs.Bridge.Notify('You must be on a motorcycle', 'error')
        return false, 'Not on motorcycle'
    end
    
    local result = lib.callback.await('free-gangs:callback:joinTerritoryRide', false)
    
    if result and result.success then
        FreeGangs.Bridge.Notify(result.message or 'Joined territory ride', 'success')
    else
        FreeGangs.Bridge.Notify(result and result.message or 'Failed to join', 'error')
    end
    
    return result and result.success or false, result and result.message or 'Unknown error'
end

---Territory ride monitoring thread
function FreeGangs.Client.Archetypes.TerritoryRideMonitorThread()
    local ride = activeActivities.territoryRide
    if not ride then return end
    
    local lastZoneCheck = 0
    local zoneCheckInterval = 5000 -- 5 seconds
    
    while activeActivities.territoryRide and activeActivities.territoryRide.rideId == ride.rideId do
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        
        -- Check if still on motorcycle
        local onBike = FreeGangs.Client.Archetypes.IsOnMotorcycle()
        
        if not onBike then
            FreeGangs.Bridge.Notify('Get back on your motorcycle!', 'warning')
        end
        
        -- Periodic zone check (only leader sends to server)
        if ride.isLeader and GetGameTimer() - lastZoneCheck > zoneCheckInterval then
            lastZoneCheck = GetGameTimer()
            
            -- Get nearby gang members data
            local memberData = FreeGangs.Client.Archetypes.GetNearbyRideMemberData(playerCoords, ride.proximityRadius)
            
            -- Get current zone
            local currentZone = FreeGangs.Client.Archetypes.GetCurrentTerritoryZone(playerCoords)
            
            if currentZone then
                -- Send to server for validation
                TriggerServerEvent('free-gangs:server:territoryRideZoneCheck', {
                    rideId = ride.rideId,
                    leaderCoords = playerCoords,
                    memberData = memberData,
                    zoneName = currentZone.name,
                    isOwnedZone = currentZone.isOwned,
                    isOppositionZone = currentZone.isOpposition,
                    oppositionGang = currentZone.oppositionGang,
                })
            end
        end
        
        Wait(1000)
    end
end

---Get nearby ride member data for validation
---@param leaderCoords vector3
---@param radius number
---@return table memberData
function FreeGangs.Client.Archetypes.GetNearbyRideMemberData(leaderCoords, radius)
    local memberData = {}
    
    -- Get all players
    local players = GetActivePlayers()
    
    for _, playerId in ipairs(players) do
        local serverId = GetPlayerServerId(playerId)
        local ped = GetPlayerPed(playerId)
        
        if DoesEntityExist(ped) then
            local coords = GetEntityCoords(ped)
            local dist = #(coords - leaderCoords)
            
            -- Check if in proximity
            if dist <= radius then
                local vehicle = GetVehiclePedIsIn(ped, false)
                local onBike = false
                
                if vehicle ~= 0 then
                    local model = GetEntityModel(vehicle)
                    onBike = motorcycleHashes[model] == true or GetVehicleClass(vehicle) == 8
                end
                
                memberData[serverId] = {
                    coords = coords,
                    onBike = onBike,
                    distance = dist,
                }
            end
        end
    end
    
    return memberData
end

---Get current territory zone player is in
---@param coords vector3
---@return table|nil
function FreeGangs.Client.Archetypes.GetCurrentTerritoryZone(coords)
    -- This would integrate with your territory system
    -- For now, return a stub that server can validate
    
    local zoneId = GetNameOfZone(coords.x, coords.y, coords.z)
    
    return {
        name = zoneId,
        isOwned = false, -- Server determines this
        isOpposition = false,
        oppositionGang = nil,
    }
end

---End territory ride
---@return boolean, string
function FreeGangs.Client.Archetypes.EndTerritoryRide()
    local result = lib.callback.await('free-gangs:callback:endTerritoryRide', false)
    
    if result and result.success then
        FreeGangs.Bridge.Notify(result.message or 'Territory ride complete!', 'success')
        activeActivities.territoryRide = nil
    else
        FreeGangs.Bridge.Notify(result and result.message or 'Failed to end ride', 'error')
    end
    
    return result and result.success or false, result and result.message or 'Unknown error'
end

-- ============================================================================
-- CARTEL: HALCON NETWORK (TIER 1)
-- ============================================================================

---Toggle Halcon Network
---@param enabled boolean
---@return boolean, string
function FreeGangs.Client.Archetypes.ToggleHalconNetwork(enabled)
    local result = lib.callback.await('free-gangs:callback:toggleHalconNetwork', false, enabled)
    
    if result and result.success then
        halconEnabled = enabled
        FreeGangs.Bridge.Notify(result.message or (enabled and 'Halcon Network activated' or 'Halcon Network deactivated'), 'success')
    else
        FreeGangs.Bridge.Notify(result and result.message or 'Failed to toggle Halcon Network', 'error')
    end
    
    return result and result.success or false, result and result.message or 'Unknown error'
end

---Handle Halcon alert
---@param data table
function FreeGangs.Client.Archetypes.HandleHalconAlert(data)
    local alertType = data.alertType or 'unknown'
    local icon = 'eye'
    local color = '#FFA500'
    
    if alertType == 'rival' then
        icon = 'users'
        color = '#FF0000'
    elseif alertType == 'police' then
        icon = 'shield-halved'
        color = '#0000FF'
    end
    
    local description = 'Unknown activity detected'
    if data.intelQuality == 'basic' then
        description = string.format('%d contacts in %s', data.count or 1, data.zoneName or 'territory')
    elseif data.intelQuality == 'detailed' then
        description = string.format('%s (%d) in %s', data.names or 'Contacts', data.count or 1, data.zoneName or 'territory')
    elseif data.intelQuality == 'full' then
        description = string.format('%s in %s - Vehicle: %s', data.names or 'Contacts', data.zoneName or 'territory', data.vehicle or 'Unknown')
    end
    
    lib.notify({
        title = 'Halcon Alert',
        description = description,
        type = 'warning',
        duration = 8000,
        icon = icon,
        iconColor = color,
    })
    
    -- Create temp blip if coords provided
    if data.coords then
        local blip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
        SetBlipSprite(blip, 1)
        SetBlipColour(blip, alertType == 'police' and 3 or 1)
        SetBlipScale(blip, 0.8)
        SetBlipFlashes(blip, true)
        
        -- Remove after duration
        SetTimeout((data.blipDuration or 30) * 1000, function()
            if DoesBlipExist(blip) then
                RemoveBlip(blip)
            end
        end)
    end
    
    PlaySoundFrontend(-1, 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET', false)
end

-- ============================================================================
-- CARTEL: CONVOY PROTECTION (TIER 2)
-- Item delivery - NO route ambush, only destination ambush
-- Synced to all online gang members
-- ============================================================================

---Start convoy protection
---@return boolean, string
function FreeGangs.Client.Archetypes.StartConvoyProtection()
    local result = lib.callback.await('free-gangs:callback:startConvoyProtection', false)
    
    if result and result.success then
        FreeGangs.Bridge.Notify(result.message or 'Convoy protection started', 'success')
    else
        FreeGangs.Bridge.Notify(result and result.message or 'Failed to start convoy', 'error')
    end
    
    return result and result.success or false, result and result.message or 'Unknown error'
end

---Handle convoy start (synced to all members)
---@param data table
function FreeGangs.Client.Archetypes.HandleConvoyStart(data)
    activeActivities.convoyProtection = {
        convoyId = data.convoyId,
        startedBy = data.startedBy,
        requiredItems = data.requiredItems,
        destination = data.destination,
        timeLimit = data.timeLimit,
        startTime = GetGameTimer(),
        expiresAt = os.time() + data.timeLimit,
        destinationAmbushChance = data.destinationAmbushChance,
        hasRouteAmbush = data.hasRouteAmbush, -- Always false for Cartel
        atDestination = false,
    }
    
    -- Notify all gang members
    lib.notify({
        title = 'Convoy Protection Active',
        description = string.format('%s started a convoy!\nTime: %d minutes',
            data.startedBy,
            math.floor(data.timeLimit / 60)
        ),
        type = 'inform',
        duration = 10000,
        icon = 'truck',
    })
    
    -- Show required items
    FreeGangs.Client.Archetypes.ShowRequiredItemsUI(data.requiredItems, 'Convoy Protection')
    
    -- Create destination blip
    if data.destination and data.destination.coords then
        local coords = data.destination.coords
        FreeGangs.Client.Archetypes.CreateDestinationBlip(
            vector3(coords.x, coords.y, coords.z),
            477, -- Warehouse
            2,   -- Green
            'Convoy Delivery: ' .. (data.destination.label or 'Drop-off')
        )
    end
    
    -- Ask to join
    local confirm = lib.alertDialog({
        header = 'Join Convoy?',
        content = 'A convoy protection mission has started. Join the crew?',
        centered = true,
        cancel = true,
    })
    
    if confirm == 'confirm' then
        FreeGangs.Client.Archetypes.JoinConvoy()
    end
    
    -- Start monitoring thread
    CreateThread(function()
        FreeGangs.Client.Archetypes.ConvoyMonitorThread()
    end)
end

---Join convoy protection
---@return boolean, string
function FreeGangs.Client.Archetypes.JoinConvoy()
    local result = lib.callback.await('free-gangs:callback:joinConvoy', false)
    
    if result and result.success then
        FreeGangs.Bridge.Notify(result.message or 'Joined convoy', 'success')
    else
        FreeGangs.Bridge.Notify(result and result.message or 'Failed to join', 'error')
    end
    
    return result and result.success or false, result and result.message or 'Unknown error'
end

---Convoy monitoring thread
function FreeGangs.Client.Archetypes.ConvoyMonitorThread()
    local convoy = activeActivities.convoyProtection
    if not convoy then return end
    
    local playerPed = PlayerPedId()
    local destCoords = convoy.destination and convoy.destination.coords
    
    if destCoords then
        destCoords = vector3(destCoords.x, destCoords.y, destCoords.z)
    end
    
    while activeActivities.convoyProtection and activeActivities.convoyProtection.convoyId == convoy.convoyId do
        local playerCoords = GetEntityCoords(playerPed)
        
        -- Check time
        local remaining = convoy.expiresAt - os.time()
        if remaining <= 0 then
            FreeGangs.Bridge.Notify('Convoy time expired!', 'error')
            activeActivities.convoyProtection = nil
            break
        end
        
        -- Check distance to destination
        if destCoords and not convoy.atDestination then
            local dist = #(playerCoords - destCoords)
            
            if dist < 30 then
                convoy.atDestination = true
                FreeGangs.Client.Archetypes.HandleConvoyArrival()
            end
        end
        
        Wait(1000)
    end
end

---Handle convoy arrival at destination
function FreeGangs.Client.Archetypes.HandleConvoyArrival()
    local convoy = activeActivities.convoyProtection
    if not convoy then return end
    
    -- Check for doublecross
    local ambushed = math.random() < convoy.destinationAmbushChance
    
    if ambushed then
        FreeGangs.Bridge.Notify('Double-cross! They\'re turning on you!', 'error')
        PlaySoundFrontend(-1, 'ENEMY_SPOTTED', 'HUD_FRONTEND_DEFAULT_SOUNDSET', false)
        
        -- Spawn hostile NPCs
        local destCoords = vector3(convoy.destination.coords.x, convoy.destination.coords.y, convoy.destination.coords.z)
        
        for i = 1, 4 do
            local offset = vector3(math.random(-15, 15), math.random(-15, 15), 0)
            local npc = FreeGangs.Client.Archetypes.SpawnNPC(
                'g_m_y_mexgoon_01',
                destCoords + offset,
                math.random(0, 360),
                'WEAPON_ASSAULTRIFLE'
            )
            
            TaskCombatPed(npc, PlayerPedId(), 0, 16)
        end
        
        FreeGangs.Bridge.Notify('Eliminate the threat and complete delivery!', 'warning')
    else
        -- Show delivery prompt
        local confirm = lib.alertDialog({
            header = 'Complete Convoy Delivery',
            content = 'Deliver the cargo to complete the convoy protection?',
            centered = true,
            cancel = true,
        })
        
        if confirm == 'confirm' then
            FreeGangs.Client.Archetypes.CompleteConvoy()
        end
    end
end

---Complete convoy protection
function FreeGangs.Client.Archetypes.CompleteConvoy()
    local convoy = activeActivities.convoyProtection
    if not convoy then return end
    
    local result = lib.callback.await('free-gangs:callback:completeConvoy', false, {
        convoyId = convoy.convoyId,
        wasAmbushed = false,
    })
    
    if result and result.success then
        FreeGangs.Bridge.Notify(result.message or 'Convoy delivered!', 'success')
    else
        FreeGangs.Bridge.Notify(result and result.message or 'Failed to complete delivery', 'error')
    end
    
    FreeGangs.Client.Archetypes.CleanupEntities()
    activeActivities.convoyProtection = nil
end

-- ============================================================================
-- CRIME FAMILY: BUSINESS EXTORTION (PASSIVE BONUS)
-- ============================================================================

---Get extortion bonus info (for UI display)
---@return table
function FreeGangs.Client.Archetypes.GetExtortionBonusInfo()
    local result = lib.callback.await('free-gangs:callback:getExtortionBonusInfo', false)
    return result or { active = false, repBonus = '0%', payoutBonus = '0%' }
end

-- ============================================================================
-- BLOCK PARTY (STREET GANG - TIER 2)
-- ============================================================================

---Start a block party
---@param zoneName string
---@return boolean, string
function FreeGangs.Client.Archetypes.StartBlockParty(zoneName)
    local result = lib.callback.await('free-gangs:callback:startBlockParty', false, zoneName)
    
    if result and result.success then
        FreeGangs.Bridge.Notify(result.message or 'Block party started!', 'success')
    else
        FreeGangs.Bridge.Notify(result and result.message or 'Failed to start block party', 'error')
    end
    
    return result and result.success or false, result and result.message or 'Unknown error'
end

---Handle block party notification
---@param data table
function FreeGangs.Client.Archetypes.HandleBlockPartyNotification(data)
    lib.notify({
        title = 'Block Party!',
        description = string.format('%s is throwing a block party in %s!', 
            data.gangLabel or 'A gang',
            data.zoneName or 'the neighborhood'
        ),
        type = 'inform',
        duration = 10000,
        icon = 'music',
    })
    
    -- Create party blip
    if data.coords then
        local blip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
        SetBlipSprite(blip, 614) -- Party icon
        SetBlipColour(blip, 5) -- Yellow
        SetBlipScale(blip, 1.0)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Block Party')
        EndTextCommandSetBlipName(blip)
        
        -- Remove when party ends
        SetTimeout((data.duration or 3600) * 1000, function()
            if DoesBlipExist(blip) then
                RemoveBlip(blip)
            end
        end)
    end
end

-- ============================================================================
-- ARCHETYPE INFO & UI
-- ============================================================================

---Get archetype info
---@return table|nil
function FreeGangs.Client.Archetypes.GetInfo()
    if cachedArchetypeInfo then
        return cachedArchetypeInfo
    end
    
    local result = lib.callback.await('free-gangs:callback:getArchetypeInfo', false)
    if result then
        cachedArchetypeInfo = result
    end
    return result
end

---Get available tier activities
---@return table
function FreeGangs.Client.Archetypes.GetTierActivities()
    if cachedTierActivities then
        return cachedTierActivities
    end
    
    local result = lib.callback.await('free-gangs:callback:getTierActivities', false)
    if result then
        cachedTierActivities = result
    end
    return result or {}
end

---Open archetype activities menu
function FreeGangs.Client.Archetypes.OpenActivitiesMenu()
    local info = FreeGangs.Client.Archetypes.GetInfo()
    if not info then
        FreeGangs.Bridge.Notify('Unable to load archetype info', 'error')
        return
    end
    
    local activities = FreeGangs.Client.Archetypes.GetTierActivities()
    local options = {}
    
    for _, activity in ipairs(activities) do
        local locked = not activity.unlocked
        
        table.insert(options, {
            title = activity.name,
            description = locked and ('Requires Level ' .. activity.requiredLevel) or activity.description,
            icon = activity.icon or 'star',
            disabled = locked,
            onSelect = function()
                FreeGangs.Client.Archetypes.ExecuteActivity(activity.id)
            end,
        })
    end
    
    lib.registerContext({
        id = 'archetype_activities',
        title = (info.label or 'Gang') .. ' Activities',
        options = options,
    })
    
    lib.showContext('archetype_activities')
end

---Execute an archetype activity
---@param activityId string
function FreeGangs.Client.Archetypes.ExecuteActivity(activityId)
    local actions = {
        -- Street Gang
        driveby_contract = FreeGangs.Client.Archetypes.StartDriveByContract,
        block_party = FreeGangs.Client.Archetypes.StartBlockParty,
        
        -- MC
        prospect_run = FreeGangs.Client.Archetypes.StartProspectRun,
        club_run = FreeGangs.Client.Archetypes.JoinClubRun,
        territory_ride = FreeGangs.Client.Archetypes.StartTerritoryRide,
        
        -- Cartel
        halcon_toggle = function() 
            FreeGangs.Client.Archetypes.ToggleHalconNetwork(not halconEnabled)
        end,
        convoy_protection = FreeGangs.Client.Archetypes.StartConvoyProtection,
        
        -- Crime Family
        extortion_info = function()
            local info = FreeGangs.Client.Archetypes.GetExtortionBonusInfo()
            lib.alertDialog({
                header = 'Business Extortion Bonus',
                content = string.format(
                    'Status: %s\nRep Bonus: %s\nPayout Bonus: %s\n\n%s',
                    info.active and 'Active' or 'Inactive',
                    info.repBonus,
                    info.payoutBonus,
                    info.description or ''
                ),
                centered = true,
            })
        end,
    }
    
    local action = actions[activityId]
    if action then
        action()
    else
        FreeGangs.Bridge.Notify('Unknown activity: ' .. activityId, 'error')
    end
end

-- ============================================================================
-- PRISON ACTIVITIES (STUBS)
-- ============================================================================

function FreeGangs.Client.Prison.HandleContrabandReady()
    lib.notify({
        title = 'Contraband Ready',
        description = 'Your smuggled goods are ready for pickup',
        type = 'inform',
        duration = 10000,
        icon = 'box',
    })
end

function FreeGangs.Client.Prison.HandleEscapeInitiated(data)
    lib.notify({
        title = 'Prison Break',
        description = 'An escape attempt has been initiated!',
        type = 'warning',
        duration = 15000,
        icon = 'unlock',
    })
end

-- ============================================================================
-- CACHE INVALIDATION
-- ============================================================================

---Clear cached data
function FreeGangs.Client.Archetypes.ClearCache()
    cachedArchetypeInfo = nil
    cachedPassiveBonuses = nil
    cachedTierActivities = nil
    cachedPrisonData = nil
end

-- Listen for cache invalidation
RegisterNetEvent('free-gangs:client:clearArchetypeCache', function()
    FreeGangs.Client.Archetypes.ClearCache()
end)

-- ============================================================================
-- CLEANUP ON RESOURCE STOP
-- ============================================================================

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    FreeGangs.Client.Archetypes.CleanupEntities()
end)

-- Initialize on resource start
CreateThread(function()
    Wait(1000)
    FreeGangs.Client.Archetypes.Initialize()
end)
