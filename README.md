# Eventora — College Event Management & Registration Portal

> **Eventora** is a realistic, responsive, database-backed multi-college event platform built with vanilla web technologies, Node.js/Express, and Supabase PostgreSQL.

---

## 🌟 Key Features

1. **Multi-College & Multi-Tenant Architecture**
   - Seeded with **Malla Reddy Engineering College for Women (MRECW)** (`identifier: 'mrecw'`).
   - Isolated administration: College administrators can only create, update, and manage events and check-in attendees for their own college.
   - Cross-college discovery: Students can browse, filter, and register for events across participating institutions.

2. **Atomic, Concurrency-Safe Registrations**
   - Stored procedure `register_student()` uses PostgreSQL row locks (`SELECT ... FOR UPDATE`) to prevent overbooking during simultaneous registration spikes.
   - Enforces unique registration per student per event with cancellation and seat reallocation support.

3. **Digital QR Code Tickets**
   - Unique UUID registration tokens transformed into high-resolution QR codes displayed directly on the student ticket pass.

4. **Attendance Check-In Station**
   - Single-use check-in stored procedure `checkin_registration()` validates tickets, prevents repeated check-ins, and enforces college isolation.

5. **Modern Purple Aesthetic**
   - Deep purple (`#4C1D95`), lavender (`#F5F3FF`, `#EDE9FE`), crisp white card elevation, responsive for desktop, tablet, and mobile.

---

## 📁 Project Structure

```
Eventora/
├── .env.example
├── .gitignore
├── package.json
├── README.md
├── docs/
│   ├── setup.md                 <-- Step-by-step installation & troubleshooting
│   ├── test-cases.md            <-- Manual test cases
│   └── deployment-checklist.md  <-- Production readiness checklist
├── supabase/
│   ├── 00_full_setup.sql        <-- Run this single file in Supabase SQL Editor
│   ├── 01_schema.sql            <-- Tables, indexes, triggers
│   ├── 02_functions.sql         <-- register_student & checkin_registration
│   ├── 03_rls.sql               <-- Row Level Security policies
│   └── 04_seed.sql              <-- MRECW seed data & events
├── src/
│   ├── index.js                 <-- Express server entry point
│   ├── config.js                <-- Supabase client initialization
│   ├── middleware/
│   │   ├── auth.js              <-- Supabase JWT & role verification
│   │   └── errorHandler.js      <-- Central error handling
│   ├── routes/
│   │   ├── auth.js              <-- Sign up, sign in, colleges list
│   │   ├── events.js            <-- Public event discovery & details
│   │   ├── registrations.js     <-- Capacity-safe registration & check-in
│   │   └── admin.js             <-- College admin event CRUD & roster
│   └── utils/
│       └── qr.js                <-- QR code generator
└── public/
    ├── index.html               <-- Landing page with hero & MRECW spotlight
    ├── events.html              <-- Event discovery with search & filters
    ├── event.html               <-- Event detail & 1-click registration
    ├── auth.html                <-- Student sign in & sign up tabs
    ├── dashboard.html           <-- Student dashboard with QR ticket passes
    ├── admin.html               <-- College admin portal & attendee rosters
    ├── checkin.html             <-- Single-scan attendance check-in station
    ├── css/
    │   └── style.css            <-- Modern purple aesthetic design system
    └── js/
        ├── api.js               <-- Client API wrapper & toast notifications
        └── navbar.js            <-- Dynamic navigation bar & user badges
```

---

## 🚀 Quick Setup

1. **Install Node.js** (if not already installed):
   ```powershell
   winget install OpenJS.NodeJS.LTS
   ```
2. **Database Setup**:
   Copy and run [`supabase/00_full_setup.sql`](file:///C:/Users/pavan/Downloads/Eventora/supabase/00_full_setup.sql) in your **Supabase Dashboard → SQL Editor**.
3. **Configure Environment Variables**:
   Copy `.env.example` to `.env` and fill in your Supabase keys.
4. **Install Dependencies & Start**:
   ```powershell
   npm install
   npm run dev
   ```
5. **Open Browser**: `http://localhost:3000`

