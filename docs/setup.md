# Eventora — Local Development Setup & Troubleshooting Guide

## 1. Quick Resolution: "npm is not recognized" Error
If your PowerShell shows:
```
npm : The term 'npm' is not recognized as the name of a cmdlet...
```
This means Node.js is either not installed or not in your Windows `PATH` environment variable.

### Option A: Install via Windows Package Manager (`winget`) (Fastest)
Open a new **PowerShell as Administrator** and run:
```powershell
winget install OpenJS.NodeJS.LTS
```
Once installed, close and reopen your PowerShell terminal in the `Eventora` folder, then run:
```powershell
node -v
npm -v
```

### Option B: Download Installer
1. Download Node.js LTS from: **https://nodejs.org/**
2. Run the `.msi` installer and make sure the checkbox **"Add to PATH"** is checked.
3. Restart VS Code or your terminal.

---

## 2. Setting Up the Database in Supabase

### Why did you see `relation "colleges" does not exist`?
In PostgreSQL and Supabase, tables must be created **before** applying Row Level Security (RLS) policies or triggers that reference them. If `rls.sql` is run alone, PostgreSQL cannot find the `colleges` table.

### Solution: Single-Click Setup
We created a consolidated script: [`supabase/00_full_setup.sql`](file:///C:/Users/pavan/Downloads/Eventora/supabase/00_full_setup.sql).

1. Log into your Supabase Dashboard: **https://supabase.com/dashboard/project/hzytlqnfrxxjbvigiwwp**
2. In the left sidebar, click on **SQL Editor**.
3. Click **New Query**.
4. Open [`supabase/00_full_setup.sql`](file:///C:/Users/pavan/Downloads/Eventora/supabase/00_full_setup.sql), copy its entire content, paste it into the SQL Editor, and click **Run**.
5. All 4 tables (`colleges`, `profiles`, `events`, `registrations`), triggers, stored procedures, RLS policies, and sample MRECW events are initialized in the exact right order!

---

## 3. Configuring Environment Variables (`.env`)

Copy `.env.example` to `.env`:
```powershell
copy .env.example .env
```
Inside `.env`, verify:
```env
SUPABASE_URL=https://hzytlqnfrxxjbvigiwwp.supabase.co
SUPABASE_ANON_KEY=your_supabase_anon_public_key
SUPABASE_SERVICE_ROLE_KEY=your_supabase_service_role_key
PORT=3000
```
*(You can retrieve your `anon` and `service_role` keys under Supabase Dashboard → **Project Settings** → **API**).*

---

## 4. Installing Dependencies & Running Eventora

1. In the `Eventora` root folder, run:
```powershell
npm install
```

2. Start the local server:
```powershell
npm run dev
```
*(or `npm start`)*

3. Open your browser and navigate to:
```
http://localhost:3000
```

---

## 5. Setting Up Your First College Administrator Account

1. Open `http://localhost:3000/auth.html` and click **"Create Account"**.
2. Sign up with your administrator email (e.g. `admin@mrecw.edu`), enter your name, and select **Malla Reddy Engineering College for Women (MRECW)**.
3. Because public signups default to `student` for security, run this single SQL query in Supabase SQL Editor to elevate your account to **College Administrator**:

```sql
UPDATE public.profiles
SET role = 'admin',
    college_id = (SELECT id FROM public.colleges WHERE identifier = 'mrecw')
WHERE email = 'admin@mrecw.edu';
```

4. Sign out and sign back in. The navbar will now display the **Admin Panel** and **Check-In Scanner** tabs!

