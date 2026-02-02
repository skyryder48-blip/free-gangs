# FREE-GANGS Parallel Development Guide

## Current Status

### Completed Files (~8,300 lines)

| File | Lines | Status |
|------|-------|--------|
| `fxmanifest.lua` | 80 | ✅ Complete |
| `sql/schema.sql` | 250 | ✅ Complete (15 tables) |
| `shared/enums.lua` | 964 | ✅ Complete |
| `shared/utils.lua` | 745 | ✅ Complete |
| `config/config.lua` | 813 | ✅ Complete |
| `bridge/qbx.lua` | 574 | ✅ Complete |
| `server/main.lua` | 630 | ✅ Complete |
| `server/db/queries.lua` | 941 | ✅ Complete |
| `server/db/cache.lua` | 550 | ✅ Complete |
| `server/modules/gang.lua` | 515 | ✅ Complete |
| `server/modules/members.lua` | 692 | ✅ Complete |
| `server/modules/reputation.lua` | 489 | ✅ Complete |
| `client/main.lua` | 607 | ✅ Complete |
| `client/cache.lua` | 384 | ✅ Complete |
| `locales/en.lua` | 424 | ✅ Complete |

### Remaining Work (~9,000-11,000 lines estimated)

The remaining development is split into **6 parallelizable phases**. Each phase can be developed independently by a separate Claude conversation.

---

## Phase A: Territory System (Server + Client)

**Assignable to: Conversation 1**
**Dependencies:** Foundation complete (it is)
**Estimated Lines:** ~1,800

### Files to Create

```
server/modules/territory.lua       (~600 lines)
client/modules/territory.lua       (~500 lines)
config/territories.lua             (~400 lines)
server/callbacks/territory.lua     (~300 lines)
```

### Responsibilities

1. **Zone Definition System**
   - Load territory configurations from `config/territories.lua`
   - Support box, sphere, and polygon zones via ox_lib
   - Store zone metadata (type, coords, size, benefits)

2. **Influence Tracking**
   - Global 100% competition model (all gangs compete for shares)
   - Loyalty point accumulation per activity
   - Influence decay over time (2% per 4 hours unattended)

3. **Zone Control Tiers**
   - 0-5%: -20% drug profits
   - 6-10%: -15% drug profits
   - 11-24%: Base profit
   - 25-50%: +5% profit, Level 1 bribes
   - 51-79%: +10% profit, protection collection
   - 80-100%: +15% profit, 2x protection, discount bribes

4. **Capture Mechanics**
   - Zone flip when attacker exceeds defender by 25% margin
   - 2-hour capture cooldown after flip
   - Notifications to both gangs

5. **Client Zone Handlers**
   - `onEnter`, `onExit` callbacks
   - Presence tick for loyalty (every 30 minutes = +15 loyalty)
   - Territory HUD display (optional)

### Key Functions to Implement

```lua
-- Server
FreeGangs.Server.Territory.Create(zoneName, config)
FreeGangs.Server.Territory.AddInfluence(zoneName, gangName, amount)
FreeGangs.Server.Territory.RemoveInfluence(zoneName, gangName, amount)
FreeGangs.Server.Territory.GetOwner(zoneName) -- returns gang with >51%
FreeGangs.Server.Territory.GetInfluence(zoneName, gangName)
FreeGangs.Server.Territory.CheckCapture(zoneName)
FreeGangs.Server.Territory.ProcessDecay()

-- Client
FreeGangs.Client.Territory.CreateZone(zoneName, config)
FreeGangs.Client.Territory.OnEnter(zoneName)
FreeGangs.Client.Territory.OnExit(zoneName)
FreeGangs.Client.Territory.UpdateHUD()
```

### Interface with Other Phases

- **Exports for Activities Phase:** `GetZoneControlTier()`, `IsInOwnTerritory()`, `GetDrugProfitModifier()`
- **Exports for Heat Phase:** `GetContestingGangs()`, `NotifyTerritoryContest()`

---

## Phase B: Heat & War System (Server)

