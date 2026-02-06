# FREE-GANGS Testing Guide

Comprehensive testing checklist for pre-deployment verification. Run through each section in order to validate all systems are functioning correctly.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Database Verification](#database-verification)
3. [Foundation Tests](#foundation-tests)
4. [Phase A: Territory System](#phase-a-territory-system)
5. [Phase B: Heat & War System](#phase-b-heat--war-system)
6. [Phase C: Criminal Activities](#phase-c-criminal-activities)
7. [Phase D: Bribery System](#phase-d-bribery-system)
8. [Phase E: Archetypes & Prison](#phase-e-archetypes--prison)
9. [Phase F: UI & Exports](#phase-f-ui--exports)
10. [Integration Tests](#integration-tests)
11. [Debug Commands Reference](#debug-commands-reference)
12. [Common Issues & Troubleshooting](#common-issues--troubleshooting)

---

## Prerequisites

### Server Requirements
- [ ] FiveM server with txAdmin
- [ ] QBCore or QBox framework installed
- [ ] ox_lib installed and updated
- [ ] ox_target installed (for activity interactions)
- [ ] MySQL database configured (oxmysql recommended)

### Config Verification
```lua
-- Verify debug mode is enabled for testing
-- config/config.lua
FreeGangs.Config.General.Debug = true
```

### Test Accounts
Create at least 3 test characters:
- **Player A**: Will be gang boss
- **Player B**: Will be gang officer/member
- **Player C**: Will be rival gang or civilian

---

## Database Verification

### 1. Schema Import
```sql
-- Run in your database console
SOURCE sql/schema.sql;

-- Verify all 15 tables exist
SHOW TABLES LIKE 'freegangs_%';
```

**Expected tables:**
- [ ] `freegangs_gangs`
- [ ] `freegangs_members`
- [ ] `freegangs_reputation_log`
- [ ] `freegangs_territories`
- [ ] `freegangs_territory_log`
- [ ] `freegangs_heat`
- [ ] `freegangs_heat_log`
- [ ] `freegangs_wars`
- [ ] `freegangs_war_kills`
- [ ] `freegangs_bribes`
- [ ] `freegangs_bribe_log`
- [ ] `freegangs_graffiti`
- [ ] `freegangs_protection`
- [ ] `freegangs_activity_log`
- [ ] `freegangs_prison`

### 2. Verify Constraints
```sql
-- Check foreign keys are properly set
SELECT TABLE_NAME, CONSTRAINT_NAME
FROM information_schema.TABLE_CONSTRAINTS
WHERE CONSTRAINT_TYPE = 'FOREIGN KEY'
AND TABLE_NAME LIKE 'freegangs_%';
```

---

## Foundation Tests

### Test F1: Resource Start
- [ ] Start the resource: `ensure free-gangs`
- [ ] Check server console for errors
- [ ] Verify "FREE-GANGS initialized" message appears
- [ ] No Lua errors in console

### Test F2: Gang Creation
**As Player A:**
1. [ ] Open gang menu (F6 or configured keybind)
2. [ ] Select "Create Gang"
3. [ ] Enter gang name, select archetype, choose color
4. [ ] Verify gang is created successfully
5. [ ] Verify player is now boss of the gang
6. [ ] Check database: `SELECT * FROM freegangs_gangs;`

### Test F3: Member Invitation
**As Player A (boss):**
1. [ ] Open gang menu > Members > Invite
2. [ ] Enter Player B's server ID
3. [ ] Verify invitation sent notification

**As Player B:**
1. [ ] Receive invitation notification
2. [ ] Accept invitation
3. [ ] Verify now a member of the gang
4. [ ] Check database: `SELECT * FROM freegangs_members;`

### Test F4: Rank Management
**As Player A (boss):**
1. [ ] Open gang menu > Members
2. [ ] Select Player B
3. [ ] Promote to Officer
4. [ ] Verify rank change notification
5. [ ] Demote back to Member
6. [ ] Verify rank change

### Test F5: Treasury Operations
**As Player A (boss):**
1. [ ] Open gang menu > Treasury
2. [ ] Deposit $1,000
3. [ ] Verify balance increased
4. [ ] Withdraw $500
5. [ ] Verify balance decreased
6. [ ] Check database treasury field

### Test F6: Reputation System
```
/fg_addrep [gangname] 100
```
- [ ] Verify reputation increased
- [ ] Check if level increased (if applicable)
- [ ] Verify notification received
- [ ] Check database: `SELECT * FROM freegangs_reputation_log ORDER BY created_at DESC LIMIT 5;`

---

## Phase A: Territory System

### Test A1: Zone Detection
1. [ ] Walk into a configured territory zone
2. [ ] **If zone is controlled (>50%)**: Verify entry notification appears
3. [ ] **If zone is uncontrolled**: Verify NO entry notification appears
4. [ ] Walk out of the zone
5. [ ] Verify zone exit is detected (debug message if enabled)

### Test A2: Territory HUD (Gang Members Only)
**As gang member:**
1. [ ] Enter a territory zone
2. [ ] Verify HUD appears (if `ShowTerritoryHUD = true`)
3. [ ] Verify HUD shows: zone name, owner, your influence
4. [ ] Toggle HUD with keybind (if configured)

### Test A3: Presence Tick
**As gang member in territory:**
1. [ ] Stay in zone for configured tick interval (default 30 min, use debug command to speed up)
```
/fg_presencetick
```
2. [ ] Verify influence increased
3. [ ] Check GlobalState update

### Test A4: Influence & Control
```
/fg_setinfluence [zonename] [gangname] 60
```
- [ ] Verify influence set correctly
- [ ] Verify zone now shows as "controlled" by gang
- [ ] Verify entry notification now fires for all players
- [ ] Check GlobalState: `GetConvar('territory:[zonename]')`

### Test A5: Territory Decay
```
/fg_decaytest
```
- [ ] Verify decay cycle runs
- [ ] Verify influence decreased by configured amount
- [ ] Verify neighboring zone bonuses applied (if configured)

### Test A6: Capture Mechanics
1. [ ] Set Gang A influence to 60%
2. [ ] Set Gang B influence to 30%
3. [ ] Verify Gang A is owner
4. [ ] Set Gang B influence to 70%
5. [ ] Verify ownership transferred to Gang B
6. [ ] Verify capture cooldown applied

### Test A7: Gang UI Territory Map
**As gang member:**
1. [ ] Open F6 menu > Territories
2. [ ] Verify territory list loads
3. [ ] Verify shows: owned count, contested count
4. [ ] Select a territory for details
5. [ ] Verify influence bar, zone type, owner displayed

### Test A8: Pause Map (Should NOT Show Territories)
1. [ ] Open GTA pause map (ESC or M)
2. [ ] Verify NO territory blips appear
3. [ ] Verify NO colored zone indicators
4. [ ] Territories should only be visible in gang UI

---

## Phase B: Heat & War System

### Test B1: Heat Generation
```
/fg_setheat [gang1] [gang2] 0
```
Then perform activities that generate heat (mugging in rival territory, etc.)
- [ ] Verify heat increased
- [ ] Check: `/fg_heat [gang1] [gang2]`

### Test B2: Heat Stages
Test each stage threshold:
```
/fg_setheat [gang1] [gang2] 25   -- Neutral
/fg_setheat [gang1] [gang2] 35   -- Tension
/fg_setheat [gang1] [gang2] 60   -- Cold War
/fg_setheat [gang1] [gang2] 80   -- Rivalry
/fg_setheat [gang1] [gang2] 95   -- War Ready
```
- [ ] Verify stage change notifications
- [ ] Verify UI reflects correct stage
- [ ] Verify rivalry effects (drug profit reduction at 75+)

### Test B3: Heat Decay
```
/fg_heatdecay
```
- [ ] Verify heat decreased
- [ ] Verify decay respects minimum (doesn't go below 0)

### Test B4: War Declaration
**Prerequisites:** Heat at 90+ between two gangs

**As Gang A boss:**
1. [ ] Open F6 > Wars > Declare War
2. [ ] Select target gang
3. [ ] Enter collateral amount
4. [ ] Confirm declaration
5. [ ] Verify war status: PENDING

**As Gang B boss:**
1. [ ] Receive war declaration notification
2. [ ] Open F6 > Wars > Pending Wars
3. [ ] Accept war (match collateral)
4. [ ] Verify war status: ACTIVE

### Test B5: War Kill Tracking
**During active war:**
1. [ ] Gang A member kills Gang B member
2. [ ] Verify kill recorded
3. [ ] Check war scoreboard
4. [ ] Verify death notification to victim's gang

### Test B6: War Resolution
Test each resolution type:

**Surrender:**
```
/fg_wars  -- Get war ID
```
- [ ] Boss surrenders
- [ ] Verify winner gets collateral
- [ ] Verify war ends

**Mutual Peace:**
- [ ] Both bosses request peace
- [ ] Verify collateral returned
- [ ] Verify war ends

### Test B7: War Cooldown
- [ ] After war ends, attempt to declare new war
- [ ] Verify 48-hour cooldown enforced
- [ ] Check: `/fg_warcooldown [gang1] [gang2]`

---

## Phase C: Criminal Activities

### Test C1: Mugging
**As gang member with weapon:**
1. [ ] Approach NPC
2. [ ] Use ox_target interaction "Mug"
3. [ ] Complete progress bar
4. [ ] Verify loot received
5. [ ] Verify heat generated (in rival territory)
6. [ ] Verify cooldown applied
7. [ ] Try mugging same NPC - should fail (cooldown)

**Without weapon:**
1. [ ] Approach NPC without weapon
2. [ ] Verify mugging option not available or fails

### Test C2: Pickpocketing
**As gang member:**
1. [ ] Approach NPC from behind
2. [ ] Use ox_target "Pickpocket"
3. [ ] Stay within 2m during progress bar
4. [ ] Verify loot rolls (up to 3)
5. [ ] Test detection failure (move away during attempt)

### Test C3: Drug Sales
**Check time restriction:**
```lua
-- Should only work 4PM-7AM game time
-- Test during allowed hours
```

**As gang member with drugs:**
1. [ ] Have drug item in inventory
2. [ ] Approach NPC during allowed hours
3. [ ] Use ox_target "Sell Drugs"
4. [ ] Select drug type
5. [ ] Complete progress bar
6. [ ] Verify money received
7. [ ] Verify drug item removed
8. [ ] Test in own territory (should get bonus)
9. [ ] Test in rival territory (should get penalty)

**Outside allowed hours:**
- [ ] Verify drug sale not available or fails

### Test C4: Protection Racket
**Prerequisites:** >51% zone control, boss rank

**As boss in controlled territory:**
1. [ ] Find business location
2. [ ] Use ox_target "Register Protection"
3. [ ] Verify business registered
4. [ ] Wait for collection cooldown (or use debug to skip)
5. [ ] Collect protection payment
6. [ ] Verify money added to treasury

**As non-boss:**
- [ ] Verify cannot register protection

**In uncontrolled zone:**
- [ ] Verify cannot register protection

### Test C5: Graffiti System
**As gang member with spray can:**
1. [ ] Approach wall surface
2. [ ] Open graffiti menu (keybind or ox_target)
3. [ ] Select "Spray Tag"
4. [ ] Complete progress bar with animation
5. [ ] Verify tag appears on wall
6. [ ] Verify spray can consumed
7. [ ] Verify influence/loyalty gained

**Tag limit:**
1. [ ] Spray maximum tags per cycle (6 default)
2. [ ] Verify cannot spray more until cycle resets

**Tag removal:**
1. [ ] Have paint cleaner item
2. [ ] Approach rival gang's tag
3. [ ] Use "Remove Tag" option
4. [ ] Verify tag removed
5. [ ] Verify bonus for removing rival tag

**Tag-over:**
1. [ ] Approach rival gang's tag with spray can
2. [ ] Use "Tag Over"
3. [ ] Verify replaces rival tag with yours
4. [ ] Verify no cleaner required for tag-over

---

## Phase D: Bribery System

### Test D1: Contact Discovery
**Prerequisites:** Master level meets contact requirement

1. [ ] Go to contact spawn location during spawn hours
2. [ ] Verify contact NPC spawns
3. [ ] Verify only visible to qualifying gang members
4. [ ] Non-gang members should not see contact

### Test D2: Approach Contact
**As qualifying gang member:**
1. [ ] Use ox_target on contact NPC
2. [ ] Select "Approach"
3. [ ] Verify success/failure based on level
4. [ ] If failed, verify cooldown applied

### Test D3: Establish Bribe
**After successful approach:**
1. [ ] Complete establishment dialogue
2. [ ] Verify bribe established
3. [ ] Verify initial payment made
4. [ ] Check database: `SELECT * FROM freegangs_bribes;`

### Test D4: Contact Abilities
Test each contact type:

**Beat Cop (Level 2):**
- [ ] Establish contact
- [ ] Verify dispatch blocking in controlled zones (50%+)

**Dispatcher (Level 3):**
- [ ] Use "Redirect Dispatch" ability
- [ ] Verify cooldown applied

**Detective (Level 4):**
- [ ] Use "Evidence Exchange"
- [ ] Verify random loot received

**Judge/DA (Level 5):**
- [ ] Verify passive -30% sentence reduction
- [ ] Use "Reduce Sentence" on jailed member
- [ ] Use "Release Prisoner"

**Customs (Level 5):**
- [ ] Use "Arms Deal"
- [ ] Verify discount applied

**Prison Guard (Level 6):**
- [ ] Use "Deliver Contraband" to jailed member
- [ ] Use "Help Escape"

**City Official (Level 7):**
- [ ] Wait for kickback timer
- [ ] Collect kickback payment

### Test D5: Payment System
1. [ ] Note payment due date
2. [ ] Wait until due (or advance time)
3. [ ] Make payment before deadline
4. [ ] Verify payment accepted

**Missed payment:**
1. [ ] Let payment deadline pass
2. [ ] Verify first miss penalty (+50% next payment)
3. [ ] Let second payment miss
4. [ ] Verify contact terminated

### Test D6: Heat Effects on Bribes
```
/fg_setheat [gang1] [gang2] 95
```
- [ ] Verify payment cost increased at high heat
- [ ] Verify payment interval shortened

---

## Phase E: Archetypes & Prison

### Test E1: Passive Bonuses
Test each archetype's passive:

**Street Gang:**
- [ ] Do drug sale, verify +20% profit
- [ ] Do graffiti, verify +25% loyalty

**MC:**
- [ ] Vehicle-related income +15%
- [ ] Convoy payout +20%

**Cartel:**
- [ ] Supplier relationship +30%
- [ ] Drug production +25%

**Crime Family:**
- [ ] Protection income +25%
- [ ] Bribe effectiveness +20%

### Test E2: Tier 1 Activities (Level 4+)
**Street Gang - Main Corner:**
1. [ ] Designate a zone as main corner
2. [ ] Do drug sales in that zone
3. [ ] Verify +5 rep per sale bonus

**MC - Prospect Runs:**
1. [ ] Start prospect run
2. [ ] Complete delivery
3. [ ] Verify passive income

**Cartel - Halcon Network:**
1. [ ] Toggle network on
2. [ ] Have rival enter territory
3. [ ] Verify alert received

**Crime Family - Tribute Network:**
1. [ ] Collect tribute from controlled zones
2. [ ] Verify tribute amount based on influence
3. [ ] Verify cooldown applied

### Test E3: Tier 2 Activities (Level 6+)
**Street Gang - Block Party:**
1. [ ] Start block party
2. [ ] Verify 2x loyalty gain
3. [ ] Verify 1-hour duration

**MC - Club Runs:**
1. [ ] Gather 4+ members
2. [ ] Start club run convoy
3. [ ] Complete route
4. [ ] Verify major payout

**Cartel - Convoy Protection:**
1. [ ] Start convoy protection
2. [ ] Escort shipment
3. [ ] Verify bonus on completion

**Crime Family - High-Value Contracts:**
1. [ ] Link a heist
2. [ ] Verify 1.5x reputation bonus

### Test E4: Tier 3 Activities (Level 8+)
**Street Gang - Drive-By Contracts:**
1. [ ] Accept contract
2. [ ] Complete hit
3. [ ] Verify payment and rep

**MC - Territory Ride:**
1. [ ] Start territory ride
2. [ ] Pass through multiple zones
3. [ ] Verify +5 loyalty per zone

**Cartel - Exclusive Suppliers:**
1. [ ] Access exclusive supplier
2. [ ] Verify top-tier products available

**Crime Family - Political Immunity:**
1. [ ] Verify all bribes accessible
2. [ ] Verify reduced bribe costs

### Test E5: Prison System
**Prison Control:**
```
/fg_prison [gangname] 35   -- 30%+ access
/fg_prison [gangname] 55   -- 50%+ benefits
/fg_prison [gangname] 80   -- 75%+ benefits
```

At each level, verify:
- [ ] 30%+: Prison guard bribes accessible
- [ ] 50%+: Free contraband delivery
- [ ] 51%+: Free prison guard bribes
- [ ] 75%+: Reduced escape cost ($10K vs $30K)

**Smuggle Mission:**
1. [ ] Have a jailed gang member
2. [ ] Start smuggle mission
3. [ ] Complete mission
4. [ ] Verify items delivered

---

## Phase F: UI & Exports

### Test F1: Main Menu (F6)
- [ ] Press F6 (or configured key)
- [ ] Verify menu opens
- [ ] Verify all sections accessible based on rank
- [ ] Close menu

### Test F2: Dashboard
- [ ] Open Dashboard from menu
- [ ] Verify gang stats display
- [ ] Verify reputation bar
- [ ] Verify treasury display

### Test F3: NUI Dashboard
- [ ] Open NUI (if configured keybind)
- [ ] Test each tab: Dashboard, Members, Territories, Wars, Treasury
- [ ] Verify data loads correctly
- [ ] Verify Godfather theme (dark bg, gold accents)

### Test F4: Notifications
Test each notification type:
```
/fg_notify territory contested TestZone
/fg_notify war declared TestGang
/fg_notify rep 100 5
/fg_notify heat TestGang rivalry
/fg_notify bribe due beat_cop
```
- [ ] Verify notifications display correctly
- [ ] Verify styling and icons

### Test F5: Exports
Test from another resource or console:
```lua
-- Membership
exports['free-gangs']:GetPlayerGang(source)
exports['free-gangs']:IsInGang(source, 'TestGang')
exports['free-gangs']:GetGangRank(source)

-- Reputation
exports['free-gangs']:GetMasterRep('TestGang')
exports['free-gangs']:GetMasterLevel('TestGang')

-- Territory
exports['free-gangs']:GetZoneControl('ZONE_NAME', 'TestGang')
exports['free-gangs']:GetZoneOwner('ZONE_NAME')

-- Heat
exports['free-gangs']:GetGangHeat('Gang1', 'Gang2')
exports['free-gangs']:AreGangsAtWar('Gang1', 'Gang2')
```
- [ ] Verify each export returns correct data

---

## Integration Tests

### Test I1: Activity -> Heat -> War Pipeline
1. [ ] Gang A mugs in Gang B territory
2. [ ] Verify heat increased
3. [ ] Continue activities until heat reaches 90+
4. [ ] Declare war
5. [ ] Conduct war
6. [ ] End war
7. [ ] Verify heat reduced post-war

### Test I2: Territory -> Activities -> Reputation
1. [ ] Gain 60% territory control
2. [ ] Perform activities (drugs, protection)
3. [ ] Verify territory bonuses applied
4. [ ] Verify reputation gained
5. [ ] Verify level up if threshold crossed

### Test I3: Archetype -> Territory -> Bribes
1. [ ] Set archetype to Crime Family
2. [ ] Gain territory control
3. [ ] Establish bribes
4. [ ] Verify archetype bonuses on bribe costs
5. [ ] Collect tribute from territories

### Test I4: Prison -> Bribes -> Archetypes
1. [ ] Have member jailed
2. [ ] Gain prison control (50%+)
3. [ ] Use prison guard bribe to help escape
4. [ ] Verify prison control bonuses applied

### Test I5: Full Gang Lifecycle
1. [ ] Create gang
2. [ ] Invite members
3. [ ] Establish in territory
4. [ ] Build reputation through activities
5. [ ] Engage rival (heat -> war)
6. [ ] Use bribes for advantages
7. [ ] Use archetype abilities
8. [ ] Manage treasury through it all

---

## Debug Commands Reference

### General
| Command | Description |
|---------|-------------|
| `/fg_menu` | Open main gang menu |
| `/fg_debug` | Toggle debug mode |

### Gang Management
| Command | Description |
|---------|-------------|
| `/fg_addrep [gang] [amount]` | Add reputation |
| `/fg_setlevel [gang] [level]` | Set master level |

### Territory
| Command | Description |
|---------|-------------|
| `/fg_territory [zone]` | Show zone info |
| `/fg_setinfluence [zone] [gang] [%]` | Set influence |
| `/fg_decaytest` | Trigger decay cycle |
| `/fg_presencetick` | Force presence tick |

### Heat & War
| Command | Description |
|---------|-------------|
| `/fg_heat [gang1] [gang2]` | Show heat level |
| `/fg_setheat [gang1] [gang2] [amount]` | Set heat |
| `/fg_heatdecay` | Trigger heat decay |
| `/fg_declarewar [target] [collateral]` | Force declare war |
| `/fg_wars` | List active wars |
| `/fg_endwar [warId] [winner]` | Force end war |

### Activities
| Command | Description |
|---------|-------------|
| `/fg_spray` | Force spray at location |
| `/fg_protection [business]` | Test protection |
| `/fg_drugsale` | Simulate drug sale |

### Bribes
| Command | Description |
|---------|-------------|
| `/fg_spawncontact [type]` | Force spawn contact |
| `/fg_establishbribe [type]` | Force establish bribe |
| `/fg_bribeuse [type] [ability]` | Test ability |

### Archetypes & Prison
| Command | Description |
|---------|-------------|
| `/fg_setarchetype [gang] [type]` | Change archetype |
| `/fg_tieractivity [activity]` | Test tier activity |
| `/fg_prison [gang] [%]` | Set prison control |

---

## Common Issues & Troubleshooting

### Issue: Resource fails to start
**Symptoms:** Error on `ensure free-gangs`
**Checks:**
1. Verify all dependencies installed (ox_lib, ox_target, qbx_core)
2. Check fxmanifest.lua for syntax errors
3. Verify database connection in server.cfg
4. Check for missing files

### Issue: Database errors
**Symptoms:** "MySQL error" in console
**Checks:**
1. Verify schema imported correctly
2. Check database credentials
3. Verify oxmysql is running
4. Check for table name conflicts

### Issue: Zones not detecting entry
**Symptoms:** No notification when entering territory
**Checks:**
1. Verify ox_lib zones are creating (debug messages)
2. Check territory config coordinates
3. Verify GlobalState is syncing
4. Check if zone has >50% owner (notifications only for controlled zones)

### Issue: Heat not generating
**Symptoms:** Activities don't increase heat
**Checks:**
1. Verify Heat module initialized
2. Check if activities are in rival territory
3. Verify heat config values

### Issue: War declaration fails
**Symptoms:** Cannot declare war at 90+ heat
**Checks:**
1. Verify exact heat level (must be 90+)
2. Check war cooldown between gangs
3. Verify war chest has sufficient funds
4. Check boss permissions

### Issue: Bribes not spawning
**Symptoms:** Contact NPCs don't appear
**Checks:**
1. Verify spawn time windows (config/bribes.lua)
2. Check spawn locations
3. Verify player meets level requirement
4. Check spawn distance from player

### Issue: Exports return nil
**Symptoms:** External resource gets nil from exports
**Checks:**
1. Verify resource name matches ('free-gangs')
2. Check if module is initialized
3. Verify player has gang membership
4. Check export function exists in server/exports.lua

### Issue: NUI not opening
**Symptoms:** Keybind doesn't open dashboard
**Checks:**
1. Verify NUI is enabled in config
2. Check browser console for JS errors (F8)
3. Verify nui files are loading (fxmanifest)
4. Check keybind registration

---

## Performance Checklist

Before deployment, verify:
- [ ] No memory leaks (monitor over extended test)
- [ ] Database queries optimized (no N+1 queries)
- [ ] GlobalState updates batched appropriately
- [ ] Client-side rendering efficient (FPS stable in territories)
- [ ] Event handlers not duplicating
- [ ] Threads sleeping appropriately when idle

---

## Sign-Off

| Test Section | Tester | Date | Pass/Fail |
|--------------|--------|------|-----------|
| Database | | | |
| Foundation | | | |
| Territory | | | |
| Heat & War | | | |
| Activities | | | |
| Bribes | | | |
| Archetypes | | | |
| UI & Exports | | | |
| Integration | | | |

**Final Approval:** _________________ **Date:** _________
