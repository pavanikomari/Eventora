# Eventora — End-to-End Test Cases & Verification Scenarios

## 1. Student Workflow Test Cases

| Test ID | Scenario | Steps to Execute | Expected Behavior |
| :--- | :--- | :--- | :--- |
| **ST-01** | Student Sign-Up | 1. Navigate to `/auth.html` & select "Create Account".<br>2. Fill in Name, Email, Password, and select College `MRECW`.<br>3. Click "Create Student Account". | Account is created in Supabase Auth & public `profiles` table. Role is strictly assigned as `student`. |
| **ST-02** | Student Login | 1. Enter email & password on `/auth.html`.<br>2. Submit form. | JWT token stored in browser session. Redirects to `/dashboard.html`. Welcome message displays student's name. |
| **ST-03** | Event Discovery & Filtering | 1. Go to `/events.html`.<br>2. Type "AI" into the search box.<br>3. Select `MRECW` in the college filter dropdown. | Event cards dynamically filter in real time. Shows capacity meter and seats remaining. |
| **ST-04** | Capacity-Safe Registration | 1. Click "View Event & Register" on an active event.<br>2. Click "🎫 Register for Event". | Atomic stored procedure `register_student` executes. Registration record created with unique UUID `qr_token`. QR Ticket Modal displays immediately. |
| **ST-05** | Duplicate Registration Prevention | 1. Refresh event detail page or attempt to register for the same event again. | Backend returns 400 error: *"You are already registered for this event"*. No duplicate seat is consumed. |
| **ST-06** | View Tickets & Attendance Status | 1. Navigate to `/dashboard.html`. | Shows list of registered events. Shows active status badge (`REGISTERED`). Clicking "📱 View QR Ticket" opens high-res QR code. |
| **ST-07** | Cancel Registration | 1. On `/dashboard.html`, click "Cancel" on a ticket.<br>2. Confirm the prompt. | Registration status updates to `cancelled`. Reserved seat is immediately released back to the event capacity pool. |

---

## 2. College Administrator Workflow Test Cases

| Test ID | Scenario | Steps to Execute | Expected Behavior |
| :--- | :--- | :--- | :--- |
| **AD-01** | Multi-Tenant College Isolation | 1. Log in as an administrator for MRECW.<br>2. Open `/admin.html`. | Only events belonging to MRECW are visible. Events from other colleges (e.g. CBIT) are not listed or editable. |
| **AD-02** | Create College Event | 1. Click "+ Create New Event".<br>2. Fill in Title, Category, Capacity (e.g. 50), Venue, Dates, Description, check "Publish".<br>3. Submit. | Event is saved to PostgreSQL with `college_id` bound to the admin's college. Instantly visible in public discovery catalog. |
| **AD-03** | Edit & Delete Event | 1. Click "✏️ Edit" on an event.<br>2. Change venue or capacity.<br>3. Save. | Updates reflected immediately in database and UI. |
| **AD-04** | Participant Roster Inspection | 1. Click "👥 Roster" on an event. | Displays attendee table with Student Name, Email, Registration Timestamp, and Attendance Status. |
| **AD-05** | Single-Scan Attendance Check-In | 1. Open `/checkin.html`.<br>2. Copy the `qr_token` from a student's ticket.<br>3. Paste into the Check-In Station and click "Validate & Check In". | Ticket validated. Attendee marked as `checked_in`. Check-in timestamp recorded. Green approval card appears. |
| **AD-06** | Duplicate Check-In Prevention | 1. Submit the exact same `qr_token` again into `/checkin.html`. | System rejects check-in with message: *"Already checked in!"* along with previous timestamp. Prevents reuse of ticket. |
| **AD-07** | Cross-College Check-In Defense | 1. As MRECW admin, attempt to check in a ticket token for a CBIT event. | Stored procedure blocks operation: *"Forbidden: You are not authorized to check in participants for other colleges"*. |

