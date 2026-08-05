// Default is light mode. Dark mode only activates if the person explicitly
// chose it before — checked via the inline anti-flicker script in <head>,
// this file just wires up the actual toggle button click.
function initThemeToggle() {
  const toggleBtn = document.getElementById('themeToggle');
  if (!toggleBtn) return;

  toggleBtn.addEventListener('click', () => {
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
    if (isDark) {
      document.documentElement.removeAttribute('data-theme');
      localStorage.setItem('accounting-theme', 'light');
    } else {
      document.documentElement.setAttribute('data-theme', 'dark');
      localStorage.setItem('accounting-theme', 'dark');
    }
  });
}

document.addEventListener('DOMContentLoaded', initThemeToggle);

