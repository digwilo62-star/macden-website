// Pings the server every 20 seconds while any accounting page is open,
// keeping this person's online status live for everyone else.
async function sendHeartbeat() {
  try {
    await apiRequest('/presence/heartbeat', { method: 'POST' });
  } catch (err) {
    // Not logged in, or a network blip — fail silently, next heartbeat will retry
  }
}

document.addEventListener('DOMContentLoaded', () => {
  sendHeartbeat();
  setInterval(sendHeartbeat, 20000);
});

