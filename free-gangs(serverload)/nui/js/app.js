/**
 * FREE-GANGS NUI Application v2.0
 *
 * Complete client-side UI for the FREE-GANGS FiveM resource.
 * Single IIFE module -- no ES module imports (FiveM NUI limitation).
 *
 * Sections:
 *   1. Configuration
 *   2. State Management
 *   3. DOM Element Cache
 *   4. Utility Functions
 *   5. NUI Communication (JS <-> Lua)
 *   6. Role-Based Visibility
 *   7. UI Open / Close
 *   8. Tab Navigation
 *   9. Dashboard Tab
 *  10. Operations Tab
 *  11. Territories Tab
 *  12. Members Tab
 *  13. Wars & Heat Tab
 *  14. Contacts Tab
 *  15. Treasury Tab
 *  16. Settings Tab
 *  17. Modal System
 *  18. Toast Notifications
 *  19. Activity Feed
 *  20. Event Listeners
 *  21. Initialization
 */

(function () {
    'use strict';

    // ========================================================================
    // 1. CONFIGURATION
    // ========================================================================

    var CONFIG = {
        resourceName: 'free-gangs',
        toastDuration: 5000,
        animationDuration: 300,
        maxActivityItems: 20,
        maxTransactions: 20,
        maxMembers: 30,
        maxHeatRivals: 5,
        gaugeCircumference: 2 * Math.PI * 42, // ~263.89
    };

    // ========================================================================
    // 2. STATE MANAGEMENT
    // ========================================================================

    var State = {
        isOpen: false,
        currentTab: 'dashboard',
        playerRole: 'civilian', // civilian | gang_member | officer | boss
        gangData: null,
        members: [],
        territories: {},
        heatData: {},
        activeWars: [],
        transactions: [],
        cooldowns: {},
        operations: {},
        contacts: [],
        activities: [],
    };

    // ========================================================================
    // 3. DOM ELEMENT CACHE
    // ========================================================================

    var Elements = {
        ui: document.getElementById('gang-ui'),
        closeBtn: document.getElementById('closeBtn'),
        navTabs: document.querySelectorAll('.nav-tab'),
        tabContents: document.querySelectorAll('.tab-content'),
        modalOverlay: document.getElementById('modalOverlay'),
        modal: document.getElementById('modal'),
        modalTitle: document.getElementById('modalTitle'),
        modalBody: document.getElementById('modalBody'),
        modalFooter: document.getElementById('modalFooter'),
        modalClose: document.getElementById('modalClose'),
        modalCancel: document.getElementById('modalCancel'),
        modalConfirm: document.getElementById('modalConfirm'),
        toastContainer: document.getElementById('toastContainer'),
    };

    // ========================================================================
    // 4. UTILITY FUNCTIONS
    // ========================================================================

    /**
     * Format a number with commas.
     * @param {number} num
     * @returns {string}
     */
    function formatNumber(num) {
        if (num == null || isNaN(num)) return '0';
        return Math.floor(num).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    /**
     * Format a monetary value with $ prefix and commas.
     * @param {number} amount
     * @returns {string}
     */
    function formatMoney(amount) {
        if (amount == null || isNaN(amount)) return '$0';
        return '$' + formatNumber(Math.abs(amount));
    }

    /**
     * Format a timestamp into a relative time string.
     * @param {number|string} timestamp
     * @returns {string}
     */
    function formatTime(timestamp) {
        if (!timestamp) return '-';

        var now = Date.now();
        var time = typeof timestamp === 'number' ? timestamp : new Date(timestamp).getTime();
        var diff = now - time;

        if (diff < 60000) return 'Just now';
        if (diff < 3600000) return Math.floor(diff / 60000) + 'm ago';
        if (diff < 86400000) return Math.floor(diff / 3600000) + 'h ago';
        return Math.floor(diff / 86400000) + 'd ago';
    }

    /**
     * Format a duration in milliseconds into MM:SS.
     * @param {number} ms
     * @returns {string}
     */
    function formatDuration(ms) {
        if (!ms || ms <= 0) return '0:00';
        var totalSeconds = Math.ceil(ms / 1000);
        var minutes = Math.floor(totalSeconds / 60);
        var seconds = totalSeconds % 60;
        return minutes + ':' + (seconds < 10 ? '0' : '') + seconds;
    }

    /**
     * Escape HTML to prevent XSS using textContent assignment.
     * @param {string} text
     * @returns {string}
     */
    function escapeHtml(text) {
        if (!text) return '';
        var div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    /**
     * Lighten a hex color by a percentage.
     * @param {string} color - Hex color (#RRGGBB or RRGGBB)
     * @param {number} percent - 0-100
     * @returns {string}
     */
    function lightenColor(color, percent) {
        if (!color) return '#666666';
        var num = parseInt(color.replace('#', ''), 16);
        var amt = Math.round(2.55 * percent);
        var R = (num >> 16) + amt;
        var G = ((num >> 8) & 0x00FF) + amt;
        var B = (num & 0x0000FF) + amt;

        return '#' + (
            0x1000000 +
            (R < 255 ? (R < 0 ? 0 : R) : 255) * 0x10000 +
            (G < 255 ? (G < 0 ? 0 : G) : 255) * 0x100 +
            (B < 255 ? (B < 0 ? 0 : B) : 255)
        ).toString(16).slice(1);
    }

    /**
     * Get a human-readable label for a gang archetype code.
     * @param {string} code
     * @returns {string}
     */
    function getArchetypeLabel(code) {
        var labels = {
            street: 'Street Gang',
            mc: 'Motorcycle Club',
            cartel: 'Drug Cartel',
            crime_family: 'Crime Family',
        };
        return labels[code] || 'Organization';
    }

    /**
     * Get a Font Awesome icon class for a gang archetype code.
     * @param {string} code
     * @returns {string}
     */
    function getArchetypeIcon(code) {
        var icons = {
            street: 'fas fa-fist-raised',
            mc: 'fas fa-motorcycle',
            cartel: 'fas fa-cannabis',
            crime_family: 'fas fa-user-tie',
        };
        return icons[code] || 'fas fa-skull';
    }

    /**
     * Calculate reputation progress percentage towards the next level.
     * @param {number} rep
     * @param {number} level
     * @returns {number} 0-100
     */
    function calculateRepProgress(rep, level) {
        var thresholds = [0, 500, 1500, 3500, 6000, 10000, 15000, 22000, 30000, 50000];
        rep = rep || 0;
        level = level || 1;

        if (level >= 10) return 100;

        var currentThreshold = thresholds[level - 1] || 0;
        var nextThreshold = thresholds[level] || thresholds[thresholds.length - 1];
        var range = nextThreshold - currentThreshold;

        if (range <= 0) return 100;

        var progress = ((rep - currentThreshold) / range) * 100;
        return Math.min(100, Math.max(0, progress));
    }

    /**
     * Get reputation level meta-information.
     * @param {number} level
     * @returns {{ name: string, maxTerritories: number }}
     */
    function getReputationLevelInfo(level) {
        var levels = {
            1:  { name: 'Startup Crew',  maxTerritories: 1 },
            2:  { name: 'Known',         maxTerritories: 2 },
            3:  { name: 'Established',   maxTerritories: 3 },
            4:  { name: 'Respected',     maxTerritories: 4 },
            5:  { name: 'Notorious',     maxTerritories: 5 },
            6:  { name: 'Feared',        maxTerritories: 6 },
            7:  { name: 'Infamous',       maxTerritories: 7 },
            8:  { name: 'Legendary',     maxTerritories: 8 },
            9:  { name: 'Empire',        maxTerritories: 10 },
            10: { name: 'Untouchable',   maxTerritories: -1 },
        };
        return levels[level] || levels[1];
    }

    /**
     * Get the heat stage descriptor for a numeric heat value.
     * @param {number} heat
     * @returns {{ label: string, class: string }}
     */
    function getHeatStage(heat) {
        if (heat >= 85) return { label: 'War Ready', class: 'rivalry' };
        if (heat >= 65) return { label: 'Rivalry',   class: 'rivalry' };
        if (heat >= 50) return { label: 'Cold War',  class: 'tension' };
        if (heat >= 30) return { label: 'Tension',   class: 'tension' };
        return { label: 'Neutral', class: 'neutral' };
    }

    /**
     * Get CSS class for heat bar fill colour.
     * @param {number} heat
     * @returns {string}
     */
    function getHeatClass(heat) {
        if (heat >= 65) return 'high';
        if (heat >= 30) return 'medium';
        return 'low';
    }

    /**
     * Get territory control status label from influence percentage.
     * @param {number} influence
     * @returns {string}
     */
    function getControlStatus(influence) {
        if (influence >= 80) return 'Dominated';
        if (influence >= 51) return 'Controlled';
        if (influence >= 25) return 'Strong Presence';
        if (influence > 0)  return 'Gaining Ground';
        return 'No Presence';
    }

    /**
     * Get a Font Awesome icon class for an activity type.
     * @param {string} type
     * @returns {string}
     */
    function getActivityIcon(type) {
        var icons = {
            join:       'fas fa-user-plus',
            leave:      'fas fa-user-minus',
            kick:       'fas fa-user-times',
            promote:    'fas fa-arrow-up',
            demote:     'fas fa-arrow-down',
            deposit:    'fas fa-money-bill-wave',
            withdraw:   'fas fa-hand-holding-dollar',
            territory:  'fas fa-map-marker-alt',
            war:        'fas fa-crosshairs',
            bribe:      'fas fa-handshake',
            robbery:    'fas fa-mask',
            drug_sale:  'fas fa-cannabis',
            mugging:    'fas fa-user-ninja',
            graffiti:   'fas fa-spray-can',
            protection: 'fas fa-shield-alt',
        };
        return icons[type] || 'fas fa-check-circle';
    }

    /**
     * Get a Font Awesome icon class for a contact type.
     * @param {string} type
     * @returns {string}
     */
    function getContactIcon(type) {
        var icons = {
            police:     'fas fa-badge',
            judge:      'fas fa-gavel',
            lawyer:     'fas fa-balance-scale',
            politician: 'fas fa-landmark',
            mechanic:   'fas fa-wrench',
            doctor:     'fas fa-user-md',
            informant:  'fas fa-eye',
            smuggler:   'fas fa-truck',
            dealer:     'fas fa-pills',
            hacker:     'fas fa-laptop-code',
            fixer:      'fas fa-tools',
        };
        return icons[type] || 'fas fa-address-card';
    }

    // ========================================================================
    // 5. NUI COMMUNICATION (JS <-> Lua)
    // ========================================================================

    /**
     * Send data to the Lua client via NUI callback.
     * @param {string} action
     * @param {object} data
     */
    function nuiCallback(action, data) {
        fetch('https://' + CONFIG.resourceName + '/' + action, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data || {}),
        }).catch(function (err) {
            console.error('[FREE-GANGS] NUI Callback Error:', err);
        });
    }

    /**
     * Window message listener -- dispatches incoming NUI messages.
     */
    window.addEventListener('message', function (event) {
        var data = event.data;
        if (!data || !data.action) return;

        switch (data.action) {
            case 'open':
                openUI(data);
                break;
            case 'close':
                closeUI();
                break;
            case 'updateGangData':
                updateGangData(data.gangData);
                break;
            case 'updateMembers':
                updateMembers(data.members);
                break;
            case 'updateTerritories':
                updateTerritories(data.territories);
                break;
            case 'updateHeat':
                updateHeatData(data.heatData);
                break;
            case 'updateWars':
                updateWars(data.wars);
                break;
            case 'updateTransactions':
                updateTransactions(data.transactions);
                break;
            case 'updateCooldowns':
                updateCooldowns(data);
                break;
            case 'updateOperations':
                updateOperations(data);
                break;
            case 'updateContacts':
                updateContacts(data.contacts);
                break;
            case 'showToast':
                showToast(data.message, data.type);
                break;
            case 'addActivity':
                addActivity(data);
                break;
            default:
                console.log('[FREE-GANGS] Unknown NUI action:', data.action);
        }
    });

    // ========================================================================
    // 6. ROLE-BASED VISIBILITY
    // ========================================================================

    /**
     * Apply role-based visibility rules to all elements carrying the
     * gang-only, officer-only, or boss-only classes.
     *
     * Civilians see neither gang-only, officer-only, nor boss-only.
     * gang_member sees gang-only but NOT officer-only or boss-only.
     * officer sees gang-only and officer-only but NOT boss-only.
     * boss sees everything.
     */
    function applyRoleVisibility(role) {
        State.playerRole = role || 'civilian';

        var isCivilian   = State.playerRole === 'civilian';
        var isGangMember = State.playerRole === 'gang_member';
        var isOfficer    = State.playerRole === 'officer';
        var isBoss       = State.playerRole === 'boss';

        // gang-only: hidden for civilians
        var gangOnly = document.querySelectorAll('.gang-only');
        for (var i = 0; i < gangOnly.length; i++) {
            gangOnly[i].style.display = isCivilian ? 'none' : '';
        }

        // officer-only: hidden for civilians and gang_members
        var officerOnly = document.querySelectorAll('.officer-only');
        for (var j = 0; j < officerOnly.length; j++) {
            officerOnly[j].style.display = (isCivilian || isGangMember) ? 'none' : '';
        }

        // boss-only: hidden for everyone except boss
        var bossOnly = document.querySelectorAll('.boss-only');
        for (var k = 0; k < bossOnly.length; k++) {
            bossOnly[k].style.display = isBoss ? '' : 'none';
        }

        // Also hide nav tabs that the role cannot access; if the current tab
        // is now hidden, fall back to dashboard.
        var visibleTabs = document.querySelectorAll('.nav-tab');
        var currentTabVisible = false;
        for (var t = 0; t < visibleTabs.length; t++) {
            var tab = visibleTabs[t];
            if (tab.style.display !== 'none') {
                if (tab.dataset.tab === State.currentTab) {
                    currentTabVisible = true;
                }
            }
        }

        if (!currentTabVisible) {
            switchTab('dashboard');
        }
    }

    // ========================================================================
    // 7. UI OPEN / CLOSE
    // ========================================================================

    /**
     * Open the gang UI.
     * @param {object} payload - { gangData, playerRole, territories, heatData, wars, members }
     */
    function openUI(payload) {
        if (State.isOpen) return;

        State.isOpen = true;
        Elements.ui.classList.remove('hidden');

        // Apply role before anything else so that visibility is correct
        applyRoleVisibility(payload.playerRole);

        // Populate initial data
        if (payload.gangData) {
            updateGangData(payload.gangData);
        } else if (State.playerRole === 'civilian') {
            // Civilian with no gang data -- set default header
            setCivilianHeader();
        }

        if (payload.members)     updateMembers(payload.members);
        if (payload.territories) updateTerritories(payload.territories);
        if (payload.heatData)    updateHeatData(payload.heatData);
        if (payload.wars)        updateWars(payload.wars);

        // Always reset to dashboard
        switchTab('dashboard');
    }

    /**
     * Close the gang UI.
     */
    function closeUI() {
        if (!State.isOpen) return;

        State.isOpen = false;
        Elements.ui.classList.add('hidden');
        closeModal();

        nuiCallback('close');
    }

    /**
     * Set header defaults for civilian players with no gang.
     */
    function setCivilianHeader() {
        var nameEl = document.getElementById('gangName');
        var archEl = document.getElementById('gangArchetype');
        var lvlEl  = document.getElementById('gangLevel');
        var trsyEl = document.getElementById('gangTreasury');

        if (nameEl) nameEl.textContent = 'The Underworld';
        if (archEl) archEl.textContent = 'Criminal Network';
        if (lvlEl)  lvlEl.textContent = '';
        if (trsyEl) trsyEl.textContent = '';
    }

    // ========================================================================
    // 8. TAB NAVIGATION
    // ========================================================================

    /**
     * Switch to a specified tab.
     * @param {string} tabName
     */
    function switchTab(tabName) {
        State.currentTab = tabName;

        // Update nav active state
        for (var i = 0; i < Elements.navTabs.length; i++) {
            var tab = Elements.navTabs[i];
            if (tab.dataset.tab === tabName) {
                tab.classList.add('active');
            } else {
                tab.classList.remove('active');
            }
        }

        // Show/hide tab content panels
        for (var j = 0; j < Elements.tabContents.length; j++) {
            var content = Elements.tabContents[j];
            if (content.id === tabName + '-tab') {
                content.classList.add('active');
            } else {
                content.classList.remove('active');
            }
        }

        // Request fresh data for the tab from Lua
        nuiCallback('requestTabData', { tab: tabName });
    }

    // ========================================================================
    // 9. DASHBOARD TAB
    // ========================================================================

    /**
     * Set an SVG circular gauge to a given percentage.
     * @param {HTMLElement} el - The <circle> element with class gauge-fill
     * @param {number} pct - 0-100
     */
    function setGauge(el, pct) {
        if (!el) return;
        pct = Math.min(100, Math.max(0, pct || 0));
        el.style.strokeDasharray = CONFIG.gaugeCircumference;
        el.style.strokeDashoffset = CONFIG.gaugeCircumference * (1 - pct / 100);
    }

    /**
     * Refresh all four dashboard gauges based on current State.gangData.
     */
    function refreshDashboardGauges() {
        var d = State.gangData;
        if (!d) {
            // Zero out all gauges for civilians or missing data
            setGauge(document.getElementById('gaugeRep'), 0);
            setGauge(document.getElementById('gaugeMembers'), 0);
            setGauge(document.getElementById('gaugeTerritories'), 0);
            setGauge(document.getElementById('gaugeHeat'), 0);

            setTextSafe('gaugeRepValue', '0');
            setTextSafe('gaugeRepLevel', 'Level 1');
            setTextSafe('gaugeMembersValue', '0');
            setTextSafe('gaugeMembersOnline', '0 online');
            setTextSafe('gaugeTerrValue', '0');
            setTextSafe('gaugeTerrMax', '/ 0 max');
            setTextSafe('gaugeHeatValue', '0');
            setTextSafe('gaugeHeatStage', 'Neutral');
            return;
        }

        var rep             = d.master_rep || 0;
        var level           = d.master_level || 1;
        var memberCount     = d.member_count || 0;
        var onlineMembers   = d.online_members || 0;
        var controlledZones = d.controlled_zones || 0;
        var activeRivalries = d.active_rivalries || 0;
        var levelInfo       = getReputationLevelInfo(level);
        var maxTerr         = levelInfo.maxTerritories === -1 ? 99 : levelInfo.maxTerritories;

        // Rep gauge
        var repPct = calculateRepProgress(rep, level);
        setGauge(document.getElementById('gaugeRep'), repPct);
        setTextSafe('gaugeRepValue', formatNumber(rep));
        setTextSafe('gaugeRepLevel', 'Level ' + level);

        // Members gauge
        var memberPct = (memberCount / CONFIG.maxMembers) * 100;
        setGauge(document.getElementById('gaugeMembers'), memberPct);
        setTextSafe('gaugeMembersValue', String(memberCount));
        setTextSafe('gaugeMembersOnline', onlineMembers + ' online');

        // Territories gauge
        var terrPct = maxTerr > 0 ? (controlledZones / maxTerr) * 100 : 0;
        setGauge(document.getElementById('gaugeTerritories'), terrPct);
        setTextSafe('gaugeTerrValue', String(controlledZones));
        setTextSafe('gaugeTerrMax', '/ ' + (levelInfo.maxTerritories === -1 ? '\u221E' : levelInfo.maxTerritories) + ' max');

        // Heat gauge
        var heatPct = Math.min(100, (activeRivalries / CONFIG.maxHeatRivals) * 100);
        setGauge(document.getElementById('gaugeHeat'), heatPct);
        setTextSafe('gaugeHeatValue', String(activeRivalries));
        var topHeat = getHighestHeat();
        setTextSafe('gaugeHeatStage', getHeatStage(topHeat).label);
    }

    /**
     * Safely set textContent on an element by ID.
     * @param {string} id
     * @param {string} text
     */
    function setTextSafe(id, text) {
        var el = document.getElementById(id);
        if (el) el.textContent = text;
    }

    /**
     * Get the highest heat value across all rivals.
     * @returns {number}
     */
    function getHighestHeat() {
        var max = 0;
        var entries = Object.values(State.heatData);
        for (var i = 0; i < entries.length; i++) {
            var val = entries[i].amount || entries[i] || 0;
            if (typeof val === 'object') val = val.amount || 0;
            if (val > max) max = val;
        }
        return max;
    }

    // ========================================================================
    // 10. OPERATIONS TAB
    // ========================================================================

    /**
     * Update cooldown chips in the cooldowns bar.
     * @param {object} data - keyed by activity name, value { remaining, formatted }
     */
    function updateCooldowns(data) {
        // Merge into state, stripping the 'action' key
        var clean = {};
        for (var key in data) {
            if (data.hasOwnProperty(key) && key !== 'action') {
                clean[key] = data[key];
            }
        }
        State.cooldowns = clean;

        var bar = document.getElementById('cooldownsBar');
        if (!bar) return;
        bar.innerHTML = '';

        var hasActive = false;
        for (var name in State.cooldowns) {
            if (!State.cooldowns.hasOwnProperty(name)) continue;
            var cd = State.cooldowns[name];
            if (!cd || (!cd.remaining && !cd.formatted)) continue;
            hasActive = true;

            var chip = document.createElement('div');
            chip.className = 'cooldown-chip';
            chip.innerHTML = '<i class="fas fa-clock"></i> ' +
                escapeHtml(capitalize(name)) + ' ' +
                escapeHtml(cd.formatted || formatDuration(cd.remaining));
            bar.appendChild(chip);
        }

        bar.style.display = hasActive ? '' : 'none';
    }

    /**
     * Update operations tab data.
     * @param {object} data - { protection, robberyTargets, drugStats, streetStats, graffitiStats }
     */
    function updateOperations(data) {
        if (!data) return;

        // Merge into state
        State.operations = {
            protection:     data.protection || [],
            robberyTargets: data.robberyTargets || [],
            drugStats:      data.drugStats || {},
            streetStats:    data.streetStats || {},
            graffitiStats:  data.graffitiStats || {},
        };

        renderProtectionList();
        renderRobberyTargets();
        renderDrugStats();
        renderStreetStats();
        renderGraffitiStats();

        // Zone indicator
        if (data.currentZone) {
            setTextSafe('opsCurrentZone', data.currentZone);
        }
        if (data.zoneControl != null) {
            setTextSafe('opsZoneControl', data.zoneControl + '%');
        }
    }

    function renderProtectionList() {
        var list = State.operations.protection || [];
        var container = document.getElementById('protectionList');
        if (!container) return;
        container.innerHTML = '';

        setTextSafe('protectionCount', String(list.length));

        if (list.length === 0) {
            container.innerHTML = '<p class="op-empty">No businesses under protection</p>';
            return;
        }

        for (var i = 0; i < list.length; i++) {
            var biz = list[i];
            var row = document.createElement('div');
            row.className = 'op-stat-row';
            row.innerHTML =
                '<span>' + escapeHtml(biz.name || 'Unknown') + '</span>' +
                '<span class="op-stat-value">' +
                    '<span class="op-status-badge ' + (biz.status === 'ready' ? 'ready' : 'cooldown') + '">' +
                        escapeHtml(biz.status || 'ready') +
                    '</span> ' +
                    escapeHtml(formatMoney(biz.payout || 0)) +
                '</span>';
            container.appendChild(row);
        }
    }

    function renderRobberyTargets() {
        var list = State.operations.robberyTargets || [];
        var container = document.getElementById('robberyTargets');
        if (!container) return;
        container.innerHTML = '';

        setTextSafe('robberyCount', String(list.length));

        if (list.length === 0) {
            container.innerHTML = '<p class="op-empty">No robbery targets available</p>';
            return;
        }

        for (var i = 0; i < list.length; i++) {
            var target = list[i];
            var row = document.createElement('div');
            row.className = 'op-stat-row';
            row.innerHTML =
                '<div class="op-target-info">' +
                    '<span class="op-target-name">' + escapeHtml(target.name || 'Unknown') + '</span>' +
                    '<span class="op-target-rival">' + escapeHtml(target.rival || '') + '</span>' +
                '</div>' +
                '<span class="op-stat-value">' +
                    escapeHtml(formatMoney(target.payout || 0)) +
                    ' <small>(' + escapeHtml(String(target.chance || 0)) + '% chance)</small>' +
                '</span>';
            container.appendChild(row);
        }
    }

    function renderDrugStats() {
        var stats = State.operations.drugStats || {};
        setTextSafe('drugSalesToday', formatNumber(stats.salesToday || 0));
        setTextSafe('drugRevenue', formatMoney(stats.revenue || 0));
    }

    function renderStreetStats() {
        var stats = State.operations.streetStats || {};
        setTextSafe('muggingCount', formatNumber(stats.muggings || 0));
        setTextSafe('pickpocketCount', formatNumber(stats.pickpockets || 0));
    }

    function renderGraffitiStats() {
        var stats = State.operations.graffitiStats || {};
        var count = stats.activeTags || 0;
        setTextSafe('graffitiCount', String(count));
        setTextSafe('activeTags', String(count));
    }

    /**
     * Capitalize the first letter of a string.
     * @param {string} str
     * @returns {string}
     */
    function capitalize(str) {
        if (!str) return '';
        return str.charAt(0).toUpperCase() + str.slice(1);
    }

    // ========================================================================
    // 11. TERRITORIES TAB
    // ========================================================================

    /**
     * Update the territories display.
     * @param {object} territories
     */
    function updateTerritories(territories) {
        State.territories = territories || {};

        var container = document.getElementById('territoriesList');
        if (!container) return;
        container.innerHTML = '';

        var gangName  = State.gangData ? State.gangData.name : null;
        var isInGang  = State.playerRole !== 'civilian' && gangName;
        var keys      = Object.keys(State.territories);

        if (keys.length === 0) {
            container.innerHTML = '<p class="no-data">No territories available</p>';
            return;
        }

        for (var i = 0; i < keys.length; i++) {
            var zoneName  = keys[i];
            var territory = State.territories[zoneName];

            var ourInfluence = isInGang ? (territory.influence && territory.influence[gangName] || 0) : 0;
            var isControlled = ourInfluence >= 51;
            var isContested  = ourInfluence > 0 && ourInfluence < 51;

            var card = document.createElement('div');
            card.className = 'territory-card' +
                (isControlled ? ' controlled' : '') +
                (isContested ? ' contested' : '');

            // Build inner HTML
            var html =
                '<div class="territory-header">' +
                    '<span class="territory-name">' + escapeHtml(territory.label || zoneName) + '</span>' +
                    '<span class="territory-type">' + escapeHtml(territory.type || 'Unknown') + '</span>' +
                '</div>' +
                '<div class="territory-influence">';

            if (isInGang) {
                // Our influence bar
                html +=
                    '<div class="influence-bar">' +
                        '<div class="influence-fill" style="width: ' + ourInfluence + '%"></div>' +
                    '</div>' +
                    '<div class="influence-text">' +
                        '<span>Your Influence: ' + ourInfluence + '%</span>' +
                        '<span>' + escapeHtml(getControlStatus(ourInfluence)) + '</span>' +
                    '</div>';

                // Rival gang bars
                if (territory.influence) {
                    var rivalKeys = Object.keys(territory.influence);
                    for (var r = 0; r < rivalKeys.length; r++) {
                        var rivalName = rivalKeys[r];
                        if (rivalName === gangName) continue;
                        var rivalInf = territory.influence[rivalName] || 0;
                        if (rivalInf <= 0) continue;

                        html +=
                            '<div class="rival-influence">' +
                                '<div class="influence-bar rival">' +
                                    '<div class="influence-fill rival" style="width: ' + rivalInf + '%"></div>' +
                                '</div>' +
                                '<div class="influence-text rival-text">' +
                                    '<span>' + escapeHtml(rivalName) + ': ' + rivalInf + '%</span>' +
                                '</div>' +
                            '</div>';
                    }
                }
            } else {
                // Civilian view: just show all factions listed
                if (territory.influence) {
                    var factionKeys = Object.keys(territory.influence);
                    for (var f = 0; f < factionKeys.length; f++) {
                        var fName = factionKeys[f];
                        var fInf  = territory.influence[fName] || 0;
                        if (fInf <= 0) continue;

                        html +=
                            '<div class="influence-bar">' +
                                '<div class="influence-fill" style="width: ' + fInf + '%"></div>' +
                            '</div>' +
                            '<div class="influence-text">' +
                                '<span>' + escapeHtml(fName) + ': ' + fInf + '%</span>' +
                                '<span>' + escapeHtml(getControlStatus(fInf)) + '</span>' +
                            '</div>';
                    }
                }

                // If no factions present
                if (!territory.influence || Object.keys(territory.influence).length === 0) {
                    html +=
                        '<div class="influence-text">' +
                            '<span>Unclaimed</span>' +
                        '</div>';
                }
            }

            html += '</div>'; // close territory-influence

            card.innerHTML = html;
            container.appendChild(card);
        }
    }

    // ========================================================================
    // 12. MEMBERS TAB
    // ========================================================================

    /**
     * Update the members list.
     * @param {Array} members
     */
    function updateMembers(members) {
        State.members = members || [];

        var container = document.getElementById('membersList');
        if (!container) return;
        container.innerHTML = '';

        // Update member count badge
        setTextSafe('memberCountBadge', State.members.length + ' member' + (State.members.length !== 1 ? 's' : ''));

        if (State.members.length === 0) {
            container.innerHTML = '<p class="no-data">No members found</p>';
            return;
        }

        // Sort by rank (highest first), then by online status
        var sorted = State.members.slice().sort(function (a, b) {
            if (b.rank !== a.rank) return b.rank - a.rank;
            if (a.isOnline && !b.isOnline) return -1;
            if (!a.isOnline && b.isOnline) return 1;
            return 0;
        });

        for (var i = 0; i < sorted.length; i++) {
            var member = sorted[i];

            var card = document.createElement('div');
            card.className = 'member-card ' + (member.isOnline ? 'online' : 'offline');

            var actionsHtml = '';
            if (member.canManage) {
                actionsHtml =
                    '<div class="member-actions">' +
                        '<button class="member-action-btn" data-action="promote" data-citizenid="' + escapeHtml(member.citizenid) + '" title="Promote">' +
                            '<i class="fas fa-arrow-up"></i>' +
                        '</button>' +
                        '<button class="member-action-btn" data-action="demote" data-citizenid="' + escapeHtml(member.citizenid) + '" title="Demote">' +
                            '<i class="fas fa-arrow-down"></i>' +
                        '</button>' +
                        '<button class="member-action-btn" data-action="kick" data-citizenid="' + escapeHtml(member.citizenid) + '" title="Kick">' +
                            '<i class="fas fa-user-times"></i>' +
                        '</button>' +
                    '</div>';
            }

            card.innerHTML =
                '<div class="member-avatar">' +
                    '<i class="fas fa-user"></i>' +
                '</div>' +
                '<div class="member-info">' +
                    '<span class="member-name">' + escapeHtml(member.name) + '</span>' +
                    '<span class="member-rank">' + escapeHtml(member.rankName || ('Rank ' + member.rank)) + '</span>' +
                '</div>' +
                '<div class="member-status ' + (member.isOnline ? 'online' : '') + '">' +
                    '<i class="fas fa-circle"></i> ' +
                    (member.isOnline ? 'Online' : 'Offline') +
                '</div>' +
                actionsHtml;

            container.appendChild(card);
        }

        // Bind action buttons via delegation
        var actionBtns = container.querySelectorAll('.member-action-btn');
        for (var b = 0; b < actionBtns.length; b++) {
            actionBtns[b].addEventListener('click', handleMemberAction);
        }
    }

    /**
     * Handle a member management action button click.
     * @param {Event} event
     */
    function handleMemberAction(event) {
        var btn       = event.currentTarget;
        var action    = btn.dataset.action;
        var citizenid = btn.dataset.citizenid;

        var member = null;
        for (var i = 0; i < State.members.length; i++) {
            if (State.members[i].citizenid === citizenid) {
                member = State.members[i];
                break;
            }
        }
        if (!member) return;

        switch (action) {
            case 'promote':
                showModal(
                    'Promote Member',
                    '<p>Promote <strong>' + escapeHtml(member.name) + '</strong> to the next rank?</p>',
                    function () { nuiCallback('promoteMember', { citizenid: citizenid }); }
                );
                break;
            case 'demote':
                showModal(
                    'Demote Member',
                    '<p>Demote <strong>' + escapeHtml(member.name) + '</strong> to a lower rank?</p>',
                    function () { nuiCallback('demoteMember', { citizenid: citizenid }); }
                );
                break;
            case 'kick':
                showModal(
                    'Kick Member',
                    '<p>Are you sure you want to kick <strong>' + escapeHtml(member.name) + '</strong> from the gang?</p>',
                    function () { nuiCallback('kickMember', { citizenid: citizenid }); }
                );
                break;
        }
    }

    /**
     * Filter member cards based on a search string.
     * @param {string} searchTerm
     */
    function filterMembers(searchTerm) {
        var term  = (searchTerm || '').toLowerCase();
        var cards = document.querySelectorAll('.member-card');
        for (var i = 0; i < cards.length; i++) {
            var nameEl = cards[i].querySelector('.member-name');
            var name   = nameEl ? nameEl.textContent.toLowerCase() : '';
            cards[i].style.display = name.indexOf(term) !== -1 ? '' : 'none';
        }
    }

    // ========================================================================
    // 13. WARS & HEAT TAB
    // ========================================================================

    /**
     * Update active wars display.
     * @param {Array} wars
     */
    function updateWars(wars) {
        State.activeWars = wars || [];

        var container = document.getElementById('activeWarsList');
        if (!container) return;
        container.innerHTML = '';

        if (State.activeWars.length === 0) {
            container.innerHTML =
                '<div class="no-data-block">' +
                    '<i class="fas fa-peace"></i>' +
                    '<p>No active wars</p>' +
                '</div>';
            return;
        }

        for (var i = 0; i < State.activeWars.length; i++) {
            var war  = State.activeWars[i];
            var card = document.createElement('div');
            card.className = 'war-card';

            card.innerHTML =
                '<div class="war-header">' +
                    '<span class="war-enemy">VS ' + escapeHtml(war.enemy_gang) + '</span>' +
                    '<span class="war-status">ACTIVE</span>' +
                '</div>' +
                '<div class="war-stats">' +
                    '<div class="war-stat">' +
                        '<span class="war-stat-value">' + (war.our_kills || 0) + '</span>' +
                        '<span class="war-stat-label">Our Kills</span>' +
                    '</div>' +
                    '<div class="war-stat">' +
                        '<span class="war-stat-value">' + (war.enemy_kills || 0) + '</span>' +
                        '<span class="war-stat-label">Enemy Kills</span>' +
                    '</div>' +
                    '<div class="war-stat">' +
                        '<span class="war-stat-value">' + escapeHtml(formatMoney(war.collateral || 0)) + '</span>' +
                        '<span class="war-stat-label">Collateral</span>' +
                    '</div>' +
                '</div>';

            container.appendChild(card);
        }
    }

    /**
     * Update heat data display.
     * @param {object} heatData
     */
    function updateHeatData(heatData) {
        State.heatData = heatData || {};

        var container = document.getElementById('heatList');
        if (!container) return;
        container.innerHTML = '';

        var entries = Object.entries(State.heatData);

        if (entries.length === 0) {
            container.innerHTML =
                '<div class="no-data-block">' +
                    '<i class="fas fa-handshake"></i>' +
                    '<p>No rivalries</p>' +
                '</div>';
            return;
        }

        for (var i = 0; i < entries.length; i++) {
            var gangName  = entries[i][0];
            var heat      = entries[i][1];
            var heatLevel = typeof heat === 'number' ? heat : (heat.amount || 0);
            var stage     = getHeatStage(heatLevel);

            var card = document.createElement('div');
            card.className = 'heat-card';

            card.innerHTML =
                '<span class="heat-gang">' + escapeHtml(gangName) + '</span>' +
                '<div class="heat-bar-container">' +
                    '<div class="heat-bar">' +
                        '<div class="heat-fill ' + getHeatClass(heatLevel) + '" style="width: ' + heatLevel + '%"></div>' +
                    '</div>' +
                '</div>' +
                '<span class="heat-value">' + heatLevel + '/100</span>' +
                '<span class="heat-stage ' + stage.class + '">' + escapeHtml(stage.label) + '</span>';

            container.appendChild(card);
        }

        // Update header heat pip
        var topHeat = getHighestHeat();
        var topStage = getHeatStage(topHeat);
        setTextSafe('headerHeatLabel', topStage.label);
        var pip = document.getElementById('headerHeatPip');
        if (pip) {
            pip.className = 'header-heat-pip ' + topStage.class;
        }
    }

    // ========================================================================
    // 14. CONTACTS TAB
    // ========================================================================

    /**
     * Update the contacts grid.
     * @param {Array} contacts
     */
    function updateContacts(contacts) {
        State.contacts = contacts || [];

        var container = document.getElementById('contactsList');
        if (!container) return;
        container.innerHTML = '';

        if (State.contacts.length === 0) {
            container.innerHTML = '<p class="no-data">No contacts available</p>';
            setTextSafe('weeklyBribeExpense', '$0');
            return;
        }

        var totalWeeklyCost = 0;

        for (var i = 0; i < State.contacts.length; i++) {
            var contact = State.contacts[i];
            totalWeeklyCost += (contact.weeklyCost || 0);

            var statusClass = 'active';
            if (contact.status === 'paused')     statusClass = 'paused';
            if (contact.status === 'terminated') statusClass = 'terminated';

            var card = document.createElement('div');
            card.className = 'contact-card';

            card.innerHTML =
                '<div class="contact-icon">' +
                    '<i class="' + getContactIcon(contact.type) + '"></i>' +
                '</div>' +
                '<div class="contact-info">' +
                    '<span class="contact-name">' + escapeHtml(contact.name || 'Unknown') + '</span>' +
                    '<span class="contact-type">' + escapeHtml(capitalize(contact.type || 'contact')) + '</span>' +
                '</div>' +
                '<span class="contact-status ' + statusClass + '">' +
                    escapeHtml(capitalize(contact.status || 'active')) +
                '</span>' +
                '<div class="contact-details">' +
                    '<span class="contact-cost">' + escapeHtml(formatMoney(contact.weeklyCost || 0)) + '/wk</span>' +
                    (contact.paymentDue
                        ? '<span class="contact-due">Due: ' + escapeHtml(contact.paymentDue) + '</span>'
                        : '') +
                '</div>' +
                (contact.status === 'active'
                    ? '<button class="contact-use-btn" data-contact-id="' + escapeHtml(String(contact.id || i)) + '">Use</button>'
                    : '');

            container.appendChild(card);
        }

        // Bind use buttons
        var useBtns = container.querySelectorAll('.contact-use-btn');
        for (var b = 0; b < useBtns.length; b++) {
            useBtns[b].addEventListener('click', function (e) {
                var contactId = e.currentTarget.dataset.contactId;
                nuiCallback('useContact', { contactId: contactId });
            });
        }

        setTextSafe('weeklyBribeExpense', formatMoney(totalWeeklyCost));
    }

    // ========================================================================
    // 15. TREASURY TAB
    // ========================================================================

    /**
     * Update transactions list.
     * @param {Array} transactions
     */
    function updateTransactions(transactions) {
        State.transactions = transactions || [];

        var container = document.getElementById('transactionList');
        if (!container) return;
        container.innerHTML = '';

        if (State.transactions.length === 0) {
            container.innerHTML =
                '<li class="transaction-item empty">' +
                    '<span class="no-transactions">No recent transactions</span>' +
                '</li>';
            return;
        }

        var items = State.transactions.slice(0, CONFIG.maxTransactions);
        for (var i = 0; i < items.length; i++) {
            var tx = items[i];
            var isPositive = tx.type === 'deposit' || tx.amount > 0;

            var li = document.createElement('li');
            li.className = 'transaction-item';

            li.innerHTML =
                '<div class="transaction-info">' +
                    '<span class="transaction-type">' + escapeHtml(tx.description || tx.type) + '</span>' +
                    '<span class="transaction-by">by ' + escapeHtml(tx.player_name || 'System') + '</span>' +
                '</div>' +
                '<span class="transaction-amount ' + (isPositive ? 'positive' : 'negative') + '">' +
                    (isPositive ? '+' : '-') + formatMoney(Math.abs(tx.amount || 0)) +
                '</span>';

            container.appendChild(li);
        }
    }

    /**
     * Show deposit modal.
     * @param {string} type - 'treasury' or 'warchest'
     */
    function showDepositModal(type) {
        var title = type === 'warchest' ? 'Deposit to War Chest' : 'Deposit to Treasury';
        var content =
            '<label>Amount to deposit:</label>' +
            '<input type="number" class="modal-input" id="depositAmount" min="1" placeholder="Enter amount...">';

        showModal(title, content, function () {
            var input  = document.getElementById('depositAmount');
            var amount = parseInt(input ? input.value : 0, 10);
            if (amount > 0) {
                nuiCallback('deposit', { type: type, amount: amount });
            }
        });
    }

    /**
     * Show withdraw modal.
     */
    function showWithdrawModal() {
        var content =
            '<label>Amount to withdraw:</label>' +
            '<input type="number" class="modal-input" id="withdrawAmount" min="1" placeholder="Enter amount...">';

        showModal('Withdraw from Treasury', content, function () {
            var input  = document.getElementById('withdrawAmount');
            var amount = parseInt(input ? input.value : 0, 10);
            if (amount > 0) {
                nuiCallback('withdraw', { amount: amount });
            }
        });
    }

    // ========================================================================
    // 16. SETTINGS TAB
    // ========================================================================

    /**
     * Populate the Settings tab with current gang data.
     */
    function refreshSettings() {
        var d = State.gangData;
        if (!d) return;

        setTextSafe('settingGangName', d.label || d.name || '-');
        setTextSafe('settingArchetype', getArchetypeLabel(d.archetype));
        setTextSafe('settingLevel', 'Level ' + (d.master_level || 1) + ' - ' + getReputationLevelInfo(d.master_level || 1).name);

        // Rank structure
        var ranksContainer = document.getElementById('ranksList');
        if (ranksContainer && d.ranks) {
            ranksContainer.innerHTML = '';
            var rankKeys = Object.keys(d.ranks).sort(function (a, b) {
                return parseInt(b) - parseInt(a);
            });
            for (var i = 0; i < rankKeys.length; i++) {
                var rank = d.ranks[rankKeys[i]];
                var row  = document.createElement('div');
                row.className = 'setting-row';
                row.innerHTML =
                    '<label>Rank ' + escapeHtml(rankKeys[i]) + '</label>' +
                    '<span class="setting-value">' + escapeHtml(typeof rank === 'string' ? rank : (rank.name || rank.label || rankKeys[i])) + '</span>';
                ranksContainer.appendChild(row);
            }
        }
    }

    // ========================================================================
    // 17. MODAL SYSTEM
    // ========================================================================

    /** Current confirm callback for modal */
    var _modalOnConfirm = null;
    var _modalOnCancel  = null;

    /**
     * Show a modal dialog.
     * @param {string}   title
     * @param {string}   bodyHtml
     * @param {function} [onConfirm]
     * @param {function} [onCancel]
     */
    function showModal(title, bodyHtml, onConfirm, onCancel) {
        Elements.modalTitle.textContent = title;
        Elements.modalBody.innerHTML    = bodyHtml;
        Elements.modalOverlay.classList.remove('hidden');

        _modalOnConfirm = onConfirm || null;
        _modalOnCancel  = onCancel  || null;

        // Focus the first input inside the modal body, if any
        var firstInput = Elements.modalBody.querySelector('input');
        if (firstInput) {
            setTimeout(function () { firstInput.focus(); }, 50);
        }
    }

    /**
     * Close the modal.
     */
    function closeModal() {
        Elements.modalOverlay.classList.add('hidden');
        _modalOnConfirm = null;
        _modalOnCancel  = null;
    }

    /**
     * Handle modal confirm click.
     */
    function handleModalConfirm() {
        if (_modalOnConfirm) _modalOnConfirm();
        closeModal();
    }

    /**
     * Handle modal cancel click.
     */
    function handleModalCancel() {
        if (_modalOnCancel) _modalOnCancel();
        closeModal();
    }

    // ========================================================================
    // 18. TOAST NOTIFICATIONS
    // ========================================================================

    /**
     * Show a toast notification.
     * @param {string} message
     * @param {string} type - 'success' | 'error' | 'warning' | 'info'
     */
    function showToast(message, type) {
        type = type || 'info';

        var iconMap = {
            success: 'fa-check-circle',
            error:   'fa-times-circle',
            warning: 'fa-exclamation-triangle',
            info:    'fa-info-circle',
        };

        var toast = document.createElement('div');
        toast.className = 'toast ' + type;

        toast.innerHTML =
            '<span class="toast-icon"><i class="fas ' + (iconMap[type] || iconMap.info) + '"></i></span>' +
            '<span class="toast-message">' + escapeHtml(message) + '</span>' +
            '<button class="toast-close"><i class="fas fa-times"></i></button>';

        Elements.toastContainer.appendChild(toast);

        // Close button
        toast.querySelector('.toast-close').addEventListener('click', function () {
            removeToast(toast);
        });

        // Auto-remove
        setTimeout(function () {
            removeToast(toast);
        }, CONFIG.toastDuration);
    }

    /**
     * Remove a toast with a slide-out animation.
     * @param {HTMLElement} toast
     */
    function removeToast(toast) {
        if (!toast || !toast.parentNode) return;
        toast.style.animation = 'slideOut 0.3s ease forwards';
        setTimeout(function () {
            if (toast.parentNode) toast.parentNode.removeChild(toast);
        }, 300);
    }

    // ========================================================================
    // 19. ACTIVITY FEED
    // ========================================================================

    /**
     * Add an activity to the dashboard feed.
     * @param {object} activity - { type, message, timestamp }
     */
    function addActivity(activity) {
        if (!activity || !activity.message) return;

        State.activities.unshift({
            type:      activity.type || 'default',
            message:   activity.message,
            timestamp: activity.timestamp || Date.now(),
        });

        // Trim to max
        if (State.activities.length > CONFIG.maxActivityItems) {
            State.activities = State.activities.slice(0, CONFIG.maxActivityItems);
        }

        renderActivityFeed();
    }

    /**
     * Render the entire activity feed from State.activities.
     */
    function renderActivityFeed() {
        var container = document.getElementById('activityList');
        if (!container) return;
        container.innerHTML = '';

        if (State.activities.length === 0) {
            container.innerHTML =
                '<li class="activity-item empty">' +
                    '<span class="activity-text">No recent activity</span>' +
                '</li>';
            return;
        }

        for (var i = 0; i < State.activities.length; i++) {
            var act = State.activities[i];
            var li  = document.createElement('li');
            li.className = 'activity-item';

            li.innerHTML =
                '<span class="activity-icon"><i class="' + getActivityIcon(act.type) + '"></i></span>' +
                '<span class="activity-text">' + escapeHtml(act.message) + '</span>' +
                '<span class="activity-time">' + formatTime(act.timestamp) + '</span>';

            container.appendChild(li);
        }
    }

    // ========================================================================
    // DATA UPDATE: GANG DATA (header + gauges)
    // ========================================================================

    /**
     * Update gang data across the entire UI.
     * @param {object} data
     */
    function updateGangData(data) {
        if (!data) return;

        State.gangData = data;

        // --- Header ---
        if (State.playerRole === 'civilian') {
            setTextSafe('gangName', 'The Underworld');
            setTextSafe('gangArchetype', 'Criminal Network');
            setTextSafe('gangLevel', '');
            setTextSafe('gangTreasury', '');
        } else {
            setTextSafe('gangName', data.label || 'Gang Operations');
            setTextSafe('gangArchetype', getArchetypeLabel(data.archetype));
            setTextSafe('gangLevel', 'Level ' + (data.master_level || 1));
            setTextSafe('gangTreasury', formatMoney(data.treasury || 0));
        }

        // Update emblem icon based on archetype
        var emblemIcon = document.getElementById('emblemIcon');
        if (emblemIcon && data.archetype) {
            emblemIcon.className = getArchetypeIcon(data.archetype);
        }

        // Update emblem colour based on gang colour
        if (data.color) {
            var emblem = document.querySelector('.gang-emblem');
            if (emblem) {
                emblem.style.background =
                    'linear-gradient(135deg, ' + data.color + ' 0%, ' + lightenColor(data.color, 20) + ' 100%)';
            }
        }

        // Treasury tab balances
        setTextSafe('treasuryBalance', formatMoney(data.treasury || 0));
        setTextSafe('warChestBalance', formatMoney(data.war_chest || 0));

        // Refresh gauges
        refreshDashboardGauges();

        // Refresh settings if data is available
        refreshSettings();
    }

    // ========================================================================
    // 20. EVENT LISTENERS
    // ========================================================================

    // --- Close button ---
    if (Elements.closeBtn) {
        Elements.closeBtn.addEventListener('click', closeUI);
    }

    // --- ESC key ---
    document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && State.isOpen) {
            if (!Elements.modalOverlay.classList.contains('hidden')) {
                closeModal();
            } else {
                closeUI();
            }
        }
    });

    // --- Tab navigation ---
    for (var t = 0; t < Elements.navTabs.length; t++) {
        (function (tab) {
            tab.addEventListener('click', function () {
                switchTab(tab.dataset.tab);
            });
        })(Elements.navTabs[t]);
    }

    // --- Modal controls ---
    if (Elements.modalClose) {
        Elements.modalClose.addEventListener('click', closeModal);
    }
    if (Elements.modalCancel) {
        Elements.modalCancel.addEventListener('click', handleModalCancel);
    }
    if (Elements.modalConfirm) {
        Elements.modalConfirm.addEventListener('click', handleModalConfirm);
    }
    if (Elements.modalOverlay) {
        Elements.modalOverlay.addEventListener('click', function (e) {
            if (e.target === Elements.modalOverlay) {
                closeModal();
            }
        });
    }

    // --- Quick action: Invite ---
    var btnInvite = document.getElementById('btnInvite');
    if (btnInvite) {
        btnInvite.addEventListener('click', function () {
            var content =
                '<label>Player ID to invite:</label>' +
                '<input type="number" class="modal-input" id="invitePlayerId" min="1" placeholder="Enter server ID...">';

            showModal('Invite Member', content, function () {
                var input    = document.getElementById('invitePlayerId');
                var playerId = parseInt(input ? input.value : 0, 10);
                if (playerId > 0) {
                    nuiCallback('inviteMember', { playerId: playerId });
                }
            });
        });
    }

    // --- Quick action: Deposit ---
    var btnDeposit = document.getElementById('btnDeposit');
    if (btnDeposit) {
        btnDeposit.addEventListener('click', function () {
            showDepositModal('treasury');
        });
    }

    // --- Quick action: Stash ---
    var btnStash = document.getElementById('btnStash');
    if (btnStash) {
        btnStash.addEventListener('click', function () {
            nuiCallback('openStash', {});
        });
    }

    // --- Quick action: War Chest ---
    var btnWarChest = document.getElementById('btnWarChest');
    if (btnWarChest) {
        btnWarChest.addEventListener('click', function () {
            showDepositModal('warchest');
        });
    }

    // --- Treasury: Deposit ---
    var btnTreasuryDeposit = document.getElementById('btnTreasuryDeposit');
    if (btnTreasuryDeposit) {
        btnTreasuryDeposit.addEventListener('click', function () {
            showDepositModal('treasury');
        });
    }

    // --- Treasury: Withdraw ---
    var btnTreasuryWithdraw = document.getElementById('btnTreasuryWithdraw');
    if (btnTreasuryWithdraw) {
        btnTreasuryWithdraw.addEventListener('click', showWithdrawModal);
    }

    // --- Treasury: War Chest Deposit ---
    var btnWarChestDeposit = document.getElementById('btnWarChestDeposit');
    if (btnWarChestDeposit) {
        btnWarChestDeposit.addEventListener('click', function () {
            showDepositModal('warchest');
        });
    }

    // --- Member search ---
    var memberSearchInput = document.getElementById('memberSearch');
    if (memberSearchInput) {
        memberSearchInput.addEventListener('input', function (e) {
            filterMembers(e.target.value);
        });
    }

    // --- Settings: Open stash ---
    var btnOpenStash = document.getElementById('btnOpenStash');
    if (btnOpenStash) {
        btnOpenStash.addEventListener('click', function () {
            nuiCallback('openStash', {});
        });
    }

    // ========================================================================
    // 21. INITIALIZATION
    // ========================================================================

    console.log('[FREE-GANGS] NUI v2.0 Initialized');

})();