**Assignable to: Conversation 2**
**Dependencies:** Foundation complete, Territory Phase (can stub interfaces)
**Estimated Lines:** ~1,500

### Files to Create

```
server/modules/heat.lua            (~500 lines)
server/modules/war.lua             (~600 lines)
server/callbacks/heat.lua          (~200 lines)
server/callbacks/war.lua           (~200 lines)
```

### Responsibilities

1. **Heat Tracking**
   - Per-gang-pair heat levels (0-100)
   - Heat point values per activity (defined in config)
   - Individual decay: 1 point per 5 real minutes
   - Gang decay: 1 point per 10 real minutes

2. **Escalation Stages**
   - Neutral (0-29): Normal interactions
   - Tension (30-49): UI indicator
   - Cold War (50-74): Warnings in rival territory
   - Rivalry (75-89): 70% drug profit reduction, protection stopped
   - War Ready (90-100): Can declare war

3. **War Declaration**
   - Requires 90+ heat
   - Collateral from War Chest ($5K-$100K)
   - Target gang must accept (match collateral) or forfeit
   - 24-hour acceptance window

4. **War Resolution**
   - Leader surrender (loses collateral)
   - Mutual peace (collateral returned)
   - Admin ends (determines winner)
   - 48-hour cooldown before same-gang war

5. **War Dashboard Data**
   - Kill tracking (attacker_kills, defender_kills)
   - Collateral amounts
   - Duration tracking

### Key Functions to Implement

```lua
-- Heat
FreeGangs.Server.Heat.Add(gangA, gangB, amount, reason)
FreeGangs.Server.Heat.Get(gangA, gangB)
FreeGangs.Server.Heat.GetStage(gangA, gangB)
FreeGangs.Server.Heat.ProcessDecay()
FreeGangs.Server.Heat.OnStageChange(gangA, gangB, oldStage, newStage)

-- War
FreeGangs.Server.War.Declare(attackerGang, defenderGang, collateral)
FreeGangs.Server.War.Accept(warId, defenderCollateral)
FreeGangs.Server.War.Decline(warId)
FreeGangs.Server.War.Surrender(warId, surrenderingGang)
FreeGangs.Server.War.End(warId, winner)
FreeGangs.Server.War.RecordKill(warId, killerGang)
FreeGangs.Server.War.GetActive(gangName)
FreeGangs.Server.War.IsAtWarWith(gangA, gangB)
```

### Interface with Other Phases

- **Exports for Activities Phase:** `AddHeat()`, `GetHeatStage()`
- **Exports for Territory Phase:** `AreGangsAtWar()`

---

## Phase C: Criminal Activities (Server + Client)

**Assignable to: Conversation 3**
**Dependencies:** Foundation, Territory (can stub)
**Estimated Lines:** ~2,500

### Files to Create

```
server/modules/activities.lua      (~800 lines)
client/modules/activities.lua      (~600 lines)
server/modules/graffiti.lua        (~400 lines)
client/modules/graffiti.lua        (~400 lines)
server/callbacks/activities.lua    (~300 lines)
```

### Responsibilities

1. **Mugging System**
   - Target: World NPCs via ox_target
   - Requires weapon in hand
   - Reward: $1-200 + loot table items
   - Heat: +22 per mugging
   - Cooldown: 5 minutes between muggings

2. **Pickpocketing System**
   - Progress bar with distance check (2m max)
   - 3 loot rolls per attempt
   - Detection triggers police notification
   - 30-minute cooldown per NPC

3. **Drug Sales**
   - Target: World NPCs via ox_target
   - Time restriction: 4PM-7AM in-game
   - Territory bonuses: +20% success in owned, -30% in rival
   - Diminishing returns per hour

4. **Protection Racket**
   - Register business (leader only, >51% zone control)
   - Collection every 4 hours
   - Base payout: $200-800 per business
   - Contested zones reduce payout

5. **Graffiti/Tagging**
   - Spray can item required (consumed on use)
   - 5-second spray with animation
   - +10 zone loyalty, +5 master rep, +5 heat
   - Max 6 sprays per 6-hour cycle
   - Tag removal with paint cleaner item
   - Runtime texture replacement for visuals

