--[[
    FREE-GANGS: Client Activities Module
    
    Handles client-side criminal activity interactions:
    - ox_target integration for NPCs
    - Progress bars and minigames
    - Animations and effects
    - UI feedback
]]

FreeGangs.Client = FreeGangs.Client or {}
FreeGangs.Client.Activities = {}

-- ============================================================================
-- LOCAL STATE
-- ============================================================================

local isPerformingActivity = false
local targetingEnabled = false
local drugSaleKeybindRegistered = false
local muggingThreadActive = false
local currentMugTarget = nil
local recentMugTargets = {}          -- ped -> gameTimer of last attempt
local MUG_RETRIGGER_COOLDOWN = 10000 -- 10 seconds before can auto-mug same NPC again
local blacklistedPedHashes = nil     -- lazily built hash set from config
local resistancePedHashes = nil  -- lazily built hash map: pedHash -> category

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

---Check if player is currently performing an activity
---@return boolean
function FreeGangs.Client.Activities.IsBusy()
    return isPerformingActivity
end

---Set busy state
---@param busy boolean
local function SetBusy(busy)
    isPerformingActivity = busy
end

---Check if a ped model is blacklisted for drug sales (law enforcement, military, etc.)
---@param ped number Ped handle
---@return boolean
local function IsBlacklistedPed(ped)
    -- Build hash set on first use
    if not blacklistedPedHashes then
        blacklistedPedHashes = {}
        local models = FreeGangs.Config.Activities.DrugSales
            and FreeGangs.Config.Activities.DrugSales.BlacklistedPedModels or {}
        for _, model in ipairs(models) do
            blacklistedPedHashes[GetHashKey(model)] = true
        end
    end
    return blacklistedPedHashes[GetEntityModel(ped)] == true
end

---Classify an NPC's resistance category based on ped model
---@param ped number Ped handle
---@return string|nil category ('armed', 'gang', 'wealthy', or nil for civilian)
local function GetNPCResistanceCategory(ped)
    local resistConfig = FreeGangs.Config.Activities.Mugging.Resistance
    if not resistConfig or not resistConfig.Enabled then return nil end

    -- Build hash map on first use
    if not resistancePedHashes then
        resistancePedHashes = {}
        if resistConfig.ArmedPedModels then
            for _, model in ipairs(resistConfig.ArmedPedModels) do
                resistancePedHashes[GetHashKey(model)] = 'armed'
            end
        end
        if resistConfig.GangPedModels then
            for _, model in ipairs(resistConfig.GangPedModels) do
                resistancePedHashes[GetHashKey(model)] = 'gang'
            end
        end
        if resistConfig.WealthyPedModels then
            for _, model in ipairs(resistConfig.WealthyPedModels) do
                resistancePedHashes[GetHashKey(model)] = 'wealthy'
            end
        end
    end

    return resistancePedHashes[GetEntityModel(ped)]
end

---Check if player has a weapon that can be used for mugging
---@return boolean
local function HasMugWeapon()
    local ped = FreeGangs.Client.GetPlayerPed()
    local _, currentWeapon = GetCurrentPedWeapon(ped, true)
    
    if currentWeapon == 0 or currentWeapon == `WEAPON_UNARMED` then
        return false
    end
    
    -- Check weapon class
    local weaponClass = GetWeapontypeGroup(currentWeapon)
    
    -- Allow specific weapon types
    local allowedGroups = {
        [`GROUP_PISTOL`] = true,
        [`GROUP_SMG`] = true,
        [`GROUP_MELEE`] = true,
        [2685387236] = true, -- GROUP_PISTOL
        [3337201093] = true, -- GROUP_SMG
        [3566412244] = true, -- GROUP_MELEE
    }
    
    return allowedGroups[weaponClass] or false
end

---Get current game hour
---@return number
local function GetGameHour()
    return GetClockHours()
end

---Check if within drug sale hours
---@return boolean
local function IsDrugSaleTime()
    local hour = GetGameHour()
    local startHour = FreeGangs.Config.Activities.DrugSales.AllowedStartHour
    local endHour = FreeGangs.Config.Activities.DrugSales.AllowedEndHour
    
    if startHour > endHour then
        return hour >= startHour or hour < endHour
    else
        return hour >= startHour and hour < endHour
    end
end

---Play animation
---@param dict string Animation dictionary
---@param anim string Animation name
---@param duration number Duration in ms
---@param flag number Animation flag
local function PlayAnim(dict, anim, duration, flag)
    local ped = FreeGangs.Client.GetPlayerPed()
    
    lib.requestAnimDict(dict)
    TaskPlayAnim(ped, dict, anim, 8.0, -8.0, duration or -1, flag or 0, 0, false, false, false)
end

