// Pings the server every 20 seconds while this page is open AND visible,
// keeping this person's online status live for everyone else. Pauses
// entirely when the tab is backgrounded/minimized -- no point spending
// server load or someone's mobile data keeping a hidden tab "online."
async function sendHeartbeat() {
  try {
    await apiRequest('/presence/heartbeat', { method: 'POST' });
  } catch (err) {
    // Not logged in, or a network blip -- fail silently, next heartbeat will retry
  }
}

let heartbeatInterval = null;

function startHeartbeat() {
  if (heartbeatInterval) return; // already running
  sendHeartbeat();
  heartbeatInterval = setInterval(sendHeartbeat, 60000);
}

function stopHeartbeat() {
  if (heartbeatInterval) {
    clearInterval(heartbeatInterval);
    heartbeatInterval = null;
  }
}

document.addEventListener('DOMContentLoaded', () => {
  if (document.visibilityState === 'visible') {
    startHeartbeat();
  }
});

document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') {
    startHeartbeat(); // immediately confirm "online" the moment they come back
  } else {
    stopHeartbeat();
  }
});