### Key Functions to Implement

```lua
-- Server Activities
FreeGangs.Server.Activities.Mug(source, targetNetId)
FreeGangs.Server.Activities.Pickpocket(source, targetNetId)
FreeGangs.Server.Activities.SellDrug(source, targetNetId, drugItem)
FreeGangs.Server.Activities.CollectProtection(source, businessId)
FreeGangs.Server.Activities.RegisterProtection(source, businessId)

-- Server Graffiti
FreeGangs.Server.Graffiti.Spray(source, coords, rotation)
FreeGangs.Server.Graffiti.Remove(source, tagId)
FreeGangs.Server.Graffiti.GetNearby(coords, radius)
FreeGangs.Server.Graffiti.GetZoneTags(zoneName)

-- Client Activities
FreeGangs.Client.Activities.StartMugging(targetPed)
FreeGangs.Client.Activities.StartPickpocket(targetPed)
FreeGangs.Client.Activities.StartDrugSale(targetPed)
FreeGangs.Client.Activities.CollectProtection(business)

-- Client Graffiti
FreeGangs.Client.Graffiti.StartSpray()
FreeGangs.Client.Graffiti.StartRemoval(tagId)
FreeGangs.Client.Graffiti.LoadNearby()
FreeGangs.Client.Graffiti.RenderTag(tagData)
```

### ox_target Integration Points

```lua
-- NPC targeting for mugging/pickpocket/drug sales
exports.ox_target:addGlobalPed({...})

-- Business targeting for protection
exports.ox_target:addBoxZone({...})

-- Wall targeting for graffiti
exports.ox_target:addModel({...}) -- for specific wall props
```

---

## Phase D: Bribery System (Server + Client)

**Assignable to: Conversation 4**
**Dependencies:** Foundation, Heat (can stub)
**Estimated Lines:** ~1,500

### Files to Create

```
server/modules/bribes.lua          (~500 lines)
client/modules/bribes.lua          (~500 lines)
server/callbacks/bribes.lua        (~250 lines)
config/bribes.lua                  (~250 lines)
```

### Responsibilities

1. **Contact Discovery**
   - Officials spawn at specific locations during specific times (6PM-2AM)
   - Only visible to gang members meeting master level requirements
   - Subtle visual tells for identification

2. **Approach & Establishment**
   - ox_target interaction on identified NPC
   - Dialogue system (lib.alertDialog or custom)
   - Success: NPC states bribe requirements
   - Failure: 6-hour cooldown, -20 master rep

3. **Bribe Maintenance**
   - Weekly payments due
   - Notification 24 hours before due
   - First miss: paused, +50% cost
   - Second miss: terminated, 48-hour cooldown, -30 rep

4. **Contact Abilities**

| Contact | Min Level | Weekly Cost | Ability |
|---------|-----------|-------------|---------|
| Beat Cop | 2 | $2,000 | Auto-block dispatch (>50% zones) |
| Dispatcher | 3 | $5,000 | Delay/redirect dispatch |
| Detective | 4 | $8,000 | Evidence exchange meeting |
| Judge/DA | 5 | $15,000 | -30% sentences, reduce/release |
| Customs | 5 | $8,000/use | Reduced arms trafficking costs |
| Prison Guard | 6 | $3,000 | Contraband delivery, help escape |
| City Official | 7 | 25% initial | Kickback payments |

5. **Heat Integration**
   - Each bribe use adds heat (+3 to +15)
   - High heat increases payment frequency
   - 90+ heat: payment cost +100%

### Key Functions to Implement

```lua
-- Server
FreeGangs.Server.Bribes.SpawnContacts() -- called periodically
FreeGangs.Server.Bribes.Approach(source, contactType)
FreeGangs.Server.Bribes.Establish(source, gangName, contactType)
FreeGangs.Server.Bribes.MakePayment(source, gangName, contactType)
FreeGangs.Server.Bribes.UseAbility(source, contactType, abilityName, params)
FreeGangs.Server.Bribes.CheckPayments() -- background task
FreeGangs.Server.Bribes.Terminate(gangName, contactType, reason)

-- Client
FreeGangs.Client.Bribes.IdentifyContact(ped)
FreeGangs.Client.Bribes.ApproachContact(contactType)
FreeGangs.Client.Bribes.ShowAbilityMenu(contactType)
```

