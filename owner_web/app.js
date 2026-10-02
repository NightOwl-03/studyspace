const SUPABASE_URL = localStorage.getItem("supabase_url") || "https://mlwhsqvvezxnnxezydcn.supabase.co";
const SUPABASE_ANON_KEY = localStorage.getItem("supabase_anon_key") || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1sd2hzcXZ2ZXp4bm54ZXp5ZGNuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwMDM3OTksImV4cCI6MjA5MjU3OTc5OX0.iqUw58o00QkVFWRReIfbZN2We1483G4jofibT_I0kbY";

// Supabase client (used for Storage uploads)
const supabaseClient = window.supabase
    ? window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
    : null;

// Live Data (populated from API)
let liveReservations = [];
let liveTables = [];

// DOM Elements
const navLinks = document.querySelectorAll('.nav-links li');
const sections = document.querySelectorAll('.content-section');
const menuToggle = document.getElementById('menu-toggle');
const sidebar = document.querySelector('.sidebar');
const reservationsTbody = document.getElementById('reservations-tbody');
const searchReservations = document.getElementById('search-reservations');
const reviewsContainer = document.getElementById('reviews-container');
const tablesGrid = document.getElementById('tables-grid');

// Modal Elements
const addTableModal = document.getElementById('add-table-modal');
const addTableBtn = document.getElementById('add-table-btn');
const cancelAddTable = document.getElementById('cancel-add-table');
const confirmAddTable = document.getElementById('confirm-add-table');
const newTableId = document.getElementById('new-table-id');
const newTableSeats = document.getElementById('new-table-seats');

// Initialize App
// Inject table-number-badge style if not already in external CSS
(function injectStyles() {
    const style = document.createElement('style');
    style.textContent = `
    /* ── NEW Reservation Badge ── */
    .new-res-badge {
        display: inline-block;
        margin-left: 6px;
        padding: 1px 6px;
        background: #10B981;
        color: #fff;
        border-radius: 4px;
        font-size: 10px;
        font-weight: 700;
        letter-spacing: 0.6px;
        vertical-align: middle;
        animation: pulse-green 2s infinite;
    }
    @keyframes pulse-green {
        0%, 100% { box-shadow: 0 0 0 0 rgba(16,185,129,0.5); }
        50%       { box-shadow: 0 0 0 4px rgba(16,185,129,0); }
    }

    /* ── Row highlight for new reservations ── */
    tr.reservation-row-new {
        border-left: 3px solid #10B981;
    }

    /* ── Redesigned Message Button ── */
    .msg-btn {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 32px;
        height: 32px;
        border-radius: 8px;
        border: 1px solid #d0d5dd;
        background: #fff;
        color: #1976D2;
        font-size: 14px;
        cursor: pointer;
        transition: background 0.15s, border-color 0.15s, color 0.15s, box-shadow 0.15s;
    }
    .msg-btn:hover {
        background: #e3f0fb;
        border-color: #1976D2;
        color: #1255a0;
        box-shadow: 0 2px 6px rgba(25,118,210,0.18);
    }
    .msg-btn:active {
        background: #1976D2;
        color: #fff;
    }

    /* ── Status Select Dropdown (Table Management) ── */
    .status-select-dropdown:focus {
        border-color: #1976D2;
        box-shadow: 0 0 0 3px rgba(25,118,210,0.15);
    }
    .status-select-dropdown:disabled {
        opacity: 0.5;
        cursor: not-allowed;
    }

    /* ── Table Number Badge ── */
    .table-number-badge {
        display: inline-block;
        padding: 2px 8px;
        background: #e3f0fb;
        color: #1976D2;
        border-radius: 4px;
        font-size: 12px;
        font-weight: 600;
        letter-spacing: 0.5px;
    }

    /* ── List View Fix: uniform row height & alignment ── */
    #tables-grid.list-view {
        display: flex;
        flex-direction: column;
        gap: 0;
        background: #fff;
        border-radius: 12px;
        overflow: hidden;
        box-shadow: 0 1px 4px rgba(0,0,0,0.08);
    }
    #tables-grid.list-view .table-card {
        display: flex;
        flex-direction: row;
        align-items: center;
        gap: 14px;
        padding: 8px 20px;
        border-radius: 0;
        border-bottom: 1px solid #f0f0f0;
        min-height: 52px;
        height: 52px;
        box-shadow: none;
        text-align: left;
        overflow: hidden;
    }
    #tables-grid.list-view .table-card:last-child { border-bottom: none; }
    #tables-grid.list-view .table-card .table-icon {
        font-size: 18px;
        width: 30px;
        flex-shrink: 0;
        display: flex;
        align-items: center;
        justify-content: center;
    }
    #tables-grid.list-view .table-card h3 {
        font-size: 14px;
        font-weight: 600;
        min-width: 90px;
        margin: 0;
    }
    #tables-grid.list-view .table-card p {
        font-size: 13px;
        color: #666;
        min-width: 130px;
        margin: 0;
    }
    #tables-grid.list-view .table-badge {
        font-size: 11px;
        min-width: 80px;
        text-align: center;
    }
    #tables-grid.list-view .table-actions {
        margin-top: 0 !important;
        margin-left: auto;
        display: flex !important;
        gap: 8px;
        align-items: center;
        justify-content: flex-end;
    }

    /* ── Grid View: uniform card height ── */
    #tables-grid.grid-view {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
        gap: 16px;
    }
    #tables-grid.grid-view .table-card {
        display: flex;
        flex-direction: column;
        align-items: center;
        padding: 24px 16px 16px;
        border-radius: 12px;
        text-align: center;
        min-height: 200px;
    }

    /* ── Messages Layout ── */
    .messages-layout {
        display: grid;
        grid-template-columns: 300px 1fr;
        gap: 16px;
        height: calc(100vh - 180px);
        min-height: 500px;
    }
    .conversations-list {
        display: flex;
        flex-direction: column;
        overflow: hidden;
        padding: 0;
    }
    .conversations-header {
        padding: 16px;
        border-bottom: 1px solid #f0f0f0;
        display: flex;
        flex-direction: column;
        gap: 10px;
    }
    .conversations-header h3 {
        font-size: 14px;
        font-weight: 600;
        margin: 0;
    }
    .conversations-header .search-container {
        margin: 0;
        width: 100%;
    }
    #conversation-items {
        overflow-y: auto;
        flex: 1;
    }
    .conversation-item {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 12px 16px;
        cursor: pointer;
        border-bottom: 1px solid #f7f7f7;
        transition: background 0.15s;
    }
    .conversation-item:hover, .conversation-item.active { background: #f0f6ff; }
    .conversation-item.unread .conv-name { font-weight: 700; }
    .conv-avatar {
        width: 40px; height: 40px;
        border-radius: 50%;
        background: #1976D2;
        color: #fff;
        display: flex; align-items: center; justify-content: center;
        font-size: 16px; font-weight: 600;
        flex-shrink: 0;
    }
    .conv-info { flex: 1; overflow: hidden; }
    .conv-name { font-size: 13px; font-weight: 500; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .conv-preview { font-size: 12px; color: #888; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .conv-meta { display: flex; flex-direction: column; align-items: flex-end; gap: 4px; }
    .conv-time { font-size: 11px; color: #aaa; }
    .unread-dot { width: 8px; height: 8px; border-radius: 50%; background: #1976D2; flex-shrink: 0; animation: pulse-blue 2s infinite; }
    @keyframes pulse-blue {
        0%, 100% { box-shadow: 0 0 0 0 rgba(25,118,210,0.5); }
        50%       { box-shadow: 0 0 0 4px rgba(25,118,210,0); }
    }
    /* Unread conversation: bold name + slightly highlighted background */
    .conversation-item.unread { background: #f0f6ff; }
    .conversation-item.unread .conv-name { font-weight: 700; color: #1976D2; }
    .conversation-item.unread .conv-preview { color: #555; font-weight: 500; }
    .chat-window {
        display: flex;
        flex-direction: column;
        overflow: hidden;
        padding: 0;
    }
    .chat-placeholder {
        flex: 1;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        color: #aaa;
        font-size: 14px;
        gap: 12px;
    }
    .chat-placeholder i { font-size: 40px; color: #ddd; }
    .chat-header {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 14px 20px;
        border-bottom: 1px solid #f0f0f0;
        background: #fff;
    }
    .chat-messages {
        flex: 1;
        overflow-y: auto;
        padding: 16px;
        display: flex;
        flex-direction: column;
        gap: 10px;
        background: #f9fafb;
    }
    .chat-bubble { max-width: 70%; }
    .chat-bubble.outgoing { align-self: flex-end; }
    .chat-bubble.incoming { align-self: flex-start; }
    .bubble-text {
        padding: 10px 14px;
        border-radius: 16px;
        font-size: 13px;
        line-height: 1.5;
    }
    .outgoing .bubble-text { background: #1976D2; color: #fff; border-bottom-right-radius: 4px; }
    .incoming .bubble-text { background: #fff; color: #222; border: 1px solid #eee; border-bottom-left-radius: 4px; }
    .bubble-time { font-size: 11px; color: #aaa; margin-top: 4px; text-align: right; }
    .incoming .bubble-time { text-align: left; }
    .chat-input-row {
        display: flex;
        gap: 8px;
        padding: 12px 16px;
        border-top: 1px solid #f0f0f0;
        background: #fff;
        align-items: center;
    }

    /* ── Profile Layout ── */
    .profile-layout {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 20px;
    }
    .shop-photos-card { grid-column: 1 / -1; }
    .profile-card { padding: 24px; }
    .profile-avatar-wrapper {
        display: flex;
        align-items: center;
        gap: 20px;
        margin-bottom: 20px;
        padding-bottom: 20px;
        border-bottom: 1px solid #f0f0f0;
    }
    .profile-avatar {
        width: 80px; height: 80px;
        border-radius: 50%;
        background: #e3f0fb;
        color: #1976D2;
        display: flex; align-items: center; justify-content: center;
        font-size: 32px;
        flex-shrink: 0;
        overflow: hidden;
    }
    .avatar-upload-btn {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        padding: 8px 14px;
        background: #f5f5f5;
        border: 1px solid #e0e0e0;
        border-radius: 8px;
        font-size: 13px;
        font-weight: 500;
        cursor: pointer;
        transition: background 0.15s;
        color: #333;
    }
    .avatar-upload-btn:hover { background: #e8e8e8; }
    .form-row {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 12px;
    }
    .form-label {
        display: block;
        font-size: 13px;
        color: #666;
        margin-bottom: 6px;
        font-weight: 500;
    }
    .form-group { margin-bottom: 14px; }
    textarea.form-control { resize: vertical; min-height: 80px; }
    .photo-upload-area {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        padding: 32px;
        border: 2px dashed #d0dff5;
        border-radius: 10px;
        cursor: pointer;
        background: #f8faff;
        transition: border-color 0.2s, background 0.2s;
        margin-bottom: 16px;
        text-align: center;
        font-size: 14px;
        color: #555;
    }
    .photo-upload-area:hover { border-color: #1976D2; background: #f0f6ff; }
    .shop-photos-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
        gap: 10px;
    }
    .shop-photo-thumb {
        position: relative;
        border-radius: 8px;
        overflow: hidden;
        aspect-ratio: 1;
        background: #f0f0f0;
    }
    .shop-photo-thumb img {
        width: 100%; height: 100%;
        object-fit: cover;
        display: block;
    }
    .remove-photo-btn {
        position: absolute;
        top: 4px; right: 4px;
        width: 22px; height: 22px;
        border-radius: 50%;
        background: rgba(0,0,0,0.55);
        color: #fff;
        border: none;
        cursor: pointer;
        font-size: 12px;
        display: flex; align-items: center; justify-content: center;
        transition: background 0.15s;
    }
    .remove-photo-btn:hover { background: #e53935; }

    @media (max-width: 900px) {
        .messages-layout { grid-template-columns: 1fr; height: auto; }
        .conversations-list { height: 260px; }
        .chat-window { min-height: 400px; }
        .profile-layout { grid-template-columns: 1fr; }
        .form-row { grid-template-columns: 1fr; }
    }
    `;
    document.head.appendChild(style);
})();

