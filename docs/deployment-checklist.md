# Eventora — Production Deployment & Security Checklist

### 1. Database & Supabase Security
- [ ] Run [`supabase/00_full_setup.sql`](file:///C:/Users/pavan/Downloads/Eventora/supabase/00_full_setup.sql) in production database.
- [ ] Ensure Row Level Security (RLS) is enabled on all tables (`colleges`, `profiles`, `events`, `registrations`).
- [ ] Verify that public users CANNOT modify `role` or `college_id` in `profiles`.
- [ ] Confirm stored procedures (`register_student`, `checkin_registration`) run with `SECURITY DEFINER` and perform internal authorization checks.
- [ ] Configure Supabase Database Backups (Daily / Point-In-Time recovery).

### 2. Environment Variables & Secrets
- [ ] Ensure `.env` is listed in `.gitignore` and never committed to source control.
- [ ] Store `SUPABASE_SERVICE_ROLE_KEY` exclusively on the Node.js server.
- [ ] Ensure client browser code only communicates with the Express backend or uses `SUPABASE_ANON_KEY`.

### 3. Server Configuration & Production Hardening
- [ ] Enforce HTTPS across all routes (TLS termination via Cloudflare, Nginx, or AWS ALB).
- [ ] Set `NODE_ENV=production`.
- [ ] Adjust CORS origin in `src/index.js` to whitelist your production domain only.
- [ ] Configure `express-rate-limit` for DDoS / brute-force mitigation (currently set to 120 req/min).
- [ ] Enable HTTP security headers via `helmet`.

### 4. Continuous Integration & Hosting
- [ ] Backend deployment targets: Render, Railway, Fly.io, AWS Elastic Beanstalk, or DigitalOcean App Platform.
- [ ] Health Check endpoint: `/api/health` configured for load balancer probes.
- [ ] Domain & DNS configuration with SSL/TLS certificate.

