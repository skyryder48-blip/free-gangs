--[[
    FREE-GANGS: Client Graffiti Module
    
    Handles client-side graffiti/tagging system:
    - Wall detection and targeting
    - Spray animations and progress
    - Tag visual rendering (decals/props)
    - Zone-based loading/unloading
    - Removal mechanics
    - ox_target integration
]]

FreeGangs.Client = FreeGangs.Client or {}
FreeGangs.Client.Graffiti = {}

-- ============================================================================
-- LOCAL STATE
-- ============================================================================

local isSpraying = false
local activeGraffitiObjects = {} -- tagId -> entity handle
local loadedGraffiti = {}        -- tagId -> tag data
local currentRenderZone = nil
local renderThread = nil

-- Graffiti decal/prop models (using in-game props for visual representation)
local graffitiModels = {
    'prop_graffiti_ld_01',    -- Gang graffiti prop
    'prop_graffiti_ld_02',
    'prop_graffiti_ld_03',
    'prop_graffiti_ld_04',
    'prop_graffiti_ld_05',
    'prop_graffiti_ld_06',
    'prop_graffiti_ld_07',
    'prop_graffiti_ld_08',
}

-- Texture dictionary and names for runtime texturing (if supported)
local graffitiTextures = {
    dict = 'graffiti_tags',
    textures = {
        'gang_tag_01',
        'gang_tag_02', 
        'gang_tag_03',
        'gang_tag_04',
    },
}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

---Check if currently spraying
---@return boolean
function FreeGangs.Client.Graffiti.IsBusy()
    return isSpraying
end

---Set spraying state
---@param busy boolean
local function SetBusy(busy)
    isSpraying = busy
end

---Get config values with fallbacks
local function GetConfig()
    local cfg = FreeGangs.Config.Activities and FreeGangs.Config.Activities.Graffiti or {}
    return {
        requiredItem = cfg.RequiredItem or 'spray_can',
        consumeItem = cfg.ConsumeItem ~= false,
        sprayDuration = cfg.SprayDuration or 5000,
        animDict = cfg.Animation and cfg.Animation.dict or 'switch@franklin@lamar_tagging_wall',
        animName = cfg.Animation and cfg.Animation.anim or 'lamar_tagging_wall_loop_lamar',
        removalItem = cfg.RemovalItem or 'cleaning_kit',
        removalDuration = cfg.RemovalDuration or 8000,
        renderDistance = cfg.RenderDistance or 100.0,
        maxPerZone = cfg.MaxPerZone or 20,
    }
end

---Get player's current heading for tag rotation
---@return table rotation
local function GetPlayerRotation()
    local ped = FreeGangs.Client.GetPlayerPed()
    local heading = GetEntityHeading(ped)
    return { x = 0.0, y = 0.0, z = heading }
end

---Find suitable wall surface in front of player
---@return boolean found
---@return table|nil coords
---@return table|nil rotation
---@return table|nil surfaceNormal
local function FindWallSurface()
    local ped = FreeGangs.Client.GetPlayerPed()
    local coords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    
    -- Raycast to find wall
    local startPos = coords + vector3(0, 0, 0.5) -- Slightly above ground
    local endPos = startPos + (forward * 2.0)    -- 2 meters in front
    
    local rayHandle = StartShapeTestRay(
        startPos.x, startPos.y, startPos.z,
        endPos.x, endPos.y, endPos.z,
        1 + 16, -- World + buildings
        ped,
        0
    )
    
    local _, hit, hitCoords, surfaceNormal, _ = GetShapeTestResult(rayHandle)
    
    if hit == 1 then
        -- Calculate rotation to face wall
        local wallHeading = math.deg(math.atan2(surfaceNormal.y, surfaceNormal.x)) + 90
        local rotation = { x = 0.0, y = 0.0, z = wallHeading }
        
        -- Offset slightly from wall to prevent z-fighting
        local sprayCoords = {
            x = hitCoords.x + (surfaceNormal.x * 0.05),
            y = hitCoords.y + (surfaceNormal.y * 0.05),
            z = hitCoords.z + (surfaceNormal.z * 0.05),
        }
        
        return true, sprayCoords, rotation, { x = surfaceNormal.x, y = surfaceNormal.y, z = surfaceNormal.z }
    end
    
    return false, nil, nil, nil