document.addEventListener('DOMContentLoaded', () => {
    loadBusinessName();
    setupNavigation();
    setupViewToggles();
    loadOverview();
    loadLiveReservations();
    loadLiveTables();
    setupSearch();
    loadReviews();
    setupModal();
    setupExportCSV();
    initCharts();
    loadProfileData();
    setupProfileHandlers();
    loadConversations();

    // --- Fix #1 & #2: Explicit per-event listeners on seats for reliable realtime updates ---
    if (SUPABASE_URL && !SUPABASE_URL.includes('YOUR_') && supabaseClient) {
      supabaseClient
        .channel('schema-db-changes')
        .on('postgres_changes', { event: '*', schema: 'public', table: 'reservations' },
          (payload) => {
            console.log('Reservation changed:', payload);
            loadLiveReservations();
            loadOverview();
          }
        )
        .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'seats' },
          (payload) => {
            console.log('Seat inserted:', payload);
            loadLiveTables();
            loadOverview();
          }
        )
        .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'seats' },
          (payload) => {
            console.log('Seat updated:', payload);
            loadLiveTables();
            loadOverview();
          }
        )
        .on('postgres_changes', { event: 'DELETE', schema: 'public', table: 'seats' },
          (payload) => {
            console.log('Seat deleted:', payload);
            loadLiveTables();
            loadOverview();
          }
        )
        .on('postgres_changes', { event: '*', schema: 'public', table: 'study_spot_tables' },
          (payload) => {
            console.log('Table changed:', payload);
            loadLiveTables();
            loadOverview();
          }
        )
       
        .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' },
        async (payload) => {
            console.log('New message received from Realtime:', payload.new);
            
            if (window.activeConversationId && payload.new.conversation_id === window.activeConversationId) {
                console.log('Refreshing chat window for conversation:', window.activeConversationId);
                
                
                try {
                    const r = await fetch(`http://localhost:3000/api/messages/${window.activeConversationId}`);
                    const msgs = await r.json();
                    renderMessages(msgs); 
                } catch (err) {
                    console.error("Fetch error on realtime update:", err);
                }
            }
            
            loadConversations(); 
        }
        )
        .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'conversations' },
          (payload) => {
            console.log('Conversation updated:', payload);
            loadConversations();
          }
        )
        .subscribe((status) => {
          console.log('Realtime subscription status:', status);
        });
    } else {
      console.warn('Set SUPABASE_URL/KEY in app.js or localStorage to enable realtime.');
    }

});

// Business Name — read from localStorage (saved on login)
function loadBusinessName() {
    const businessName = localStorage.getItem('business_name');
    const profilePictureUrl = localStorage.getItem('profile_picture_url');
    const nameEl = document.getElementById('sidebar-business-name');
    const sidebarLogo = document.querySelector('.logo-icon');

    if (nameEl && businessName) {
        nameEl.textContent = businessName;
    }

    if (sidebarLogo) {
        if (profilePictureUrl) {
            sidebarLogo.innerHTML = `<img src="${profilePictureUrl}" alt="Owner profile">`;
        }
    }
}