---

## Phase E: Archetypes & Special Mechanics (Server + Client)

**Assignable to: Conversation 5**
**Dependencies:** Foundation, Territory, Activities (can stub)
**Estimated Lines:** ~1,800

### Files to Create

```
server/modules/archetypes.lua      (~600 lines)
client/modules/archetypes.lua      (~400 lines)
server/modules/prison.lua          (~400 lines)
server/callbacks/archetypes.lua    (~200 lines)
config/archetypes.lua              (~200 lines)
```

### Responsibilities

1. **Passive Bonuses (Always Active)**

| Archetype | Bonus |
|-----------|-------|
| Street Gang | +20% corner drug profits, +25% graffiti loyalty |
| MC | +15% vehicle income, +20% convoy payouts |
| Cartel | +30% supplier relationship, +25% drug production |
| Crime Family | +25% protection income, +20% bribe effectiveness |

2. **Tier 1 Activities (Level 4+)**

| Archetype | Activity | Description |
|-----------|----------|-------------|
| Street Gang | Main Corner | Designate zone for +5 rep per sale |
| MC | Prospect Runs | Passive income delivery missions |
| Cartel | Halcon Network | Alert when rivals/police enter territory |
| Crime Family | Tribute Network | 5% cut from NPC sales in zones |

3. **Tier 2 Activities (Level 6+)**

| Archetype | Activity | Description |
|-----------|----------|-------------|
| Street Gang | Block Party | 2x loyalty gain for 1 hour |
| MC | Club Runs | Convoy mission, 4+ members, major payout |
| Cartel | Convoy Protection | Escort shipment with bonus |
| Crime Family | High-Value Contracts | 1.5x heist reputation |

4. **Tier 3 Activities (Level 8+)**

| Archetype | Activity | Description |
|-----------|----------|-------------|
| Street Gang | Drive-By Contracts | NPC hit contracts |
| MC | Territory Ride | +5 loyalty per zone passed |
| Cartel | Exclusive Suppliers | Top-tier supplier access |
| Crime Family | Political Immunity | All bribes, reduced costs |

5. **Prison Zone System**
   - Special territory all archetypes compete for
   - 30%+: Prison Guard bribes access
   - 50%+: Free contraband delivery
   - 51%+: Free prison guard bribes
   - 75%+: Reduced escape cost ($10K vs $30K)
   - Smuggle missions (require jailed member)

### Key Functions to Implement

```lua
-- Server
FreeGangs.Server.Archetypes.GetPassiveBonus(gangName, bonusType)
FreeGangs.Server.Archetypes.ApplyBonus(gangName, baseValue, bonusType)
FreeGangs.Server.Archetypes.HasTierAccess(gangName, tier)
FreeGangs.Server.Archetypes.ExecuteTierActivity(source, activityName)

-- Street Gang specific
FreeGangs.Server.Archetypes.Street.SetMainCorner(gangName, zoneName)
FreeGangs.Server.Archetypes.Street.StartBlockParty(gangName)
FreeGangs.Server.Archetypes.Street.AcceptDriveByContract(source, contractId)

-- MC specific
FreeGangs.Server.Archetypes.MC.StartProspectRun(source)
FreeGangs.Server.Archetypes.MC.StartClubRun(source, memberSources)
FreeGangs.Server.Archetypes.MC.StartTerritoryRide(source)

-- Cartel specific
FreeGangs.Server.Archetypes.Cartel.ToggleHalconNetwork(gangName, enabled)
FreeGangs.Server.Archetypes.Cartel.StartConvoyProtection(source)
FreeGangs.Server.Archetypes.Cartel.AccessExclusiveSupplier(source)

-- Crime Family specific
FreeGangs.Server.Archetypes.CrimeFamily.GetTributeCut(zoneName)
FreeGangs.Server.Archetypes.CrimeFamily.LinkHeist(heistName)
FreeGangs.Server.Archetypes.CrimeFamily.GetBribeDiscount()

-- Prison
FreeGangs.Server.Prison.GetControlLevel(gangName)
FreeGangs.Server.Prison.StartSmuggleMission(source)
FreeGangs.Server.Prison.DeliverContraband(source, targetCitizenId, items)
FreeGangs.Server.Prison.HelpEscape(source, targetCitizenId)
```

