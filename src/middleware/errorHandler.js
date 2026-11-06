// src/middleware/errorHandler.js

function errorHandler(err, req, res, next) {
    console.error('Unhandled Server Error:', err);

    // Joi validation error
    if (err.isJoi) {
        return res.status(400).json({
            success: false,
            error: err.details.map(d => d.message).join('; ')
        });
    }

    const statusCode = err.status || err.statusCode || 500;
    const message = err.message || 'Internal Server Error';

    res.status(statusCode).json({
        success: false,
        error: message
    });
}

module.exports = errorHandler;