// Navigation Logic
function setupNavigation() {
    navLinks.forEach(link => {
        link.addEventListener('click', () => {
            navLinks.forEach(l => l.classList.remove('active'));
            sections.forEach(s => s.classList.remove('active'));

            link.classList.add('active');
            const targetId = link.getAttribute('data-target');
            if (targetId) document.getElementById(targetId).classList.add('active');

            if (window.innerWidth <= 768) {
                sidebar.classList.remove('open');
            }
        });
    });

    if (menuToggle) {
        menuToggle.addEventListener('click', () => {
            sidebar.classList.toggle('open');
        });
    }

    const logoutBtn = document.getElementById('logout-btn');
    if (logoutBtn) {
        logoutBtn.addEventListener('click', () => {
            localStorage.removeItem('business_name');
            localStorage.removeItem('owner_id');
            window.location.href = 'auth.html';
        });
    }
}

function setupViewToggles() {
    const gridBtn = document.getElementById('grid-view-btn');
    const listBtn = document.getElementById('list-view-btn');
    const container = document.getElementById('tables-grid');

    gridBtn.addEventListener('click', () => {
        gridBtn.classList.add('active');
        listBtn.classList.remove('active');
        container.classList.replace('list-view', 'grid-view');
    });

    listBtn.addEventListener('click', () => {
        listBtn.classList.add('active');
        gridBtn.classList.remove('active');
        container.classList.replace('grid-view', 'list-view');
    });
}

// Overview Logic
async function loadOverview() {
    try {
        const studySpotId = localStorage.getItem('study_spot_id');
        const overviewUrl = studySpotId
            ? `http://localhost:3000/api/overview?study_spot_id=${studySpotId}`
            : 'http://localhost:3000/api/overview';
        const response = await fetch(overviewUrl);
        const data = await response.json();

        const metricValues = document.querySelectorAll('.metric-value');
        if (metricValues[0]) metricValues[0].textContent = data.totalSeatsReserved;
        if (metricValues[1]) metricValues[1].textContent = data.todayReservations;
        if (metricValues[2]) metricValues[2].textContent = `${data.availableCapacityPct}%`;

        const progressBar = document.querySelector('.progress-bar');
        if (progressBar) {
            const width = data.occupiedPct ?? 0;
            progressBar.style.width = `${width}%`;
            progressBar.setAttribute('aria-valuenow', String(width));
        }

        const occupiedText = document.querySelector('.occupied-text');
        if (occupiedText) {
            occupiedText.textContent = `${data.occupiedPct}% Occupied (${data.occupiedSeats}/${data.totalSeats} seats)`;
        }

        const availableText = document.querySelector('.available-text');
        if (availableText) {
            availableText.textContent = `${data.availableCapacityPct}% Available`;
        }
    } catch (error) {
        console.error('Failed to load overview:', error);
    }
}

// Reservations Logic
function renderReservations(data) {
    reservationsTbody.innerHTML = '';
    const now = Date.now();
    const ONE_DAY_MS = 24 * 60 * 60 * 1000;

    data.forEach(res => {
        const tr = document.createElement('tr');
        tr.dataset.id = res.id;

        // Format booking reference: show as pill badge
        const refDisplay = res.booking_ref
            ? `<span class="booking-ref-badge">${res.booking_ref}</span>`
            : '<span style="color:#aaa;">—</span>';

        // Format time: strip seconds from HH:mm:ss → HH:mm
        const timeParts = (res.time || '').split(':');
        const timeDisplay = timeParts.length >= 2
            ? `${timeParts[0]}:${timeParts[1]}`
            : res.time || '—';

        // NEW badge: reservation created within the last 24 hours
        // res.created_at is included via the API (see GET /api/reservations)
        const isNew = res.created_at && (now - new Date(res.created_at).getTime()) < ONE_DAY_MS;
        const newBadge = isNew
            ? `<span class="new-res-badge" title="Created within the last 24 hours">NEW</span>`
            : '';

        // Apply a distinct left-border class for new reservations
        if (isNew) tr.classList.add('reservation-row-new');

        tr.innerHTML = `
            <td>${refDisplay}${newBadge}</td>
            <td><strong>${res.name}</strong></td>
            <td class="text-muted-sm">${res.contact}</td>
            <td>${res.date}<br><span style="color:var(--text-muted);font-size:12px;">${timeDisplay}</span></td>
            <td style="text-align:center;font-weight:600;">${res.seats}</td>
            <td>${res.table_number ? '<span class="table-number-badge">T' + res.table_number.replace(/^T/i, '') + '</span>' : '—'}</td>
            <td><span class="status-badge status-${res.status.toLowerCase()}">${res.status}</span></td>
            <td>
                <button class="msg-btn" title="Message customer" aria-label="Message ${res.name}">
                    <i class="fa-solid fa-message"></i>
                </button>
            </td>
            <td class="action-btns">
                <button class="edit-btn" title="Change Status"><i class="fa-solid fa-pen"></i></button>
                <button class="cancel-btn" title="Cancel" ${res.status.toLowerCase() === 'cancelled' ? 'disabled' : ''}><i class="fa-solid fa-xmark"></i></button>
            </td>
        `;

        // Edit button — inline status change
        tr.querySelector('.edit-btn').addEventListener('click', () => openEditModal(res));

        // Message button — open chat with this customer
        tr.querySelector('.msg-btn').addEventListener('click', () => {
            openCustomerChat(res.name, res.contact, res.id);
        });

        // Cancel button — mark as cancelled in DB
        tr.querySelector('.cancel-btn').addEventListener('click', async () => {
            if (!confirm(`Cancel reservation for ${res.name}?`)) return;
            try {
                const r = await fetch(`http://localhost:3000/api/reservations/${res.id}/cancel`, { method: 'PATCH' });
                if (r.ok) {
                    await loadLiveReservations();
                    await loadOverview();
                } else {
                    alert('Failed to cancel reservation.');
                }
            } catch (err) {
                alert('Could not connect to server.');
            }
        });

        reservationsTbody.appendChild(tr);
    });
}

async function loadLiveReservations() {
    const studySpotId = localStorage.getItem('study_spot_id');
    try {
        const response = await fetch(`http://localhost:3000/api/reservations${studySpotId ? '?study_spot_id=' + studySpotId : ''}`);
        const data = await response.json();

        if (Array.isArray(data)) {
            liveReservations = data;
            renderReservations(liveReservations);
        }
    } catch (error) {
        console.error('Failed to load reservations:', error);
    }
}

function setupSearch() {
    searchReservations.addEventListener('input', (e) => {
        const query = e.target.value.toLowerCase();
        const filtered = liveReservations.filter(res =>
            res.name.toLowerCase().includes(query) ||
            res.contact.toLowerCase().includes(query)
        );
        renderReservations(filtered);
    });
}

// Edit Reservation Modal
function openEditModal(res) {
    // Build a simple inline modal dynamically
    const existing = document.getElementById('edit-reservation-modal');
    if (existing) existing.remove();

    const modal = document.createElement('div');
    modal.id = 'edit-reservation-modal';
    modal.className = 'modal active';
    modal.innerHTML = `
        <div class="modal-content">
            <div class="modal-header"><h2>Edit Reservation — ${res.name}</h2></div>
            <div class="modal-body">
                <div class="form-group">
                    <label style="font-size:13px;color:var(--text-secondary);margin-bottom:6px;display:block;">Status</label>
                    <select id="edit-status" class="form-control">
                        <option value="confirmed" ${res.status.toLowerCase() === 'confirmed' ? 'selected' : ''}>Confirmed</option>
                        <option value="cancelled" ${res.status.toLowerCase() === 'cancelled' ? 'selected' : ''}>Cancelled</option>
                    </select>
                </div>
            </div>
            <div class="modal-footer">
                <button class="btn btn-text" id="cancel-edit">Cancel</button>
                <button class="btn btn-primary" id="confirm-edit">Save</button>
            </div>
        </div>
    `;

    document.body.appendChild(modal);

    document.getElementById('cancel-edit').addEventListener('click', () => modal.remove());
    modal.addEventListener('click', (e) => { if (e.target === modal) modal.remove(); });

    document.getElementById('confirm-edit').addEventListener('click', async () => {
    const newStatus = document.getElementById('edit-status').value;
    console.log("Updating reservation:", res.id, "to", newStatus); // I-check ni sa console
        try {
            const r = await fetch(`http://localhost:3000/api/reservations/${res.id}/status`, {
                method: 'PATCH',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ status: newStatus })
            });
            if (r.ok) {
                modal.remove();
                await loadLiveReservations();
                await loadOverview(); 
            } else {
                alert('Failed to update reservation.');
            }
        } catch (err) {
            alert('Could not connect to server.');
        }
    });
}

