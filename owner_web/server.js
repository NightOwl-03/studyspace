require('dotenv').config();
const express = require('express');
const cors = require('cors');
const multer = require('multer');
const { createClient } = require('@supabase/supabase-js');

// ── ENV DIAGNOSTIC ─────────────────────────────────────────────
console.log('--- ENV CHECK ---');
console.log('SUPABASE_URL     :', process.env.SUPABASE_URL     ? '✅ loaded (' + process.env.SUPABASE_URL + ')' : '❌ MISSING');
console.log('SERVICE_ROLE_KEY :', process.env.SUPABASE_SERVICE_ROLE_KEY ? '✅ loaded (hidden)' : '❌ MISSING');
if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    console.error('\n❌ FATAL: Missing Supabase credentials in .env file.');
    console.error('   Make sure your .env file is in the SAME folder as server.js');
    console.error('   and contains:\n');
    console.error('   SUPABASE_URL=https://xxxx.supabase.co');
    console.error('   SUPABASE_SERVICE_ROLE_KEY=eyJ...\n');
    process.exit(1);
}
console.log('-----------------\n');
// ──────────────────────────────────────────────────────────────

const app = express();
app.use(cors());
app.use(express.json());

// multer: store upload in memory so we can pipe bytes to Supabase Storage
const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 5 * 1024 * 1024 }, // 5 MB cap
    fileFilter: (req, file, cb) => {
        if (!file.mimetype.startsWith('image/')) {
            return cb(new Error('Only image files are allowed.'));
        }
        cb(null, true);
    }
});

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

// Endpoint Registration
app.post('/api/register-owner', async (req, res) => {
    const { email, password, business_name, total_seats } = req.body;

    const { data: authData, error: authError } = await supabase.auth.admin.createUser({
        email,
        password,
        email_confirm: true
    });

    if (authError) return res.status(400).json({ error: authError.message });

    const { error: dbError } = await supabase.from('owners').insert([{
        id: authData.user.id,
        business_name,
        email,
        verification_status: 'unverified'
    }]);

    if (dbError) return res.status(400).json({ error: dbError.message });

    res.json({ message: 'Success! Owner registered.' });
});

app.listen(3000, () => console.log('Server running on port 3000'));

// Login Handler
// Accepted owner email: greencoffee@gmail.com
app.post('/api/login', async (req, res) => {
    const { email } = req.body;
    console.log("Login attempt for:", email);

    // Guard: only allow the registered owner email
    const OWNER_EMAIL = 'greencoffee@gmail.com';
    if (!email || email.trim().toLowerCase() !== OWNER_EMAIL) {
        console.log("Result: Email not authorised");
        return res.status(401).json({ error: 'Invalid credentials.' });
    }

    try {
        const { data: owner, error } = await supabase
            .from('owners')
            .select('*')
            .eq('email', email.trim())
            .maybeSingle();

        if (error) {
            console.error("Supabase Error:", error.message);
            return res.status(500).json({ error: error.message });
        }

        if (!owner) {
            console.log("Result: No owner found in DB");
            return res.status(401).json({ error: 'User not found in owners table.' });
        }

        // Fetch the owner's study spot ID so frontend can scope table operations
        const { data: spot, error: spotError } = await supabase
            .from('study_spots')
            .select('id')
            .eq('owner_id', owner.id)
            .maybeSingle();

        if (spotError) console.error("Could not fetch study_spot:", spotError.message);

        console.log("Result: Success! Owner found.");
        return res.status(200).json({
            message: 'Login successful',
            user: { ...owner, study_spot_id: spot ? spot.id : null }
        });

    } catch (err) {
        console.error('Login handler exception:', err.message);
        return res.status(500).json({ error: 'Internal Server Error: ' + err.message });
    }
});

