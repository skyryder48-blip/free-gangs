--[[
    FREE-GANGS: Client Graffiti Module (DUI + Scaleform)

    Projects custom images onto world surfaces using:
    - DUI (Direct-rendered UI): CEF browser instances that render images
    - Runtime Textures: DUI output converted to GTA textures
    - generic_texture_renderer Scaleform: renders textures as 3D quads
    - DrawScaleformMovie_3dSolid: positions quads in world space

    Requires: generic_texture_renderer_gfx community resource

    Features:
    - Distance-based DUI lifecycle (create/destroy based on proximity)
    - Pool limit for GPU memory management
    - Surface detection via raycast (wall alignment)
    - ox_target sphere zones for removal interaction
    - Gang-specific image selection
    - Event-driven tag sync from server
]]

FreeGangs.Client = FreeGangs.Client or {}
FreeGangs.Client.Graffiti = {}

-- ============================================================================
-- LOCAL STATE
-- ============================================================================

local isSpraying = false
local activeDUI = {}          -- tagId -> DUI render data
local loadedTags = {}         -- tagId -> tag data from server
local targetZones = {}        -- tagId -> ox_target zone ID
local duiCount = 0            -- current active DUI count
local scaleformAvailable = nil -- cached check for generic_texture_renderer

-- ============================================================================
-- CONFIG
-- ============================================================================

local resourceName = GetCurrentResourceName()
local htmlUrl = string.format('nui://%s/html/graffiti.html', resourceName)

local function GetConfig()
    local cfg = FreeGangs.Config.Activities and FreeGangs.Config.Activities.Graffiti or {}
    return {
        requiredItem = cfg.RequiredItem or 'spray_can',
        sprayDuration = cfg.SprayDuration or 5000,
        animDict = cfg.Animation and cfg.Animation.dict or 'switch@franklin@lamar_tagging_wall',
        animName = cfg.Animation and cfg.Animation.anim or 'lamar_tagging_wall_loop_lamar',
        removalItem = cfg.RemovalItem or 'cleaning_kit',
        removalDuration = cfg.RemovalDuration or 8000,
        renderDistance = cfg.RenderDistance or 100.0,
        maxVisibleTags = cfg.MaxVisibleTags or 20,
        duiResolution = cfg.DuiResolution or 512,
        defaultScale = cfg.DefaultScale or 1.0,
        defaultWidth = cfg.DefaultWidth or 1.2,
        defaultHeight = cfg.DefaultHeight or 1.2,
        wallOffset = cfg.WallOffset or 0.03,
    }
end

-- ============================================================================
-- SCALEFORM AVAILABILITY CHECK
-- ============================================================================

---Check if generic_texture_renderer scaleform is available (bundled in stream/)
---@return boolean
local function IsScaleformAvailable()
    if scaleformAvailable ~= nil then
        return scaleformAvailable
    end

    -- Try to load the scaleform (bundled in stream/generic_texture_renderer.gfx)
    local sf = RequestScaleformMovie('generic_texture_renderer')
    local timeout = 0
    while not HasScaleformMovieLoaded(sf) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    if HasScaleformMovieLoaded(sf) then
        SetScaleformMovieAsNoLongerNeeded(sf)
        scaleformAvailable = true
    else
        scaleformAvailable = false
        FreeGangs.Utils.Log('[Graffiti] WARNING: generic_texture_renderer scaleform failed to load. Graffiti rendering disabled.')
        FreeGangs.Utils.Log('[Graffiti] Ensure stream/generic_texture_renderer.gfx exists in the resource.')
    end

    return scaleformAvailable
end

-- ============================================================================
-- DUI LIFECYCLE
-- ============================================================================