// Export CSV
function setupExportCSV() {
    const exportBtn = document.querySelector('.btn-primary[class*="download"], .section-header .btn-primary');
    // Target the export button specifically by its icon
    const allBtns = document.querySelectorAll('#reservations-section .btn-primary');
    allBtns.forEach(btn => {
        if (btn.querySelector('.fa-download')) {
            btn.addEventListener('click', exportCSV);
        }
    });
}

function exportCSV() {
    if (!liveReservations.length) {
        alert('No reservations to export.');
        return;
    }
    const headers = ['Name', 'Contact', 'Date', 'Time', 'Seats', 'Table', 'Status'];
    const rows = liveReservations.map(r => [r.name, r.contact, r.date, r.time, r.seats, r.table_number || '—', r.status]);
    const csv = [headers, ...rows].map(row => row.map(v => `"${v}"`).join(',')).join('\n');

    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `reservations_${new Date().toISOString().split('T')[0]}.csv`;
    a.click();
    URL.revokeObjectURL(url);
}

// Reviews Logic
function renderReviews(data) {
    reviewsContainer.innerHTML = '';

    if (!data || data.length === 0) {
        reviewsContainer.innerHTML = `
            <div style="text-align:center;padding:48px 16px;color:#888;">
                <i class="fa-regular fa-star" style="font-size:40px;color:#ddd;"></i>
                <p style="margin-top:12px;font-weight:500;">No reviews yet</p>
                <p style="font-size:13px;">Reviews submitted by users will appear here.</p>
            </div>`;
        return;
    }

    // Summary bar: average rating
    const avg = (data.reduce((s, r) => s + r.rating, 0) / data.length).toFixed(1);
    const summaryDiv = document.createElement('div');
    summaryDiv.style.cssText = 'display:flex;align-items:center;gap:12px;padding:12px 0 20px;border-bottom:1px solid #f0f0f0;margin-bottom:16px;';
    summaryDiv.innerHTML =
        '<span style="font-size:40px;font-weight:700;color:#1a1a2e;">' + avg + '</span>' +
        '<div>' +
        '<div style="color:#f59e0b;font-size:20px;">' +
            '★'.repeat(Math.round(avg)) + '☆'.repeat(5 - Math.round(avg)) +
        '</div>' +
        '<div style="font-size:13px;color:#888;">' + data.length + ' review' + (data.length !== 1 ? 's' : '') + '</div>' +
        '</div>';
    reviewsContainer.appendChild(summaryDiv);

    data.forEach(function(review) {
        const initial = (review.customer || '?').charAt(0).toUpperCase();
        let starsHtml = '';
        for (let i = 0; i < 5; i++) {
            starsHtml += i < review.rating
                ? '<i class="fa-solid fa-star" style="color:#f59e0b;"></i>'
                : '<i class="fa-regular fa-star" style="color:#ddd;"></i>';
        }

        // Show profile picture if available, fallback to initial letter avatar
        const avatarHtml = review.avatar
            ? `<img src="${review.avatar}" alt="${_escapeHtml(review.customer || '')}"
                style="width:40px;height:40px;border-radius:50%;object-fit:cover;flex-shrink:0;"
                onerror="this.outerHTML='<div class=\'reviewer-avatar\'>${initial}</div>'">`
            : `<div class="reviewer-avatar">${initial}</div>`;

        const div = document.createElement('div');
        div.className = 'review-card';
        div.innerHTML =
            '<div class="review-header">' +
                '<div class="reviewer-info">' +
                    avatarHtml +
                    '<div class="reviewer-details">' +
                        '<h4>' + _escapeHtml(review.customer || 'Anonymous') + '</h4>' +
                        '<span>' + (review.time || '') + '</span>' +
                    '</div>' +
                '</div>' +
                '<div class="review-stars" style="display:flex;align-items:center;gap:6px;">' +
                    '<span style="font-weight:700;color:#1a1a2e;">' + review.rating + '/5</span>' +
                    '<span>' + starsHtml + '</span>' +
                '</div>' +
            '</div>' +
            '<p class="review-comment">' + _escapeHtml(review.comment || '(No comment)') + '</p>' +
            '<div class="review-actions">' +
                '<button class="btn btn-text reply-btn"><i class="fa-solid fa-reply"></i> Reply</button>' +
            '</div>';

        div.querySelector('.reply-btn').addEventListener('click', function() {
            const subject = encodeURIComponent('Re: Your Review');
            const body = encodeURIComponent('Hi ' + review.customer + ',\n\nThank you for your feedback!\n\n');
            window.location.href = 'mailto:?subject=' + subject + '&body=' + body;
        });

        reviewsContainer.appendChild(div);
    });
}

async function loadReviews() {
    try {
        const response = await fetch('http://localhost:3000/api/reviews');
        const data = await response.json();
        if (Array.isArray(data)) {
            renderReviews(data);
        }
    } catch (error) {
        console.error('Failed to load reviews:', error);
        reviewsContainer.innerHTML = '<p style="color:red;padding:16px;">Failed to load reviews. Check server connection.</p>';
    }
}

// Auto-refresh reviews every 30 s so new submissions appear without manual reload
setInterval(function() {
    const activeNav = document.querySelector('.nav-item.active');
    if (activeNav && activeNav.dataset && activeNav.dataset.section === 'reviews') {
        loadReviews();
    }
}, 30000);

