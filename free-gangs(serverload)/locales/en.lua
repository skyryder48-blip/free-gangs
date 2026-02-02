--[[
    FREE-GANGS: English Locale
    
    All user-facing text strings for the gang system.
]]

FreeGangs.Locale = FreeGangs.Locale or {}

FreeGangs.Locale.en = {
    -- ========================================================================
    -- GENERAL
    -- ========================================================================
    general = {
        yes = 'Yes',
        no = 'No',
        confirm = 'Confirm',
        cancel = 'Cancel',
        close = 'Close',
        back = 'Back',
        submit = 'Submit',
        loading = 'Loading...',
        error = 'Error',
        success = 'Success',
        warning = 'Warning',
        unknown = 'Unknown',
    },
    
    -- ========================================================================
    -- GANG MANAGEMENT
    -- ========================================================================
    gang = {
        -- Creation
        create_title = 'Create Gang',
        create_name = 'Gang Name',
        create_name_desc = 'Enter a unique name for your gang',
        create_archetype = 'Organization Type',
        create_archetype_desc = 'Choose your gang\'s archetype',
        create_color = 'Gang Color',
        create_color_desc = 'Choose your gang\'s representative color',
        create_confirm = 'Create Gang',
        create_success = 'Gang "%s" has been established!',
        create_fail = 'Failed to create gang: %s',
        create_exists = 'A gang with that name already exists',
        create_invalid_name = 'Invalid gang name',
        create_requirements = 'You need %s to create a gang',
        
        -- Info
        info_title = 'Gang Information',
        info_name = 'Name',
        info_archetype = 'Type',
        info_level = 'Level',
        info_reputation = 'Reputation',
        info_members = 'Members',
        info_territories = 'Territories',
        info_treasury = 'Treasury',
        info_warchest = 'War Chest',
        info_founded = 'Founded',
        
        -- Membership
        joined = '%s has joined the gang',
        left = '%s has left the gang',
        kicked = '%s has been kicked from the gang',
        promoted = '%s has been promoted to %s',
        demoted = '%s has been demoted to %s',
        invite_sent = 'Invitation sent to %s',
        invite_received = 'You have been invited to join %s',
        invite_accepted = 'You have joined %s',
        invite_declined = 'Invitation declined',
        already_in_gang = 'You are already in a gang',
        not_in_gang = 'You are not in a gang',
        target_in_gang = 'That player is already in a gang',
        
        -- Permissions
        no_permission = 'You don\'t have permission to do this',
        rank_too_low = 'Your rank is too low for this action',
        cannot_kick_higher = 'You cannot kick someone of equal or higher rank',
        cannot_promote_higher = 'You cannot promote beyond your own rank',
        
        -- Dissolution
        dissolve_title = 'Dissolve Gang',
        dissolve_confirm = 'Are you sure you want to dissolve your gang? This cannot be undone.',
        dissolve_success = 'Gang has been dissolved',
        dissolve_fail = 'Failed to dissolve gang',
    },
    
    -- ========================================================================
    -- REPUTATION
    -- ========================================================================
    reputation = {
        gained = '+%d reputation',
        lost = '-%d reputation',
        level_up = 'Gang reached Level %d: %s!',
        level_down = 'Gang dropped to Level %d: %s',
        current = 'Current Reputation: %d',
        progress = 'Progress to Level %d: %d%%',
        
        -- Level names
        levels = {
            [1] = 'Startup Crew',
            [2] = 'Known',
            [3] = 'Established',
            [4] = 'Respected',
            [5] = 'Notorious',
            [6] = 'Feared',
            [7] = 'Infamous',
            [8] = 'Legendary',
            [9] = 'Empire',
            [10] = 'Untouchable',
        },
    },
    
    -- ========================================================================
    -- TERRITORY
    -- ========================================================================
    territory = {
        entered = 'Entering %s territory',
        exited = 'Leaving territory',
        captured = 'Your gang now controls %s!',
        lost = 'Your gang has lost control of %s!',
        contested = '%s is being contested by rivals!',
        on_cooldown = 'This territory is on capture cooldown',
        influence = 'Influence: %d%%',
        owner = 'Controlled by: %s',
        neutral = 'Neutral Territory',
        
        -- Types
        types = {
            residential = 'Residential',
            commercial = 'Commercial',
            industrial = 'Industrial',
            strategic = 'Strategic',
            prison = 'Prison',
        },
    },
    
    -- ========================================================================
    -- HEAT & RIVALRY
    -- ========================================================================
    heat = {
        increased = 'Heat with %s increased to %d',
        decreased = 'Heat with %s decreased to %d',
        stage_changed = 'Relations with %s escalated to %s',
        
        -- Stages
        stages = {
            neutral = 'Neutral',
            tension = 'Tension',
            cold_war = 'Cold War',
            rivalry = 'Rivalry',
            war_ready = 'War Ready',
        },
    },
    
    -- ========================================================================
    -- WAR
    -- ========================================================================
    war = {
        -- Declaration
        declare_title = 'Declare War',
        declare_target = 'Target Gang',
        declare_collateral = 'Collateral Amount',
        declare_collateral_desc = 'Funds to stake (both gangs must match)',
        declare_confirm = 'Declare War',
        declare_success = 'War declared on %s!',
        declare_fail = 'Failed to declare war: %s',
        declare_insufficient_heat = 'Not enough heat with this gang (need %d+)',
        declare_insufficient_funds = 'Insufficient funds in war chest',
        declare_cooldown = 'Cannot declare war on this gang yet',
        
        -- Notification
        declared_on_you = '%s has declared war on your gang!',
        war_started = 'War with %s has begun!',
        war_ended = 'War with %s has ended',
        
        -- Acceptance
        accept_title = 'War Declaration',
        accept_message = '%s has declared war!\nCollateral: %s\nDo you accept?',
        accept_confirm = 'Accept War',
        accept_decline = 'Decline (Forfeit)',
        accept_success = 'War accepted!',
        accept_declined = 'War declined - you forfeit the conflict',
        
        -- Resolution
        victory = 'Victory!',
        defeat = 'Defeat',
        draw = 'Draw',
        surrender = 'Surrender',
        surrender_confirm = 'Are you sure you want to surrender? You will lose your collateral.',
        surrender_success = 'Your gang has surrendered',
        
        -- Stats
        stats_kills = 'Kills',
        stats_deaths = 'Deaths',
        stats_collateral = 'Collateral',
        stats_duration = 'Duration',
    },
    
    -- ========================================================================
    -- ACTIVITIES
    -- ========================================================================
    activities = {
        -- General
        on_cooldown = 'This action is on cooldown. %s remaining.',
        too_far = 'You are too far away',
        invalid_target = 'Invalid target',
        
        -- Mugging
        mugging_success = 'Mugging successful! Got %s',
        mugging_fail = 'Mugging failed!',
        mugging_no_weapon = 'You need a weapon to mug someone',
        
        -- Pickpocketing
        pickpocket_success = 'Pickpocket successful!',
        pickpocket_fail = 'Pickpocket failed! You\'ve been spotted!',
        pickpocket_detected = 'The target noticed you!',
        
        -- Drug Sales
        drug_sale_success = 'Sold %s for %s',
        drug_sale_fail = 'Customer rejected the deal',
        drug_sale_no_product = 'You don\'t have any product to sell',
        drug_sale_wrong_time = 'Corner sales only between 4 PM and 7 AM',
        
        -- Graffiti
        graffiti_sprayed = 'Tag sprayed! +%d zone influence',
        graffiti_removed = 'Rival tag removed!',
        graffiti_no_spray = 'You need spray paint',
        graffiti_max_reached = 'Maximum sprays reached for this cycle',
        graffiti_max_zone = 'Too many tags in this area',
        
        -- Protection
        protection_collected = 'Collected %s in protection money',
        protection_registered = 'Protection registered at %s',
        protection_not_ready = 'Collection not ready yet',
        protection_no_permission = 'You don\'t have permission to collect',
        protection_need_control = 'Your gang needs >50%% control to collect protection',
    },
    
    -- ========================================================================
    -- BRIBES
    -- ========================================================================
    bribes = {
        -- General
        established = '%s is now on your payroll',
        failed = 'The contact rejected your approach',
        terminated = '%s contact has been lost',
        payment_due = 'Payment due to %s within %d hours',
        payment_made = 'Payment made to %s',
        payment_missed = 'Missed payment to %s!',
        
        -- Contacts
        contacts = {
            beat_cop = 'Beat Cop',
            dispatcher = 'Dispatcher',
            detective = 'Detective',
            judge = 'Judge/DA',
            customs = 'Customs Agent',
            prison_guard = 'Prison Guard',
            city_official = 'City Official',
        },
        
        -- Abilities
        dispatch_blocked = 'Dispatch blocked by your contact',
        dispatch_delayed = 'Dispatch delayed by 60 seconds',
        dispatch_redirected = 'Police redirected to false location',
        sentence_reduced = 'Sentence reduced by %d minutes',
        prisoner_released = 'Prisoner has been released',
        contraband_delivered = 'Contraband delivered to prisoner',
    },
    
    -- ========================================================================
    -- TREASURY
    -- ========================================================================
    treasury = {
        title = 'Gang Treasury',
        balance = 'Balance: %s',
        deposit = 'Deposit',
        withdraw = 'Withdraw',
        deposit_success = 'Deposited %s into treasury',
        withdraw_success = 'Withdrew %s from treasury',
        insufficient_funds = 'Insufficient funds',
        
        -- War Chest
        warchest_title = 'War Chest',
        warchest_deposit = 'Deposit to War Chest',
        warchest_withdraw = 'Withdraw from War Chest',
    },
    
    -- ========================================================================
    -- STASH
    -- ========================================================================
    stash = {
        gang_stash = 'Gang Stash',
        personal_locker = 'Personal Locker',
        war_chest = 'War Chest',
        no_access = 'You don\'t have access to this stash',
    },
    
    -- ========================================================================
    -- UI MENU ITEMS
    -- ========================================================================
    menu = {
        -- Main menu
        main_title = 'Gang Operations',
        dashboard = 'Dashboard',
        members = 'Member Roster',
        territory = 'Territory Map',
        reputation = 'Reputation',
        wars = 'Wars & Rivalries',
        bribes = 'Contacts',
        activities = 'Activities',
        treasury = 'Treasury',
        stash = 'Gang Stash',
        settings = 'Settings',
        
        -- Member management
        invite_member = 'Invite Member',
        kick_member = 'Kick Member',
        promote_member = 'Promote',
        demote_member = 'Demote',
        set_permissions = 'Set Permissions',
        
        -- Territory
        view_territories = 'View Territories',
        territory_info = 'Territory Info',
        
        -- Activities
        start_corner = 'Work Corner',
        spray_tag = 'Spray Tag',
        collect_protection = 'Collect Protection',
        
        -- Archetype specific
        set_main_corner = 'Set Main Corner',
        start_club_run = 'Start Club Run',
        halcon_alerts = 'Halcon Alerts',
    },
    
    -- ========================================================================
    -- ARCHETYPES
    -- ========================================================================
    archetypes = {
        street = 'Street Gang',
        mc = 'Motorcycle Club',
        cartel = 'Drug Cartel',
        crime_family = 'Crime Family',
        
        -- Descriptions
        street_desc = 'Traditional street-level criminal organization focused on territory control and drug operations.',
        mc_desc = 'Outlaw motorcycle club with brotherhood culture and vehicle-focused operations.',
        cartel_desc = 'International drug trafficking organization with supplier networks and distribution corridors.',
        crime_family_desc = 'Traditional organized crime family focused on high-value operations and political influence.',
    },
    
    -- ========================================================================
    -- RANKS (Default names)
    -- ========================================================================
    ranks = {
        street = {
            [0] = 'Youngin',
            [1] = 'Soldier',
            [2] = 'Lieutenant',
            [3] = 'OG',
            [4] = 'Warlord',
            [5] = 'Shot Caller',
        },
        mc = {
            [0] = 'Prospect',
            [1] = 'Patched Member',
            [2] = 'Road Captain',
            [3] = 'Sergeant at Arms',
            [4] = 'Vice President',
            [5] = 'President',
        },
        cartel = {
            [0] = 'Street Dealer',
            [1] = 'Halcon',
            [2] = 'Sicario',
            [3] = 'Lieutenant',
            [4] = 'Plaza Boss',
            [5] = 'El Jefe',
        },
        crime_family = {
            [0] = 'Associate',
            [1] = 'Soldier',
            [2] = 'Capo',
            [3] = 'Consigliere',
            [4] = 'Underboss',
            [5] = 'Don',
        },
    },
    
    -- ========================================================================
    -- ERRORS
    -- ========================================================================
    errors = {
        generic = 'An error occurred',
        not_loaded = 'System not loaded yet',
        invalid_input = 'Invalid input',
        server_error = 'Server error occurred',
        timeout = 'Request timed out',
        not_found = 'Not found',
    },
}

-- Set active locale
FreeGangs.Locale.Active = FreeGangs.Locale.en

---Get localized string
---@param category string
---@param key string
---@param ... any Format arguments
---@return string
function FreeGangs.L(category, key, ...)
    local locale = FreeGangs.Locale.Active
    if locale[category] and locale[category][key] then
        local str = locale[category][key]
        if select('#', ...) > 0 then
            return string.format(str, ...)
        end
        return str
    end
    return string.format('[%s.%s]', category, key)
end

return FreeGangs.Locale