---

## Phase F: UI, Menus, Callbacks & Exports (Client + Server)

**Assignable to: Conversation 6**
**Dependencies:** All other phases (can stub interfaces)
**Estimated Lines:** ~2,500

### Files to Create

```
client/ui/menus.lua                (~600 lines)
client/ui/inputs.lua               (~300 lines)
client/ui/notifications.lua        (~200 lines)
server/callbacks.lua               (~500 lines)
server/exports.lua                 (~400 lines)
nui/index.html                     (~200 lines)
nui/css/style.css                  (~200 lines)
nui/js/app.js                      (~300 lines)
```

### Responsibilities

1. **ox_lib Context Menus**
   - Main gang menu (F6 keybind)
   - Dashboard submenu
   - Member roster submenu
   - Territory map submenu
   - Reputation stats submenu
   - War status submenu
   - Bribe contacts submenu
   - Treasury submenu
   - Settings submenu (boss only)

2. **ox_lib Input Dialogs**
   - Gang creation form
   - Invite member input
   - Treasury deposit/withdraw
   - War chest deposit
   - War declaration form
   - Bribe payment confirmation

3. **Notification Wrappers**
   - Territory alerts (contested, captured, lost)
   - War alerts (declared, started, ended)
   - Reputation changes (level up/down)
   - Heat stage changes
   - Bribe payment reminders

4. **Server Callbacks (lib.callback)**
   - `gangs:getPlayerGang`
   - `gangs:getGangInfo`
   - `gangs:getMembers`
   - `gangs:getTerritories`
   - `gangs:getHeatData`
   - `gangs:getActiveWars`
   - `gangs:getBribes`
   - `gangs:getNearbyGraffiti`
   - All action callbacks for activities

5. **Public Exports**

```lua
-- Membership
exports['free-gangs']:GetPlayerGang(source)
exports['free-gangs']:IsInGang(source, gangName)
exports['free-gangs']:GetGangRank(source)

-- Reputation
exports['free-gangs']:AddMasterRep(gangName, amount, reason)
exports['free-gangs']:RemoveMasterRep(gangName, amount, reason)
exports['free-gangs']:GetMasterRep(gangName)
exports['free-gangs']:GetMasterLevel(gangName)

-- Territory
exports['free-gangs']:GetZoneControl(zoneName, gangName)
exports['free-gangs']:AddZoneLoyalty(zoneName, gangName, amount)
exports['free-gangs']:GetZoneOwner(zoneName)

-- Heat & War
exports['free-gangs']:AddGangHeat(gang1, gang2, amount)
exports['free-gangs']:GetGangHeat(gang1, gang2)
exports['free-gangs']:AreGangsAtWar(gang1, gang2)
exports['free-gangs']:GetRivalryStage(gang1, gang2)

-- Archetype
exports['free-gangs']:GetArchetype(gangName)
exports['free-gangs']:HasArchetypeAccess(gangName, feature)
```

