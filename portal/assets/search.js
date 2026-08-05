// Company-wide search — wires up the search box that's been sitting in
// every topbar, unwired, since the portal rebuild started. Requires this
// markup around the input (added automatically by fix-search-and-bugs.js):
//   <div class="topbar-search">
//     <input type="text" id="globalSearchInput" placeholder="...">
//     <div class="search-dropdown" id="globalSearchDropdown"></div>
//   </div>

function initGlobalSearch() {
  const input = document.getElementById('globalSearchInput');
  const dropdown = document.getElementById('globalSearchDropdown');
  if (!input || !dropdown) return;

  let searchTimeout = null;

  input.addEventListener('input', () => {
    clearTimeout(searchTimeout);
    const q = input.value.trim();

    if (!q) {
      dropdown.classList.remove('visible');
      return;
    }
    if (q.length < 2) {
      dropdown.innerHTML = '<div class="search-hint">Keep typing…</div>';
      dropdown.classList.add('visible');
      return;
    }

    searchTimeout = setTimeout(() => runSearch(q), 300);
  });

  input.addEventListener('focus', () => {
    if (input.value.trim().length >= 2) dropdown.classList.add('visible');
  });

  document.addEventListener('click', (e) => {
    if (!e.target.closest('.topbar-search')) {
      dropdown.classList.remove('visible');
    }
  });

  async function runSearch(q) {
    dropdown.innerHTML = '<div class="search-hint">Searching…</div>';
    dropdown.classList.add('visible');

    try {
      const result = await apiRequest('/search?q=' + encodeURIComponent(q));
      const totalResults = result.messages.length + result.documents.length + result.policies.length;

      if (totalResults === 0) {
        dropdown.innerHTML = '<div class="search-empty-state">No results for "' + q + '"</div>';
        return;
      }

      let html = '';

      if (result.messages.length > 0) {
        html += '<div class="search-section"><div class="search-section-label">Messages</div>';
        html += result.messages.map(m =>
          '<a class="search-result-row" href="inbox.html?id=' + m.conversationId + '">' +
            '<div class="search-result-title">' + m.subject + '</div>' +
            (m.snippet ? '<div class="search-result-detail">' + m.snippet + '</div>' : '') +
          '</a>'
        ).join('');
        html += '</div>';
      }

      if (result.documents.length > 0) {
        html += '<div class="search-section"><div class="search-section-label">Documents</div>';
        html += result.documents.map(d =>
          '<a class="search-result-row" href="documents.html">' +
            '<div class="search-result-title">' + d.fileName + '</div>' +
            '<div class="search-result-detail">' + d.category + '</div>' +
          '</a>'
        ).join('');
        html += '</div>';
      }

      if (result.policies.length > 0) {
        html += '<div class="search-section"><div class="search-section-label">Policies</div>';
        html += result.policies.map(p =>
          '<a class="search-result-row" href="policies.html?id=' + p.id + '">' +
            '<div class="search-result-title">' + p.title + '</div>' +
            (p.snippet ? '<div class="search-result-detail">' + p.snippet + '</div>' : '') +
          '</a>'
        ).join('');
        html += '</div>';
      }

      dropdown.innerHTML = html;
    } catch (err) {
      dropdown.innerHTML = '<div class="search-empty-state">Search failed. Try again.</div>';
    }
  }
}

document.addEventListener('DOMContentLoaded', initGlobalSearch);

