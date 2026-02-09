--[[
    FREE-GANGS: Member Management Module
    
    Handles gang membership, invites, promotions, demotions, and kicks.
]]

FreeGangs.Server = FreeGangs.Server or {}
FreeGangs.Server.Member = {}

-- Pending invites: citizenid -> { gangName, invitedBy, expiresAt }
local pendingInvites = {}

-- ============================================================================
-- MEMBER ADDITION
-- ============================================================================

---Add a player to a gang
---@param citizenid string
---@param gangName string
---@param rank number
---@param rankName string|nil
---@return boolean success
---@return string|nil errorMessage
function FreeGangs.Server.Member.Add(citizenid, gangName, rank, rankName)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then
        return false, 'Gang not found'
    end
    
    -- Check if already in a gang
    local existing = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if existing then
        return false, 'Player is already in a gang'
    end
    
    -- Check max members
    local config = FreeGangs.Config.General
    if config.MaxMembersPerGang > 0 then
        local memberCount = FreeGangs.Server.DB.GetMemberCount(gangName)
        if memberCount >= config.MaxMembersPerGang then
            return false, 'Gang has reached maximum member capacity'
        end
    end
    
    -- Get rank name if not provided
    if not rankName then
        local ranks = FreeGangs.Server.DB.GetGangRanks(gangName)
        for _, r in pairs(ranks) do
            if r.rank_level == rank then
                rankName = r.name
                break
            end
        end
        
        -- Fallback to default ranks
        if not rankName then
            local defaultRanks = FreeGangs.GetDefaultRanks(gang.archetype)
            if defaultRanks[rank] then
                rankName = defaultRanks[rank].name
            else
                rankName = 'Member'
            end
        end
    end
    
    -- Add to database
    FreeGangs.Server.DB.AddMember(citizenid, gangName, rank, rankName)
    
    -- Add to QBox gang system
    FreeGangs.Bridge.AddPlayerToGang(citizenid, gangName, rank)
    FreeGangs.Bridge.SetPrimaryGang(citizenid, gangName)
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, citizenid, 'member_joined', FreeGangs.LogCategories.MEMBERSHIP, {
        rank = rank,
        rankName = rankName,
    })
    
    -- Notify online player if applicable
    local player = FreeGangs.Bridge.GetPlayerByCitizenId(citizenid)
    if player then
        local source = player.PlayerData.source
        FreeGangs.Bridge.Notify(source, 'You have joined ' .. gang.label .. ' as ' .. rankName, 'success')
        
        -- Send updated gang data
        TriggerClientEvent(FreeGangs.Events.Client.UPDATE_GANG_DATA, source, {
            gang = FreeGangs.Server.Gang.GetClientData(gangName),
            membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid),
        })
    end
    
    -- Notify gang members
    FreeGangs.Bridge.NotifyGang(gangName, string.format(FreeGangs.Config.Messages.MemberJoined, 
        player and FreeGangs.Bridge.GetPlayerName(player.PlayerData.source) or citizenid), 'inform')
    
    return true
end

---Remove a player from a gang
---@param citizenid string
---@param gangName string
---@param reason string|nil
---@return boolean success
---@return string|nil errorMessage
function FreeGangs.Server.Member.Remove(citizenid, gangName, reason)
    local gang = FreeGangs.Server.Gangs[gangName]
    if not gang then
        return false, 'Gang not found'
    end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership or membership.gang_name ~= gangName then
        return false, 'Player is not in this gang'
    end
    
    -- Check if this is the last boss
    local ranks = FreeGangs.Server.DB.GetGangRanks(gangName)
    local bossRank = 5 -- Assuming 5 is boss
    
    if membership.rank == bossRank then
        local members = FreeGangs.Server.DB.GetGangMembers(gangName)
        local bossCount = 0
        for _, member in pairs(members) do
            if member.rank == bossRank then
                bossCount = bossCount + 1
            end
        end
        
        if bossCount <= 1 and #members > 1 then
            return false, 'Cannot remove the last boss while other members remain'
        end
    end
    
    -- Remove from database
    FreeGangs.Server.DB.RemoveMember(citizenid, gangName)
    
    -- Remove from QBox gang system
    FreeGangs.Bridge.RemovePlayerFromGang(citizenid, gangName)
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, citizenid, 'member_left', FreeGangs.LogCategories.MEMBERSHIP, {
        reason = reason,
        rank = membership.rank,
    })
    
    -- Notify online player
    local player = FreeGangs.Bridge.GetPlayerByCitizenId(citizenid)
    if player then
        local source = player.PlayerData.source
        FreeGangs.Bridge.Notify(source, 'You have left ' .. gang.label, 'warning')
        
        -- Clear gang data on client
        TriggerClientEvent(FreeGangs.Events.Client.UPDATE_GANG_DATA, source, nil)
    end
    
    return true