// Tables Logic
function renderTables(data) {
    tablesGrid.innerHTML = '';
    data.forEach(table => {
        const totalSeats = table.seat_capacity || 0;

        // confirmed_seats is already capped at seat_capacity by the server.
        // Use it as the display count.
        const takenCount = (typeof table.confirmed_seats === 'number')
            ? table.confirmed_seats
            : (Array.isArray(table.seats) ? table.seats : []).filter(s => {
                const status = (s.seat_status || s.status || '').toLowerCase();
                return status === 'reserved' || status === 'occupied';
            }).length;

        // The server now derives table_status authoritatively from reservation data.
        // Use it as the single source of truth for BOTH the badge and the dropdown.
        const currentStatus = (table.table_status || 'available').toLowerCase();

        let badgeText;
        if (currentStatus === 'occupied') {
            badgeText = 'OCCUPIED';
        } else if (currentStatus === 'reserved') {
            badgeText = 'RESERVED';
        } else {
            badgeText = 'AVAILABLE';
        }

        const div = document.createElement('div');
        div.className = `table-card ${currentStatus}`;
        div.innerHTML = `
            <div class="table-icon">
                <i class="fa-solid fa-chair"></i>
            </div>
            <h3>Table ${table.table_number}</h3>
            <p>${takenCount}/${totalSeats} Seats Reserved</p>
            <span class="table-badge">${badgeText}</span>
            <div class="table-actions" style="display:flex;gap:8px;justify-content:center;align-items:center;">
                <select class="status-select-dropdown" data-id="${table.id}" title="Change table status"
                    style="font-size:12px;padding:5px 8px;border-radius:6px;border:1px solid #d0d5dd;
                           background:#fff;color:#333;cursor:pointer;outline:none;min-width:110px;
                           transition:border-color 0.2s,box-shadow 0.2s;">
                    <option value="available" ${currentStatus === 'available' ? 'selected' : ''}>Available</option>
                    <option value="occupied"  ${currentStatus === 'occupied'  ? 'selected' : ''}>Occupied</option>
                    <option value="reserved"  ${currentStatus === 'reserved'  ? 'selected' : ''}>Reserved</option>
                </select>
                <button class="btn btn-text delete-table-btn" data-id="${table.id}" style="font-size:12px;color:var(--danger-color);">
                    <i class="fa-solid fa-trash"></i>
                </button>
            </div>
        `;

        // Status dropdown — immediately PATCHes table + seat statuses on change
        div.querySelector('.status-select-dropdown').addEventListener('change', async (e) => {
            const id   = e.currentTarget.dataset.id;
            const next = e.currentTarget.value;

            // Disable while saving to prevent double-fire
            e.currentTarget.disabled = true;

            try {
                // Step 1: Update Table Status
                const tableRes = await fetch(`http://localhost:3000/api/tables/${id}/status`, {
                    method: 'PATCH',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ table_status: next })
                });
                if (!tableRes.ok) throw new Error('Failed to update table status');

                // Step 2: Update Seat Statuses for this table
                const seatIds = (table.seats || []).map(s => s.id);
                if (seatIds.length > 0) {
                    const seatRes = await fetch(`http://localhost:3000/api/seats/status`, {
                        method: 'PATCH',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ seat_ids: seatIds, seat_status: next })
                    });
                    if (!seatRes.ok) {
                        const errData = await seatRes.json();
                        console.error('Seat update error:', errData);
                        throw new Error('Failed to update seats');
                    }
                }

                // Refresh UI (Realtime also fires, but this ensures immediate feedback)
                await loadLiveTables();
                await loadOverview();

            } catch (err) {
                console.error('Status dropdown error:', err.message);
                alert('Error updating status: ' + err.message);
                // Re-enable on failure so user can retry
                e.currentTarget.disabled = false;
            }
        });

        // Delete table
        div.querySelector('.delete-table-btn').addEventListener('click', async (e) => {
            const id = e.currentTarget.dataset.id;
            if (!confirm(`Delete Table ${table.table_number}?`)) return;
            try {
                const r = await fetch(`http://localhost:3000/api/tables/${id}`, { method: 'DELETE' });
                if (r.ok) {
                    await loadLiveTables();
                    await loadOverview();
                } else {
                    alert('Failed to delete table.');
                }
            } catch (err) {
                alert('Could not connect to server.');
            }
        });

        tablesGrid.appendChild(div);
    });
}

async function loadLiveTables() {
    const studySpotId = localStorage.getItem('study_spot_id');
    try {
        const response = await fetch(`http://localhost:3000/api/tables${studySpotId ? '?study_spot_id=' + studySpotId : ''}`);
        const data = await response.json();

        if (Array.isArray(data)) {
            liveTables = data;
            renderTables(liveTables);
        }
    } catch (error) {
        console.error('Failed to load tables:', error);
    }
}

// Modal Logic
function setupModal() {
    addTableBtn.addEventListener('click', () => {
        addTableModal.classList.add('active');
        newTableId.value = '';
        newTableSeats.value = '';
        const errorEl = document.getElementById('add-table-error');
        if (errorEl) errorEl.style.display = 'none';
    });

    cancelAddTable.addEventListener('click', () => {
        addTableModal.classList.remove('active');
    });

    addTableModal.addEventListener('click', (e) => {
        if (e.target === addTableModal) {
            addTableModal.classList.remove('active');
        }
    });

    confirmAddTable.addEventListener('click', async () => {
        const tableNum = newTableId.value.trim();
        const seats = parseInt(newTableSeats.value);
        const studySpotId = localStorage.getItem('study_spot_id');
        const errorEl = document.getElementById('add-table-error');
        errorEl.style.display = 'none';

        if (!tableNum || !seats || seats < 1) {
            errorEl.textContent = 'Please enter valid values for both fields.';
            errorEl.style.display = 'block';
            return;
        }

        if (!studySpotId) {
            errorEl.textContent = 'Session error: study spot not found. Please log out and log in again.';
            errorEl.style.display = 'block';
            return;
        }

        try {
            const response = await fetch('http://localhost:3000/api/tables', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    study_spot_id: studySpotId,
                    table_number: tableNum,
                    seat_capacity: seats,
                    table_status: 'available'
                })
            });

            const result = await response.json();

            if (response.ok) {
                await loadLiveTables();
                await loadOverview();
                addTableModal.classList.remove('active');
            } else {
                errorEl.textContent = 'Error: ' + (result.error || 'Failed to add table.');
                errorEl.style.display = 'block';
            }
        } catch (err) {
            console.error('Error adding table:', err);
            errorEl.textContent = 'Could not connect to server.';
            errorEl.style.display = 'block';
        }
    });
}