---Create a DUI instance for a graffiti tag
---@param tagData table Tag data from server
---@return table|nil duiData
local function CreateTagDUI(tagData)
    if duiCount >= GetConfig().maxVisibleTags then return nil end
    if not tagData.image_url or tagData.image_url == '' then return nil end

    local config = GetConfig()
    local res = config.duiResolution

    -- Create DUI browser instance
    local duiObj = CreateDui(htmlUrl, res, res)
    if not duiObj then return nil end

    local duiHandle = GetDuiHandle(duiObj)

    -- Create unique runtime texture
    local txdName = 'fg_tag_' .. tagData.id
    local txnName = 'tag' .. tagData.id
    local txd = CreateRuntimeTxd(txdName)
    local txn = CreateRuntimeTextureFromDuiHandle(txd, txnName, duiHandle)

    -- Send image URL to the HTML page
    SendDuiMessage(duiObj, json.encode({
        action = 'setImage',
        url = tagData.image_url,
    }))

    -- Load scaleform
    local sf = RequestScaleformMovie('generic_texture_renderer')
    local timeout = 0
    while not HasScaleformMovieLoaded(sf) and timeout < 500 do
        Wait(0)
        timeout = timeout + 1
    end

    if not HasScaleformMovieLoaded(sf) then
        DestroyDui(duiObj)
        return nil
    end

    -- Pass texture to scaleform
    BeginScaleformMovieMethod(sf, 'SET_TEXTURE')
    ScaleformMovieMethodAddParamTextureNameString(txdName)
    ScaleformMovieMethodAddParamTextureNameString(txnName)
    ScaleformMovieMethodAddParamInt(res)
    ScaleformMovieMethodAddParamInt(res)
    EndScaleformMovieMethod()

    -- Compute rotation from surface normal
    local nx = tagData.normal_x or 0.0
    local ny = tagData.normal_y or 0.0
    local nz = tagData.normal_z or 0.0

    -- heading: direction the graffiti faces outward
    local heading = math.deg(math.atan2(ny, nx))
    -- pitch: tilt from vertical (90 = vertical wall, 0 = ground)
    local pitch = 90.0 - math.deg(math.asin(math.max(-1.0, math.min(1.0, nz))))

    local scale = tagData.scale or config.defaultScale
    local width = (tagData.width or config.defaultWidth) * scale
    local height = (tagData.height or config.defaultHeight) * scale

    duiCount = duiCount + 1

    return {
        duiObj = duiObj,
        sf = sf,
        txdName = txdName,
        pos = vector3(tagData.coords.x, tagData.coords.y, tagData.coords.z),
        rotX = pitch,
        rotY = 0.0,
        rotZ = heading,
        width = width,
        height = height,
    }
end

---Destroy a DUI instance
---@param tagId number
local function DestroyTagDUI(tagId)
    local dui = activeDUI[tagId]
    if not dui then return end

    SetScaleformMovieAsNoLongerNeeded(dui.sf)
    DestroyDui(dui.duiObj)
    activeDUI[tagId] = nil
    duiCount = duiCount - 1
end

---Destroy all DUI instances
local function DestroyAllDUI()
    for tagId in pairs(activeDUI) do
        DestroyTagDUI(tagId)
    end
    activeDUI = {}
    duiCount = 0
end

-- ============================================================================
-- ox_target INTEGRATION (sphere zones for removal)
-- ============================================================================

---Add an ox_target sphere zone for a graffiti tag
---@param tagId number
---@param coords table {x, y, z}
local function AddTagTargetZone(tagId, coords)
    if targetZones[tagId] then return end
    if not FreeGangs.Client.PlayerGang then return end

    local config = GetConfig()

    targetZones[tagId] = exports.ox_target:addSphereZone({
        coords = vec3(coords.x, coords.y, coords.z),
        radius = 1.5,
        debug = false,
        options = {
            {
                name = 'fg_remove_tag_' .. tagId,
                icon = 'fas fa-eraser',
                label = 'Remove Graffiti',
                distance = 2.5,
                canInteract = function()
                    return FreeGangs.Bridge.HasItem(config.removalItem, 1) and not isSpraying
                end,
                onSelect = function()
                    FreeGangs.Client.Graffiti.StartRemoval(tagId)
                end,
            },
        },
    })
end

---Remove an ox_target sphere zone
---@param tagId number
local function RemoveTagTargetZone(tagId)
    local zoneId = targetZones[tagId]
    if zoneId then
        exports.ox_target:removeZone(zoneId)
        targetZones[tagId] = nil
    end
end

---Remove all target zones
local function RemoveAllTargetZones()
    for tagId in pairs(targetZones) do
        RemoveTagTargetZone(tagId)
    end
    targetZones = {}
end

-- ============================================================================
-- SURFACE DETECTION
-- ============================================================================