end

-- ============================================================================
-- INVITES
-- ============================================================================

---Invite a player to a gang
---@param inviterSource number Source of the player doing the inviting
---@param targetSource number Source of the player being invited
---@return boolean success
---@return string|nil errorMessage
function FreeGangs.Server.Member.Invite(inviterSource, targetSource)
    -- Get inviter's gang
    local inviterCitizenid = FreeGangs.Bridge.GetCitizenId(inviterSource)
    local inviterMembership = FreeGangs.Server.DB.GetPlayerMembership(inviterCitizenid)
    
    if not inviterMembership then
        return false, 'You are not in a gang'
    end
    
    local gangName = inviterMembership.gang_name
    local gang = FreeGangs.Server.Gangs[gangName]
    
    -- Check permission
    local hasPermission = FreeGangs.Server.Member.HasPermission(inviterSource, FreeGangs.Permissions.INVITE)
    if not hasPermission then
        return false, 'You do not have permission to invite members'
    end
    
    -- Get target info
    local targetCitizenid = FreeGangs.Bridge.GetCitizenId(targetSource)
    if not targetCitizenid then
        return false, 'Target player not found'
    end
    
    -- Check if target is already in a gang
    local targetMembership = FreeGangs.Server.DB.GetPlayerMembership(targetCitizenid)
    if targetMembership then
        return false, 'Player is already in a gang'
    end
    
    -- Check for pending invite
    if pendingInvites[targetCitizenid] then
        return false, 'This player already has a pending invite'
    end
    
    -- Check max members
    local config = FreeGangs.Config.General
    if config.MaxMembersPerGang > 0 then
        local memberCount = FreeGangs.Server.DB.GetMemberCount(gangName)
        if memberCount >= config.MaxMembersPerGang then
            return false, 'Gang has reached maximum member capacity'
        end
    end
    
    -- Create pending invite (expires in 2 minutes)
    pendingInvites[targetCitizenid] = {
        gangName = gangName,
        invitedBy = inviterCitizenid,
        expiresAt = FreeGangs.Utils.GetTimestamp() + 120,
    }
    
    -- Send invite notification to target
    local inviterName = FreeGangs.Bridge.GetPlayerName(inviterSource)
    
    lib.callback.await('free-gangs:client:showInvite', targetSource, {
        gangName = gangName,
        gangLabel = gang.label,
        gangColor = gang.color,
        inviterName = inviterName,
    })
    
    FreeGangs.Bridge.Notify(inviterSource, 'Invite sent to ' .. FreeGangs.Bridge.GetPlayerName(targetSource), 'success')
    
    return true
end