// 1. Get Reservations with User Names and Table Number (Join)
app.get('/api/reservations', async (req, res) => {
    const { study_spot_id } = req.query;
    try {
        let query = supabase
            .from('reservations')
            .select(`
                id,
                booking_reference,
                reservation_date,
                start_time,
                number_of_seats,
                reservation_status,
                created_at,
                users (first_name, surname, email),
                reservation_details (
                    study_spot_tables (table_number)
                )
            `)
            
            .order('reservation_date', { ascending: false }) // Descending date
            .order('start_time', { ascending: false });      // Descending time;

        if (study_spot_id) query = query.eq('study_spot_id', study_spot_id);

        const { data, error } = await query;
        if (error) throw error;

        const formatted = data.map(res => {
            // Extract table number from the first reservation_detail if available
            const detail = Array.isArray(res.reservation_details) && res.reservation_details[0];
            const tableNumber = detail?.study_spot_tables?.table_number ?? null;

            // Fall back to a UUID-derived ref for rows that predate the
            // booking_reference feature (booking_reference column was NULL).
            const derivedRef = res.id.replace(/-/g, '').toUpperCase().substring(0, 8);
            return {
                id: res.id,
                booking_ref: res.booking_reference || derivedRef,
                name: `${res.users.first_name} ${res.users.surname}`,
                contact: res.users.email,
                date: res.reservation_date,
                time: res.start_time,
                seats: res.number_of_seats,
                status: res.reservation_status.charAt(0).toUpperCase() + res.reservation_status.slice(1),
                table_number: tableNumber,
                created_at: res.created_at   // used by frontend NEW badge
            };
        });

        res.json(formatted);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// 2. Get Live Table Status with confirmed reservation seat counts
app.get('/api/tables', async (req, res) => {
    const { study_spot_id } = req.query;
    try {
        // Step 1: fetch tables
        let tableQuery = supabase
            .from('study_spot_tables')
            .select('*')
            .order('table_number', { ascending: true });

        if (study_spot_id) tableQuery = tableQuery.eq('study_spot_id', study_spot_id);

        const { data: tables, error: tableError } = await tableQuery;
        if (tableError) throw tableError;
        if (!tables || tables.length === 0) return res.json([]);

        const tableIds = tables.map(t => t.id);

        // Step 2: fetch all seats for those tables
        const { data: seats, error: seatError } = await supabase
            .from('seats')
            .select('id, table_id, seat_number, seat_status')
            .in('table_id', tableIds);

        if (seatError) {
            console.warn('Could not fetch seats:', seatError.message);
        }

        // Step 3: fetch confirmed seat counts per table from reservation_details
        // Counts reservations with status: confirmed, checked_in, or pending
        const { data: reservationDetails, error: rdError } = await supabase
            .from('reservation_details')
            .select('table_id, reservations!inner(number_of_seats, reservation_status)')
            .in('table_id', tableIds);

        if (rdError) {
            console.warn('Could not fetch reservation_details:', rdError.message);
        }

        // Step 4: sum confirmed seats per table_id — capped at seat_capacity
        const confirmedSeatsByTable = {};
        if (Array.isArray(reservationDetails)) {
            reservationDetails.forEach(rd => {
                const res = rd.reservations;
                if (!res) return;
                const status = res.reservation_status;
                if (!['confirmed', 'checked_in', 'pending'].includes(status)) return;
                const count = res.number_of_seats || 0;
                confirmedSeatsByTable[rd.table_id] = (confirmedSeatsByTable[rd.table_id] || 0) + count;
            });
        }

        // Step 5: attach seats and confirmed_seats to their parent table.
        // Also derive a single authoritative status from real data so the badge
        // and the dropdown always agree:
        //   occupied  → confirmed_seats >= seat_capacity  OR  table_status = 'occupied'
        //   reserved  → confirmed_seats > 0
        //   available → no reservations
        const tablesWithSeats = tables.map(table => {
            const capacity = table.seat_capacity || 0;
            // Cap so we never show "8/5"
            const rawTaken = confirmedSeatsByTable[table.id] || 0;
            const confirmedSeats = Math.min(rawTaken, capacity);

            // Derive status from reservation data; fall back to DB column only
            // when there are no active reservations at all.
            let derivedStatus;
            if (capacity > 0 && confirmedSeats >= capacity) {
                derivedStatus = 'occupied';
            } else if (confirmedSeats > 0) {
                derivedStatus = 'reserved';
            } else {
                // No active reservations — honour whatever the owner set manually
                derivedStatus = table.table_status || 'available';
            }

            return {
                ...table,
                table_status: derivedStatus,          // single source of truth
                seats: (seats || []).filter(s => s.table_id === table.id),
                confirmed_seats: confirmedSeats
            };
        });

        res.json(tablesWithSeats);
    } catch (err) {
        console.error('GET /api/tables error:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// 3. Add New Table
app.post('/api/tables', async (req, res) => {
    const { table_number, seat_capacity, table_status, study_spot_id } = req.body;

    if (!study_spot_id) {
        return res.status(400).json({ error: 'study_spot_id is required.' });
    }

    try {
        const { data, error } = await supabase
            .from('study_spot_tables')
            .insert([{
                study_spot_id,
                table_number: String(table_number),   // varchar in DB
                seat_capacity: parseInt(seat_capacity),
                table_status: table_status || 'available'
            }])
            .select();

        if (error) {
            console.error('Supabase insert error:', error.message);
            throw error;
        }
        res.json(data[0]);
    } catch (err) {
        console.error('POST /api/tables error:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// 4. Get Reviews with User Names (Join)
app.get('/api/reviews', async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('reviews')
            .select(`
                id,
                rating,
                comment,
                review_date,
                users (first_name, surname, profile_picture_url)
            `)
            .order('review_date', { ascending: false });

        if (error) throw error;

        const formatted = data.map(review => {
            const nameParts = [review.users?.first_name, review.users?.surname].filter(Boolean);
            const customerName = nameParts.length ? nameParts.join(' ') : 'Anonymous';
            return {
                customer: customerName,
                avatar: review.users?.profile_picture_url || null,
                rating: review.rating,
                comment: review.comment,
                time: timeAgo(review.review_date)
            };
        });

        res.json(formatted);
    } catch (err) {
        console.error('GET /api/reviews error:', err.message, err.stack);
        res.status(500).json({ error: err.message });
    }
});

// 4b. Submit a review (called from Flutter app after completed reservation)
app.post('/api/reviews', async (req, res) => {
    try {
        const { user_id, study_spot_id, rating, comment } = req.body;

        if (!user_id || !study_spot_id || !rating) {
            return res.status(400).json({ error: 'user_id, study_spot_id, and rating are required.' });
        }
        if (rating < 1 || rating > 5) {
            return res.status(400).json({ error: 'Rating must be between 1 and 5.' });
        }

        // Prevent duplicate review for same user+spot
        const { data: existing } = await supabase
            .from('reviews')
            .select('id')
            .eq('user_id', user_id)
            .eq('study_spot_id', study_spot_id);

        if (existing && existing.length > 0) {
            return res.status(409).json({ error: 'You have already reviewed this spot.' });
        }

        // Insert the review
        const { data: review, error: reviewErr } = await supabase
            .from('reviews')
            .insert({
                user_id,
                study_spot_id,
                rating: parseInt(rating, 10),
                comment: comment || null,
                verified_review: true,
                review_date: new Date().toISOString(),
            })
            .select('id')
            .single();

        if (reviewErr) throw reviewErr;

        // Recalculate and update study_spots average_rating + total_reviews
        const { data: allReviews } = await supabase
            .from('reviews')
            .select('rating')
            .eq('study_spot_id', study_spot_id);

        if (allReviews && allReviews.length > 0) {
            const avg = allReviews.reduce((sum, r) => sum + r.rating, 0) / allReviews.length;
            await supabase
                .from('study_spots')
                .update({
                    average_rating: Math.round(avg * 10) / 10,
                    total_reviews: allReviews.length,
                    updated_at: new Date().toISOString(),
                })
                .eq('id', study_spot_id);
        }

        // Notify the owner
        const { data: spot } = await supabase
            .from('study_spots')
            .select('owner_id, name')
            .eq('id', study_spot_id)
            .single();

        if (spot?.owner_id) {
            const stars = '⭐'.repeat(parseInt(rating, 10));
            const preview = comment
                ? ': "' + comment.substring(0, 80) + (comment.length > 80 ? '..."' : '"')
                : '.';
            await supabase.from('owner_notifications').insert({
                owner_id: spot.owner_id,
                notification_type: 'review_posted',
                title: 'New Review Received',
                message: `A customer rated ${spot.name} ${stars} (${rating}/5)${preview}`,
                related_resource_id: review.id,
                is_read: false,
            });
        }

        res.json({ success: true, review_id: review.id });
    } catch (err) {
        console.error('POST /api/reviews error:', err.message, err.stack);
        res.status(500).json({ error: err.message });
    }
});

// 5. Get Overview Stats
app.get('/api/overview', async (req, res) => {
    try {
        const today = new Date().toISOString().split('T')[0];
        const { study_spot_id } = req.query; 

        // 1. Fetch Official Reservations (excluding cancelled ones)
        let resQuery = supabase
            .from('reservations')
            .select('number_of_seats')
            .neq('reservation_status', 'cancelled');
        
        if (study_spot_id) resQuery = resQuery.eq('study_spot_id', study_spot_id);
        const { data: resData, error: resError } = await resQuery;
        if (resError) throw resError;

        const officialReservedSeats = resData.reduce((sum, r) => sum + r.number_of_seats, 0);

        // 2. Fetch Today's Reservation Count
        let countQuery = supabase
            .from('reservations')
            .select('*', { count: 'exact', head: true })
            .eq('reservation_date', today)
            .neq('reservation_status', 'cancelled');
        
        if (study_spot_id) countQuery = countQuery.eq('study_spot_id', study_spot_id);
        const { count: todayCount, error: todayError } = await countQuery;
        if (todayError) throw todayError;

        // 3. Fetch Table Data to check Manual "Reserved" status and Occupancy
        let tablesQuery = supabase
            .from('study_spot_tables')
            .select('seat_capacity, table_status');
        
        if (study_spot_id) tablesQuery = tablesQuery.eq('study_spot_id', study_spot_id);
        const { data: tablesData, error: tablesError } = await tablesQuery;
        if (tablesError) throw tablesError;

        // Calculate seats from tables manually set to 'reserved' in the UI
        const manualReservedSeats = tablesData
            .filter(t => t.table_status === 'reserved')
            .reduce((sum, t) => sum + t.seat_capacity, 0);

        // Total Seats Reserved = Official Bookings + Manual UI Toggles
        const totalSeatsReserved = officialReservedSeats + manualReservedSeats;

        // Use study_spots.available_seats to calculate occupancy correctly.
        let spotQuery = supabase.from('study_spots').select('available_seats,total_seats');
        if (study_spot_id) spotQuery = spotQuery.eq('id', study_spot_id).maybeSingle();
        const { data: spotData, error: spotError } = await spotQuery;
        if (spotError) throw spotError;

     // 1. Fetch seats by joining with study_spot_tables
        let seatsQuery = supabase
            .from('seats')
            .select(`
                seat_status,
                study_spot_tables!inner(study_spot_id)
            `);

        if (study_spot_id) {
            // This filters the seats based on the ID inside the joined table
            seatsQuery = seatsQuery.eq('study_spot_tables.study_spot_id', study_spot_id);
        }

        const { data: seatData, error: seatError } = await seatsQuery;

        if (seatError) {
            console.error('Overview API Error:', seatError.message);
            return res.status(500).json({ error: seatError.message });
        }

        // 2. The rest of the logic remains the same
        const totalSeats = seatData.length;
        const occupiedSeats = seatData.filter(s => 
            s.seat_status === 'occupied' || s.seat_status === 'reserved'
        ).length;
        const availableSeats = totalSeats - occupiedSeats;

        const occupiedPct = totalSeats > 0 ? Math.round((occupiedSeats / totalSeats) * 100) : 0;
        const availablePct = totalSeats > 0 ? Math.round((availableSeats / totalSeats) * 100) : 0;

        // Send to frontend
        res.json({
            totalSeatsReserved, // ensure this is defined earlier in your route
            todayReservations: todayCount || 0,
            availableCapacityPct: availablePct,
            occupiedPct,
            occupiedSeats,
            totalSeats
        });

    } catch (err) {
        console.error('Overview API Error:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// 6. Weekly Reservations (last 7 days, Mon–Sun order)
app.get('/api/analytics/weekly', async (req, res) => {
    try {
        // Get the last 7 days
        const days = Array.from({ length: 7 }, (_, i) => {
            const d = new Date();
            d.setDate(d.getDate() - (6 - i));
            return d.toISOString().split('T')[0];
        });

        const { data, error } = await supabase
            .from('reservations')
            .select('reservation_date')
            .in('reservation_date', days)
            .neq('reservation_status', 'cancelled');

        if (error) throw error;

        // Count reservations per day
        const counts = days.map(day => ({
            label: new Date(day).toLocaleDateString('en-US', { weekday: 'short' }),
            count: data.filter(r => r.reservation_date === day).length
        }));

        res.json(counts);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// 7. Peak Hours (today's reservations grouped by start hour)
app.get('/api/analytics/peak-hours', async (req, res) => {
    try {
        const today = new Date().toISOString().split('T')[0];

        const { data, error } = await supabase
            .from('reservations')
            .select('start_time')
            .eq('reservation_date', today)
            .neq('reservation_status', 'cancelled');

        if (error) throw error;

        // Build hourly buckets (8:00 to 22:00, every 2 hrs)
        const hours = ['8:00', '10:00', '12:00', '14:00', '16:00', '18:00', '20:00', '22:00'];
        const counts = hours.map(slot => {
            const slotHour = parseInt(slot.split(':')[0]);
            const count = data.filter(r => {
                const hour = parseInt(r.start_time.split(':')[0]);
                return hour >= slotHour && hour < slotHour + 2;
            }).length;
            return { label: slot, count };
        });

        res.json(counts);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// 8. Cancel a Reservation
app.patch('/api/reservations/:id/cancel', async (req, res) => {
    const reservationId = req.params.id;
    try {
        // 1. I-update ang status ug kuhaa ang user_id para sa notification
        const { data: reservation, error } = await supabase
            .from('reservations')
            .update({ reservation_status: 'cancelled' })
            .eq('id', reservationId)
            .select('user_id')
            .maybeSingle();

        if (error) throw error;

        // 2. I-release ang mga seats (i-set sa 'available')
        await syncSeatsForReservation(reservationId, 'cancelled');

        // 3. I-insert ang notification para sa Flutter App[cite: 4]
        if (reservation && reservation.user_id) {
            await supabase
                .from('user_notifications')
                .insert([{
                    user_id: reservation.user_id,
                    reservation_id: reservationId,
                    title: 'Reservation Cancelled',
                    message: 'Your reservation has been cancelled by the owner.',
                    notification_type: 'cancellation',
                    is_read: false,
                    created_at: new Date().toISOString()
                }]);
        }

        res.json({ message: 'Reservation cancelled and user notified.' });
    } catch (err) {
        console.error('Cancel Error:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// 9. Update Reservation Status
app.patch('/api/reservations/:id/status', async (req, res) => {
    const { status } = req.body;
    const reservationId = req.params.id;

    try {
        const { data: reservation, error: reservationError } = await supabase
            .from('reservations')
            .select('id, user_id, study_spot_id, reservation_status')
            .eq('id', reservationId)
            .maybeSingle();

        if (reservationError) throw reservationError;
        if (!reservation) return res.status(404).json({ error: 'Reservation not found.' });

        const { error: updateError } = await supabase
            .from('reservations')
            .update({ reservation_status: status })
            .eq('id', reservationId);

        if (updateError) throw updateError;

        if (reservation.user_id) {
            const typeMap = {
                confirmed:  'reservation_confirmed',
                cancelled:  'cancellation',
                checked_in: 'system',
                completed:  'system',
                pending:    'system',
            };
            const titleMap = {
                confirmed:  'Reservation Confirmed',
                cancelled:  'Reservation Cancelled',
                checked_in: 'You are Checked In',
                completed:  'Visit Completed',
                pending:    'Reservation Pending',
            };
            const notifType = typeMap[status] || 'system';

            const { error: notifyError } = await supabase
                .from('user_notifications')
                .insert([{
                    user_id: reservation.user_id,
                    reservation_id: reservationId,
                    notification_type: notifType,
                    title: titleMap[status] || 'Reservation Update',
                    message: `Your reservation is now ${status}.`,
                    is_read: false,
                    created_at: new Date().toISOString()
                }]);

            if (notifyError) {
                console.error('Failed to insert user notification:', notifyError?.message || JSON.stringify(notifyError));
            }
        }

        // Sync seat statuses to match new reservation status
        await syncSeatsForReservation(reservationId, status);

        res.json({ message: 'Status updated.' });
    } catch (err) {
        const detail = err?.details || err?.hint || err?.code || '';
        console.error('PATCH /api/reservations/:id/status error:', err.message, detail);
        res.status(500).json({ error: err.message, detail });
    }
});

// 10. Update Table Status — also syncs all seat statuses for that table
app.patch('/api/tables/:id/status', async (req, res) => {
    const { table_status } = req.body;
    const tableId = req.params.id;

    // Map table status → seat status
    const seatStatusMap = {
        'available': 'available',
        'occupied':  'occupied',
        'reserved':  'reserved',
    };
    const newSeatStatus = seatStatusMap[table_status] || 'available';

    try {
        // 1. Update the table record
        const { error: tableError } = await supabase
            .from('study_spot_tables')
            .update({ table_status })
            .eq('id', tableId);
        if (tableError) throw tableError;

        // 2. Sync all seats belonging to this table
        const { error: seatError } = await supabase
            .from('seats')
            .update({ seat_status: newSeatStatus, updated_at: new Date().toISOString() })
            .eq('table_id', tableId);
        if (seatError) {
            console.warn('Seat sync warning (non-fatal):', seatError.message);
        }

        res.json({ message: 'Table and seat statuses updated.' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// 11. Delete Table
app.delete('/api/tables/:id', async (req, res) => {
    try {
        const { error } = await supabase
            .from('study_spot_tables')
            .delete()
            .eq('id', req.params.id);

        if (error) throw error;
        res.json({ message: 'Table deleted.' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});


// 12. Update seat statuses when reservation is confirmed/cancelled
//     Called by Flutter after a reservation is made or status changes
app.patch('/api/reservations/:id/sync-seats', async (req, res) => {
    const reservationId = req.params.id;
    try {
        // Get reservation + its assigned seats from reservation_details
        const { data: reservation, error: resError } = await supabase
            .from('reservations')
            .select('id, reservation_status, study_spot_id')
            .eq('id', reservationId)
            .maybeSingle();

        if (resError) throw resError;
        if (!reservation) return res.status(404).json({ error: 'Reservation not found.' });

        const { data: details, error: detailsError } = await supabase
            .from('reservation_details')
            .select('seat_id, table_id')
            .eq('reservation_id', reservationId);

        if (detailsError) throw detailsError;
        if (!details || details.length === 0) {
            return res.json({ message: 'No seat assignments found for this reservation.', synced: 0 });
        }

        const seatIds = details.map(d => d.seat_id);

        // Map reservation status → seat status
        const statusMap = {
            'confirmed':   'reserved',
            'checked_in':  'occupied',
            'completed':   'available',
            'cancelled':   'available',
            'pending':     'reserved',
        };
        const newSeatStatus = statusMap[reservation.reservation_status] || 'available';

        const { error: updateError } = await supabase
            .from('seats')
            .update({ seat_status: newSeatStatus, updated_at: new Date().toISOString() })
            .in('id', seatIds);

        if (updateError) throw updateError;

        res.json({ message: `Synced ${seatIds.length} seat(s) to '${newSeatStatus}'.`, synced: seatIds.length });
    } catch (err) {
        console.error('PATCH /api/reservations/:id/sync-seats error:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// 13. Directly set seat status by seat IDs (called by Flutter during booking flow)
app.patch('/api/seats/status', async (req, res) => {
    const { seat_ids, seat_status } = req.body;

    if (!Array.isArray(seat_ids) || seat_ids.length === 0) {
        return res.status(400).json({ error: 'seat_ids must be a non-empty array.' });
    }

    try {
        const { data, error } = await supabase
            .from('seats')
            .update({ seat_status: seat_status, updated_at: new Date().toISOString() })
            .in('id', seat_ids) // Ginagamit ang 'in' para sa array sa IDs
            .select();

        if (error) throw error;
        res.json({ message: 'Seats updated successfully', data });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// 14. Auto-sync: when reservation status changes, also update seat statuses
//     Trigger this internally from the status update endpoint
// syncSeatsForReservation defined below


// ── Seat Sync Helper ──────────────────────────────────────────────────────────
async function syncSeatsForReservation(reservationId, reservationStatus) {
    try {
        const statusMap = {
            'pending':    'reserved',
            'confirmed':  'reserved',
            'checked_in': 'occupied',
            'completed':  'available',
            'cancelled':  'available',
        };
        const newSeatStatus = statusMap[reservationStatus];
        if (!newSeatStatus) return;

        // Fetch seat_id AND table_id so we can reset the parent table too
        const { data: details } = await supabase
            .from('reservation_details')
            .select('seat_id, table_id')
            .eq('reservation_id', reservationId);

        if (!details || details.length === 0) return;

        // 1. Reset individual seat statuses
        const seatIds = details.map(d => d.seat_id).filter(Boolean);
        if (seatIds.length > 0) {
            const { error } = await supabase
                .from('seats')
                .update({ seat_status: newSeatStatus, updated_at: new Date().toISOString() })
                .in('id', seatIds);

            if (error) console.error('syncSeatsForReservation seat error:', error.message);
            else console.log(`Synced ${seatIds.length} seat(s) -> '${newSeatStatus}' for reservation ${reservationId}`);
        }

        // 2. When a reservation ends (cancelled / completed), also reset the
        //    parent table's stored status back to 'available' so stale
        //    'occupied' values never persist in study_spot_tables.
        if (['completed', 'cancelled'].includes(reservationStatus)) {
            const tableIds = [...new Set(details.map(d => d.table_id).filter(Boolean))];
            if (tableIds.length > 0) {
                const { error: tableErr } = await supabase
                    .from('study_spot_tables')
                    .update({ table_status: 'available' })
                    .in('id', tableIds);

                if (tableErr) console.error('Table status reset error:', tableErr.message);
                else console.log(`Reset ${tableIds.length} table(s) -> 'available' after ${reservationStatus}`);
            }
        }
    } catch (err) {
        console.error('syncSeatsForReservation exception:', err.message);
    }
}

// 12. Directly update seat statuses by seat IDs
// Helper: relative time string
function timeAgo(dateStr) {
    // new Date() correctly parses ISO strings with or without timezone offset.
    // If there's no offset and no Z, treat as UTC by appending Z.
    let str = dateStr || '';
    const hasOffset = str.endsWith('Z') || /[+-]\d{2}:\d{2}$/.test(str);
    const utcStr = hasOffset ? str : str + 'Z';
    const diff = Date.now() - new Date(utcStr).getTime();
    if (isNaN(diff) || diff < 0) return 'Just now'; // bad parse or clock skew
    const mins = Math.floor(diff / 60000);
    if (mins < 1) return 'Just now';
    if (mins < 60) return `${mins} minute${mins !== 1 ? 's' : ''} ago`;
    const hrs = Math.floor(mins / 60);
    if (hrs < 24) return `${hrs} hour${hrs !== 1 ? 's' : ''} ago`;
    const days = Math.floor(hrs / 24);
    if (days < 30) return `${days} day${days !== 1 ? 's' : ''} ago`;
    const months = Math.floor(days / 30);
    return `${months} month${months !== 1 ? 's' : ''} ago`;
}

// ─────────────────────────────────────────────
// OWNER PROFILE ENDPOINTS
// ─────────────────────────────────────────────

// GET /api/owner/profile — fetch owner info
app.get('/api/owner/profile', async (req, res) => {
    const { owner_id } = req.query;
    if (!owner_id) return res.status(400).json({ error: 'owner_id required.' });
    try {
        const { data, error } = await supabase
            .from('owners')
            .select('id, owner_name, email, phone_number, business_name, profile_picture_url')
            .eq('id', owner_id)
            .maybeSingle();
        if (error) throw error;
        if (!data) return res.status(404).json({ error: 'Owner not found.' });
        res.json(data);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ─────────────────────────────────────────────
// AVATAR UPLOAD ENDPOINT
// Receives the image file from the frontend, uploads it to Supabase Storage
// using the service-role key (bypasses RLS), then returns the public URL.
// This sidesteps the "row-level security policy" error that occurs when the
// browser tries to upload directly with the anon key without a Supabase session.
// ─────────────────────────────────────────────
const AVATAR_BUCKET = 'avatars';

app.post('/api/owner/avatar', upload.single('avatar'), async (req, res) => {
    const { owner_id } = req.body;
    if (!owner_id)  return res.status(400).json({ error: 'owner_id is required.' });
    if (!req.file)  return res.status(400).json({ error: 'No image file received.' });

    try {
        const ext      = req.file.originalname.split('.').pop().toLowerCase();
        const filePath = `owner-profiles/${owner_id}-${Date.now()}.${ext}`;

        // Upload with the service-role client → RLS is bypassed server-side
        const { error: uploadError } = await supabase
            .storage
            .from(AVATAR_BUCKET)
            .upload(filePath, req.file.buffer, {
                contentType: req.file.mimetype,
                upsert: true
            });

        if (uploadError) {
            // Surface a clear message if the bucket name is wrong
            if (uploadError.message.toLowerCase().includes('bucket not found')) {
                return res.status(404).json({
                    error: `Bucket "${AVATAR_BUCKET}" not found. ` +
                           `Create it in Supabase Dashboard → Storage and name it exactly "${AVATAR_BUCKET}".`
                });
            }
            throw uploadError;
        }

        // Build the permanent public URL (no auth required to view)
        const { data: urlData } = supabase.storage.from(AVATAR_BUCKET).getPublicUrl(filePath);
        const publicUrl = urlData.publicUrl;

        // Immediately persist to the owners table so the URL is never lost
        const { error: dbError } = await supabase
            .from('owners')
            .update({ profile_picture_url: publicUrl, updated_at: new Date().toISOString() })
            .eq('id', owner_id);

        if (dbError) throw dbError;

        res.json({ message: 'Avatar uploaded.', profile_picture_url: publicUrl });
    } catch (err) {
        console.error('Avatar upload error:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// PATCH /api/owner/profile — update owner name/phone/business/profile_picture_url
app.patch('/api/owner/profile', async (req, res) => {
    const { owner_id, owner_name, phone_number, business_name, profile_picture_url } = req.body;
    if (!owner_id) return res.status(400).json({ error: 'owner_id required.' });

    // Critical-field validation
    if (owner_name !== undefined && !owner_name.trim())
        return res.status(400).json({ error: 'Name cannot be empty.' });
    if (business_name !== undefined && !business_name.trim())
        return res.status(400).json({ error: 'Business name cannot be empty.' });

    try {
        const updates = { updated_at: new Date().toISOString() };
        if (owner_name !== undefined)          updates.owner_name = owner_name.trim();
        if (phone_number !== undefined)        updates.phone_number = phone_number;
        if (business_name !== undefined)       updates.business_name = business_name.trim();
        if (profile_picture_url !== undefined) updates.profile_picture_url = profile_picture_url;

        const { data, error } = await supabase
            .from('owners')
            .update(updates)
            .eq('id', owner_id)
            .select('owner_name, email, phone_number, business_name, profile_picture_url')
            .maybeSingle();

        if (error) throw error;
        res.json({ message: 'Profile updated.', ...data });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /api/owner/shop — fetch study spot details
app.get('/api/owner/shop', async (req, res) => {
    const { study_spot_id } = req.query;
    if (!study_spot_id) return res.status(400).json({ error: 'study_spot_id required.' });
    try {
        const { data, error } = await supabase
            .from('study_spots')
            .select('id, name, description, location_address, opening_time, closing_time, email, phone_number, image_urls')
            .eq('id', study_spot_id)
            .maybeSingle();
        if (error) throw error;
        if (!data) return res.status(404).json({ error: 'Study spot not found.' });
        res.json(data);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// PATCH /api/owner/shop — update shop details
app.patch('/api/owner/shop', async (req, res) => {
    const { study_spot_id, name, description, opening_time, closing_time, location_address, email, phone_number } = req.body;

    console.log('[PATCH /api/owner/shop] Received body:', req.body);

    if (!study_spot_id) return res.status(400).json({ error: 'study_spot_id required.' });

    // Critical-field validation
    if (location_address !== undefined && !String(location_address).trim())
        return res.status(400).json({ error: 'Address cannot be empty.' });

    try {
        const updates = { updated_at: new Date().toISOString() };
        if (name !== undefined)             updates.name = String(name).trim();
        if (description !== undefined)      updates.description = description;
        if (opening_time !== undefined)     updates.opening_time = opening_time || null;
        if (closing_time !== undefined)     updates.closing_time = closing_time || null;
        if (location_address !== undefined) updates.location_address = String(location_address).trim();
        if (email !== undefined)            updates.email = email;
        if (phone_number !== undefined)     updates.phone_number = phone_number;

        console.log('[PATCH /api/owner/shop] Applying updates:', updates);

        const { data, error } = await supabase
            .from('study_spots')
            .update(updates)
            .eq('id', study_spot_id)
            .select('id, name, description, location_address, opening_time, closing_time, email, phone_number, image_urls')
            .maybeSingle();

        if (error) {
            console.error('[PATCH /api/owner/shop] Supabase error:', error.message);
            throw error;
        }

        if (!data) {
            console.warn('[PATCH /api/owner/shop] No row matched study_spot_id:', study_spot_id);
            return res.status(404).json({ error: 'Study spot not found. Check study_spot_id.' });
        }

        console.log('[PATCH /api/owner/shop] Updated successfully:', data.id);
        res.json({ message: 'Shop details updated.', ...data });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ─────────────────────────────────────────────
// MESSAGING ENDPOINTS
// Note: These use an in-DB messages table. If you haven't created it yet,
// the endpoints return graceful empty responses so the UI won't break.
// Suggested schema:
//   CREATE TABLE messages (
//     id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
//     conversation_id uuid REFERENCES conversations(id),
//     sender_type varchar CHECK (sender_type IN ('owner','user')),
//     message text NOT NULL,
//     created_at timestamptz DEFAULT now()
//   );
//   CREATE TABLE conversations (
//     id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
//     study_spot_id uuid REFERENCES study_spots(id),
//     reservation_id uuid REFERENCES reservations(id),
//     customer_email varchar NOT NULL,
//     customer_name varchar,
//     last_message text,
//     last_message_time timestamptz,
//     unread boolean DEFAULT false,
//     created_at timestamptz DEFAULT now()
//   );
// ─────────────────────────────────────────────

// GET /api/messages/conversations — list all conversations for this study spot
// ── REPLACE: GET /api/messages/conversations ──
app.get('/api/messages/conversations', async (req, res) => {
    const { study_spot_id } = req.query;
    try {
        // ── Step 1: fetch conversations ──────────────────────────────────────
        let query = supabase
            .from('conversations')
            .select('*')
            .order('last_message_time', { ascending: false });
 
        if (study_spot_id) query = query.eq('study_spot_id', study_spot_id);
 
        const { data: convos, error: convError } = await query;
        if (convError) throw convError;
        if (!convos || convos.length === 0) return res.json([]);
 
        // ── Step 2: fetch user profiles for every unique customer_email ──────
        // conversations.customer_email has no FK → we do a manual lookup.
        const uniqueEmails = [...new Set(convos.map(c => c.customer_email).filter(Boolean))];
 
        const { data: users, error: userError } = await supabase
            .from('users')
            .select('email, first_name, surname, profile_picture_url')
            .in('email', uniqueEmails);
 
        if (userError) {
            // Non-fatal: fall through with whatever data we have.
            console.warn('Could not fetch user profiles for conversations:', userError.message);
        }
 
        // Build a quick lookup map  email → user row
        const userMap = {};
        (users || []).forEach(u => { userMap[u.email] = u; });
 
        // ── Step 3: merge profile data into each conversation ────────────────
        const enriched = convos.map(conv => {
            const user = userMap[conv.customer_email];
            const fullName = user
                ? [user.first_name, user.surname].filter(Boolean).join(' ')
                : null;
 
            return {
                ...conv,
                // Override customer_name with the real DB name when available.
                // Falls back to whatever was stored on the conversation row
                // (often the email address) so nothing ever shows as blank.
                customer_name: fullName || conv.customer_name || conv.customer_email || 'Unknown',
                profile_picture_url: user?.profile_picture_url ?? null,
            };
        });
 
        res.json(enriched);
    } catch (err) {
        console.warn('Conversations fetch failed:', err.message);
        res.json([]); // graceful fallback keeps the UI functional
    }
});

// GET /api/messages/:conversationId — get messages for a conversation
app.get('/api/messages/:conversationId', async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('messages')
            .select('*')
            .eq('conversation_id', req.params.conversationId)
            .order('created_at', { ascending: true });
        if (error) throw error;
        res.json(data || []);
    } catch (err) {
        console.warn('Messages table not available:', err.message);
        res.json([]);
    }
});

app.post('/api/messages/:conversationId/send', async (req, res) => {
    const { message, sender_type } = req.body;
    const conversationId = req.params.conversationId;

    try {
        // 1. Insert actual message
        const { error: msgError } = await supabase.from('messages').insert([{
            conversation_id: conversationId,
            sender_type: 'owner',
            message: message
        }]);
        if (msgError) throw msgError;

        // 2. Update conversation preview ug mark as unread para sa user[cite: 11]
        await supabase.from('conversations').update({
            last_message: message,
            last_message_time: new Date().toISOString(),
            unread: true 
        }).eq('id', conversationId);

        // 3. TRIGGER NOTIFICATION: Para makita sa Notifications Screen sa user[cite: 3, 11]
        const { data: convo } = await supabase.from('conversations').select('customer_email').eq('id', conversationId).single();
        const { data: user } = await supabase.from('users').select('id').eq('email', convo.customer_email).single();

        if (user) {
            await supabase.from('user_notifications').insert([{
                user_id: user.id,
                title: 'New Message',
                message: `Owner: ${message}`,
                notification_type: 'system',
                is_read: false
            }]);
        }

        res.json({ success: true });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: err.message });
    }
});

// POST /api/messages/new — create new conversation + send first message
app.post('/api/messages/new', async (req, res) => {
    const { customer_email, reservation_id, message, study_spot_id } = req.body;
    if (!customer_email || !message) return res.status(400).json({ error: 'customer_email and message required.' });
    try {
        // Get customer name from users table
        const { data: userRow } = await supabase
            .from('users')
            .select('first_name, surname')
            .eq('email', customer_email)
            .maybeSingle();
        const customerName = userRow ? `${userRow.first_name} ${userRow.surname}` : customer_email;

        const { data: conv, error: convError } = await supabase
            .from('conversations')
            .insert([{
                study_spot_id: study_spot_id || null,
                reservation_id: reservation_id || null,
                customer_email,
                customer_name: customerName,
                last_message: message,
                last_message_time: new Date().toISOString(),
                unread: true
            }])
            .select()
            .maybeSingle();
        if (convError) throw convError;

        await supabase.from('messages').insert([{
            conversation_id: conv.id,
            sender_type: 'owner',
            message
        }]);

        const { data: userIdRow } = await supabase
            .from('users')
            .select('id')
            .eq('email', customer_email)
            .maybeSingle();

        if (userIdRow?.id) {
            await supabase.from('user_notifications').insert([{
                user_id: userIdRow.id,
                notification_type: 'system',
                title: 'New message from your study spot',
                message: message,
                is_read: false,
                created_at: new Date().toISOString(),
            }]);
        }

        res.json({ conversation: conv });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});