---Find wall surface in front of player via raycast
---@return boolean found
---@return table|nil hitCoords {x, y, z}
---@return table|nil surfaceNormal {x, y, z}
local function FindWallSurface()
    local ped = FreeGangs.Client.GetPlayerPed()
    local coords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local config = GetConfig()

    -- Raycast 2 meters forward, slightly above ground
    local startPos = coords + vector3(0, 0, 0.5)
    local endPos = startPos + (forward * 2.0)

    local rayHandle = StartShapeTestLosProbe(
        startPos.x, startPos.y, startPos.z,
        endPos.x, endPos.y, endPos.z,
        1 + 16, -- World + buildings
        ped,
        4 -- Ignore transparent
    )

    local _, hit, hitCoords, surfaceNormal = GetShapeTestResult(rayHandle)

    if hit == 1 then
        -- Offset from wall to prevent z-fighting
        local offset = config.wallOffset
        local sprayCoords = {
            x = hitCoords.x + (surfaceNormal.x * offset),
            y = hitCoords.y + (surfaceNormal.y * offset),
            z = hitCoords.z + (surfaceNormal.z * offset),
        }

        local normal = {
            x = surfaceNormal.x,
            y = surfaceNormal.y,
            z = surfaceNormal.z,
        }

        return true, sprayCoords, normal
    end

    return false, nil, nil
end

-- ============================================================================
-- SPRAY MECHANICS
-- ============================================================================

---Check if currently spraying
---@return boolean
function FreeGangs.Client.Graffiti.IsBusy()
    return isSpraying
end