---Accept a gang invite
---@param source number Player source
---@return boolean success
---@return string|nil errorMessage
function FreeGangs.Server.Member.AcceptInvite(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    
    local invite = pendingInvites[citizenid]
    if not invite then
        return false, 'No pending invite found'
    end
    
    -- Check expiry
    if FreeGangs.Utils.GetTimestamp() > invite.expiresAt then
        pendingInvites[citizenid] = nil
        return false, 'Invite has expired'
    end
    
    -- Clear invite
    local gangName = invite.gangName
    pendingInvites[citizenid] = nil
    
    -- Add to gang at rank 0 (lowest)
    return FreeGangs.Server.Member.Add(citizenid, gangName, 0)
end

---Decline a gang invite
---@param source number Player source
---@return boolean
function FreeGangs.Server.Member.DeclineInvite(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    
    if pendingInvites[citizenid] then
        local invite = pendingInvites[citizenid]
        pendingInvites[citizenid] = nil
        
        -- Notify inviter if online
        local inviter = FreeGangs.Bridge.GetPlayerByCitizenId(invite.invitedBy)
        if inviter then
            FreeGangs.Bridge.Notify(inviter.PlayerData.source, 
                FreeGangs.Bridge.GetPlayerName(source) .. ' declined the gang invite', 'warning')
        end
        
        return true
    end
    
    return false
end

-- ============================================================================
-- RANK CHANGES
-- ============================================================================

---Promote a gang member
---@param promoterSource number Source of the player doing the promoting
---@param targetCitizenid string Citizenid of the player being promoted
---@return boolean success
---@return string|nil errorMessage
function FreeGangs.Server.Member.Promote(promoterSource, targetCitizenid)
    local promoterCitizenid = FreeGangs.Bridge.GetCitizenId(promoterSource)
    local promoterMembership = FreeGangs.Server.DB.GetPlayerMembership(promoterCitizenid)
    
    if not promoterMembership then
        return false, 'You are not in a gang'
    end
    
    local gangName = promoterMembership.gang_name
    
    -- Check permission
    local hasPermission = FreeGangs.Server.Member.HasPermission(promoterSource, FreeGangs.Permissions.PROMOTE)
    if not hasPermission then
        return false, 'You do not have permission to promote members'
    end
    
    -- Get target membership
    local targetMembership = FreeGangs.Server.DB.GetPlayerMembership(targetCitizenid)
    if not targetMembership or targetMembership.gang_name ~= gangName then
        return false, 'Target is not in your gang'
    end
    
    -- Check rank hierarchy (can only promote those below you)
    if targetMembership.rank >= promoterMembership.rank then
        return false, 'You cannot promote someone of equal or higher rank'
    end
    
    -- Check max rank (can only promote to one below your own rank, or boss can promote to any)
    local newRank = targetMembership.rank + 1
    local maxRank = 5 -- Boss rank
    
    if newRank >= maxRank then
        return false, 'Cannot promote to boss rank this way'
    end
    
    if newRank >= promoterMembership.rank and promoterMembership.rank < maxRank then
        return false, 'You cannot promote someone to your rank or higher'
    end
    
    -- Get new rank name
    local gang = FreeGangs.Server.Gangs[gangName]
    local defaultRanks = FreeGangs.GetDefaultRanks(gang.archetype)
    local newRankName = defaultRanks[newRank] and defaultRanks[newRank].name or 'Member'
    
    -- Check custom ranks
    local customRanks = FreeGangs.Server.DB.GetGangRanks(gangName)
    for _, rank in pairs(customRanks) do
        if rank.rank_level == newRank then
            newRankName = rank.name
            break
        end
    end
    
    -- Update rank
    FreeGangs.Server.DB.UpdateMemberRank(targetCitizenid, gangName, newRank, newRankName)
    FreeGangs.Bridge.SetPlayerGangGrade(targetCitizenid, gangName, newRank)
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, targetCitizenid, 'member_promoted', FreeGangs.LogCategories.MEMBERSHIP, {
        promotedBy = promoterCitizenid,
        oldRank = targetMembership.rank,
        newRank = newRank,
        newRankName = newRankName,
    })
    
    -- Notify
    FreeGangs.Bridge.NotifyGang(gangName, string.format(FreeGangs.Config.Messages.MemberPromoted,
        FreeGangs.Bridge.GetPlayerName(promoterSource) or targetCitizenid, newRankName), 'success')
    
    -- Update target's client if online
    local targetPlayer = FreeGangs.Bridge.GetPlayerByCitizenId(targetCitizenid)
    if targetPlayer then
        TriggerClientEvent(FreeGangs.Events.Client.UPDATE_GANG_DATA, targetPlayer.PlayerData.source, {
            gang = FreeGangs.Server.Gang.GetClientData(gangName),
            membership = FreeGangs.Server.DB.GetPlayerMembership(targetCitizenid),
        })
    end
    
    return true
end

---Demote a gang member
---@param demoterSource number Source of the player doing the demoting
---@param targetCitizenid string Citizenid of the player being demoted
---@return boolean success
---@return string|nil errorMessage
function FreeGangs.Server.Member.Demote(demoterSource, targetCitizenid)
    local demoterCitizenid = FreeGangs.Bridge.GetCitizenId(demoterSource)
    local demoterMembership = FreeGangs.Server.DB.GetPlayerMembership(demoterCitizenid)
    
    if not demoterMembership then
        return false, 'You are not in a gang'
    end
    
    local gangName = demoterMembership.gang_name
    
    -- Check permission
    local hasPermission = FreeGangs.Server.Member.HasPermission(demoterSource, FreeGangs.Permissions.DEMOTE)
    if not hasPermission then
        return false, 'You do not have permission to demote members'
    end
    
    -- Get target membership
    local targetMembership = FreeGangs.Server.DB.GetPlayerMembership(targetCitizenid)
    if not targetMembership or targetMembership.gang_name ~= gangName then
        return false, 'Target is not in your gang'
    end
    
    -- Check rank hierarchy
    if targetMembership.rank >= demoterMembership.rank then
        return false, 'You cannot demote someone of equal or higher rank'
    end
    
    -- Check minimum rank
    if targetMembership.rank <= 0 then
        return false, 'Cannot demote below minimum rank'
    end
    
    local newRank = targetMembership.rank - 1
    
    -- Get new rank name
    local gang = FreeGangs.Server.Gangs[gangName]
    local defaultRanks = FreeGangs.GetDefaultRanks(gang.archetype)
    local newRankName = defaultRanks[newRank] and defaultRanks[newRank].name or 'Member'
    
    -- Check custom ranks
    local customRanks = FreeGangs.Server.DB.GetGangRanks(gangName)
    for _, rank in pairs(customRanks) do
        if rank.rank_level == newRank then
            newRankName = rank.name
            break
        end
    end
    
    -- Update rank
    FreeGangs.Server.DB.UpdateMemberRank(targetCitizenid, gangName, newRank, newRankName)
    FreeGangs.Bridge.SetPlayerGangGrade(targetCitizenid, gangName, newRank)
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, targetCitizenid, 'member_demoted', FreeGangs.LogCategories.MEMBERSHIP, {
        demotedBy = demoterCitizenid,
        oldRank = targetMembership.rank,
        newRank = newRank,
        newRankName = newRankName,
    })
    
    -- Notify
    FreeGangs.Bridge.NotifyGang(gangName, string.format(FreeGangs.Config.Messages.MemberDemoted,
        FreeGangs.Bridge.GetPlayerName(demoterSource) or targetCitizenid, newRankName), 'warning')
    
    -- Update target's client if online
    local targetPlayer = FreeGangs.Bridge.GetPlayerByCitizenId(targetCitizenid)
    if targetPlayer then
        TriggerClientEvent(FreeGangs.Events.Client.UPDATE_GANG_DATA, targetPlayer.PlayerData.source, {
            gang = FreeGangs.Server.Gang.GetClientData(gangName),
            membership = FreeGangs.Server.DB.GetPlayerMembership(targetCitizenid),
        })
    end
    
    return true
