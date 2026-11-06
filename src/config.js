// src/config.js
require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://hzytlqnfrxxjbvigiwwp.supabase.co';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || 'placeholder_anon_key';
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY || 'placeholder_service_role_key';

// Client for public operations respecting RLS
const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: {
        persistSession: false,
        autoRefreshToken: false
    }
});

// Admin client using service_role key for backend elevated operations
const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: {
        persistSession: false,
        autoRefreshToken: false
    }
});

// Helper to create an authenticated client using user's bearer token
function createUserScopedClient(jwtToken) {
    return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
        global: {
            headers: {
                Authorization: `Bearer ${jwtToken}`
            }
        },
        auth: {
            persistSession: false,
            autoRefreshToken: false
        }
    });
}

module.exports = {
    SUPABASE_URL,
    SUPABASE_ANON_KEY,
    supabaseAnon,
    supabaseAdmin,
    createUserScopedClient
};

