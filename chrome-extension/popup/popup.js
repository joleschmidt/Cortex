// Popup script for Chrome extension

const supabaseClient = new SupabaseClient();

let currentView = 'main';

// Initialize popup
document.addEventListener('DOMContentLoaded', async () => {
  await loadSettings();
  await loadSavedItems();
  
  // Set up event listeners
  document.getElementById('saveBtn').addEventListener('click', handleSaveCurrentPage);
  document.getElementById('settingsBtn').addEventListener('click', showSettings);
  document.getElementById('saveSettingsBtn').addEventListener('click', saveSettings);
  document.getElementById('cancelSettingsBtn').addEventListener('click', showMain);
});

async function loadSettings() {
  const config = await chrome.storage.sync.get(['supabaseUrl', 'supabaseKey', 'youtubeApiKey']);
  
  if (config.supabaseUrl) {
    document.getElementById('supabaseUrl').value = config.supabaseUrl;
  }
  if (config.supabaseKey) {
    document.getElementById('supabaseKey').value = config.supabaseKey;
  }
  if (config.youtubeApiKey) {
    document.getElementById('youtubeApiKey').value = config.youtubeApiKey;
  }
}

async function saveSettings() {
  const supabaseUrl = document.getElementById('supabaseUrl').value.trim();
  const supabaseKey = document.getElementById('supabaseKey').value.trim();
  const youtubeApiKey = document.getElementById('youtubeApiKey').value.trim();

  if (!supabaseUrl || !supabaseKey) {
    showStatus('Please fill in Supabase URL and Anon Key', 'error');
    return;
  }

  // Validate URL format
  try {
    new URL(supabaseUrl);
  } catch (e) {
    showStatus('Invalid Supabase URL format', 'error');
    return;
  }

  await chrome.storage.sync.set({
    supabaseUrl,
    supabaseKey,
    youtubeApiKey
  });

  showStatus('Settings saved successfully!', 'success');
  setTimeout(() => {
    showMain();
    loadSavedItems();
  }, 1000);
}

function showSettings() {
  currentView = 'settings';
  document.getElementById('mainView').classList.add('hidden');
  document.getElementById('settingsView').classList.remove('hidden');
}

function showMain() {
  currentView = 'main';
  document.getElementById('mainView').classList.remove('hidden');
  document.getElementById('settingsView').classList.add('hidden');
}

function showStatus(message, type) {
  const statusEl = document.getElementById('statusMessage');
  statusEl.textContent = message;
  statusEl.className = `status-message ${type}`;
  
  if (type === 'success') {
    setTimeout(() => {
      statusEl.classList.remove('success');
      statusEl.style.display = 'none';
    }, 3000);
  }
}

async function handleSaveCurrentPage() {
  const saveBtn = document.getElementById('saveBtn');
  saveBtn.disabled = true;
  saveBtn.textContent = 'Saving...';

  try {
    // Get current tab
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    
    if (!tab || !tab.url) {
      throw new Error('Could not get current tab');
    }

    // Check if it's a YouTube video
    const isYouTube = tab.url.includes('youtube.com/watch') || tab.url.includes('youtu.be/');
    
    if (isYouTube) {
      // Extract YouTube content
      const response = await chrome.tabs.sendMessage(tab.id, { action: 'extractYouTube' });
      
      if (!response || !response.success) {
        throw new Error(response?.error || 'Failed to extract YouTube content');
      }

      // Send to background script
      const bgResponse = await chrome.runtime.sendMessage({
        action: 'saveYouTube',
        data: response.data
      });

      if (!bgResponse || !bgResponse.success) {
        throw new Error(bgResponse?.error || 'Failed to save YouTube content');
      }

      showStatus('YouTube video saved successfully!', 'success');
    } else {
      // Extract regular page content
      const response = await chrome.tabs.sendMessage(tab.id, { action: 'extractContent' });
      
      if (!response || !response.success) {
        throw new Error(response?.error || 'Failed to extract page content');
      }

      // Send to background script
      const bgResponse = await chrome.runtime.sendMessage({
        action: 'saveContent',
        data: response.data
      });

      if (!bgResponse || !bgResponse.success) {
        throw new Error(bgResponse?.error || 'Failed to save content');
      }

      showStatus('Page saved successfully!', 'success');
    }

    // Reload saved items
    setTimeout(() => {
      loadSavedItems();
    }, 500);
  } catch (error) {
    console.error('Error saving page:', error);
    showStatus(error.message || 'Failed to save page', 'error');
  } finally {
    saveBtn.disabled = false;
    saveBtn.textContent = 'Save Current Page';
  }
}

async function loadSavedItems() {
  const container = document.getElementById('savedItems');
  container.innerHTML = '<div class="loading">Loading...</div>';

  try {
    await supabaseClient.init();
    const items = await supabaseClient.getRecentContent(20);
    
    if (!items || items.length === 0) {
      container.innerHTML = `
        <div class="empty-state">
          <p>No saved content yet.</p>
          <p>Click "Save Current Page" to get started!</p>
        </div>
      `;
      return;
    }

    // Fetch summaries for each item
    const itemsWithSummaries = await Promise.all(
      items.map(async (item) => {
        const summary = await supabaseClient.getSummaryForContent(item.id);
        return { ...item, summary };
      })
    );

    container.innerHTML = itemsWithSummaries.map(item => createItemHTML(item)).join('');
  } catch (error) {
    console.error('Error loading saved items:', error);
    container.innerHTML = `
      <div class="empty-state">
        <p>Error loading content: ${error.message}</p>
        <p>Please check your settings.</p>
      </div>
    `;
  }
}

function createItemHTML(item) {
  const statusClass = item.status || 'pending';
  const date = new Date(item.created_at).toLocaleDateString();
  
  let summariesHTML = '';
  if (item.summary) {
    summariesHTML = `
      <div class="summaries">
        <div class="summary-section">
          <div class="summary-label">Short Summary</div>
          <div class="summary-text">${escapeHtml(item.summary.short_summary)}</div>
        </div>
        <div class="summary-section">
          <div class="summary-label">Detailed Summary</div>
          <div class="summary-text">${escapeHtml(item.summary.detailed_summary)}</div>
        </div>
      </div>
    `;
  }

  return `
    <div class="item">
      <div class="item-header">
        <div style="flex: 1;">
          <div class="item-title">${escapeHtml(item.title)}</div>
          <a href="${escapeHtml(item.url)}" target="_blank" class="item-url">${escapeHtml(item.url)}</a>
        </div>
        <span class="status-badge ${statusClass}">${statusClass}</span>
      </div>
      <div style="font-size: 11px; color: #999; margin-top: 4px;">Saved on ${date}</div>
      ${summariesHTML}
    </div>
  `;
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