end

---Kick a member from the gang
---@param kickerSource number Source of the player doing the kicking
---@param targetCitizenid string Citizenid of the player being kicked
---@param reason string|nil
---@return boolean success
---@return string|nil errorMessage
function FreeGangs.Server.Member.Kick(kickerSource, targetCitizenid, reason)
    local kickerCitizenid = FreeGangs.Bridge.GetCitizenId(kickerSource)
    local kickerMembership = FreeGangs.Server.DB.GetPlayerMembership(kickerCitizenid)
    
    if not kickerMembership then
        return false, 'You are not in a gang'
    end
    
    local gangName = kickerMembership.gang_name
    
    -- Check permission
    local hasPermission = FreeGangs.Server.Member.HasPermission(kickerSource, FreeGangs.Permissions.KICK)
    if not hasPermission then
        return false, 'You do not have permission to kick members'
    end
    
    -- Get target membership
    local targetMembership = FreeGangs.Server.DB.GetPlayerMembership(targetCitizenid)
    if not targetMembership or targetMembership.gang_name ~= gangName then
        return false, 'Target is not in your gang'
    end
    
    -- Cannot kick yourself
    if targetCitizenid == kickerCitizenid then
        return false, 'You cannot kick yourself'
    end
    
    -- Check rank hierarchy
    if targetMembership.rank >= kickerMembership.rank then
        return false, 'You cannot kick someone of equal or higher rank'
    end
    
    local gang = FreeGangs.Server.Gangs[gangName]
    
    -- Remove member
    local success, err = FreeGangs.Server.Member.Remove(targetCitizenid, gangName, reason or 'Kicked')
    if not success then
        return false, err
    end
    
    -- Log
    FreeGangs.Server.DB.Log(gangName, targetCitizenid, 'member_kicked', FreeGangs.LogCategories.MEMBERSHIP, {
        kickedBy = kickerCitizenid,
        reason = reason,
    })
    
    -- Notify gang
    FreeGangs.Bridge.NotifyGang(gangName, string.format(FreeGangs.Config.Messages.MemberKicked,
        targetCitizenid), 'warning')
    
    -- Notify kicked player if online
    local targetPlayer = FreeGangs.Bridge.GetPlayerByCitizenId(targetCitizenid)
    if targetPlayer then
        FreeGangs.Bridge.Notify(targetPlayer.PlayerData.source, 
            'You have been kicked from ' .. gang.label .. (reason and ': ' .. reason or ''), 'error')
    end
    
    return true
end

