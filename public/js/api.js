// public/js/api.js
// Universal client helper for API calls, authentication state, and UI feedback

const API_BASE = '/api';

// ------------------------------------------------------------------------------
// 1. AUTH & STORAGE HELPERS
// ------------------------------------------------------------------------------
function getAuthToken() {
    return localStorage.getItem('eventora_token');
}

function setAuthToken(token) {
    if (token) {
        localStorage.setItem('eventora_token', token);
    } else {
        localStorage.removeItem('eventora_token');
    }
}

function getCurrentUser() {
    try {
        const userStr = localStorage.getItem('eventora_user');
        return userStr ? JSON.parse(userStr) : null;
    } catch (e) {
        return null;
    }
}

function setCurrentUser(user) {
    if (user) {
        localStorage.setItem('eventora_user', JSON.stringify(user));
    } else {
        localStorage.removeItem('eventora_user');
    }
}

function logout() {
    setAuthToken(null);
    setCurrentUser(null);
    showToast('Signed out successfully.', 'info');
    setTimeout(() => {
        window.location.href = '/index.html';
    }, 500);
}

// ------------------------------------------------------------------------------
// 2. UNIFIED FETCH WRAPPER
// ------------------------------------------------------------------------------
async function apiRequest(endpoint, options = {}) {
    const token = getAuthToken();
    const headers = {
        'Content-Type': 'application/json',
        ...(options.headers || {})
    };

    if (token) {
        headers['Authorization'] = `Bearer ${token}`;
    }

    try {
        const response = await fetch(`${API_BASE}${endpoint}`, {
            ...options,
            headers
        });

        const data = await response.json().catch(() => ({}));

        if (!response.ok) {
            // Handle session expiry
            if (response.status === 401 && token) {
                setAuthToken(null);
                setCurrentUser(null);
                showToast('Session expired. Please sign in again.', 'error');
                setTimeout(() => {
                    window.location.href = '/auth.html';
                }, 1000);
            }
            const errorMsg = data.error || data.message || `Request failed with status ${response.status}`;
            throw new Error(errorMsg);
        }

        return data;
    } catch (err) {
        console.error(`API Error on [${endpoint}]:`, err.message);
        throw err;
    }
}

// ------------------------------------------------------------------------------
// 3. TOAST NOTIFICATION SYSTEM
// ------------------------------------------------------------------------------
function showToast(message, type = 'info') {
    let container = document.getElementById('toast-container');
    if (!container) {
        container = document.createElement('div');
        container.id = 'toast-container';
        document.body.appendChild(container);
    }

    const toast = document.createElement('div');
    toast.className = `toast ${type}`;

    let icon = 'ℹ️';
    if (type === 'success') icon = '✅';
    if (type === 'error') icon = '⚠️';

    toast.innerHTML = `<span>${icon}</span> <span>${escapeHtml(message)}</span>`;
    container.appendChild(toast);

    setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transform = 'translateY(10px)';
        toast.style.transition = 'all 0.3s ease';
        setTimeout(() => toast.remove(), 300);
    }, 4000);
}

// ------------------------------------------------------------------------------
// 4. FORMATTING UTILITIES
// ------------------------------------------------------------------------------
function formatDate(dateString) {
    if (!dateString) return '-';
    const d = new Date(dateString);
    return d.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric'
    });
}

function formatDateTime(dateString) {
    if (!dateString) return '-';
    const d = new Date(dateString);
    return d.toLocaleDateString('en-US', {
        weekday: 'short',
        month: 'short',
        day: 'numeric',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
    });
}

function escapeHtml(text) {
    if (!text) return '';
    return text
        .toString()
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

function getUrlParam(param) {
    const params = new URLSearchParams(window.location.search);
    return params.get(param);
}

