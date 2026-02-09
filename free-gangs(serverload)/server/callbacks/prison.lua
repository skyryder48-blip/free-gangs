-- ============================================================================
-- PRISON CALLBACKS
-- Server-side callbacks for prison system operations
-- ============================================================================

---Get prison data
lib.callback.register('free-gangs:callback:getPrisonData', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return nil end

    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return nil end

    return FreeGangs.Server.Prison.GetDataForClient(membership.gang_name)
end)

---Get prison control level
lib.callback.register('free-gangs:callback:getPrisonControl', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return 0 end

    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return 0 end

    return FreeGangs.Server.Prison.GetControlLevel(membership.gang_name)
end)

---Get prison leaderboard
lib.callback.register('free-gangs:callback:getPrisonLeaderboard', function(source)
    return FreeGangs.Server.Prison.GetLeaderboard()
end)

---Check prison benefit
lib.callback.register('free-gangs:callback:hasPrisonBenefit', function(source, benefit)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false end

    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return false end

    return FreeGangs.Server.Prison.HasBenefit(membership.gang_name, benefit)
end)

---Get jailed members
lib.callback.register('free-gangs:callback:getJailedMembers', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return {} end

    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return {} end

    local jailed = FreeGangs.Server.Prison.GetJailedMembers(membership.gang_name)

    -- Get player info for each jailed member
    local result = {}
    for _, jailedCitizenId in ipairs(jailed) do
        local name = FreeGangs.Bridge.GetPlayerNameByCitizenId(jailedCitizenId)
        table.insert(result, {
            citizenid = jailedCitizenId,
            name = name or 'Unknown',
        })
    end

    return result
end)

---Start smuggle mission
lib.callback.register('free-gangs:callback:startSmuggleMission', function(source)
    local success, message = FreeGangs.Server.Prison.StartSmuggleMission(source)
    return { success = success, message = message }
end)

---Complete smuggle mission
lib.callback.register('free-gangs:callback:completeSmuggleMission', function(source, success, detected)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false end

    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return false end

    return FreeGangs.Server.Prison.CompleteSmuggleMission(source, membership.gang_name, success, detected)
end)

---Deliver contraband
lib.callback.register('free-gangs:callback:deliverContraband', function(source, targetCitizenId, items)
    local success, message = FreeGangs.Server.Prison.DeliverContraband(source, targetCitizenId, items)
    return { success = success, message = message }
end)

---Claim contraband
lib.callback.register('free-gangs:callback:claimContraband', function(source)
    local success, items = FreeGangs.Server.Prison.ClaimContraband(source)
    return { success = success, items = items }
end)

---Help escape
lib.callback.register('free-gangs:callback:helpEscape', function(source, targetCitizenId)
    local success, message = FreeGangs.Server.Prison.HelpEscape(source, targetCitizenId)
    return { success = success, message = message }
end)

---Get jail time reduction
lib.callback.register('free-gangs:callback:getJailTimeReduction', function(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return 0 end

    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return 0 end

    return FreeGangs.Server.Prison.GetJailTimeReduction(membership.gang_name)
end)