-- ============================================================================
-- PERMISSION CHECKS
-- ============================================================================

---Check if a player has a specific permission
---@param source number Player source
---@param permission string Permission to check
---@return boolean
function FreeGangs.Server.Member.HasPermission(source, permission)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return false end
    
    -- Check personal permissions override first
    if membership.permissions and membership.permissions[permission] ~= nil then
        return membership.permissions[permission]
    end
    
    -- Check rank-based permissions
    local gangName = membership.gang_name
    local ranks = FreeGangs.Server.DB.GetGangRanks(gangName)
    
    for _, rank in pairs(ranks) do
        if rank.rank_level == membership.rank then
            if rank.permissions and rank.permissions[permission] then
                return true
            end
            break
        end
    end
    
    -- Check default permissions by rank tier
    local gang = FreeGangs.Server.Gangs[gangName]
    local defaultRanks = FreeGangs.GetDefaultRanks(gang.archetype)
    local rankData = defaultRanks[membership.rank]
    
    if rankData then
        if rankData.isBoss then
            return FreeGangs.DefaultPermissions.boss[permission] or false
        elseif rankData.isOfficer then
            return FreeGangs.DefaultPermissions.officer[permission] or false
        else
            return FreeGangs.DefaultPermissions.member[permission] or false
        end
    end
    
    return false
end

---Check if player is a boss
---@param source number
---@return boolean
function FreeGangs.Server.Member.IsBoss(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return false end
    
    local gang = FreeGangs.Server.Gangs[membership.gang_name]
    if not gang then return false end
    
    local defaultRanks = FreeGangs.GetDefaultRanks(gang.archetype)
    local rankData = defaultRanks[membership.rank]
    
    return rankData and rankData.isBoss or false
end

---Check if player is an officer (or boss)
---@param source number
---@return boolean
function FreeGangs.Server.Member.IsOfficer(source)
    local citizenid = FreeGangs.Bridge.GetCitizenId(source)
    if not citizenid then return false end
    
    local membership = FreeGangs.Server.DB.GetPlayerMembership(citizenid)
    if not membership then return false end
    
    local gang = FreeGangs.Server.Gangs[membership.gang_name]
    if not gang then return false end
    
    local defaultRanks = FreeGangs.GetDefaultRanks(gang.archetype)
    local rankData = defaultRanks[membership.rank]
    
    return rankData and (rankData.isOfficer or rankData.isBoss) or false
end

-- ============================================================================
-- MEMBER QUERIES
-- ============================================================================

---Get online members of a gang
---@param gangName string
---@return table
function FreeGangs.Server.Member.GetOnlineMembers(gangName)
    local onlineMembers = {}
    local players = FreeGangs.Bridge.GetPlayers()
    
    for source, player in pairs(players) do
        if player.PlayerData.gang and player.PlayerData.gang.name == gangName then
            onlineMembers[#onlineMembers + 1] = {
                source = source,
                citizenid = player.PlayerData.citizenid,
                name = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname,
                rank = player.PlayerData.gang.grade.level,
                rankName = player.PlayerData.gang.grade.name,
            }
        end
    end
    
    return onlineMembers
end

---Get all members for display
---@param gangName string
---@return table
function FreeGangs.Server.Member.GetAllForDisplay(gangName)
    local members = FreeGangs.Server.DB.GetGangMembers(gangName)
    local result = {}
    
    for _, member in pairs(members) do
        local isOnline = false
        local player = FreeGangs.Bridge.GetPlayerByCitizenId(member.citizenid)
        
        local displayName = 'Unknown'
        if player then
            isOnline = true
            displayName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
        end
        
        result[#result + 1] = {
            citizenid = member.citizenid,
            name = displayName,
            rank = member.rank,
            rankName = member.rank_name,
            isOnline = isOnline,
            joinedAt = member.joined_at,
            lastActive = member.last_active,
        }
    end
    
    -- Sort by rank descending, then by join date
    table.sort(result, function(a, b)
        if a.rank ~= b.rank then
            return a.rank > b.rank
        end
        return a.joinedAt < b.joinedAt
    end)
    
    return result
end

-- ============================================================================
-- CLEANUP
-- ============================================================================

-- Cleanup expired invites periodically
CreateThread(function()
    while true do
        Wait(60000) -- Every minute
        
        local currentTime = FreeGangs.Utils.GetTimestamp()
        for citizenid, invite in pairs(pendingInvites) do
            if currentTime > invite.expiresAt then
                pendingInvites[citizenid] = nil
            end
        end
    end
end)

return FreeGangs.Server.Member
