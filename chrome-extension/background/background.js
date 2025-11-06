// Background service worker for Chrome extension

// Listen for messages from content script
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === 'saveContent') {
    handleSaveContent(message.data)
      .then(result => sendResponse({ success: true, data: result }))
      .catch(error => sendResponse({ success: false, error: error.message }));
    return true; // Keep channel open for async response
  }

  if (message.action === 'saveYouTube') {
    handleSaveYouTube(message.data)
      .then(result => sendResponse({ success: true, data: result }))
      .catch(error => sendResponse({ success: false, error: error.message }));
    return true; // Keep channel open for async response
  }
});

async function handleSaveContent(data) {
  const { url, title, text, markdown } = data;
  
  // Validate data
  if (!url || !title || !text) {
    throw new Error('Missing required fields: url, title, or text');
  }

  // Clean and validate
  const cleanText = text.trim();
  if (cleanText.length === 0) {
    throw new Error('No content extracted from page');
  }

  // Get Supabase config
  const config = await chrome.storage.sync.get(['supabaseUrl', 'supabaseKey']);
  if (!config.supabaseUrl || !config.supabaseKey) {
    throw new Error('Supabase not configured. Please set up in extension settings.');
  }

  // Save to Supabase
  const metadata = {
    extracted_at: new Date().toISOString(),
    content_length: cleanText.length
  };

  const payload = {
    url,
    title,
    content_text: cleanText,
    content_markdown: markdown || cleanText,
    metadata,
    status: 'pending'
  };

  const response = await fetch(`${config.supabaseUrl}/rest/v1/saved_content`, {
    method: 'POST',
    headers: {
      'apikey': config.supabaseKey,
      'Authorization': `Bearer ${config.supabaseKey}`,
      'Content-Type': 'application/json',
      'Prefer': 'return=representation'
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Failed to save: ${response.status} ${error}`);
  }

  const result = await response.json();
  
  // Add to processing queue
  if (result && result[0]) {
    await fetch(`${config.supabaseUrl}/rest/v1/processing_queue`, {
      method: 'POST',
      headers: {
        'apikey': config.supabaseKey,
        'Authorization': `Bearer ${config.supabaseKey}`,
        'Content-Type': 'application/json',
        'Prefer': 'return=representation'
      },
      body: JSON.stringify({
        content_id: result[0].id,
        status: 'pending'
      })
    });
  }
  
  // Show notification
  chrome.notifications.create({
    type: 'basic',
    iconUrl: 'icons/icon48.png',
    title: 'Content Saved',
    message: `"${title}" has been saved and queued for processing.`
  }, () => {
    if (chrome.runtime.lastError) {
      console.log('Notification error:', chrome.runtime.lastError);
    }
  });

  return result;
}

async function handleSaveYouTube(data) {
  const { videoId, title, transcript } = data;
  
  // Validate data
  if (!videoId || !title || !transcript) {
    throw new Error('Missing required fields: videoId, title, or transcript');
  }

  // Get Supabase config
  const config = await chrome.storage.sync.get(['supabaseUrl', 'supabaseKey']);
  if (!config.supabaseUrl || !config.supabaseKey) {
    throw new Error('Supabase not configured. Please set up in extension settings.');
  }

  // Save to Supabase
  const url = `https://www.youtube.com/watch?v=${videoId}`;
  const metadata = {
    extracted_at: new Date().toISOString(),
    content_length: transcript.length,
    type: 'youtube',
    video_id: videoId
  };

  const payload = {
    url,
    title,
    content_text: transcript,
    content_markdown: transcript,
    video_id: videoId,
    metadata,
    status: 'pending'
  };

  const response = await fetch(`${config.supabaseUrl}/rest/v1/saved_content`, {
    method: 'POST',
    headers: {
      'apikey': config.supabaseKey,
      'Authorization': `Bearer ${config.supabaseKey}`,
      'Content-Type': 'application/json',
      'Prefer': 'return=representation'
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Failed to save: ${response.status} ${error}`);
  }

  const result = await response.json();
  
  // Add to processing queue
  if (result && result[0]) {
    await fetch(`${config.supabaseUrl}/rest/v1/processing_queue`, {
      method: 'POST',
      headers: {
        'apikey': config.supabaseKey,
        'Authorization': `Bearer ${config.supabaseKey}`,
        'Content-Type': 'application/json',
        'Prefer': 'return=representation'
      },
      body: JSON.stringify({
        content_id: result[0].id,
        status: 'pending'
      })
    });
  }
  
  // Show notification
  chrome.notifications.create({
    type: 'basic',
    iconUrl: 'icons/icon48.png',
    title: 'YouTube Video Saved',
    message: `"${title}" has been saved and queued for processing.`
  }, () => {
    if (chrome.runtime.lastError) {
      console.log('Notification error:', chrome.runtime.lastError);
    }
  });

  return result;
}

// Handle extension installation
chrome.runtime.onInstalled.addListener(() => {
  console.log('Cortex extension installed');
});

