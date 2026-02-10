/**
 * FREE-GANGS NUI Application
 * 
 * Handles all client-side UI interactions, NUI callbacks,
 * and communication with the Lua client scripts.
 */

(function() {
    'use strict';

    // ============================================================================
    // CONFIGURATION
    // ============================================================================
    
    const CONFIG = {
        resourceName: 'free-gangs',
        toastDuration: 5000,
        animationDuration: 300,
    };

    // ============================================================================
    // STATE MANAGEMENT
    // ============================================================================
    
    const State = {
        isOpen: false,
        currentTab: 'dashboard',
        gangData: null,
        members: [],
        territories: {},
        heatData: {},
        activeWars: [],
        transactions: [],
    };

    // ============================================================================
    // DOM ELEMENTS
    // ============================================================================
    
    const Elements = {
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

    // ============================================================================
    // NUI COMMUNICATION
    // ============================================================================
    
    /**
     * Send data to the Lua client
     * @param {string} action - Action name
     * @param {object} data - Data to send
     */
    function nuiCallback(action, data = {}) {
        fetch(`https://${CONFIG.resourceName}/${action}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data),
        }).catch(err => console.error('[FREE-GANGS] NUI Callback Error:', err));
    }

    /**
     * Handle incoming NUI messages
     */
    window.addEventListener('message', function(event) {
        const data = event.data;
        
        switch (data.action) {
            case 'open':
                openUI(data.gangData);
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
            case 'showToast':
                showToast(data.message, data.type);
                break;
            case 'addActivity':
                addActivity(data.activity);
                break;
            default:
                console.log('[FREE-GANGS] Unknown NUI action:', data.action);
        }
    });

    // ============================================================================
    // UI OPEN/CLOSE
    // ============================================================================
    
    /**
     * Open the gang UI
     * @param {object} gangData - Initial gang data
     */
    function openUI(gangData = null) {
        if (State.isOpen) return;
        
        State.isOpen = true;
        Elements.ui.classList.remove('hidden');
        
        if (gangData) {
            updateGangData(gangData);
        }
        
        // Reset to dashboard tab
        switchTab('dashboard');
    }

    /**
     * Close the gang UI
     */
    function closeUI() {
        if (!State.isOpen) return;
        
        State.isOpen = false;
        Elements.ui.classList.add('hidden');
        closeModal();
        
        nuiCallback('close');
    }

    // ============================================================================
    // TAB NAVIGATION
    // ============================================================================
    
    /**
     * Switch to a different tab
     * @param {string} tabName - Name of the tab to switch to
     */
    function switchTab(tabName) {
        State.currentTab = tabName;
        
        // Update nav tabs
        Elements.navTabs.forEach(tab => {
            tab.classList.toggle('active', tab.dataset.tab === tabName);
        });
        
        // Update tab content
        Elements.tabContents.forEach(content => {
            content.classList.toggle('active', content.id === `${tabName}-tab`);
        });
        
        // Request fresh data for the tab
        nuiCallback('requestTabData', { tab: tabName });
    }

    // ============================================================================
    // DATA UPDATE HANDLERS
    // ============================================================================
    
    /**
     * Update gang data display
     * @param {object} data - Gang data
     */
    function updateGangData(data) {
        if (!data) return;
        
        State.gangData = data;
        
        // Update header
        document.getElementById('gangName').textContent = data.label || 'Gang Operations';
        document.getElementById('gangArchetype').textContent = getArchetypeLabel(data.archetype);
        document.getElementById('gangLevel').textContent = `Level ${data.master_level || 1}`;
        document.getElementById('gangTreasury').textContent = formatMoney(data.treasury || 0);
        
        // Update dashboard stats
        document.getElementById('statRep').textContent = formatNumber(data.master_rep || 0);
        document.getElementById('statMembers').textContent = data.member_count || 0;
        document.getElementById('statTerritories').textContent = data.controlled_zones || 0;
        document.getElementById('statRivalries').textContent = data.active_rivalries || 0;
        
        // Update progress bar
        const repProgress = calculateRepProgress(data.master_rep, data.master_level);
        document.getElementById('repProgress').style.width = `${repProgress}%`;
        
        // Update max territories
        const levelInfo = getReputationLevelInfo(data.master_level);
        document.getElementById('maxTerritories').textContent = 
            levelInfo.maxTerritories === -1 ? '∞' : levelInfo.maxTerritories;
        document.getElementById('membersOnline').textContent = data.online_members || 0;
        
        // Update treasury tab
        document.getElementById('treasuryBalance').textContent = formatMoney(data.treasury || 0);
        document.getElementById('warChestBalance').textContent = formatMoney(data.war_chest || 0);
        
        // Update emblem color based on gang color
        if (data.color) {
            document.querySelector('.gang-emblem').style.background = 
                `linear-gradient(135deg, ${data.color} 0%, ${lightenColor(data.color, 20)} 100%)`;
        }
    }

    /**
     * Update members list
     * @param {array} members - Array of member objects
     */
    function updateMembers(members) {
        State.members = members || [];
        
        const container = document.getElementById('membersList');
        container.innerHTML = '';
        
        if (State.members.length === 0) {
            container.innerHTML = '<p class="no-data">No members found</p>';
            return;
        }
        
        // Sort by rank (highest first)
        const sortedMembers = [...State.members].sort((a, b) => b.rank - a.rank);
        
        sortedMembers.forEach(member => {
            const card = document.createElement('div');
            card.className = `member-card ${member.isOnline ? 'online' : 'offline'}`;
            
            card.innerHTML = `
                <div class="member-avatar">
                    <i class="fas fa-user"></i>
                </div>
                <div class="member-info">
                    <span class="member-name">${escapeHtml(member.name)}</span>
                    <span class="member-rank">${escapeHtml(member.rankName || `Rank ${member.rank}`)}</span>
                </div>
                <div class="member-status ${member.isOnline ? 'online' : ''}">
                    <i class="fas fa-circle"></i>
                    ${member.isOnline ? 'Online' : 'Offline'}
                </div>
                ${member.canManage ? `
                    <div class="member-actions">
                        <button class="member-action-btn" data-action="promote" data-citizenid="${member.citizenid}" title="Promote">
                            <i class="fas fa-arrow-up"></i>
                        </button>
                        <button class="member-action-btn" data-action="demote" data-citizenid="${member.citizenid}" title="Demote">
                            <i class="fas fa-arrow-down"></i>
                        </button>
                        <button class="member-action-btn" data-action="kick" data-citizenid="${member.citizenid}" title="Kick">
                            <i class="fas fa-user-times"></i>
                        </button>
                    </div>
                ` : ''}
            `;
            
            container.appendChild(card);
        });
        
        // Add event listeners for member actions
        container.querySelectorAll('.member-action-btn').forEach(btn => {
            btn.addEventListener('click', handleMemberAction);
        });
    }

    /**
     * Update territories display
     * @param {object} territories - Territory data object
     */
    function updateTerritories(territories) {
        State.territories = territories || {};
        
        const container = document.getElementById('territoriesList');
        container.innerHTML = '';
        
        const gangName = State.gangData?.name;
        
        Object.entries(State.territories).forEach(([zoneName, territory]) => {
            const ourInfluence = gangName ? (territory.influence?.[gangName] || 0) : 0;
            const isControlled = ourInfluence >= 51;
            const isContested = ourInfluence > 0 && ourInfluence < 51;
            
            const card = document.createElement('div');
            card.className = `territory-card ${isControlled ? 'controlled' : isContested ? 'contested' : ''}`;
            
            card.innerHTML = `
                <div class="territory-header">
                    <span class="territory-name">${escapeHtml(territory.label || zoneName)}</span>
                    <span class="territory-type">${escapeHtml(territory.type || 'Unknown')}</span>
                </div>
                <div class="territory-influence">
                    <div class="influence-bar">
                        <div class="influence-fill" style="width: ${ourInfluence}%"></div>
                    </div>
                    <div class="influence-text">
                        <span>Your Influence: ${ourInfluence}%</span>
                        <span>${getControlStatus(ourInfluence)}</span>
                    </div>
                </div>
            `;
            
            container.appendChild(card);
        });
        
        if (Object.keys(State.territories).length === 0) {
            container.innerHTML = '<p class="no-data">No territories available</p>';
        }
    }

    /**
     * Update heat data display
     * @param {object} heatData - Heat levels with other gangs
     */
    function updateHeatData(heatData) {
        State.heatData = heatData || {};
        
        const container = document.getElementById('heatList');
        container.innerHTML = '';
        
        const entries = Object.entries(State.heatData);
        
        if (entries.length === 0) {
            container.innerHTML = '<p class="no-data">No rivalries</p>';
            return;
        }
        
        entries.forEach(([gangName, heat]) => {
            const heatLevel = heat.amount || 0;
            const stage = getHeatStage(heatLevel);
            
            const card = document.createElement('div');
            card.className = 'heat-card';
            
            card.innerHTML = `
                <span class="heat-gang">${escapeHtml(gangName)}</span>
                <div class="heat-bar-container">
                    <div class="heat-bar">
                        <div class="heat-fill ${getHeatClass(heatLevel)}" style="width: ${heatLevel}%"></div>
                    </div>
                </div>
                <span class="heat-value">${heatLevel}/100</span>
                <span class="heat-stage ${stage.class}">${stage.label}</span>
            `;
            
            container.appendChild(card);
        });
        
        // Update stat
        document.getElementById('statRivalries').textContent = entries.length;
    }

    /**
     * Update active wars display
     * @param {array} wars - Array of active war objects
     */
    function updateWars(wars) {
        State.activeWars = wars || [];
        
        const container = document.getElementById('activeWarsList');
        container.innerHTML = '';
        
        if (State.activeWars.length === 0) {
            container.innerHTML = `
                <div class="no-wars">
                    <i class="fas fa-peace"></i>
                    <p>No active wars</p>
                </div>
            `;
            return;
        }
        
        State.activeWars.forEach(war => {
            const card = document.createElement('div');
            card.className = 'war-card';
            
            card.innerHTML = `
                <div class="war-header">
                    <span class="war-enemy">VS ${escapeHtml(war.enemy_gang)}</span>
                    <span class="war-status">ACTIVE</span>
                </div>
                <div class="war-stats">
                    <div class="war-stat">
                        <span class="war-stat-value">${war.our_kills || 0}</span>
                        <span class="war-stat-label">Our Kills</span>
                    </div>
                    <div class="war-stat">
                        <span class="war-stat-value">${war.enemy_kills || 0}</span>
                        <span class="war-stat-label">Enemy Kills</span>
                    </div>
                    <div class="war-stat">
                        <span class="war-stat-value">${formatMoney(war.collateral || 0)}</span>
                        <span class="war-stat-label">Collateral</span>
                    </div>
                </div>
            `;
            
            container.appendChild(card);
        });
    }

    /**
     * Update transactions list
     * @param {array} transactions - Array of transaction objects
     */
    function updateTransactions(transactions) {
        State.transactions = transactions || [];
        
        const container = document.getElementById('transactionList');
        container.innerHTML = '';
        
        if (State.transactions.length === 0) {
            container.innerHTML = '<li class="transaction-item"><span class="no-transactions">No recent transactions</span></li>';
            return;
        }
        
        State.transactions.slice(0, 20).forEach(tx => {
            const li = document.createElement('li');
            li.className = 'transaction-item';
            
            const isPositive = tx.type === 'deposit' || tx.amount > 0;
            
            li.innerHTML = `
                <div class="transaction-info">
                    <span class="transaction-type">${escapeHtml(tx.description || tx.type)}</span>
                    <span class="transaction-by">by ${escapeHtml(tx.player_name || 'System')}</span>
                </div>
                <span class="transaction-amount ${isPositive ? 'positive' : 'negative'}">
                    ${isPositive ? '+' : ''}${formatMoney(tx.amount)}
                </span>
            `;
            
            container.appendChild(li);
        });
    }

    /**
     * Add activity to the feed
     * @param {object} activity - Activity data
     */
    function addActivity(activity) {
        const container = document.getElementById('activityList');
        
        // Remove "no activity" placeholder if present
        const placeholder = container.querySelector('.no-activity');
        if (placeholder) placeholder.remove();
        
        const li = document.createElement('li');
        li.className = 'activity-item';
        
        li.innerHTML = `
            <span class="activity-icon"><i class="${getActivityIcon(activity.type)}"></i></span>
            <span class="activity-text">${escapeHtml(activity.message)}</span>
            <span class="activity-time">${formatTime(activity.timestamp)}</span>
        `;
        
        container.insertBefore(li, container.firstChild);
        
        // Limit to 20 items
        while (container.children.length > 20) {
            container.removeChild(container.lastChild);
        }
    }

    // ============================================================================
    // MODAL HANDLERS
    // ============================================================================
    
    /**
     * Show a modal dialog
     * @param {string} title - Modal title
     * @param {string} content - HTML content
     * @param {function} onConfirm - Confirm callback
     * @param {function} onCancel - Cancel callback
     */
    function showModal(title, content, onConfirm = null, onCancel = null) {
        Elements.modalTitle.textContent = title;
        Elements.modalBody.innerHTML = content;
        Elements.modalOverlay.classList.remove('hidden');
        
        Elements.modalConfirm.onclick = () => {
            if (onConfirm) onConfirm();
            closeModal();
        };
        
        Elements.modalCancel.onclick = () => {
            if (onCancel) onCancel();
            closeModal();
        };
    }

    /**
     * Close the modal
     */
    function closeModal() {
        Elements.modalOverlay.classList.add('hidden');
    }

    /**
     * Show deposit modal
     * @param {string} type - 'treasury' or 'warchest'
     */
    function showDepositModal(type) {
        const title = type === 'warchest' ? 'Deposit to War Chest' : 'Deposit to Treasury';
        const content = `
            <label>Amount to deposit:</label>
            <input type="number" class="modal-input" id="depositAmount" min="1" placeholder="Enter amount...">
        `;
        
        showModal(title, content, () => {
            const amount = parseInt(document.getElementById('depositAmount').value);
            if (amount > 0) {
                nuiCallback('deposit', { type, amount });
            }
        });
    }

    /**
     * Show withdraw modal
     */
    function showWithdrawModal() {
        const content = `
            <label>Amount to withdraw:</label>
            <input type="number" class="modal-input" id="withdrawAmount" min="1" placeholder="Enter amount...">
        `;
        
        showModal('Withdraw from Treasury', content, () => {
            const amount = parseInt(document.getElementById('withdrawAmount').value);
            if (amount > 0) {
                nuiCallback('withdraw', { amount });
            }
        });
    }

    // ============================================================================
    // TOAST NOTIFICATIONS
    // ============================================================================
    
    /**
     * Show a toast notification
     * @param {string} message - Toast message
     * @param {string} type - 'success', 'error', 'warning', 'info'
     */
    function showToast(message, type = 'info') {
        const toast = document.createElement('div');
        toast.className = `toast ${type}`;
        
        const icons = {
            success: 'fa-check-circle',
            error: 'fa-times-circle',
            warning: 'fa-exclamation-triangle',
            info: 'fa-info-circle',
        };
        
        toast.innerHTML = `
            <span class="toast-icon"><i class="fas ${icons[type] || icons.info}"></i></span>
            <span class="toast-message">${escapeHtml(message)}</span>
            <button class="toast-close"><i class="fas fa-times"></i></button>
        `;
        
        Elements.toastContainer.appendChild(toast);
        
        // Close button
        toast.querySelector('.toast-close').onclick = () => removeToast(toast);
        
        // Auto remove
        setTimeout(() => removeToast(toast), CONFIG.toastDuration);
    }

    /**
     * Remove a toast with animation
     * @param {HTMLElement} toast - Toast element
     */
    function removeToast(toast) {
        toast.style.animation = 'slideOut 0.3s ease forwards';
        setTimeout(() => toast.remove(), 300);
    }

    // ============================================================================
    // MEMBER ACTIONS
    // ============================================================================
    
    /**
     * Handle member action button click
     * @param {Event} event - Click event
     */
    function handleMemberAction(event) {
        const btn = event.currentTarget;
        const action = btn.dataset.action;
        const citizenid = btn.dataset.citizenid;
        
        const member = State.members.find(m => m.citizenid === citizenid);
        if (!member) return;
        
        switch (action) {
            case 'promote':
                showModal(
                    'Promote Member',
                    `<p>Promote <strong>${escapeHtml(member.name)}</strong> to the next rank?</p>`,
                    () => nuiCallback('promoteMember', { citizenid })
                );
                break;
            case 'demote':
                showModal(
                    'Demote Member',
                    `<p>Demote <strong>${escapeHtml(member.name)}</strong> to a lower rank?</p>`,
                    () => nuiCallback('demoteMember', { citizenid })
                );
                break;
            case 'kick':
                showModal(
                    'Kick Member',
                    `<p>Are you sure you want to kick <strong>${escapeHtml(member.name)}</strong> from the gang?</p>`,
                    () => nuiCallback('kickMember', { citizenid })
                );
                break;
        }
    }

    // ============================================================================
    // UTILITY FUNCTIONS
    // ============================================================================
    
    /**
     * Format number with commas
     * @param {number} num - Number to format
     * @returns {string} Formatted number
     */
    function formatNumber(num) {
        return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    /**
     * Format money with $ and commas
     * @param {number} amount - Amount to format
     * @returns {string} Formatted money string
     */
    function formatMoney(amount) {
        return '$' + formatNumber(amount);
    }

    /**
     * Format timestamp to relative time
     * @param {number|string} timestamp - Timestamp
     * @returns {string} Relative time string
     */
    function formatTime(timestamp) {
        if (!timestamp) return '-';
        
        const now = Date.now();
        const time = typeof timestamp === 'number' ? timestamp : new Date(timestamp).getTime();
        const diff = now - time;
        
        if (diff < 60000) return 'Just now';
        if (diff < 3600000) return Math.floor(diff / 60000) + 'm ago';
        if (diff < 86400000) return Math.floor(diff / 3600000) + 'h ago';
        return Math.floor(diff / 86400000) + 'd ago';
    }

    /**
     * Escape HTML to prevent XSS
     * @param {string} text - Text to escape
     * @returns {string} Escaped text
     */
    function escapeHtml(text) {
        if (!text) return '';
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    /**
     * Lighten a hex color
     * @param {string} color - Hex color
     * @param {number} percent - Percentage to lighten
     * @returns {string} Lightened hex color
     */
    function lightenColor(color, percent) {
        const num = parseInt(color.replace('#', ''), 16);
        const amt = Math.round(2.55 * percent);
        const R = (num >> 16) + amt;
        const G = (num >> 8 & 0x00FF) + amt;
        const B = (num & 0x0000FF) + amt;
        
        return '#' + (
            0x1000000 +
            (R < 255 ? (R < 1 ? 0 : R) : 255) * 0x10000 +
            (G < 255 ? (G < 1 ? 0 : G) : 255) * 0x100 +
            (B < 255 ? (B < 1 ? 0 : B) : 255)
        ).toString(16).slice(1);
    }

    /**
     * Get archetype display label
     * @param {string} archetype - Archetype code
     * @returns {string} Display label
     */
    function getArchetypeLabel(archetype) {
        const labels = {
            street: 'Street Gang',
            mc: 'Motorcycle Club',
            cartel: 'Drug Cartel',
            crime_family: 'Crime Family',
        };
        return labels[archetype] || 'Organization';
    }

    /**
     * Calculate reputation progress percentage to next level
     * @param {number} rep - Current reputation
     * @param {number} level - Current level
     * @returns {number} Progress percentage
     */
    function calculateRepProgress(rep, level) {
        const levels = [0, 500, 1500, 3500, 6000, 10000, 15000, 22000, 30000, 50000];
        const currentThreshold = levels[level - 1] || 0;
        const nextThreshold = levels[level] || levels[levels.length - 1];
        
        if (level >= 10) return 100;
        
        const progress = ((rep - currentThreshold) / (nextThreshold - currentThreshold)) * 100;
        return Math.min(100, Math.max(0, progress));
    }

    /**
     * Get reputation level info
     * @param {number} level - Level number
     * @returns {object} Level info
     */
    function getReputationLevelInfo(level) {
        const levels = {
            1: { name: 'Startup Crew', maxTerritories: 1 },
            2: { name: 'Known', maxTerritories: 2 },
            3: { name: 'Established', maxTerritories: 3 },
            4: { name: 'Respected', maxTerritories: 4 },
            5: { name: 'Notorious', maxTerritories: 5 },
            6: { name: 'Feared', maxTerritories: 6 },
            7: { name: 'Infamous', maxTerritories: 7 },
            8: { name: 'Legendary', maxTerritories: 8 },
            9: { name: 'Empire', maxTerritories: 10 },
            10: { name: 'Untouchable', maxTerritories: -1 },
        };
        return levels[level] || levels[1];
    }

    /**
     * Get heat stage info
     * @param {number} heat - Heat level
     * @returns {object} Stage info
     */
    function getHeatStage(heat) {
        if (heat >= 85) return { label: 'War Ready', class: 'rivalry' };
        if (heat >= 65) return { label: 'Rivalry', class: 'rivalry' };
        if (heat >= 50) return { label: 'Cold War', class: 'tension' };
        if (heat >= 30) return { label: 'Tension', class: 'tension' };
        return { label: 'Neutral', class: 'neutral' };
    }

    /**
     * Get heat bar class based on level
     * @param {number} heat - Heat level
     * @returns {string} CSS class
     */
    function getHeatClass(heat) {
        if (heat >= 65) return 'high';
        if (heat >= 30) return 'medium';
        return 'low';
    }

    /**
     * Get territory control status text
     * @param {number} influence - Influence percentage
     * @returns {string} Status text
     */
    function getControlStatus(influence) {
        if (influence >= 80) return 'Dominated';
        if (influence >= 51) return 'Controlled';
        if (influence >= 25) return 'Strong Presence';
        if (influence > 0) return 'Gaining Ground';
        return 'No Presence';
    }

    /**
     * Get activity icon based on type
     * @param {string} type - Activity type
     * @returns {string} Font Awesome class
     */
    function getActivityIcon(type) {
        const icons = {
            join: 'fas fa-user-plus',
            leave: 'fas fa-user-minus',
            kick: 'fas fa-user-times',
            promote: 'fas fa-arrow-up',
            demote: 'fas fa-arrow-down',
            deposit: 'fas fa-money-bill-wave',
            withdraw: 'fas fa-hand-holding-dollar',
            territory: 'fas fa-map-marker-alt',
            war: 'fas fa-crosshairs',
            bribe: 'fas fa-handshake',
            default: 'fas fa-check-circle',
        };
        return icons[type] || icons.default;
    }

    // ============================================================================
    // EVENT LISTENERS
    // ============================================================================
    
    // Close button
    Elements.closeBtn.addEventListener('click', closeUI);
    
    // Modal close
    Elements.modalClose.addEventListener('click', closeModal);
    Elements.modalOverlay.addEventListener('click', (e) => {
        if (e.target === Elements.modalOverlay) closeModal();
    });
    
    // Tab navigation
    Elements.navTabs.forEach(tab => {
        tab.addEventListener('click', () => switchTab(tab.dataset.tab));
    });
    
    // Quick action buttons
    document.getElementById('btnInvite')?.addEventListener('click', () => {
        const content = `
            <label>Player ID to invite:</label>
            <input type="number" class="modal-input" id="invitePlayerId" min="1" placeholder="Enter server ID...">
        `;
        showModal('Invite Member', content, () => {
            const playerId = parseInt(document.getElementById('invitePlayerId').value);
            if (playerId > 0) {
                nuiCallback('inviteMember', { playerId });
            }
        });
    });
    
    document.getElementById('btnDeposit')?.addEventListener('click', () => showDepositModal('treasury'));
    document.getElementById('btnStash')?.addEventListener('click', () => nuiCallback('openStash'));
    
    // Treasury buttons
    document.getElementById('btnTreasuryDeposit')?.addEventListener('click', () => showDepositModal('treasury'));
    document.getElementById('btnTreasuryWithdraw')?.addEventListener('click', showWithdrawModal);
    document.getElementById('btnWarChestDeposit')?.addEventListener('click', () => showDepositModal('warchest'));
    
    // Member search
    document.getElementById('memberSearch')?.addEventListener('input', (e) => {
        const searchTerm = e.target.value.toLowerCase();
        document.querySelectorAll('.member-card').forEach(card => {
            const name = card.querySelector('.member-name')?.textContent.toLowerCase() || '';
            card.style.display = name.includes(searchTerm) ? '' : 'none';
        });
    });
    
    // ESC key to close
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && State.isOpen) {
            if (!Elements.modalOverlay.classList.contains('hidden')) {
                closeModal();
            } else {
                closeUI();
            }
        }
    });

    // ============================================================================
    // INITIALIZATION
    // ============================================================================
    
    console.log('[FREE-GANGS] NUI Initialized');

})();