// Charts Logic
async function initCharts() {
    if (typeof Chart === 'undefined') return;

    const ctxWeekly = document.getElementById('weeklyChart');
    if (ctxWeekly) {
        try {
            const res = await fetch('http://localhost:3000/api/analytics/weekly');
            const weeklyData = await res.json();

            new Chart(ctxWeekly, {
                type: 'bar',
                data: {
                    labels: weeklyData.map(d => d.label),
                    datasets: [{
                        label: 'Reservations',
                        data: weeklyData.map(d => d.count),
                        backgroundColor: '#1976D2',
                        borderRadius: 4
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: { legend: { display: false } },
                    scales: {
                        y: { beginAtZero: true, grid: { display: false } },
                        x: { grid: { display: false } }
                    }
                }
            });
        } catch (error) {
            console.error('Failed to load weekly chart:', error);
        }
    }

    const ctxPeak = document.getElementById('peakHoursChart');
    if (ctxPeak) {
        try {
            const res = await fetch('http://localhost:3000/api/analytics/peak-hours');
            const peakData = await res.json();

            new Chart(ctxPeak, {
                type: 'line',
                data: {
                    labels: peakData.map(d => d.label),
                    datasets: [{
                        label: 'Reservations',
                        data: peakData.map(d => d.count),
                        borderColor: '#10B981',
                        backgroundColor: 'rgba(16, 185, 129, 0.2)',
                        tension: 0.4,
                        fill: true,
                        pointRadius: 0
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: { legend: { display: false } },
                    scales: {
                        y: { beginAtZero: true },
                        x: { grid: { display: false } }
                    }
                }
            });
        } catch (error) {
            console.error('Failed to load peak hours chart:', error);
        }
    }
}

// ─────────────────────────────────────────────
// MESSAGING HELPERS
// These were missing from the file — their absence caused a ReferenceError
// inside renderConversations on every load, silently clearing the list.
// ─────────────────────────────────────────────

/**
 * Escapes a string for safe insertion into HTML attribute values and text nodes.
 * Prevents XSS when rendering user-supplied data (names, messages, emails).
 */
function _escapeHtml(str) {
    if (str == null) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

/**
 * Returns the module-level Supabase JS client.
 * supabaseClient is defined at the top of app.js as:
 *   const supabaseClient = window.supabase.createClient(...)
 * This wrapper lets internal helpers reference it safely.
 */
function _getSupabaseClient() {
    if (typeof supabaseClient !== 'undefined' && supabaseClient) return supabaseClient;
    if (window.supabase) return window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    return null;
}

// ─────────────────────────────────────────────
// MESSAGING MODULE
// ─────────────────────────────────────────────

window.activeConversationId = null;
let allConversations = [];

async function loadConversations() {
    const studySpotId = localStorage.getItem('study_spot_id');
    try {
        const response = await fetch(`http://localhost:3000/api/messages/conversations${studySpotId ? '?study_spot_id=' + studySpotId : ''}`);
        const data = await response.json();
        if (Array.isArray(data)) {
            allConversations = data;
            renderConversations(data);
        }
    } catch (err) {
        // silently fail — feature is opt-in
        console.info('Messaging API not available yet.');
    }
}

function renderConversations(conversations) {
    const container = document.getElementById('conversation-items');
    if (!container) return;
 
    if (!conversations.length) {
        container.innerHTML = `
            <div class="empty-state" style="padding:32px;text-align:center;color:var(--text-secondary);">
                <i class="fa-regular fa-comment-dots" style="font-size:32px;margin-bottom:8px;display:block;"></i>
                <p>No conversations yet.</p>
                <p style="font-size:12px;">Messages from customers will appear here.</p>
            </div>`;
        return;
    }
 
    container.innerHTML = '';
    conversations.forEach(conv => {
        const div = document.createElement('div');
        div.className = `conversation-item${window.activeConversationId === conv.id ? ' active' : ''}${conv.unread ? ' unread' : ''}`;
        div.dataset.id = conv.id;
 
        // ── Avatar: photo if available, initial letter as fallback ───────────
        const avatarHtml = _buildAvatarHtml(conv.profile_picture_url, conv.customer_name, '40px', '16px');
 
        div.innerHTML = `
            ${avatarHtml}
            <div class="conv-info">
                <div class="conv-name">${_escapeHtml(conv.customer_name || 'Unknown')}</div>
                <div class="conv-preview">${_escapeHtml(conv.last_message || 'No messages yet')}</div>
            </div>
            <div class="conv-meta">
                <span class="conv-time">${conv.last_message_time ? timeAgoClient(conv.last_message_time) : ''}</span>
                ${conv.unread ? '<span class="unread-dot"></span>' : ''}
            </div>
        `;
        div.addEventListener('click', () => openConversation(conv));
        container.appendChild(div);
    });
}

async function openConversation(conv) {
    window.activeConversationId = conv.id;
    renderConversations(allConversations); // re-render sidebar to update active highlight
 
    const chatWindow = document.getElementById('chat-window');
    if (!chatWindow) return;
 
    // Avatar for the chat header (slightly smaller than the sidebar)
    const headerAvatarHtml = _buildAvatarHtml(conv.profile_picture_url, conv.customer_name, '36px', '14px');
 
    chatWindow.innerHTML = `
        <div class="chat-header">
            ${headerAvatarHtml}
            <div>
                <div style="font-weight:600;font-size:14px;">${_escapeHtml(conv.customer_name || 'Customer')}</div>
                <div style="font-size:12px;color:var(--text-secondary);">${_escapeHtml(conv.customer_email || '')}</div>
            </div>
        </div>
        <div class="chat-messages" id="chat-messages-list">
            <div style="text-align:center;color:var(--text-secondary);font-size:13px;padding:24px;">Loading messages...</div>
        </div>
        <div class="chat-input-row">
            <input type="text" id="chat-input" class="form-control" placeholder="Type a message..." style="flex:1;">
            <button class="btn btn-primary" id="chat-send-btn" style="padding:10px 18px;">
                <i class="fa-solid fa-paper-plane"></i>
            </button>
        </div>
    `;
 
    document.getElementById('chat-send-btn').addEventListener('click', () => sendMessage(conv.id));
    document.getElementById('chat-input').addEventListener('keydown', (e) => {
        if (e.key === 'Enter') sendMessage(conv.id);
    });
 
    // ── Load existing messages ────────────────────────────────────────────────
    try {
        const r    = await fetch(`http://localhost:3000/api/messages/${conv.id}`);
        const msgs = await r.json();
        renderMessages(msgs);
    } catch (err) {
        const el = document.getElementById('chat-messages-list');
        if (el) el.innerHTML = '<div style="text-align:center;color:var(--text-secondary);font-size:13px;padding:24px;">Could not load messages.</div>';
    }
 
    // ── Realtime: subscribe to new INSERTs for this conversation ─────────────
    // Clean up any channel from a previously opened conversation.
    if (window.activeMsgChannel) {
        const sc = _getSupabaseClient();
        if (sc) sc.removeChannel(window.activeMsgChannel);
        window.activeMsgChannel = null;
    }
 
    const sc = _getSupabaseClient();
    if (sc) {
        window.activeMsgChannel = sc
            .channel('conv-messages-' + conv.id)
            .on(
                'postgres_changes',
                {
                    event:  'INSERT',
                    schema: 'public',
                    table:  'messages',
                    filter: `conversation_id=eq.${conv.id}`,
                },
                async () => {
                    if (window.activeConversationId !== conv.id) return;
                    try {
                        const r    = await fetch(`http://localhost:3000/api/messages/${conv.id}`);
                        const msgs = await r.json();
                        if (r.ok) renderMessages(msgs);
                    } catch (_) { /* ignore — next event will retry */ }
                }
            )
            .subscribe(status => console.log(`[Realtime] conv-messages-${conv.id}:`, status));
    }
}

function _buildAvatarHtml(imageUrl, name, size = '40px', fontSize = '16px') {
    const initial = (name || 'U').trim().charAt(0).toUpperCase();
 
    if (imageUrl) {
        return `
            <div class="conv-avatar" style="width:${size};height:${size};overflow:hidden;flex-shrink:0;">
                <img
                    src="${_escapeHtml(imageUrl)}"
                    alt="${_escapeHtml(initial)}"
                    style="width:100%;height:100%;object-fit:cover;border-radius:50%;display:block;"
                    onerror="this.parentElement.innerHTML='${initial}';this.parentElement.style.fontSize='${fontSize}';"
                >
            </div>`;
    }
 
    return `<div class="conv-avatar" style="width:${size};height:${size};font-size:${fontSize};flex-shrink:0;">${initial}</div>`;
}

function renderMessages(messages) {
    const list = document.getElementById('chat-messages-list');
    if (!list) return;
    if (!messages.length) {
        list.innerHTML = '<div style="text-align:center;color:var(--text-secondary);font-size:13px;padding:24px;">No messages yet. Say hello!</div>';
        return;
    }

    // Remove optimistic bubbles before re-rendering confirmed messages
    list.querySelectorAll('[data-optimistic="true"]').forEach(el => el.remove());

    // Only append messages not already in the DOM (avoids full re-render flicker)
    const existingIds = new Set(
        Array.from(list.querySelectorAll('[data-msg-id]')).map(el => el.dataset.msgId)
    );

    // If DOM is empty or has changed significantly, do a full clean render
    if (existingIds.size === 0 || messages.length < existingIds.size) {
        list.innerHTML = '';
        existingIds.clear();
    }

    let appended = false;
    messages.forEach(msg => {
        if (existingIds.has(msg.id)) return; // already rendered
        const isOwner = msg.sender_type === 'owner';
        const bubble = document.createElement('div');
        bubble.className = `chat-bubble ${isOwner ? 'outgoing' : 'incoming'}`;
        bubble.dataset.msgId = msg.id;
        bubble.innerHTML =
            '<div class="bubble-text">' + msg.message + '</div>' +
            '<div class="bubble-time">' + timeAgoClient(msg.created_at) + '</div>';
        list.appendChild(bubble);
        appended = true;
    });

    if (appended) list.scrollTop = list.scrollHeight;
}

async function sendMessage(conversationId) {
    const input = document.getElementById('chat-input');
    if (!input) return;
    const text = input.value.trim();
    if (!text) return;

    // Optimistic UI: show bubble instantly, do not wait for realtime
    input.value = '';
    input.disabled = true;

    const list = document.getElementById('chat-messages-list');
    if (list) {
        const bubble = document.createElement('div');
        bubble.className = 'chat-bubble outgoing';
        bubble.dataset.optimistic = 'true';
        bubble.innerHTML =
            '<div class="bubble-text">' + text + '</div>' +
            '<div class="bubble-time">Just now</div>';
        list.appendChild(bubble);
        list.scrollTop = list.scrollHeight;
    }

    try {
        const res = await fetch(`http://localhost:3000/api/messages/${conversationId}/send`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ message: text, sender_type: 'owner' })
        });
        if (!res.ok) {
            const err = await res.json();
            throw new Error(err.error || 'Send failed');
        }
        // Realtime will call renderMessages() replacing the optimistic bubble
    } catch (err) {
        console.error('Send failed:', err);
        if (list) {
            const opt = list.querySelector('[data-optimistic="true"]');
            if (opt) opt.remove();
        }
        input.value = text;
        alert('Failed to send message. Please try again.');
    } finally {
        input.disabled = false;
        input.focus();
    }
}

// Called from the Message button in the Reservations table
function openCustomerChat(customerName, customerEmail, reservationId) {
    // Switch to messages section
    document.querySelectorAll('.nav-links li').forEach(l => l.classList.remove('active'));
    document.querySelectorAll('.content-section').forEach(s => s.classList.remove('active'));
    const msgNav = document.querySelector('[data-target="messages-section"]');
    if (msgNav) msgNav.classList.add('active');
    const msgSection = document.getElementById('messages-section');
    if (msgSection) msgSection.classList.add('active');

    // Check if conversation already exists, else show a compose view
    const existing = allConversations.find(c => c.customer_email === customerEmail);
    if (existing) {
        openConversation(existing);
    } else {
        const chatWindow = document.getElementById('chat-window');
        if (!chatWindow) return;
        chatWindow.innerHTML = `
            <div class="chat-header">
                <div class="conv-avatar" style="width:36px;height:36px;font-size:14px;">${customerName.charAt(0).toUpperCase()}</div>
                <div>
                    <div style="font-weight:600;font-size:14px;">${customerName}</div>
                    <div style="font-size:12px;color:var(--text-secondary);">${customerEmail}</div>
                </div>
            </div>
            <div class="chat-messages" id="chat-messages-list">
                <div style="text-align:center;color:var(--text-secondary);font-size:13px;padding:24px;">Start a conversation with ${customerName}.</div>
            </div>
            <div class="chat-input-row">
                <input type="text" id="chat-input" class="form-control" placeholder="Type a message..." style="flex:1;">
                <button class="btn btn-primary" id="chat-send-btn" style="padding:10px 18px;">
                    <i class="fa-solid fa-paper-plane"></i>
                </button>
            </div>
        `;
        // New conversation — send creates it
        document.getElementById('chat-send-btn').addEventListener('click', () => sendNewMessage(customerEmail, reservationId));
        document.getElementById('chat-input').addEventListener('keydown', (e) => {
            if (e.key === 'Enter') sendNewMessage(customerEmail, reservationId);
        });
    }
}

async function sendNewMessage(customerEmail, reservationId) {
    const input = document.getElementById('chat-input');
    if (!input) return;
    const text = input.value.trim();
    if (!text) return;

    const studySpotId = localStorage.getItem('study_spot_id');
    input.value = '';
    try {
        const r = await fetch('http://localhost:3000/api/messages/new', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ customer_email: customerEmail, reservation_id: reservationId, message: text, study_spot_id: studySpotId })
        });
        if (r.ok) {
            await loadConversations();
            const conv = allConversations.find(c => c.customer_email === customerEmail);
            if (conv) openConversation(conv);
        }
    } catch (err) {
        alert('Could not send message.');
    }
}

