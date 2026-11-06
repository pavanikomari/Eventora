// src/utils/qr.js
const QRCode = require('qrcode');

/**
 * Generate a high quality QR Code Data URL for an event ticket token
 * @param {string} token - The unique UUID token of the registration
 * @returns {Promise<string>} Base64 Data URL
 */
async function generateTicketQR(token) {
    try {
        const qrDataUrl = await QRCode.toDataURL(token, {
            errorCorrectionLevel: 'H',
            type: 'image/png',
            margin: 2,
            width: 280,
            color: {
                dark: '#2E1065', // Deep purple
                light: '#FFFFFF'
            }
        });
        return qrDataUrl;
    } catch (err) {
        console.error('Error generating QR code:', err);
        throw new Error('Failed to generate ticket QR code');
    }
}

module.exports = {
    generateTicketQR
};

