// public/js/navbar.js
// Renders dynamic navigation bar and footer across pages

document.addEventListener('DOMContentLoaded', () => {
    renderNavbar();
    renderFooter();
});

function renderNavbar() {
    const navPlaceholder = document.getElementById('navbar-mount');
    if (!navPlaceholder) return;

    const user = getCurrentUser();
    const currentPath = window.location.pathname;

    let userSectionHtml = '';
    let navLinksHtml = `
        <li><a href="/events.html" class="${currentPath.includes('events.html') ? 'active' : ''}">Discover Events</a></li>
    `;

    if (user) {
        if (user.role === 'student') {
            navLinksHtml += `
                <li><a href="/dashboard.html" class="${currentPath.includes('dashboard.html') ? 'active' : ''}">My Tickets</a></li>
            `;
        } else if (user.role === 'admin' || user.role === 'superadmin') {
            navLinksHtml += `
                <li><a href="/admin.html" class="${currentPath.includes('admin.html') ? 'active' : ''}">Admin Panel</a></li>
                <li><a href="/checkin.html" class="${currentPath.includes('checkin.html') ? 'active' : ''}">Check-In Scanner</a></li>
            `;
        }

        userSectionHtml = `
            <div style="display: flex; align-items: center; gap: 1rem;">
                <div class="user-badge">
                    <span>👤</span>
                    <span>${escapeHtml(user.full_name || user.email)}</span>
                    <span class="role-pill ${user.role}">${user.role}</span>
                </div>
                <button onclick="logout()" class="btn btn-secondary btn-sm">Sign Out</button>
            </div>
        `;
    } else {
        userSectionHtml = `
            <div style="display: flex; align-items: center; gap: 0.75rem;">
                <a href="/auth.html" class="btn btn-secondary btn-sm">Sign In</a>
                <a href="/auth.html?mode=signup" class="btn btn-primary btn-sm">Sign Up</a>
            </div>
        `;
    }

    navPlaceholder.innerHTML = `
        <nav class="navbar">
            <div class="container navbar-inner">
                <a href="/index.html" class="brand">
                    <div class="brand-icon">⚡</div>
                    <span>Eventora</span>
                </a>
                <ul class="nav-links">
                    ${navLinksHtml}
                </ul>
                <div>
                    ${userSectionHtml}
                </div>
            </div>
        </nav>
    `;
}

function renderFooter() {
    const footerPlaceholder = document.getElementById('footer-mount');
    if (!footerPlaceholder) return;

    footerPlaceholder.innerHTML = `
        <footer class="footer">
            <div class="container footer-content">
                <div>
                    <div class="brand" style="margin-bottom: 0.5rem;">
                        <div class="brand-icon" style="width: 28px; height: 28px; font-size: 1rem;">⚡</div>
                        <span style="font-size: 1.15rem;">Eventora</span>
                    </div>
                    <p style="font-size: 0.85rem; color: var(--neutral-500); max-width: 320px;">
                        The multi-campus technical symposium and college event registration platform.
                    </p>
                </div>
                <div>
                    <strong style="font-size: 0.85rem; color: var(--neutral-800); text-transform: uppercase;">Partner Colleges</strong>
                    <p style="font-size: 0.85rem; margin-top: 0.35rem; color: var(--purple-main); font-weight: 600;">
                        🏛️ Malla Reddy Engineering College for Women (MRECW)
                    </p>
                </div>
            </div>
            <div class="container footer-bottom">
                © ${new Date().getFullYear()} Eventora Portal. Built for college fests, technical conclaves, and seamless QR check-ins.
            </div>
        </footer>
    `;
}

