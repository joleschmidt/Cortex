// Content script for extracting page content and converting to markdown

function extractTextToMarkdown() {
  const body = document.body.cloneNode(true);
  
  // Remove script and style elements
  const scripts = body.querySelectorAll('script, style, noscript, iframe, embed, object');
  scripts.forEach(el => el.remove());
  
  // Remove common ad/annoyance selectors
  const adSelectors = [
    '[class*="ad"]',
    '[id*="ad"]',
    '[class*="advertisement"]',
    '[class*="popup"]',
    '[class*="modal"]',
    '[class*="cookie"]',
    '[class*="newsletter"]',
    'nav',
    'header',
    'footer',
    'aside'
  ];
  
  adSelectors.forEach(selector => {
    try {
      body.querySelectorAll(selector).forEach(el => el.remove());
    } catch (e) {
      // Ignore invalid selectors
    }
  });

  function nodeToMarkdown(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      return node.textContent.trim();
    }
    
    if (node.nodeType !== Node.ELEMENT_NODE) {
      return '';
    }

    const tagName = node.tagName.toLowerCase();
    const children = Array.from(node.childNodes)
      .map(child => nodeToMarkdown(child))
      .filter(text => text.length > 0)
      .join(' ');

    if (!children) return '';

    switch (tagName) {
      case 'h1':
        return `# ${children}\n\n`;
      case 'h2':
        return `## ${children}\n\n`;
      case 'h3':
        return `### ${children}\n\n`;
      case 'h4':
        return `#### ${children}\n\n`;
      case 'h5':
        return `##### ${children}\n\n`;
      case 'h6':
        return `###### ${children}\n\n`;
      case 'p':
        return `${children}\n\n`;
      case 'br':
        return '\n';
      case 'strong':
      case 'b':
        return `**${children}**`;
      case 'em':
      case 'i':
        return `*${children}*`;
      case 'code':
        return `\`${children}\``;
      case 'pre':
        return `\`\`\`\n${children}\n\`\`\`\n\n`;
      case 'a':
        const href = node.getAttribute('href') || '';
        return href ? `[${children}](${href})` : children;
      case 'ul':
      case 'ol':
        const items = Array.from(node.querySelectorAll(':scope > li'))
          .map(li => {
            const text = Array.from(li.childNodes)
              .map(child => nodeToMarkdown(child))
              .filter(text => text.length > 0)
              .join(' ')
              .trim();
            return `- ${text}`;
          })
          .join('\n');
        return `${items}\n\n`;
      case 'li':
        return children;
      case 'blockquote':
        return `> ${children}\n\n`;
      default:
        return children;
    }
  }

  const markdown = nodeToMarkdown(body).trim();
  const plainText = body.innerText || body.textContent || '';
  
  return {
    text: plainText.trim(),
    markdown: markdown
  };
}

function extractYouTubeVideoId() {
  const url = window.location.href;
  const match = url.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/)([^&\n?#]+)/);
  return match ? match[1] : null;
}

async function fetchYouTubeTranscript(videoId, apiKey) {
  if (!apiKey) {
    throw new Error('YouTube API key not configured');
  }

  try {
    // First, get video details to get the title
    const videoUrl = `https://www.googleapis.com/youtube/v3/videos?part=snippet&id=${videoId}&key=${apiKey}`;
    const videoResponse = await fetch(videoUrl);
    const videoData = await videoResponse.json();
    
    if (!videoData.items || videoData.items.length === 0) {
      throw new Error('Video not found');
    }

    const title = videoData.items[0].snippet.title;

    // Try to get captions
    const captionsUrl = `https://www.googleapis.com/youtube/v3/captions?part=snippet&videoId=${videoId}&key=${apiKey}`;
    const captionsResponse = await fetch(captionsUrl);
    const captionsData = await captionsResponse.json();

    if (!captionsData.items || captionsData.items.length === 0) {
      // No captions available, return title only
      return { title, transcript: `Video: ${title}\n\nNo transcript available.` };
    }

    // Get the first available caption track (prefer English)
    const captionTrack = captionsData.items.find(item => 
      item.snippet.language === 'en' || item.snippet.language.startsWith('en')
    ) || captionsData.items[0];

    // Download the caption
    const downloadUrl = `https://www.googleapis.com/youtube/v3/captions/${captionTrack.id}?tfmt=srt&key=${apiKey}`;
    const transcriptResponse = await fetch(downloadUrl);
    const transcriptText = await transcriptResponse.text();

    // Parse SRT format and extract text
    const transcript = parseSRT(transcriptText);

    return { title, transcript };
  } catch (error) {
    console.error('Error fetching YouTube transcript:', error);
    throw error;
  }
}

function parseSRT(srtText) {
  // Simple SRT parser - extracts text from subtitle blocks
  const blocks = srtText.split(/\n\s*\n/);
  const lines = blocks
    .map(block => {
      const lines = block.split('\n');
      // Skip sequence number and timestamp, get text lines
      return lines.slice(2).join(' ').trim();
    })
    .filter(line => line.length > 0);
  
  return lines.join(' ');
}

// Listen for messages from background script
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === 'extractContent') {
    try {
      const { text, markdown } = extractTextToMarkdown();
      const title = document.title || 'Untitled';
      const url = window.location.href;
      
      sendResponse({
        success: true,
        data: {
          url,
          title,
          text,
          markdown
        }
      });
    } catch (error) {
      sendResponse({
        success: false,
        error: error.message
      });
    }
    return true; // Keep channel open for async response
  }

  if (request.action === 'extractYouTube') {
    const videoId = extractYouTubeVideoId();
    if (!videoId) {
      sendResponse({
        success: false,
        error: 'Not a YouTube video page'
      });
      return true;
    }

    // Fetch transcript asynchronously
    (async () => {
      try {
        const result = await chrome.storage.sync.get(['youtubeApiKey']);
        const { title, transcript } = await fetchYouTubeTranscript(videoId, result.youtubeApiKey);
        sendResponse({
          success: true,
          data: {
            videoId,
            title,
            transcript
          }
        });
      } catch (error) {
        sendResponse({
          success: false,
          error: error.message
        });
      }
    })();

    return true; // Keep channel open for async response
  }
});