---Stop animation
local function StopAnim()
    local ped = FreeGangs.Client.GetPlayerPed()
    ClearPedTasks(ped)
end

---Make NPC react
---@param ped number NPC ped handle
---@param reaction string Type of reaction
local function TriggerNPCReaction(ped, reaction)
    if not DoesEntityExist(ped) then return end
    
    if reaction == 'scared' then
        -- Make NPC flee
        ClearPedTasks(ped)
        TaskReactAndFleePed(ped, PlayerPedId())
        
    elseif reaction == 'hands_up' then
        -- Make NPC put hands up
        ClearPedTasks(ped)
        lib.requestAnimDict('missminuteman_1ig_2')
        TaskPlayAnim(ped, 'missminuteman_1ig_2', 'handsup_base', 8.0, -8.0, -1, 49, 0, false, false, false)
        
    elseif reaction == 'aggressive' then
        -- Make NPC attack
        ClearPedTasks(ped)
        TaskCombatPed(ped, PlayerPedId(), 0, 16)
    end
end

-- ============================================================================
-- MUGGING SYSTEM (Auto-trigger on weapon approach, distance-based cancel)
-- ============================================================================

---Check if NPC is facing toward the player (within angle threshold)
---@param npcPed number
---@param playerPed number
---@param threshold number Angle in degrees
---@return boolean
local function IsNPCFacingPlayer(npcPed, playerPed, threshold)
    local npcCoords = GetEntityCoords(npcPed)
    local playerCoords = GetEntityCoords(playerPed)
    local npcHeading = GetEntityHeading(npcPed)

    local dx = playerCoords.x - npcCoords.x
    local dy = playerCoords.y - npcCoords.y
    local angleToPlayer = math.deg(math.atan(dx, dy)) % 360

    local angleDiff = math.abs(npcHeading - angleToPlayer) % 360
    if angleDiff > 180 then angleDiff = 360 - angleDiff end

    return angleDiff <= threshold
end

---Trigger reactions from nearby witness NPCs
---@param mugTarget number The NPC being mugged
---@param radius number Witness reaction radius
local function TriggerWitnessReactions(mugTarget, radius)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local peds = GetGamePool('CPed')

    for _, witnessPed in pairs(peds) do
        if witnessPed ~= playerPed
           and witnessPed ~= mugTarget
           and not IsPedAPlayer(witnessPed)
           and not IsPedDeadOrDying(witnessPed) then
            local witnessCoords = GetEntityCoords(witnessPed)
            if #(playerCoords - witnessCoords) <= radius then
                ClearPedTasks(witnessPed)
                TaskReactAndFleePed(witnessPed, playerPed)
            end
        end
    end
end