end

---Calculate distance between two coordinate tables
---@param c1 table {x, y, z}
---@param c2 table {x, y, z}
---@return number distance
local function GetDistance(c1, c2)
    return math.sqrt(
        (c1.x - c2.x)^2 +
        (c1.y - c2.y)^2 +
        (c1.z - c2.z)^2
    )
end

-- ============================================================================
-- VISUAL RENDERING
-- ============================================================================

---Create visual representation of graffiti tag
---@param tagData table Tag data from server
---@return number|nil entity handle
local function CreateGraffitiVisual(tagData)
    if not tagData or not tagData.coords then
        return nil
    end
    
    -- Select model based on gang or random
    local modelIndex = (tagData.id % #graffitiModels) + 1
    local model = graffitiModels[modelIndex]
    
    -- Request model
    local modelHash = joaat(model)
    lib.requestModel(modelHash, 5000)
    
    if not HasModelLoaded(modelHash) then
        FreeGangs.Utils.Debug('Failed to load graffiti model:', model)
        return nil
    end
    
    -- Create object
    local coords = tagData.coords
    local rotation = tagData.rotation or { x = 0, y = 0, z = 0 }
    
    local entity = CreateObject(
        modelHash,
        coords.x, coords.y, coords.z,
        false, false, false
    )
    
    if entity and entity ~= 0 then
        -- Set rotation
        SetEntityRotation(entity, rotation.x, rotation.y, rotation.z, 2, true)
        
        -- Freeze in place
        FreezeEntityPosition(entity, true)
        
        -- Make non-collidable
        SetEntityCollision(entity, false, false)
        
        -- Set alpha for subtle effect
        SetEntityAlpha(entity, 230, false)
        
        -- Mark as mission entity so it doesn't despawn
        SetEntityAsMissionEntity(entity, true, true)
        
        SetModelAsNoLongerNeeded(modelHash)
        
        return entity
    end
    
    SetModelAsNoLongerNeeded(modelHash)
    return nil
end

---Remove graffiti visual
---@param tagId number
local function RemoveGraffitiVisual(tagId)
    local entity = activeGraffitiObjects[tagId]
    if entity and DoesEntityExist(entity) then
        SetEntityAsMissionEntity(entity, false, true)
        DeleteEntity(entity)
    end
    activeGraffitiObjects[tagId] = nil
end

---Load graffiti visuals for a set of tags
---@param tags table Array of tag data
local function LoadGraffitiVisuals(tags)
    for _, tag in pairs(tags) do
        if not activeGraffitiObjects[tag.id] then
            local entity = CreateGraffitiVisual(tag)
            if entity then
                activeGraffitiObjects[tag.id] = entity
                loadedGraffiti[tag.id] = tag
                AddTagTargeting(tag.id)
            end
        end
    end
end

---Unload all graffiti visuals
local function UnloadAllGraffiti()
    for tagId, entity in pairs(activeGraffitiObjects) do
        if DoesEntityExist(entity) then
            SetEntityAsMissionEntity(entity, false, true)
            DeleteEntity(entity)
        end
    end
    activeGraffitiObjects = {}
    loadedGraffiti = {}
end

---Update visible graffiti based on player position
local function UpdateVisibleGraffiti()
    local ped = FreeGangs.Client.GetPlayerPed()
    local coords = GetEntityCoords(ped)
    local config = GetConfig()
    
    -- Remove out-of-range graffiti (collect IDs first to avoid modifying table during iteration)
    local toRemove = {}
    for tagId, tag in pairs(loadedGraffiti) do
        if tag.coords then
            local distance = GetDistance(coords, tag.coords)
            if distance > config.renderDistance then
                toRemove[#toRemove + 1] = tagId
            end
        end
    end
    for _, tagId in ipairs(toRemove) do
        RemoveGraffitiVisual(tagId)
        loadedGraffiti[tagId] = nil
    end
    
    -- Request nearby graffiti from server
    local nearbyTags = lib.callback.await(FreeGangs.Callbacks.GET_NEARBY_GRAFFITI, false, 
        { x = coords.x, y = coords.y, z = coords.z }, 
        config.renderDistance
    )
    
    if nearbyTags then
        LoadGraffitiVisuals(nearbyTags)
    end
end

-- ============================================================================
-- SPRAY MECHANICS
-- ============================================================================

---Attempt to spray graffiti on a wall
---@param wallCoords table|nil Optional specific coordinates
function FreeGangs.Client.Graffiti.StartSpray(wallCoords)
    if isSpraying then
        FreeGangs.Bridge.Notify(FreeGangs.L('errors', 'busy'), 'error')
        return
    end
    
    -- Check if in gang
    if not FreeGangs.Client.PlayerGang then
        FreeGangs.Bridge.Notify(FreeGangs.L('gangs', 'not_in_gang'), 'error')
        return
    end
    
    local config = GetConfig()
    
    -- Check for spray can
    if not FreeGangs.Bridge.HasItem(config.requiredItem, 1) then
        FreeGangs.Bridge.Notify(FreeGangs.L('activities', 'graffiti_no_spray'), 'error')
        return
    end
    
    -- Find wall surface if not provided
    local coords, rotation, surfaceNormal
    if wallCoords then
        coords = wallCoords.coords
        rotation = wallCoords.rotation or GetPlayerRotation()
        surfaceNormal = wallCoords.normal or { x = 0, y = 0, z = 0 }
    else
        local found
        found, coords, rotation, surfaceNormal = FindWallSurface()
        
        if not found then
            FreeGangs.Bridge.Notify(FreeGangs.L('activities', 'graffiti_no_wall'), 'error')
            return
        end
    end
    
    SetBusy(true)
    
    -- Notify server of start
    TriggerServerEvent('freegangs:server:startGraffiti', coords)
    
    local ped = FreeGangs.Client.GetPlayerPed()
    
    -- Face the wall
    local wallDir = vector3(surfaceNormal.x, surfaceNormal.y, 0)
    local heading = math.deg(math.atan2(-wallDir.y, -wallDir.x))
    TaskTurnPedToFaceCoord(ped, coords.x, coords.y, coords.z, 1000)
    Wait(500)
    
    -- Attach spray can prop to hand
    local sprayCanHash = joaat('prop_cs_spray_can')
    lib.requestModel(sprayCanHash, 5000)
    
    local sprayCanProp = nil
    if HasModelLoaded(sprayCanHash) then
        sprayCanProp = CreateObject(sprayCanHash, 0, 0, 0, true, true, true)
        AttachEntityToEntity(
            sprayCanProp, ped,
            GetPedBoneIndex(ped, 57005), -- Right hand
            0.12, 0.01, -0.01,
            -80.0, 0.0, 0.0,
            true, true, false, true, 1, true
        )
    end
    
    -- Play spray animation with progress bar
    local success = lib.progressBar({
        duration = config.sprayDuration,
        label = FreeGangs.L('activities', 'graffiti_spraying') or 'Spraying...',
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
        anim = {
            dict = config.animDict,
            clip = config.animName,
            flag = 1,
        },
    })
    
    -- Clean up prop and release model
    if sprayCanProp and DoesEntityExist(sprayCanProp) then
        DeleteEntity(sprayCanProp)
    end
    SetModelAsNoLongerNeeded(sprayCanHash)
    
    -- Clear animation
    ClearPedTasks(ped)
    
    if success then
        -- Complete spray on server
        local spraySuccess, message, result = lib.callback.await('freegangs:graffiti:spray', false, 
            coords, 
            rotation, 
            nil -- image (optional custom image reference)
        )
        
        if spraySuccess then
            FreeGangs.Bridge.Notify(message, 'success')
            
            -- If result includes new tag data, add visual immediately
            if result and result.tag then
                local entity = CreateGraffitiVisual(result.tag)
                if entity then
                    activeGraffitiObjects[result.tag.id] = entity
                    loadedGraffiti[result.tag.id] = result.tag
                end
            end
            
            -- Play success effect (non-looped particle with timeout and cleanup)
            local particleDict = 'core'
            local particleName = 'ent_amb_smoke_foundry'
            RequestNamedPtfxAsset(particleDict)
            local ptfxTimeout = 0
            while not HasNamedPtfxAssetLoaded(particleDict) and ptfxTimeout < 200 do
                Wait(10)
                ptfxTimeout = ptfxTimeout + 1
            end
            if HasNamedPtfxAssetLoaded(particleDict) then
                SetPtfxAssetNextCall(particleDict)
                local ptfxHandle = StartParticleFxLoopedAtCoord(
                    particleName,
                    coords.x, coords.y, coords.z,
                    0.0, 0.0, 0.0,
                    0.5, false, false, false, false
                )
                -- Stop looped particle after 2 seconds and release asset
                SetTimeout(2000, function()
                    if ptfxHandle then
                        StopParticleFxLooped(ptfxHandle, false)
                    end
                    RemoveNamedPtfxAsset(particleDict)
                end)
            end
        else
            FreeGangs.Bridge.Notify(message or FreeGangs.L('errors', 'generic'), 'error')
        end
    else
        FreeGangs.Bridge.Notify(FreeGangs.L('activities', 'graffiti_cancelled'), 'info')
    end
    
    SetBusy(false)
end

---Quick spray using keybind (finds nearest wall)
function FreeGangs.Client.Graffiti.QuickSpray()
    FreeGangs.Client.Graffiti.StartSpray(nil)
end

-- ============================================================================
-- REMOVAL MECHANICS
-- ============================================================================

---Remove a graffiti tag
---@param tagId number Tag ID to remove
function FreeGangs.Client.Graffiti.StartRemoval(tagId)
    if isSpraying then
        FreeGangs.Bridge.Notify(FreeGangs.L('errors', 'busy'), 'error')
        return
    end
    
    local tagData = loadedGraffiti[tagId]
    if not tagData then
        FreeGangs.Bridge.Notify(FreeGangs.L('activities', 'graffiti_not_found'), 'error')
        return
    end
    
    local config = GetConfig()
    
    -- Check for cleaning item
    if not FreeGangs.Bridge.HasItem(config.removalItem, 1) then
        FreeGangs.Bridge.Notify(FreeGangs.L('activities', 'graffiti_no_cleaner'), 'error')
        return
    end
    
    SetBusy(true)
    
    local ped = FreeGangs.Client.GetPlayerPed()
    
    -- Face the tag
    TaskTurnPedToFaceCoord(ped, tagData.coords.x, tagData.coords.y, tagData.coords.z, 1000)
    Wait(500)
    
    -- Play cleaning animation with progress bar
    local success = lib.progressBar({
        duration = config.removalDuration,
        label = FreeGangs.L('activities', 'graffiti_removing') or 'Removing graffiti...',
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
        anim = {
            dict = 'timetable@floyd@clean_kitchen@base',
            clip = 'base',
            flag = 1,
        },
    })
    
    -- Clear animation
    ClearPedTasks(ped)
    
    if success then
        -- Complete removal on server
        local removeSuccess, message, result = lib.callback.await('freegangs:graffiti:remove', false, tagId)
        
        if removeSuccess then
            FreeGangs.Bridge.Notify(message, 'success')
            
            -- Remove visual immediately
            RemoveGraffitiVisual(tagId)
            loadedGraffiti[tagId] = nil
        else
            FreeGangs.Bridge.Notify(message or FreeGangs.L('errors', 'generic'), 'error')
        end
    else
        FreeGangs.Bridge.Notify(FreeGangs.L('activities', 'graffiti_cancelled'), 'info')
    end
    
    SetBusy(false)
end

---Get nearby tag for targeting
---@param coords table|nil Player coords (uses current if nil)
---@return table|nil nearestTag
function FreeGangs.Client.Graffiti.GetNearestTag(coords)
    if not coords then
        local ped = FreeGangs.Client.GetPlayerPed()
        local pedCoords = GetEntityCoords(ped)
        coords = { x = pedCoords.x, y = pedCoords.y, z = pedCoords.z }
    end
    
    local nearest = nil
    local nearestDist = math.huge
    
    for tagId, tag in pairs(loadedGraffiti) do
        if tag.coords then
            local dist = GetDistance(coords, tag.coords)
            if dist < nearestDist then
                nearestDist = dist
                nearest = tag
            end
        end
    end
    
    return nearest, nearestDist
end

-- ============================================================================
-- ox_target INTEGRATION
-- ============================================================================

local graffitiTargetActive = false

---Enable graffiti target zones
function FreeGangs.Client.Graffiti.EnableTargeting()
    if graffitiTargetActive then return end
    
    -- Target for graffiti tags (removal)
    for tagId, tag in pairs(loadedGraffiti) do
        local entity = activeGraffitiObjects[tagId]
        if entity and DoesEntityExist(entity) then
            exports.ox_target:addLocalEntity(entity, {
                {
                    name = 'fg_remove_tag_' .. tagId,
                    icon = 'fas fa-eraser',
                    label = 'Remove Graffiti',
                    distance = 2.0,
                    canInteract = function()
                        -- Check if player has cleaning item
                        local config = GetConfig()
                        return FreeGangs.Bridge.HasItem(config.removalItem, 1)
                    end,
                    onSelect = function()
                        FreeGangs.Client.Graffiti.StartRemoval(tagId)
                    end,
                },
            })
        end
    end
    
    graffitiTargetActive = true
end

---Disable graffiti target zones
function FreeGangs.Client.Graffiti.DisableTargeting()
    if not graffitiTargetActive then return end
    
    for tagId, entity in pairs(activeGraffitiObjects) do
        if entity and DoesEntityExist(entity) then
            exports.ox_target:removeLocalEntity(entity, { 'fg_remove_tag_' .. tagId })
        end
    end
    
    graffitiTargetActive = false
end

---Add targeting for a new tag
---@param tagId number
local function AddTagTargeting(tagId)
    local entity = activeGraffitiObjects[tagId]
    if entity and DoesEntityExist(entity) and graffitiTargetActive then
        exports.ox_target:addLocalEntity(entity, {
            {
                name = 'fg_remove_tag_' .. tagId,
                icon = 'fas fa-eraser',
                label = 'Remove Graffiti',
                distance = 2.0,
                canInteract = function()
                    local config = GetConfig()
                    return FreeGangs.Bridge.HasItem(config.removalItem, 1)
                end,
                onSelect = function()
                    FreeGangs.Client.Graffiti.StartRemoval(tagId)
                end,
            },
        })
    end
end

---Remove targeting for a tag
---@param tagId number
local function RemoveTagTargeting(tagId)
    local entity = activeGraffitiObjects[tagId]
    if entity and DoesEntityExist(entity) then
        exports.ox_target:removeLocalEntity(entity, { 'fg_remove_tag_' .. tagId })
    end
end

-- ============================================================================
-- KEYBIND INTEGRATION
-- ============================================================================

---Register graffiti keybinds
function FreeGangs.Client.Graffiti.RegisterKeybinds()
    -- Register spray keybind (disabled by default, players enable in settings)
    lib.addKeybind({
        name = 'fg_spray_graffiti',
        description = 'Spray graffiti on nearby wall',
        defaultKey = '', -- No default, let players set if they want
        onPressed = function()
            if FreeGangs.Client.PlayerGang then
                FreeGangs.Client.Graffiti.QuickSpray()
            end
        end,
    })
end

-- ============================================================================
-- CONTEXT MENU
-- ============================================================================

---Open graffiti management menu
function FreeGangs.Client.Graffiti.OpenMenu()
    if not FreeGangs.Client.PlayerGang then
        FreeGangs.Bridge.Notify(FreeGangs.L('gangs', 'not_in_gang'), 'error')
        return
    end
    
    local config = GetConfig()
    local hasSprayCan = FreeGangs.Bridge.HasItem(config.requiredItem, 1)
    local hasCleaner = FreeGangs.Bridge.HasItem(config.removalItem, 1)
    
    local options = {}
    
    -- Spray option
    options[#options + 1] = {
        title = 'Spray Tag',
        description = hasSprayCan and 'Spray your gang\'s tag on a nearby wall' or 'Requires: ' .. config.requiredItem,
        icon = 'fas fa-spray-can',
        disabled = not hasSprayCan,
        onSelect = function()
            FreeGangs.Client.Graffiti.QuickSpray()
        end,
    }
    
    -- Find nearby tag for removal option
    local nearestTag, nearestDist = FreeGangs.Client.Graffiti.GetNearestTag()
    if nearestTag and nearestDist <= 5.0 then
        local isOwnTag = nearestTag.gang_name == FreeGangs.Client.PlayerGang.name
        options[#options + 1] = {
            title = isOwnTag and 'Remove Own Tag' or 'Remove Rival Tag',
            description = hasCleaner 
                and string.format('Remove %s tag (%.1fm away)', nearestTag.gang_name, nearestDist)
                or 'Requires: ' .. config.removalItem,
            icon = 'fas fa-eraser',
            disabled = not hasCleaner,
            onSelect = function()
                FreeGangs.Client.Graffiti.StartRemoval(nearestTag.id)
            end,
        }
    end
    
    -- View gang tags option
    options[#options + 1] = {
        title = 'View Gang Tags',
        description = 'Show locations of your gang\'s tags',
        icon = 'fas fa-map-marker-alt',
        onSelect = function()
            FreeGangs.Client.Graffiti.ShowGangTags()
        end,
    }
    
    lib.registerContext({
        id = 'fg_graffiti_menu',
        title = 'Graffiti',
        options = options,
    })
    
    lib.showContext('fg_graffiti_menu')
end

---Show all gang tags on map temporarily
function FreeGangs.Client.Graffiti.ShowGangTags()
    local gangTags = lib.callback.await('freegangs:graffiti:getGangTags', false)
    
    if not gangTags or #gangTags == 0 then
        FreeGangs.Bridge.Notify('No tags found for your gang', 'info')
        return
    end
    
    -- Add blips for each tag
    local blips = {}
    for _, tag in pairs(gangTags) do
        if tag.coords then
            local blip = AddBlipForCoord(tag.coords.x, tag.coords.y, tag.coords.z)
            SetBlipSprite(blip, 486) -- Spray can icon
            SetBlipColour(blip, 5) -- Yellow
            SetBlipScale(blip, 0.8)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName('Gang Tag')
            EndTextCommandSetBlipName(blip)
            
            blips[#blips + 1] = blip
        end
    end
    
    FreeGangs.Bridge.Notify(string.format('Showing %d gang tags on map for 30 seconds', #blips), 'info')
    
    -- Remove blips after 30 seconds
    SetTimeout(30000, function()
        for _, blip in pairs(blips) do
            RemoveBlip(blip)
        end
    end)
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

---Handle loading graffiti from server
RegisterNetEvent(FreeGangs.Events.Client.LOAD_GRAFFITI, function(tags)
    FreeGangs.Utils.Debug('Loading ' .. #(tags or {}) .. ' graffiti tags')
    
    if tags then
        LoadGraffitiVisuals(tags)
        
        -- Enable targeting if player is in gang
        if FreeGangs.Client.PlayerGang then
            FreeGangs.Client.Graffiti.EnableTargeting()
        end
    end
end)

---Handle new graffiti added
RegisterNetEvent(FreeGangs.Events.Client.ADD_GRAFFITI, function(tagData)
    if not tagData then return end
    
    FreeGangs.Utils.Debug('Adding new graffiti tag:', tagData.id)
    
    -- Check if in range
    local ped = FreeGangs.Client.GetPlayerPed()
    local coords = GetEntityCoords(ped)
    local config = GetConfig()
    
    if tagData.coords then
        local distance = GetDistance(coords, tagData.coords)
        if distance <= config.renderDistance then
            local entity = CreateGraffitiVisual(tagData)
            if entity then
                activeGraffitiObjects[tagData.id] = entity
                loadedGraffiti[tagData.id] = tagData
                AddTagTargeting(tagData.id)
            end
        end
    end
end)

---Handle graffiti removed
RegisterNetEvent(FreeGangs.Events.Client.REMOVE_GRAFFITI, function(tagId)
    FreeGangs.Utils.Debug('Removing graffiti tag:', tagId)
    
    RemoveTagTargeting(tagId)
    RemoveGraffitiVisual(tagId)
    loadedGraffiti[tagId] = nil
end)

---Handle player gang change
RegisterNetEvent(FreeGangs.Events.Client.GANG_UPDATED, function(gangData)
    if gangData then
        FreeGangs.Client.Graffiti.EnableTargeting()
    else
        FreeGangs.Client.Graffiti.DisableTargeting()
    end
end)

-- ============================================================================
-- BACKGROUND THREADS
-- ============================================================================

---Start the graffiti render thread
local renderThreadStarted = false
local function StartRenderThread()
    if renderThreadStarted then return end
    renderThreadStarted = true

    CreateThread(function()
        while true do
            Wait(5000) -- Check every 5 seconds

            if FreeGangs.Client.Ready then
                UpdateVisibleGraffiti()
            end
        end
    end)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Initialize graffiti system
function FreeGangs.Client.Graffiti.Initialize()
    FreeGangs.Utils.Log('Initializing graffiti system...')
    
    -- Start render thread
    StartRenderThread()
    
    -- Register keybinds
    FreeGangs.Client.Graffiti.RegisterKeybinds()
    
    -- Initial load of nearby graffiti
    Wait(2000) -- Wait for client to be ready
    UpdateVisibleGraffiti()
    
    -- Enable targeting if player has gang
    if FreeGangs.Client.PlayerGang then
        FreeGangs.Client.Graffiti.EnableTargeting()
    end
    
    FreeGangs.Utils.Log('Graffiti system initialized')
end

-- ============================================================================
-- CLEANUP
-- ============================================================================

---Cleanup on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    -- Remove all graffiti visuals
    UnloadAllGraffiti()
    
    -- Disable targeting
    FreeGangs.Client.Graffiti.DisableTargeting()
end)

-- ============================================================================
-- DEBUG COMMANDS
-- ============================================================================

if FreeGangs.Config.General and FreeGangs.Config.General.Debug then
    RegisterCommand('fg_graffiti_reload', function()
        UnloadAllGraffiti()
        Wait(100)
        UpdateVisibleGraffiti()
        FreeGangs.Bridge.Notify('Reloaded nearby graffiti', 'info')
    end, false)
    
    RegisterCommand('fg_graffiti_count', function()
        local count = 0
        for _ in pairs(loadedGraffiti) do count = count + 1 end
        FreeGangs.Bridge.Notify(string.format('Loaded graffiti: %d', count), 'info')
    end, false)
    
    RegisterCommand('fg_graffiti_menu', function()
        FreeGangs.Client.Graffiti.OpenMenu()
    end, false)
end

-- Auto-initialize when client is ready
CreateThread(function()
    while not FreeGangs.Client or not FreeGangs.Client.Ready do
        Wait(100)
    end
    
    FreeGangs.Client.Graffiti.Initialize()
end)

return FreeGangs.Client.Graffiti