// Client-side relative time (mirrors server timeAgo)
function timeAgoClient(dateStr) {
    if (!dateStr) return '';
    const diff = Date.now() - new Date(dateStr).getTime();
    const mins = Math.floor(diff / 60000);
    if (mins < 1) return 'just now';
    if (mins < 60) return `${mins}m ago`;
    const hrs = Math.floor(mins / 60);
    if (hrs < 24) return `${hrs}h ago`;
    const days = Math.floor(hrs / 24);
    return `${days}d ago`;
}

// Search conversations
document.addEventListener('DOMContentLoaded', () => {
    const searchConv = document.getElementById('search-conversations');
    if (searchConv) {
        searchConv.addEventListener('input', (e) => {
            const q = e.target.value.toLowerCase();
            const filtered = allConversations.filter(c =>
                (c.customer_name || '').toLowerCase().includes(q) ||
                (c.customer_email || '').toLowerCase().includes(q)
            );
            renderConversations(filtered);
        });
    }
});

// ─────────────────────────────────────────────
// PROFILE MODULE
// ─────────────────────────────────────────────

// Central helper: apply owner + sidebar UI from a data object
function applyOwnerUI(data) {
    if (!data) return;
    const set = (id, val) => { const el = document.getElementById(id); if (el && val !== undefined && val !== null) el.value = val; };
    set('profile-owner-name',     data.owner_name);
    set('profile-email',          data.email);
    set('profile-phone',          data.phone_number);
    set('profile-business-name',  data.business_name);

    // Sidebar name — prefer business_name from profile, fallback to shop name already in DOM
    if (data.business_name) {
        const nameEl = document.getElementById('sidebar-business-name');
        if (nameEl) nameEl.textContent = data.business_name;
        localStorage.setItem('business_name', data.business_name);
    }

    // Profile picture + sidebar logo
    const url = data.profile_picture_url;
    if (url) {
        const av = document.getElementById('profile-avatar-display');
        if (av) av.innerHTML = `<img src="${url}" style="width:100%;height:100%;object-fit:cover;border-radius:50%;">`;
        const logo = document.querySelector('.logo-icon');
        if (logo) logo.innerHTML = `<img src="${url}" style="width:100%;height:100%;object-fit:cover;border-radius:50%;">`;
        localStorage.setItem('profile_picture_url', url);
    }
}

// Central helper: apply shop UI from a data object
function applyShopUI(shop) {
    if (!shop) return;
    const set = (id, val) => { const el = document.getElementById(id); if (el && val !== undefined && val !== null) el.value = val; };
    set('shop-name',         shop.name);
    set('shop-description',  shop.description);
    set('shop-opening',      shop.opening_time);
    set('shop-closing',      shop.closing_time);
    set('shop-address',      shop.location_address);
    set('shop-email',        shop.email);
    set('shop-phone',        shop.phone_number);
    // Persist study_spot_id from the shop record so PATCH always has it
    if (shop.id) localStorage.setItem('study_spot_id', shop.id);
    if (Array.isArray(shop.image_urls) && shop.image_urls.length) renderShopPhotos(shop.image_urls);
}

async function loadProfileData() {
    const ownerId     = localStorage.getItem('owner_id');
    const studySpotId = localStorage.getItem('study_spot_id');
    if (!ownerId) return;

    try {
        const r    = await fetch(`http://localhost:3000/api/owner/profile?owner_id=${ownerId}`);
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        const data = await r.json();
        applyOwnerUI(data);
    } catch (err) {
        console.info('Profile API not available yet:', err.message);
    }

    if (!studySpotId) return;
    try {
        const r2   = await fetch(`http://localhost:3000/api/owner/shop?study_spot_id=${studySpotId}`);
        if (!r2.ok) throw new Error(`HTTP ${r2.status}`);
        const shop = await r2.json();
        applyShopUI(shop);
    } catch (err) {
        console.info('Shop API not available yet:', err.message);
    }
}

const PHOTO_LIMIT = 3;

function renderShopPhotos(urls) {
    const grid = document.getElementById('shop-photos-grid');
    if (!grid) return;
    grid.innerHTML = '';
    urls.slice(0, PHOTO_LIMIT).forEach(url => {
        const div = document.createElement('div');
        div.className = 'shop-photo-thumb';
        div.innerHTML = `<img src="${url}" alt="Shop photo"><button class="remove-photo-btn" title="Remove"><i class="fa-solid fa-xmark"></i></button>`;
        div.querySelector('.remove-photo-btn').addEventListener('click', () => div.remove());
        grid.appendChild(div);
    });
}