---Start mugging an NPC (auto-triggered by proximity detection)
---@param targetPed number Target NPC ped handle
function FreeGangs.Client.Activities.StartMugging(targetPed)
    if isPerformingActivity then return end
    if not HasMugWeapon() then return end

    -- Validate target with server
    local targetNetId = NetworkGetNetworkIdFromEntity(targetPed)
    local canMug, errorMsg = lib.callback.await('freegangs:activities:validateMugTarget', false, targetNetId)

    if not canMug then
        FreeGangs.Bridge.Notify(errorMsg, 'error')
        recentMugTargets[targetPed] = GetGameTimer()
        return
    end

    SetBusy(true)
    currentMugTarget = targetPed

    -- Notify server of start (for anti-cheat tracking)
    -- Classify NPC for resistance system
    local npcCategory = GetNPCResistanceCategory(targetPed)
    TriggerServerEvent('freegangs:server:startMugging', targetNetId, npcCategory)

    -- Face target
    local ped = FreeGangs.Client.GetPlayerPed()
    local targetCoords = GetEntityCoords(targetPed)
    TaskTurnPedToFaceCoord(ped, targetCoords.x, targetCoords.y, targetCoords.z, 1000)

    -- NPC awareness: if NPC is facing away, make them turn first
    if not IsNPCFacingPlayer(targetPed, ped, 90) then
        TaskTurnPedToFaceEntity(targetPed, ped, 800)
        Wait(800)
    end

    -- NPC reacts - hands up
    TriggerNPCReaction(targetPed, 'hands_up')

    -- Nearby witnesses react
    TriggerWitnessReactions(targetPed, 15.0)

    Wait(500)

    -- Monitor thread: cancels progress if distance breaks, weapon holstered, or target lost
    local cancelDistance = FreeGangs.Config.Activities.Mugging.CancelDistance or 8.0
    local distanceCancelled = false
    local weaponHolstered = false

    CreateThread(function()
        while isPerformingActivity and currentMugTarget do
            if not DoesEntityExist(currentMugTarget) then
                distanceCancelled = true
                lib.cancelProgress()
                break
            end
            local playerCoords = GetEntityCoords(FreeGangs.Client.GetPlayerPed())
            local tgtCoords = GetEntityCoords(currentMugTarget)
            if #(playerCoords - tgtCoords) > cancelDistance then
                distanceCancelled = true
                lib.cancelProgress()
                break
            end
            if not HasMugWeapon() then
                weaponHolstered = true
                lib.cancelProgress()
                break
            end
            Wait(100)
        end
    end)

    -- Progress bar (movement enabled for distance-based cancel)
    local success = lib.progressBar({
        duration = 3000,
        label = 'Mugging...',
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            combat = true,
        },
        anim = {
            dict = 'mp_missheist_countrybank@aim',
            clip = 'aim_loop',
            flag = 49,
        },
    })

    StopAnim()
    currentMugTarget = nil

    if success and not distanceCancelled and not weaponHolstered then
        -- Complete mugging on server
        local mugSuccess, message, rewards = lib.callback.await('freegangs:activities:completeMugging', false, targetNetId)

        if mugSuccess then
            FreeGangs.Bridge.Notify(message, 'success')
            TriggerNPCReaction(targetPed, 'scared')

            if rewards and rewards.rep and rewards.rep > 0 then
                FreeGangs.Bridge.Notify('+' .. rewards.rep .. ' reputation', 'inform', 3000)
            end
        elseif rewards and rewards.resisted then
            -- NPC fought back! Make NPC attack player
            FreeGangs.Bridge.Notify(message, 'error')
            if DoesEntityExist(targetPed) and not IsPedDeadOrDying(targetPed) then
                TriggerNPCReaction(targetPed, 'aggressive')

                -- NPC fights for configured duration then flees
                local fightDuration = FreeGangs.Config.Activities.Mugging.Resistance
                    and FreeGangs.Config.Activities.Mugging.Resistance.FightBackDuration or 8000
                CreateThread(function()
                    Wait(fightDuration)
                    if DoesEntityExist(targetPed) and not IsPedDeadOrDying(targetPed) then
                        ClearPedTasks(targetPed)
                        TaskReactAndFleePed(targetPed, PlayerPedId())
                    end
                end)
            end
        else
            FreeGangs.Bridge.Notify(message, 'error')
        end
    else
        if distanceCancelled then
            FreeGangs.Bridge.Notify('Mugging cancelled - too far from target', 'warning')
        elseif weaponHolstered then
            FreeGangs.Bridge.Notify('Mugging cancelled - weapon holstered', 'warning')
        else
            FreeGangs.Bridge.Notify('Mugging cancelled', 'warning')
        end
        TriggerNPCReaction(targetPed, 'scared')
    end

    -- Track target to prevent immediate re-trigger
    recentMugTargets[targetPed] = GetGameTimer()

    SetBusy(false)
end

-- ============================================================================
-- MUGGING PROXIMITY DETECTION
-- ============================================================================

