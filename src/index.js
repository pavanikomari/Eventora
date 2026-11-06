// src/index.js
require('dotenv').config();
const path = require('path');
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const errorHandler = require('./middleware/errorHandler');

const app = express();
const PORT = process.env.PORT || 3000;

// ------------------------------------------------------------------------------
// 1. SECURITY & UTILITY MIDDLEWARES
// ------------------------------------------------------------------------------
// Helmet for HTTP security headers
app.use(helmet({
    contentSecurityPolicy: false, // Disabled for ease of loading inline scripts and CDN images (e.g. Unsplash, QR code generation)
    crossOriginEmbedderPolicy: false
}));

// CORS
app.use(cors({
    origin: true,
    credentials: true
}));

// Body parsers
app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ extended: true, limit: '2mb' }));

// Rate limiter: 120 requests per minute per IP
const limiter = rateLimit({
    windowMs: 60 * 1000,
    max: 120,
    standardHeaders: true,
    legacyHeaders: false,
    message: {
        success: false,
        error: 'Too many requests from this IP. Please try again after a minute.'
    }
});
app.use('/api/', limiter);

// ------------------------------------------------------------------------------
// 2. STATIC FRONTEND ASSETS
// ------------------------------------------------------------------------------
const publicDirectory = path.join(__dirname, '..', 'public');
app.use(express.static(publicDirectory));

// ------------------------------------------------------------------------------
// 3. API ROUTES
// ------------------------------------------------------------------------------
app.get('/api/health', (req, res) => {
    res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        service: 'Eventora API'
    });
});

app.use('/api/auth', require('./routes/auth'));
app.use('/api/events', require('./routes/events'));
app.use('/api/registrations', require('./routes/registrations'));
app.use('/api/admin', require('./routes/admin'));

// ------------------------------------------------------------------------------
// 4. ERROR & NOT FOUND HANDLING
// ------------------------------------------------------------------------------
// API 404 handler
app.use('/api/*', (req, res) => {
    res.status(404).json({
        success: false,
        error: `API route '${req.originalUrl}' not found.`
    });
});

// Fallback to landing page for root requests if not matched by static
app.get('*', (req, res) => {
    res.sendFile(path.join(publicDirectory, 'index.html'));
});

// Centralized error handler
app.use(errorHandler);

// Start server
app.listen(PORT, () => {
    console.log(`=======================================================`);
    console.log(`🎉 Eventora Portal Server running at http://localhost:${PORT}`);
    console.log(`📁 Static Frontend served from: ${publicDirectory}`);
    console.log(`📡 Health Check: http://localhost:${PORT}/api/health`);
    console.log(`=======================================================`);
});

module.exports = app;