---Select a graffiti image from available options
---@return string|nil imageUrl
local function SelectGraffitiImage()
    -- Fetch available images from server
    local images = lib.callback.await('freegangs:graffiti:getImages', false)

    if not images or #images == 0 then
        return nil
    end

    -- If only one image, auto-select
    if #images == 1 then
        return images[1]
    end

    -- Show selection menu
    local options = {}
    for i, url in ipairs(images) do
        -- Extract filename for display
        local displayName = url:match('([^/]+)$') or ('Image ' .. i)
        displayName = displayName:gsub('%.[^%.]+$', '') -- Remove extension
        displayName = displayName:gsub('[_-]', ' ')     -- Clean up separators

        options[#options + 1] = {
            title = displayName,
            description = 'Graffiti design ' .. i,
            icon = 'fas fa-paint-roller',
            metadata = { url = url },
        }
    end

    local selected = lib.inputDialog('Select Graffiti Design', {
        {
            type = 'select',
            label = 'Design',
            options = (function()
                local selectOptions = {}
                for i, url in ipairs(images) do
                    local displayName = url:match('([^/]+)$') or ('Image ' .. i)
                    displayName = displayName:gsub('%.[^%.]+$', '')
                    displayName = displayName:gsub('[_-]', ' ')
                    selectOptions[#selectOptions + 1] = { value = url, label = displayName }
                end
                return selectOptions
            end)(),
            required = true,
        },
    })

    if selected and selected[1] then
        return selected[1]
    end

    return nil
end

---Spray graffiti on a wall
---@param wallCoords table|nil Optional specific coordinates
function FreeGangs.Client.Graffiti.StartSpray(wallCoords)
    if isSpraying then
        FreeGangs.Bridge.Notify(FreeGangs.L('errors', 'busy'), 'error')
        return
    end

    if not FreeGangs.Client.PlayerGang then
        FreeGangs.Bridge.Notify(FreeGangs.L('gangs', 'not_in_gang'), 'error')
        return
    end

    if not IsScaleformAvailable() then
        FreeGangs.Bridge.Notify('Graffiti system unavailable (missing renderer)', 'error')
        return
    end

    local config = GetConfig()

    -- Check for spray can
    if not FreeGangs.Bridge.HasItem(config.requiredItem, 1) then
        FreeGangs.Bridge.Notify(FreeGangs.L('activities', 'graffiti_no_spray'), 'error')
        return
    end

    -- Find wall surface
    local coords, surfaceNormal
    if wallCoords then
        coords = wallCoords.coords
        surfaceNormal = wallCoords.normal or { x = 0, y = 1, z = 0 }
    else
        local found
        found, coords, surfaceNormal = FindWallSurface()
        if not found then
            FreeGangs.Bridge.Notify(FreeGangs.L('activities', 'graffiti_no_wall'), 'error')
            return
        end
    end

    -- Select graffiti image
    local imageUrl = SelectGraffitiImage()
    if not imageUrl then
        FreeGangs.Bridge.Notify('No graffiti images available', 'info')
        return
    end

    isSpraying = true

    -- Notify server of start (anti-cheat tracking)
    TriggerServerEvent('freegangs:server:startGraffiti', coords)

    local ped = FreeGangs.Client.GetPlayerPed()

    -- Face the wall
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

    -- Clean up prop
    if sprayCanProp and DoesEntityExist(sprayCanProp) then
        DeleteEntity(sprayCanProp)
    end
    SetModelAsNoLongerNeeded(sprayCanHash)
    ClearPedTasks(ped)

    if success then
        -- Send spray data to server
        local spraySuccess, message, result = lib.callback.await('freegangs:graffiti:spray', false, {
            coords = coords,
            normal = surfaceNormal,
            image_url = imageUrl,
            scale = config.defaultScale,
            width = config.defaultWidth,
            height = config.defaultHeight,
        })

        if spraySuccess then
            FreeGangs.Bridge.Notify(message, 'success')

            -- Create DUI for new tag immediately
            if result and result.tag then
                local dui = CreateTagDUI(result.tag)
                if dui then
                    activeDUI[result.tag.id] = dui
                    loadedTags[result.tag.id] = result.tag
                    AddTagTargetZone(result.tag.id, result.tag.coords)
                end
            end

            -- Play smoke particle effect
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

    isSpraying = false
end

---Quick spray using keybind
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

    local tagData = loadedTags[tagId]
    if not tagData then
        FreeGangs.Bridge.Notify(FreeGangs.L('activities', 'graffiti_not_found'), 'error')
        return
    end

    local config = GetConfig()

    if not FreeGangs.Bridge.HasItem(config.removalItem, 1) then
        FreeGangs.Bridge.Notify(FreeGangs.L('activities', 'graffiti_no_cleaner'), 'error')
        return
    end

    isSpraying = true

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

    ClearPedTasks(ped)

    if success then
        local removeSuccess, message = lib.callback.await('freegangs:graffiti:remove', false, tagId)

        if removeSuccess then
            FreeGangs.Bridge.Notify(message, 'success')
            -- Visual cleanup handled by REMOVE_GRAFFITI event
        else
            FreeGangs.Bridge.Notify(message or FreeGangs.L('errors', 'generic'), 'error')
        end
    else
        FreeGangs.Bridge.Notify(FreeGangs.L('activities', 'graffiti_cancelled'), 'info')
    end

    isSpraying = false
end

---Get nearest loaded tag
---@param coords table|nil
---@return table|nil nearestTag
---@return number nearestDist
function FreeGangs.Client.Graffiti.GetNearestTag(coords)
    if not coords then
        local ped = FreeGangs.Client.GetPlayerPed()
        local pedCoords = GetEntityCoords(ped)
        coords = { x = pedCoords.x, y = pedCoords.y, z = pedCoords.z }
    end

    local nearest = nil
    local nearestDist = math.huge

    for _, tag in pairs(loadedTags) do
        if tag.coords then
            local dx = coords.x - tag.coords.x
            local dy = coords.y - tag.coords.y
            local dz = coords.z - tag.coords.z
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            if dist < nearestDist then
                nearestDist = dist
                nearest = tag
            end
        end
    end

    return nearest, nearestDist
end

-- ============================================================================
-- KEYBIND INTEGRATION
-- ============================================================================

function FreeGangs.Client.Graffiti.RegisterKeybinds()
    lib.addKeybind({
        name = 'fg_spray_graffiti',
        description = 'Spray graffiti on nearby wall',
        defaultKey = '',
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

    -- Remove nearby tag option
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

    local blips = {}
    for _, tag in pairs(gangTags) do
        if tag.coords then
            local blip = AddBlipForCoord(tag.coords.x, tag.coords.y, tag.coords.z)
            SetBlipSprite(blip, 486)
            SetBlipColour(blip, 5)
            SetBlipScale(blip, 0.8)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName('Gang Tag')
            EndTextCommandSetBlipName(blip)
            blips[#blips + 1] = blip
        end
    end

    FreeGangs.Bridge.Notify(string.format('Showing %d gang tags on map for 30 seconds', #blips), 'info')

    SetTimeout(30000, function()
        for _, blip in pairs(blips) do
            RemoveBlip(blip)
        end
    end)
end

-- ============================================================================
-- VISIBILITY MANAGEMENT
-- ============================================================================

---Update which tags have active DUI instances based on player proximity
local function UpdateVisibleGraffiti()
    if not IsScaleformAvailable() then return end

    local ped = FreeGangs.Client.GetPlayerPed()
    local playerPos = GetEntityCoords(ped)
    local config = GetConfig()
    local renderDist = config.renderDistance
    local renderDistSq = renderDist * renderDist

    -- Remove out-of-range DUIs and target zones
    local toRemove = {}
    for tagId, tag in pairs(loadedTags) do
        if tag.coords then
            local dx = playerPos.x - tag.coords.x
            local dy = playerPos.y - tag.coords.y
            local dz = playerPos.z - tag.coords.z
            if (dx * dx + dy * dy + dz * dz) > renderDistSq then
                toRemove[#toRemove + 1] = tagId
            end
        end
    end
    for _, tagId in ipairs(toRemove) do
        DestroyTagDUI(tagId)
        RemoveTagTargetZone(tagId)
        loadedTags[tagId] = nil
    end

    -- Request nearby tags from server
    local nearbyTags = lib.callback.await(FreeGangs.Callbacks.GET_NEARBY_GRAFFITI, false,
        { x = playerPos.x, y = playerPos.y, z = playerPos.z },
        renderDist
    )

    if not nearbyTags then return end

    -- Track which tags are still nearby
    local nearbySet = {}
    for _, tag in pairs(nearbyTags) do
        nearbySet[tag.id] = true

        -- Add to loaded tags if new
        if not loadedTags[tag.id] then
            loadedTags[tag.id] = tag
        end

        -- Create DUI if not already active and has image
        if not activeDUI[tag.id] and tag.image_url and tag.image_url ~= '' then
            if duiCount < config.maxVisibleTags then
                local dui = CreateTagDUI(tag)
                if dui then
                    activeDUI[tag.id] = dui
                end
            end
        end

        -- Add target zone if not already created
        if not targetZones[tag.id] and tag.coords and FreeGangs.Client.PlayerGang then
            AddTagTargetZone(tag.id, tag.coords)
        end
    end

    -- Remove tags that left the nearby set but weren't caught by distance check
    for tagId in pairs(loadedTags) do
        if not nearbySet[tagId] then
            DestroyTagDUI(tagId)
            RemoveTagTargetZone(tagId)
            loadedTags[tagId] = nil
        end
    end
end

-- ============================================================================
-- RENDER THREAD
-- ============================================================================

---Main render thread: draws all active DUI scaleforms every frame
local function StartRenderThread()
    CreateThread(function()
        while true do
            local sleep = 500 -- Sleep when nothing to render

            if next(activeDUI) then
                sleep = 0
                for _, dui in pairs(activeDUI) do
                    DrawScaleformMovie_3dSolid(
                        dui.sf,
                        dui.pos.x, dui.pos.y, dui.pos.z,
                        dui.rotX, dui.rotY, dui.rotZ,
                        2.0, 2.0, 1.0,
                        dui.width, dui.height, 1.0,
                        2
                    )
                end
            end

            Wait(sleep)
        end
    end)
end

---Visibility update thread: manages DUI lifecycle based on distance
local function StartVisibilityThread()
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
-- EVENT HANDLERS
-- ============================================================================

---Handle loading graffiti from server (bulk load)
RegisterNetEvent(FreeGangs.Events.Client.LOAD_GRAFFITI, function(tags)
    if not tags or not IsScaleformAvailable() then return end

    FreeGangs.Utils.Debug('Loading ' .. #tags .. ' graffiti tags')

    local config = GetConfig()
    for _, tag in pairs(tags) do
        if not loadedTags[tag.id] then
            loadedTags[tag.id] = tag

            if tag.image_url and tag.image_url ~= '' and duiCount < config.maxVisibleTags then
                local dui = CreateTagDUI(tag)
                if dui then
                    activeDUI[tag.id] = dui
                end
            end

            if tag.coords and FreeGangs.Client.PlayerGang then
                AddTagTargetZone(tag.id, tag.coords)
            end
        end
    end
end)

---Handle new graffiti added by any player
RegisterNetEvent(FreeGangs.Events.Client.ADD_GRAFFITI, function(tagData)
    if not tagData or not IsScaleformAvailable() then return end

    FreeGangs.Utils.Debug('Adding new graffiti tag:', tagData.id)

    -- Check if in range
    local ped = FreeGangs.Client.GetPlayerPed()
    local playerPos = GetEntityCoords(ped)
    local config = GetConfig()

    if tagData.coords then
        local dx = playerPos.x - tagData.coords.x
        local dy = playerPos.y - tagData.coords.y
        local dz = playerPos.z - tagData.coords.z
        local distSq = dx * dx + dy * dy + dz * dz

        if distSq <= config.renderDistance * config.renderDistance then
            loadedTags[tagData.id] = tagData

            if tagData.image_url and tagData.image_url ~= '' and duiCount < config.maxVisibleTags then
                if not activeDUI[tagData.id] then
                    local dui = CreateTagDUI(tagData)
                    if dui then
                        activeDUI[tagData.id] = dui
                    end
                end
            end

            if FreeGangs.Client.PlayerGang then
                AddTagTargetZone(tagData.id, tagData.coords)
            end
        end
    end
end)

---Handle graffiti removed
RegisterNetEvent(FreeGangs.Events.Client.REMOVE_GRAFFITI, function(tagId)
    FreeGangs.Utils.Debug('Removing graffiti tag:', tagId)

    DestroyTagDUI(tagId)
    RemoveTagTargetZone(tagId)
    loadedTags[tagId] = nil
end)

---Handle player gang change
RegisterNetEvent(FreeGangs.Events.Client.GANG_UPDATED, function(gangData)
    if gangData then
        -- Re-add target zones for all loaded tags
        for tagId, tag in pairs(loadedTags) do
            if tag.coords and not targetZones[tagId] then
                AddTagTargetZone(tagId, tag.coords)
            end
        end
    else
        -- Remove all target zones when leaving gang
        RemoveAllTargetZones()
    end
end)

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function FreeGangs.Client.Graffiti.Initialize()
    FreeGangs.Utils.Log('Initializing graffiti system (DUI + Scaleform)...')

    -- Check scaleform availability
    if not IsScaleformAvailable() then
        FreeGangs.Utils.Log('Graffiti rendering disabled - missing generic_texture_renderer_gfx')
        return
    end

    -- Start render and visibility threads
    StartRenderThread()
    StartVisibilityThread()

    -- Register keybinds
    FreeGangs.Client.Graffiti.RegisterKeybinds()

    -- Initial load
    Wait(2000)
    UpdateVisibleGraffiti()

    FreeGangs.Utils.Log('Graffiti system initialized (DUI renderer active)')
end

-- ============================================================================
-- CLEANUP
-- ============================================================================

AddEventHandler('onResourceStop', function(resourceName_)
    if GetCurrentResourceName() ~= resourceName_ then return end

    DestroyAllDUI()
    RemoveAllTargetZones()
    loadedTags = {}
end)

-- ============================================================================
-- DEBUG COMMANDS
-- ============================================================================

if FreeGangs.Config.General and FreeGangs.Config.General.Debug then
    RegisterCommand('fg_graffiti_reload', function()
        DestroyAllDUI()
        RemoveAllTargetZones()
        loadedTags = {}
        Wait(100)
        UpdateVisibleGraffiti()
        FreeGangs.Bridge.Notify('Reloaded nearby graffiti', 'info')
    end, false)

    RegisterCommand('fg_graffiti_count', function()
        local loaded = 0
        for _ in pairs(loadedTags) do loaded = loaded + 1 end
        FreeGangs.Bridge.Notify(string.format('Loaded: %d | Active DUI: %d | Target zones: %d',
            loaded, duiCount, FreeGangs.Utils.TableLength(targetZones)), 'info')
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
