import { jest } from '@jest/globals';
import request from 'supertest';
import jwt from 'jsonwebtoken';
import app from '../src/app.js';
import pool from '../src/config/db.js';

describe('POST /api/bookings/initiate Concurrency & Locking', () => {
  let authToken;
  let testUserId;
  let testMovieId;
  let testSeatId;

  beforeAll(async () => {
    // 1. Mock global fetch so Brevo email API is not actually called during tests
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ message: 'Mocked email sent successfully' }),
    });

    // 2. Clean up any previous run of this specific test only
    await pool.query(`
      DELETE FROM otp_verifications WHERE booking_id IN (
        SELECT b.id FROM bookings b 
        JOIN users u ON b.user_id = u.id 
        WHERE u.email = 'test.concurrency@example.com'
      )
    `);
    await pool.query(`
      DELETE FROM bookings WHERE user_id IN (
        SELECT id FROM users WHERE email = 'test.concurrency@example.com'
      )
    `);
    await pool.query(`
      DELETE FROM seats WHERE movie_id IN (
        SELECT id FROM movies WHERE title = 'Concurrency Test Movie'
      )
    `);
    await pool.query('DELETE FROM movies WHERE title = $1', ['Concurrency Test Movie']);
    await pool.query('DELETE FROM users WHERE email = $1', ['test.concurrency@example.com']);

    // 3. Create a test user
    const userRes = await pool.query(
      `INSERT INTO users (google_id, email, name)
       VALUES ($1, $2, $3)
       RETURNING id`,
      ['google-test-concurrency-id', 'test.concurrency@example.com', 'Concurrency Tester']
    );
    testUserId = userRes.rows[0].id;

    // 4. Generate JWT for the test user
    authToken = jwt.sign(
      { userId: testUserId, email: 'test.concurrency@example.com' },
      process.env.JWT_SECRET || 'super_secret_jwt_key_for_development',
      { expiresIn: '1h' }
    );

    // 5. Create a test movie and 1 AVAILABLE seat
    const movieRes = await pool.query(
      `INSERT INTO movies (title, poster_url, showtime)
       VALUES ($1, $2, NOW() + INTERVAL '1 day')
       RETURNING id`,
      ['Concurrency Test Movie', 'https://example.com/poster.jpg']
    );
    testMovieId = movieRes.rows[0].id;

    const seatRes = await pool.query(
      `INSERT INTO seats (movie_id, seat_number, status)
       VALUES ($1, $2, 'AVAILABLE')
       RETURNING id`,
      [testMovieId, 'A1']
    );
    testSeatId = seatRes.rows[0].id;
  });


  it('should allow only 1 user to reserve the seat and reject all other concurrent requests with 409', async () => {
    const concurrentRequestsCount = 20;

    // Fire 20 simultaneous booking requests for the exact same seat at the same millisecond
    const requests = Array.from({ length: concurrentRequestsCount }).map(() =>
      request(app)
        .post('/api/bookings/initiate')
        .set('Authorization', `Bearer ${authToken}`)
        .send({ seatId: testSeatId })
    );

    const responses = await Promise.all(requests);

    // Filter responses by status code
    const successfulResponses = responses.filter((res) => res.status === 200);
    const rejectedResponses = responses.filter((res) => res.status === 409);

    // Assert: Exactly 1 request succeeded
    expect(successfulResponses.length).toBe(1);
    expect(successfulResponses[0].body.message).toBe('Booking initiated successfully');
    expect(successfulResponses[0].body.booking.status).toBe('PENDING_OTP');

    // Assert: Exactly 19 requests were rejected with 409 Conflict
    expect(rejectedResponses.length).toBe(concurrentRequestsCount - 1);
    rejectedResponses.forEach((res) => {
      expect(res.body.error).toBe('Seat is no longer available');
    });

    // Assert: Database state verification
    const seatInDb = await pool.query('SELECT status FROM seats WHERE id = $1', [testSeatId]);
    expect(seatInDb.rows[0].status).toBe('RESERVED');

    const bookingsInDb = await pool.query('SELECT * FROM bookings WHERE seat_id = $1', [testSeatId]);
    expect(bookingsInDb.rows.length).toBe(1);
  });

  afterAll(async () => {
    // Clean up created entities for this concurrency test
    if (testSeatId) {
      await pool.query('DELETE FROM otp_verifications WHERE booking_id IN (SELECT id FROM bookings WHERE seat_id = $1)', [testSeatId]);
      await pool.query('DELETE FROM bookings WHERE seat_id = $1', [testSeatId]);
      await pool.query('DELETE FROM seats WHERE id = $1', [testSeatId]);
    }
    if (testMovieId) {
      await pool.query('DELETE FROM movies WHERE id = $1', [testMovieId]);
    }
    if (testUserId) {
      await pool.query('DELETE FROM users WHERE id = $1', [testUserId]);
    }
    await pool.end();
  });
});