// Reusable status-message helper
function showMsg(id, text, isSuccess) {
    const el = document.getElementById(id);
    if (!el) return;
    el.style.color   = isSuccess ? '#10B981' : '#e53935';
    el.textContent   = text;
    el.style.display = 'block';
    if (isSuccess) setTimeout(() => { el.style.display = 'none'; }, 3500);
}

function setupProfileHandlers() {

    // ── Profile picture upload ──────────────────────────────────────────────
    const picInput = document.getElementById('profile-pic-input');
    if (picInput) {
        picInput.addEventListener('change', async (e) => {
            const file = e.target.files[0];
            if (!file) return;
            const ownerId = localStorage.getItem('owner_id');
            if (!ownerId) return;

            // Instant local preview
            const reader = new FileReader();
            reader.onload = (ev) => {
                const av   = document.getElementById('profile-avatar-display');
                const logo = document.querySelector('.logo-icon');
                const style = 'width:100%;height:100%;object-fit:cover;border-radius:50%;';
                if (av)   av.innerHTML   = `<img src="${ev.target.result}" style="${style}">`;
                if (logo) logo.innerHTML = `<img src="${ev.target.result}" style="${style}">`;
            };
            reader.readAsDataURL(file);

            // Upload via server (service-role key bypasses RLS)
            const formData = new FormData();
            formData.append('avatar', file);
            formData.append('owner_id', ownerId);

            try {
                const r      = await fetch('http://localhost:3000/api/owner/avatar', { method: 'POST', body: formData });
                const result = await r.json();
                if (!r.ok) { showMsg('profile-save-msg', 'Image upload failed: ' + (result.error || r.statusText), false); return; }

                // Persist permanent URL to both UI surfaces
                const style = 'width:100%;height:100%;object-fit:cover;border-radius:50%;';
                const av    = document.getElementById('profile-avatar-display');
                const logo  = document.querySelector('.logo-icon');
                if (av)   av.innerHTML   = `<img src="${result.profile_picture_url}" style="${style}">`;
                if (logo) logo.innerHTML = `<img src="${result.profile_picture_url}" style="${style}">`;
                localStorage.setItem('profile_picture_url', result.profile_picture_url);
                showMsg('profile-save-msg', 'Profile picture saved!', true);
            } catch (err) {
                console.error('Avatar upload error:', err);
                showMsg('profile-save-msg', 'Upload error: ' + err.message, false);
            }
        });
    }

    // ── Business photos upload (max 3) ──────────────────────────────────────
    const photosInput = document.getElementById('shop-photos-input');
    if (photosInput) {
        photosInput.addEventListener('change', (e) => {
            const grid = document.getElementById('shop-photos-grid');
            if (!grid) return;

            const existing   = grid.querySelectorAll('.shop-photo-thumb').length;
            const incoming   = Array.from(e.target.files);
            const available  = PHOTO_LIMIT - existing;

            if (available <= 0) {
                showMsg('shop-save-msg', `Maximum of ${PHOTO_LIMIT} photos allowed. Remove one before adding more.`, false);
                photosInput.value = '';
                return;
            }

            if (incoming.length > available) {
                showMsg('shop-save-msg',
                    `You can only add ${available} more photo${available === 1 ? '' : 's'} (limit is ${PHOTO_LIMIT}). ` +
                    `Only the first ${available} selected file${available === 1 ? '' : 's'} will be added.`, false);
            }

            incoming.slice(0, available).forEach(file => {
                const reader = new FileReader();
                reader.onload = (ev) => {
                    const div = document.createElement('div');
                    div.className = 'shop-photo-thumb';
                    div.innerHTML = `<img src="${ev.target.result}" alt="Shop photo"><button class="remove-photo-btn" title="Remove"><i class="fa-solid fa-xmark"></i></button>`;
                    div.querySelector('.remove-photo-btn').addEventListener('click', () => div.remove());
                    grid.appendChild(div);
                };
                reader.readAsDataURL(file);
            });

            photosInput.value = ''; // reset so same file can be re-selected after removal
        });
    }

    // ── Save owner profile (Name, Phone, Business Name) ────────────────────
    const saveProfileBtn = document.getElementById('save-owner-profile-btn');
    if (saveProfileBtn) {
        saveProfileBtn.addEventListener('click', async () => {
            const ownerId = localStorage.getItem('owner_id');
            if (!ownerId) { showMsg('profile-save-msg', 'Session expired. Please log in again.', false); return; }

            // Validation: owner_name is critical
            const ownerName    = (document.getElementById('profile-owner-name')    || {}).value?.trim() || '';
            const businessName = (document.getElementById('profile-business-name') || {}).value?.trim() || '';
            const phone        = (document.getElementById('profile-phone')         || {}).value?.trim() || '';

            if (!ownerName)    { showMsg('profile-save-msg', 'Name cannot be empty.', false); return; }
            if (!businessName) { showMsg('profile-save-msg', 'Business name cannot be empty.', false); return; }

            const payload = { owner_id: ownerId, owner_name: ownerName, phone_number: phone, business_name: businessName };

            try {
                const r      = await fetch('http://localhost:3000/api/owner/profile', {
                    method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
                });
                const result = await r.json();
                if (!r.ok) { showMsg('profile-save-msg', result.error || 'Failed to save profile.', false); return; }

                // Real-time refresh: re-fetch from DB and rehydrate entire profile UI
                await loadProfileData();
                showMsg('profile-save-msg', 'Profile saved!', true);
            } catch (err) {
                showMsg('profile-save-msg', 'Server not reachable: ' + err.message, false);
            }
        });
    }

    // ── Save business / shop details ────────────────────────────────────────
    const saveShopBtn = document.getElementById('save-shop-details-btn');
    if (saveShopBtn) {
        saveShopBtn.addEventListener('click', async () => {
            let studySpotId = localStorage.getItem('study_spot_id');

            // Fallback: read study_spot_id from a hidden field if available
            const hiddenSpotId = document.getElementById('hidden-study-spot-id');
            if (!studySpotId && hiddenSpotId) studySpotId = hiddenSpotId.value || null;

            if (!studySpotId) {
                showMsg('shop-save-msg', 'Session error: no study spot linked. Please log out and log in again.', false);
                return;
            }

            // Gather field values with safe fallbacks
            const getValue = (id) => {
                const el = document.getElementById(id);
                return el ? el.value.trim() : '';
            };

            const address = getValue('shop-address');
            if (!address) { showMsg('shop-save-msg', 'Address cannot be empty.', false); return; }

            const payload = {
                study_spot_id:    studySpotId,
                name:             getValue('shop-name'),
                description:      document.getElementById('shop-description')?.value?.trim() || '',
                opening_time:     document.getElementById('shop-opening')?.value || null,
                closing_time:     document.getElementById('shop-closing')?.value || null,
                location_address: address,
                email:            getValue('shop-email'),
                phone_number:     getValue('shop-phone')
            };

            console.log('[SaveShop] Sending payload:', payload);

            saveShopBtn.disabled = true;
            saveShopBtn.textContent = 'Saving…';
            try {
                const r = await fetch('http://localhost:3000/api/owner/shop', {
                    method: 'PATCH',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload)
                });
                const result = await r.json();
                if (!r.ok) {
                    showMsg('shop-save-msg', result.error || 'Failed to save business details.', false);
                    return;
                }

                // Fix 3: Real-time refresh — re-fetch fresh data and rehydrate entire UI
                await loadProfileData();
                showMsg('shop-save-msg', 'Business details saved!', true);
            } catch (err) {
                console.error('[SaveShop] Fetch error:', err);
                showMsg('shop-save-msg', 'Server not reachable: ' + err.message, false);
            } finally {
                saveShopBtn.disabled = false;
                saveShopBtn.innerHTML = '<i class="fa-solid fa-floppy-disk"></i> Save Business Details';
            }
        });
    }
}