6. **NUI (Godfather Theme)**
   - Dark colors (#1a1a1a background, #8B0000 accents)
   - Gold highlights (#D4AF37)
   - Cinzel/Times New Roman fonts
   - Dashboard with gang stats
   - Territory map visualization
   - War scoreboard
   - Member management

### Key Functions to Implement

```lua
-- Client Menus
FreeGangs.Client.UI.OpenMainMenu()
FreeGangs.Client.UI.OpenDashboard()
FreeGangs.Client.UI.OpenMemberRoster()
FreeGangs.Client.UI.OpenTerritoryMap()
FreeGangs.Client.UI.OpenWarStatus()
FreeGangs.Client.UI.OpenTreasury()
FreeGangs.Client.UI.OpenSettings()

-- Client Inputs
FreeGangs.Client.UI.ShowGangCreation()
FreeGangs.Client.UI.ShowInviteInput()
FreeGangs.Client.UI.ShowDepositInput(type)
FreeGangs.Client.UI.ShowWarDeclaration(targetGang)

-- Client Notifications
FreeGangs.Client.UI.NotifyTerritoryAlert(zoneName, alertType)
FreeGangs.Client.UI.NotifyWarAlert(alertType, data)
FreeGangs.Client.UI.NotifyRepChange(amount, newLevel)
FreeGangs.Client.UI.NotifyHeatChange(otherGang, stage)
```

---

## Shared Resources & Conventions

### Event Naming Convention

All events follow `freegangs:{context}:{action}` pattern:

```lua
-- Server events (client → server)
'freegangs:server:createGang'
'freegangs:server:joinGang'
'freegangs:server:leaveGang'
'freegangs:server:enterTerritory'
'freegangs:server:exitTerritory'
'freegangs:server:presenceTick'
'freegangs:server:sprayGraffiti'
'freegangs:server:mugTarget'
'freegangs:server:sellDrug'
'freegangs:server:declareWar'

-- Client events (server → client)
'freegangs:client:updateGangData'
'freegangs:client:notify'
'freegangs:client:territoryAlert'
'freegangs:client:warAlert'
'freegangs:client:loadGraffiti'
'freegangs:client:heatUpdate'
```

### Callback Naming Convention

```lua
-- All callbacks registered under 'freegangs:' prefix
'freegangs:getPlayerGang'
'freegangs:getGangInfo'
'freegangs:getTerritories'
'freegangs:getNearbyGraffiti'
'freegangs:canPerformAction'
```

### Shared Tables Access

All phases should access shared data through:

```lua
-- Config
FreeGangs.Config.{section}.{key}

-- Enums/Constants
FreeGangs.Archetypes.{TYPE}
FreeGangs.HeatStages.{STAGE}
FreeGangs.Permissions.{PERMISSION}
FreeGangs.Activities.{ACTIVITY}

-- Utilities
FreeGangs.Utils.{function}()

-- Bridge (framework abstraction)
FreeGangs.Bridge.{function}()

-- Server-side caches
FreeGangs.Server.Gangs[gangName]
FreeGangs.Server.Territories[zoneName]
FreeGangs.Server.Heat[key]
FreeGangs.Server.ActiveWars[warId]
FreeGangs.Server.Bribes[gangName][contactType]

-- Client-side cache
FreeGangs.Client.Cache.Get(key)
FreeGangs.Client.Cache.Set(key, value)
```

---

## Integration Points Between Phases

### Phase A (Territory) needs from others:
- Heat Phase: `AreGangsAtWar()` for capture restrictions
- Activities Phase: calls `AddInfluence()` after activities

### Phase B (Heat/War) needs from others:
- Territory Phase: `GetContestingGangs()` for auto-heat
- Activities Phase: calls `AddHeat()` after crimes

### Phase C (Activities) needs from others:
- Territory Phase: `GetZoneControlTier()`, `GetDrugProfitModifier()`
- Heat Phase: calls `AddHeat()` for crimes

### Phase D (Bribes) needs from others:
- Heat Phase: `GetHeatLevel()` for payment scaling
- Territory Phase: `GetZoneControl()` for ability restrictions

### Phase E (Archetypes) needs from others:
- Territory Phase: `GetZoneOwner()`, `AddInfluence()`
- Activities Phase: modify base values with passives

### Phase F (UI/Exports) needs from others:
- All phases: data retrieval callbacks

---

## Stubbing Strategy for Parallel Development

When a phase depends on another incomplete phase, create stubs:

```lua
-- Example: Activities phase needs Territory functions
-- Create temporary stub in activities.lua

local function GetZoneControlTier(zoneName, gangName)
    -- STUB: Replace when Territory phase complete
    -- For now, return neutral tier
    return {
        tier = 3,
        drugProfitMod = 0,
        canCollectProtection = false,
    }
end

-- Mark stubs clearly
-- TODO: STUB - Replace with FreeGangs.Server.Territory.GetControlTier()
```

After all phases complete, run integration pass to:
1. Remove all stubs
2. Connect real function calls
3. Test cross-phase interactions

---

## Testing Commands Per Phase

Each phase should include debug commands:

### Phase A (Territory)
```
/fg_territory [zone] - Show zone info
/fg_setinfluence [zone] [gang] [%] - Set influence
/fg_decaytest - Trigger decay cycle
```

### Phase B (Heat/War)
```
/fg_heat [gang1] [gang2] - Show heat
/fg_setheat [gang1] [gang2] [amount] - Set heat
/fg_declarewar [target] [amount] - Force war
```

### Phase C (Activities)
```
/fg_spray - Force spray at location
/fg_protection [business] - Test collection
/fg_drugsale - Simulate sale
```

### Phase D (Bribes)
```
/fg_spawncontact [type] - Spawn contact NPC
/fg_establishbribe [type] - Force establish
/fg_bribeuse [type] [ability] - Test ability
```

### Phase E (Archetypes)
```
/fg_setarchetype [gang] [type] - Change archetype
/fg_tieractivity [activity] - Test tier activity
/fg_prison [gang] [%] - Set prison control
```

### Phase F (UI)
```
/fg_menu - Open main menu
/fg_notify [type] [message] - Test notification
/fg_nui - Toggle NUI
```

---

## File Checklist

### Phase A: Territory
- [ ] `server/modules/territory.lua`
- [ ] `client/modules/territory.lua`
- [ ] `config/territories.lua`
- [ ] `server/callbacks/territory.lua`

### Phase B: Heat & War
- [ ] `server/modules/heat.lua`
- [ ] `server/modules/war.lua`
- [ ] `server/callbacks/heat.lua`
- [ ] `server/callbacks/war.lua`

### Phase C: Activities
- [ ] `server/modules/activities.lua`
- [ ] `client/modules/activities.lua`
- [ ] `server/modules/graffiti.lua`
- [ ] `client/modules/graffiti.lua`
- [ ] `server/callbacks/activities.lua`

### Phase D: Bribes
- [ ] `server/modules/bribes.lua`
- [ ] `client/modules/bribes.lua`
- [ ] `server/callbacks/bribes.lua`
- [ ] `config/bribes.lua`

### Phase E: Archetypes
- [ ] `server/modules/archetypes.lua`
- [ ] `client/modules/archetypes.lua`
- [ ] `server/modules/prison.lua`
- [ ] `server/callbacks/archetypes.lua`
- [ ] `config/archetypes.lua`

### Phase F: UI & Exports
- [ ] `client/ui/menus.lua`
- [ ] `client/ui/inputs.lua`
- [ ] `client/ui/notifications.lua`
- [ ] `server/callbacks.lua` (consolidated)
- [ ] `server/exports.lua`
- [ ] `nui/index.html`
- [ ] `nui/css/style.css`
- [ ] `nui/js/app.js`

---

## Starting Each Parallel Conversation

Copy this prompt to start each conversation:

```
I'm working on a FiveM gang system called "free-gangs" for QBox framework with ox_lib.

The foundation is complete (8,300 lines). I need you to develop **Phase [X]: [Name]**.

Reference files are in /mnt/project/:
- Building_Large-Scale_FiveM_Scripts_on_QBox_with_ox_lib.md
- FiveM_Free-Gangs_System__Complete_Feature_Specification_for_QBox_Framework.md  
- FREE-GANGS-Complete-Specification.docx

The existing codebase is in /home/claude/free-gangs/ - review the structure before starting.

Your phase responsibilities:
[Copy relevant section from PARALLEL-DEVELOPMENT-GUIDE.md]

Create complete, production-ready code for all files listed. Use stubs for dependencies on other phases. Follow the naming conventions and access patterns documented in the guide.
```