---Start the mugging detection thread (auto-trigger on weapon approach)
local function StartMuggingDetection()
    if muggingThreadActive then return end
    muggingThreadActive = true

    CreateThread(function()
        while muggingThreadActive do
            local ped = FreeGangs.Client.GetPlayerPed()

            -- State gate: only do expensive NPC scan when eligible
            if not isPerformingActivity
               and HasMugWeapon()
               and not IsPedInAnyVehicle(ped, false)
               and not IsEntityDead(ped) then

                local coords = GetEntityCoords(ped)
                local maxDist = FreeGangs.Config.Activities.Mugging.MaxDistance or 5.0
                local now = GetGameTimer()

                -- Clean up expired recent targets (safe: collect first, then remove)
                local toRemove = {}
                for targetPed, timestamp in pairs(recentMugTargets) do
                    if now - timestamp > MUG_RETRIGGER_COOLDOWN or not DoesEntityExist(targetPed) then
                        toRemove[#toRemove + 1] = targetPed
                    end
                end
                for i = 1, #toRemove do
                    recentMugTargets[toRemove[i]] = nil
                end

                -- Find closest valid NPC within range
                local closestPed, closestDist = nil, maxDist + 1
                local peds = GetGamePool('CPed')

                for _, npcPed in pairs(peds) do
                    if npcPed ~= ped
                       and not IsPedAPlayer(npcPed)
                       and not IsPedDeadOrDying(npcPed)
                       and not recentMugTargets[npcPed] then
                        local pedCoords = GetEntityCoords(npcPed)
                        local dist = #(coords - pedCoords)
                        if dist < closestDist then
                            closestPed = npcPed
                            closestDist = dist
                        end
                    end
                end

                if closestPed and closestDist <= maxDist then
                    FreeGangs.Client.Activities.StartMugging(closestPed)
                end
            end

            Wait(3000) -- 3 second scan interval (slight delay is realistic, saves performance)
        end
    end)
end

---Stop the mugging detection thread
local function StopMuggingDetection()
    muggingThreadActive = false
    recentMugTargets = {}
end

-- ============================================================================
-- PICKPOCKETING SYSTEM
-- ============================================================================

---Start pickpocketing an NPC
---@param targetPed number Target NPC ped handle
function FreeGangs.Client.Activities.StartPickpocket(targetPed)
    if isPerformingActivity then
        FreeGangs.Bridge.Notify(FreeGangs.L('errors', 'generic'), 'error')
        return
    end

    -- Exploit guards
    local ped = FreeGangs.Client.GetPlayerPed()
    if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then return end

    local targetNetId = NetworkGetNetworkIdFromEntity(targetPed)
    local canPickpocket, errorMsg = lib.callback.await('freegangs:activities:validatePickpocketTarget', false, targetNetId)

    if not canPickpocket then
        FreeGangs.Bridge.Notify(errorMsg, 'error')
        return
    end

    SetBusy(true)

    TriggerServerEvent('freegangs:server:startPickpocket', targetNetId)

    local config = FreeGangs.Config.Activities.Pickpocket
    local maxDistance = config.MaxDistance or 2.0
    local rolls = config.LootRolls or 3
    local baseDetectChance = config.DetectionChanceBase or 10
    local detectPerRoll = config.DetectionChancePerRoll or 10
    local successfulRolls = 0
    local detected = false

    -- Get skill check config
    local skillCheckConfig = config.SkillCheck
    local useSkillCheck = skillCheckConfig and skillCheckConfig.Enabled

    for roll = 1, rolls do
        -- Check NPC still exists and is alive
        if not DoesEntityExist(targetPed) or IsPedDeadOrDying(targetPed) then
            FreeGangs.Bridge.Notify('Target is no longer available', 'error')
            break
        end

        -- Check distance before roll
        local playerCoords = GetEntityCoords(ped)
        local targetCoords = GetEntityCoords(targetPed)
        if #(playerCoords - targetCoords) > maxDistance then
            FreeGangs.Bridge.Notify(FreeGangs.L('activities', 'too_far'), 'error')
            break
        end

        -- Sneak animation
        PlayAnim('anim@amb@clubhouse@tutorial@bkr_tut_ig3@', 'machinic_loop_mechandplayer', -1, 49)

        -- Progress bar for the "reach" phase
        local progressSuccess = lib.progressBar({
            duration = 1300,
            label = string.format('Reaching into pocket (%d/%d)...', roll, rolls),
            useWhileDead = false,
            canCancel = true,
            disable = {
                move = true,
                car = true,
                combat = true,
            },
        })

        if not progressSuccess then
            StopAnim()
            FreeGangs.Bridge.Notify('Pickpocket cancelled', 'warning')
            break
        end

        StopAnim()

        -- Recheck NPC exists and is alive
        if not DoesEntityExist(targetPed) or IsPedDeadOrDying(targetPed) then
            FreeGangs.Bridge.Notify('Target is no longer available', 'error')
            break
        end

        -- Recheck distance after progress
        playerCoords = GetEntityCoords(ped)
        targetCoords = GetEntityCoords(targetPed)
        if #(playerCoords - targetCoords) > maxDistance then
            detected = true
            FreeGangs.Bridge.Notify(FreeGangs.L('activities', 'pickpocket_detected'), 'error')
            TriggerNPCReaction(targetPed, 'aggressive')
            break
        end

        -- DETECTION CHECK: skill check or RNG fallback
        if useSkillCheck then
            -- Build skill check difficulty for this roll
            local difficulty = skillCheckConfig.DifficultyPerRoll and skillCheckConfig.DifficultyPerRoll[roll] or 'easy'
            local speed = skillCheckConfig.SpeedPerRoll and skillCheckConfig.SpeedPerRoll[roll] or 1.0
            local inputs = skillCheckConfig.InputsPerRoll and skillCheckConfig.InputsPerRoll[roll] or 1

            -- Build the difficulty table for lib.skillCheck
            -- Each input is a {difficulty, speedMultiplier} pair
            local skillInputs = {}
            for i = 1, inputs do
                skillInputs[i] = { difficulty, speed }
            end

            local passed = lib.skillCheck(skillInputs)

            if not passed then
                detected = true
                FreeGangs.Bridge.Notify(FreeGangs.L('activities', 'pickpocket_detected'), 'error')
                TriggerNPCReaction(targetPed, 'aggressive')
                break
            end
        else
            -- Fallback: pure RNG detection (original system)
            local detectChance = baseDetectChance + (detectPerRoll * (roll - 1))
            if math.random(100) <= detectChance then
                detected = true
                FreeGangs.Bridge.Notify(FreeGangs.L('activities', 'pickpocket_detected'), 'error')
                TriggerNPCReaction(targetPed, 'aggressive')
                break
            end
        end

        successfulRolls = successfulRolls + 1
    end

    StopAnim()

    -- Always report to server with rolls completed (fixes stale tracking bug)
    local pickSuccess, message, rewards = lib.callback.await(
        'freegangs:activities:completePickpocket', false,
        targetNetId, successfulRolls
    )

    if pickSuccess then
        FreeGangs.Bridge.Notify(message, 'success')

        -- Post-pickpocket NPC reaction: delayed confusion
        if DoesEntityExist(targetPed) and not detected then
            CreateThread(function()
                Wait(2000)
                if not DoesEntityExist(targetPed) or IsPedDeadOrDying(targetPed) then return end
                -- NPC checks pockets, confused
                ClearPedTasks(targetPed)
                lib.requestAnimDict('gestures@m@standing@casual')
                TaskPlayAnim(targetPed, 'gestures@m@standing@casual', 'gesture_shrug_hard', 8.0, -8.0, 3000, 49, 0, false, false, false)
                Wait(3000)
                if not DoesEntityExist(targetPed) or IsPedDeadOrDying(targetPed) then return end
                -- NPC looks around suspiciously
                TaskStartScenarioInPlace(targetPed, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
                Wait(4000)
                if DoesEntityExist(targetPed) and not IsPedDeadOrDying(targetPed) then
                    ClearPedTasks(targetPed)
                end
            end)
        end
    else
        FreeGangs.Bridge.Notify(message, 'error')

        -- Server-reported detection (e.g. too-fast validation)
        if rewards and rewards.detected and DoesEntityExist(targetPed) and not detected then
            TriggerNPCReaction(targetPed, 'aggressive')
        end
    end

    SetBusy(false)
end

-- ============================================================================
-- DRUG SALES SYSTEM
-- ============================================================================

---Start drug sale to NPC
---@param targetPed number Target NPC ped handle
function FreeGangs.Client.Activities.StartDrugSale(targetPed)
    if isPerformingActivity then
        FreeGangs.Bridge.Notify(FreeGangs.L('errors', 'generic'), 'error')
        return
    end

    -- Exploit guards
    local ped = FreeGangs.Client.GetPlayerPed()
    if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then return end

    -- Blacklisted ped check (law enforcement, military, etc.) - alerts police
    if IsBlacklistedPed(targetPed) then
        FreeGangs.Bridge.Notify('This person is not a buyer', 'error')
        local wantedLevel = FreeGangs.Config.Activities.DrugSales.BlacklistedPedWantedLevel or 2
        SetPlayerWantedLevel(PlayerId(), wantedLevel, false)
        SetPlayerWantedLevelNow(PlayerId(), false)
        return
    end

    -- Check time restriction
    if not IsDrugSaleTime() then
        FreeGangs.Bridge.Notify(FreeGangs.L('activities', 'drug_sale_wrong_time'), 'error')
        return
    end

    -- Get player's drug inventory
    local drugInventory = lib.callback.await('freegangs:activities:getDrugInventory', false)

    if not drugInventory or #drugInventory == 0 then
        FreeGangs.Bridge.Notify(FreeGangs.L('activities', 'drug_sale_no_product'), 'error')
        return
    end

    local config = FreeGangs.Config.Activities.DrugSales
    local maxDistance = config.MaxDistance or 3.0

    -- Drug selection
    local selectedDrug
    local selectedQuantity = 1

    if #drugInventory == 1 then
        selectedDrug = drugInventory[1]
    else
        -- Show drug selection menu
        local options = {}
        for _, drug in pairs(drugInventory) do
            options[#options + 1] = {
                title = drug.label,
                description = 'You have: ' .. drug.count,
                icon = 'cannabis',
                onSelect = function()
                    selectedDrug = drug
                end,
            }
        end

        lib.registerContext({
            id = 'freegangs_drug_select',
            title = 'Select Product',
            options = options,
        })

        lib.showContext('freegangs_drug_select')

        -- Wait for selection
        while lib.getOpenContextMenu() == 'freegangs_drug_select' do
            Wait(100)
        end

        if not selectedDrug then
            return
        end
    end

    -- Buyer requests a random amount (capped by player inventory and max 10)
    local maxBuy = math.min(selectedDrug.count, 10)
    selectedQuantity = math.random(1, maxBuy)

    -- Re-validate target NPC after menus (may have despawned or moved)
    if not DoesEntityExist(targetPed) or IsPedDeadOrDying(targetPed) then
        FreeGangs.Bridge.Notify('Target is no longer available', 'error')
        return
    end
    local playerCoords = GetEntityCoords(ped)
    local targetCheckCoords = GetEntityCoords(targetPed)
    if #(playerCoords - targetCheckCoords) > maxDistance then
        FreeGangs.Bridge.Notify(FreeGangs.L('activities', 'too_far') or 'Too far away', 'error')
        return
    end

    -- Pre-validate target on server (check NPC cooldown + player cooldown before committing)
    local targetNetId = NetworkGetNetworkIdFromEntity(targetPed)
    local targetValid, targetMsg = lib.callback.await('freegangs:activities:validateDrugSaleTarget', false, targetNetId)
    if not targetValid then
        FreeGangs.Bridge.Notify(targetMsg or 'Target unavailable', 'error')
        return
    end

    SetBusy(true)

    TriggerServerEvent('freegangs:server:startDrugSale', targetNetId)

    -- Face target
    local targetCoords = GetEntityCoords(targetPed)
    TaskTurnPedToFaceCoord(ped, targetCoords.x, targetCoords.y, targetCoords.z, 1000)

    -- NPC turns to face player, nervous look-around before deal
    if DoesEntityExist(targetPed) and not IsPedDeadOrDying(targetPed) then
        TaskTurnPedToFaceEntity(targetPed, ped, 800)
        Wait(800)
        -- NPC looks around nervously before accepting
        if DoesEntityExist(targetPed) and not IsPedDeadOrDying(targetPed) then
            lib.requestAnimDict('amb@world_human_stand_impatient@male@no_sign@idle_a')
            TaskPlayAnim(targetPed, 'amb@world_human_stand_impatient@male@no_sign@idle_a', 'idle_a', 8.0, -8.0, 1500, 49, 0, false, false, false)
            Wait(1500)
            RemoveAnimDict('amb@world_human_stand_impatient@male@no_sign@idle_a')
            ClearPedTasks(targetPed)
        end
    else
        Wait(500)
    end

    -- Handshake animation
    PlayAnim('mp_common', 'givetake1_a', 2000, 49)

    -- Monitor thread: cancel if NPC disappears or dies during progress
    local npcGone = false
    CreateThread(function()
        while isPerformingActivity and not npcGone do
            if not DoesEntityExist(targetPed) or IsPedDeadOrDying(targetPed) then
                npcGone = true
                lib.cancelProgress()
                break
            end
            Wait(500)
        end
    end)

    local saleDuration = 2500 + (selectedQuantity - 1) * 250

    -- Randomized diegetic buyer dialogue
    local saleLabel
    if selectedQuantity > 1 then
        local multiLines = {
            '"I need ' .. selectedQuantity .. ' of those..."',
            '"Hook me up with ' .. selectedQuantity .. '..."',
            '"Got ' .. selectedQuantity .. ' for me?"',
            '"Let me get ' .. selectedQuantity .. ' off you..."',
            '"I\'ll take ' .. selectedQuantity .. '..."',
        }
        saleLabel = multiLines[math.random(#multiLines)]
    else
        local singleLines = {
            '"Let me get one of those..."',
            '"Hook me up..."',
            '"You holding? I need one..."',
            '"Just one, quick..."',
            '"Got anything for me?"',
        }
        saleLabel = singleLines[math.random(#singleLines)]
    end
    local success = lib.progressBar({
        duration = saleDuration,
        label = saleLabel,
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
    })

    StopAnim()

    if success and not npcGone then
        local saleSuccess, message, rewards = lib.callback.await(
            'freegangs:activities:completeDrugSale',
            false,
            targetNetId,
            selectedDrug.item,
            selectedQuantity
        )

        if saleSuccess then
            FreeGangs.Bridge.Notify(message, 'success')

            if rewards then
                if rewards.rep and rewards.rep > 0 then
                    FreeGangs.Bridge.Notify('+' .. rewards.rep .. ' reputation', 'inform', 3000)
                end

                -- Diegetic diminishing returns warning
                if rewards.diminishing and rewards.diminishing < 0.8 then
                    local warningLines = {
                        '"Prices are dropping around here..."',
                        '"Market\'s getting flooded, man..."',
                        '"People ain\'t paying like they used to..."',
                        '"Too much product on the street..."',
                    }
                    Wait(1500)
                    FreeGangs.Bridge.Notify(warningLines[math.random(#warningLines)], 'warning', 4000)
                end
            end

            -- NPC reaction: handshake reciprocation, then walk away
            if DoesEntityExist(targetPed) and not IsPedDeadOrDying(targetPed) then
                CreateThread(function()
                    ClearPedTasks(targetPed)
                    lib.requestAnimDict('mp_common')
                    TaskPlayAnim(targetPed, 'mp_common', 'givetake1_b', 8.0, -8.0, 2000, 49, 0, false, false, false)
                    Wait(2000)
                    RemoveAnimDict('mp_common')
                    if DoesEntityExist(targetPed) and not IsPedDeadOrDying(targetPed) then
                        ClearPedTasks(targetPed)
                        TaskWanderStandard(targetPed, 10.0, 10)
                    end
                end)
            end
        else
            FreeGangs.Bridge.Notify(message, 'error')

            -- NPC reaction on rejection: shake head, walk away
            if rewards and rewards.rejected and DoesEntityExist(targetPed) and not IsPedDeadOrDying(targetPed) then
                CreateThread(function()
                    ClearPedTasks(targetPed)
                    lib.requestAnimDict('gestures@m@standing@casual')
                    TaskPlayAnim(targetPed, 'gestures@m@standing@casual', 'gesture_head_no', 8.0, -8.0, 2000, 49, 0, false, false, false)
                    Wait(2000)
                    RemoveAnimDict('gestures@m@standing@casual')
                    if DoesEntityExist(targetPed) and not IsPedDeadOrDying(targetPed) then
                        ClearPedTasks(targetPed)
                        TaskWanderStandard(targetPed, 10.0, 10)
                    end
                end)
            end
        end
    else
        -- Cancelled or NPC gone - notify server to clear stale tracking
        TriggerServerEvent('freegangs:server:cancelDrugSale')

        if npcGone then
            FreeGangs.Bridge.Notify('Target is no longer available', 'error')
        else
            FreeGangs.Bridge.Notify('Sale cancelled', 'warning')

            -- NPC walks away on player cancel
            if DoesEntityExist(targetPed) and not IsPedDeadOrDying(targetPed) then
                CreateThread(function()
                    Wait(1000)
                    if DoesEntityExist(targetPed) and not IsPedDeadOrDying(targetPed) then
                        ClearPedTasks(targetPed)
                        TaskWanderStandard(targetPed, 10.0, 10)
                    end
                end)
            end
        end
    end

    SetBusy(false)
end

-- ============================================================================
-- PROTECTION RACKET SYSTEM
-- ============================================================================

---Open protection collection menu for current location
function FreeGangs.Client.Activities.OpenProtectionMenu()
    if isPerformingActivity then return end
    
    -- Get protection businesses
    local businesses = lib.callback.await(FreeGangs.Callbacks.GET_PROTECTION_BUSINESSES, false)
    
    if not businesses or #businesses == 0 then
        FreeGangs.Bridge.Notify('No protection businesses registered', 'inform')
        return
    end
    
    local options = {}
    
    for _, business in pairs(businesses) do
        local status = business.isReady and 'Ready' or FreeGangs.Utils.FormatDuration(business.timeRemaining * 1000)
        
        options[#options + 1] = {
            title = business.business_label or business.business_id,
            description = 'Base payout: $' .. business.payout_base .. ' | Status: ' .. status,
            icon = business.isReady and 'hand-holding-dollar' or 'clock',
            disabled = not business.isReady,
            onSelect = function()
                FreeGangs.Client.Activities.CollectProtection(business)
            end,
        }
    end
    
    lib.registerContext({
        id = 'freegangs_protection_menu',
        title = 'Protection Racket',
        options = options,
    })
    
    lib.showContext('freegangs_protection_menu')
end

---Collect protection from a business
---@param business table Business data
function FreeGangs.Client.Activities.CollectProtection(business)
    if isPerformingActivity then return end
    
    SetBusy(true)
    
    -- Animation
    PlayAnim('anim@amb@nightclub@mini@drinking@drinking_shots@ped_a@', 'idle_a', 3000, 49)
    
    local success = lib.progressBar({
        duration = 3000,
        label = 'Collecting protection...',
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
    })
    
    StopAnim()
    
    if success then
        local collectSuccess, message, rewards = lib.callback.await(
            'freegangs:activities:collectProtection', 
            false, 
            business.business_id
        )
        
        if collectSuccess then
            FreeGangs.Bridge.Notify(message, 'success')
            
            if rewards then
                if rewards.rep and rewards.rep > 0 then
                    FreeGangs.Bridge.Notify('+' .. rewards.rep .. ' reputation', 'inform', 3000)
                end
            end
        else
            FreeGangs.Bridge.Notify(message, 'error')
        end
    else
        FreeGangs.Bridge.Notify('Collection cancelled', 'warning')
    end
    
    SetBusy(false)
end

-- ============================================================================
-- OX_TARGET INTEGRATION
-- ============================================================================

---Find the nearest non-player NPC within a given distance
---@param maxDist number Maximum search distance
---@return number|nil ped The nearest NPC ped handle, or nil
local function GetNearestNPC(maxDist)
    local ped = FreeGangs.Client.GetPlayerPed()
    local playerCoords = GetEntityCoords(ped)
    local closestPed = nil
    local closestDist = maxDist

    for _, npc in ipairs(GetGamePool('CPed')) do
        if npc ~= ped and not IsPedAPlayer(npc) and not IsPedDeadOrDying(npc) and not IsBlacklistedPed(npc) then
            local dist = #(playerCoords - GetEntityCoords(npc))
            if dist < closestDist then
                closestDist = dist
                closestPed = npc
            end
        end
    end

    return closestPed
end

---Keybind handler: sell drugs to nearest NPC within 1.5 units
local function OnDrugSaleKeybind()
    if isPerformingActivity then return end

    local nearestNPC = GetNearestNPC(1.5)
    if not nearestNPC then return end

    FreeGangs.Client.Activities.StartDrugSale(nearestNPC)
end

---Setup ox_target options for NPCs (pickpocket + drug sale only; mugging is auto-triggered)
function FreeGangs.Client.Activities.SetupTargeting()
    if targetingEnabled then return end

    -- Start mugging proximity detection (auto-trigger on weapon approach)
    StartMuggingDetection()

    -- Add global ped targeting options (pickpocket + drug sale)
    exports.ox_target:addGlobalPed({
        -- Pickpocketing option
        {
            name = 'freegangs_pickpocket',
            icon = 'fa-solid fa-hand',
            label = 'Pickpocket',
            canInteract = function(entity, distance, coords, name, bone)
                if isPerformingActivity then return false end
                if IsPedAPlayer(entity) then return false end
                if IsPedDeadOrDying(entity) then return false end
                -- Check if player is behind the NPC (position-based check)
                local ped = FreeGangs.Client.GetPlayerPed()
                local pedCoords = GetEntityCoords(ped)
                local npcCoords = GetEntityCoords(entity)
                local npcHeading = GetEntityHeading(entity)

                -- Angle from NPC to player in GTA heading space
                local dx = pedCoords.x - npcCoords.x
                local dy = pedCoords.y - npcCoords.y
                local angleToPlayer = math.deg(math.atan(dx, dy)) % 360

                -- How far is the player from the NPC's forward direction?
                local angleDiff = math.abs(npcHeading - angleToPlayer) % 360
                if angleDiff > 180 then angleDiff = 360 - angleDiff end

                -- Player is "behind" if they are more than 120 degrees from the NPC's forward
                return angleDiff > 120
            end,
            onSelect = function(data)
                FreeGangs.Client.Activities.StartPickpocket(data.entity)
            end,
            distance = FreeGangs.Config.Activities.Pickpocket.MaxDistance or 2.0,
        },
        
        -- Drug sale option
        {
            name = 'freegangs_drugsale',
            icon = 'fa-solid fa-pills',
            label = 'Sell Drugs',
            canInteract = function(entity, distance, coords, name, bone)
                if isPerformingActivity then return false end
                if IsPedAPlayer(entity) then return false end
                if IsPedDeadOrDying(entity) then return false end
                if not IsDrugSaleTime() then return false end
                if IsBlacklistedPed(entity) then return false end
                return true
            end,
            onSelect = function(data)
                FreeGangs.Client.Activities.StartDrugSale(data.entity)
            end,
            distance = FreeGangs.Config.Activities.DrugSales.MaxDistance or 3.0,
        },
    })
    
    -- Register drug sale keybind (G key by default, player can remap in settings)
    if not drugSaleKeybindRegistered then
        RegisterCommand('+freegangs_drugsale', function()
            OnDrugSaleKeybind()
        end, false)
        RegisterCommand('-freegangs_drugsale', function() end, false)
        RegisterKeyMapping('+freegangs_drugsale', 'Sell Drugs to Nearby NPC', 'keyboard', 'G')
        drugSaleKeybindRegistered = true
    end

    targetingEnabled = true
    FreeGangs.Utils.Debug('Activity targeting enabled')
end

---Remove targeting options
function FreeGangs.Client.Activities.RemoveTargeting()
    if not targetingEnabled then return end

    exports.ox_target:removeGlobalPed({
        'freegangs_pickpocket',
        'freegangs_drugsale',
    })

    -- Stop mugging proximity detection
    StopMuggingDetection()

    targetingEnabled = false
    FreeGangs.Utils.Debug('Activity targeting disabled')
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Initialize activities module
function FreeGangs.Client.Activities.Initialize()
    FreeGangs.Client.Activities.SetupTargeting()
end

-- Initialize on resource start (activities available to all players)
CreateThread(function()
    Wait(2000)
    FreeGangs.Client.Activities.SetupTargeting()
end)

return FreeGangs.Client.Activities
