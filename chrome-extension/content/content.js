// Content script for extracting page content and converting to markdown

// Extract metadata from page
function extractMetadata() {
  const metadata = {
    openGraph: {},
    jsonLd: [],
    schemaOrg: {},
    metaTags: {}
  };

  // Open Graph tags
  document.querySelectorAll('meta[property^="og:"]').forEach(meta => {
    const property = meta.getAttribute('property').replace('og:', '');
    const content = meta.getAttribute('content');
    if (content) {
      metadata.openGraph[property] = content;
    }
  });

  // JSON-LD structured data
  document.querySelectorAll('script[type="application/ld+json"]').forEach(script => {
    try {
      const data = JSON.parse(script.textContent);
      metadata.jsonLd.push(data);
    } catch (e) {
      // Invalid JSON, skip
    }
  });

  // Schema.org microdata
  document.querySelectorAll('[itemscope]').forEach(item => {
    const itemType = item.getAttribute('itemtype');
    if (itemType) {
      const schemaData = {};
      item.querySelectorAll('[itemprop]').forEach(prop => {
        const propName = prop.getAttribute('itemprop');
        const propValue = prop.getAttribute('content') || prop.textContent.trim();
        if (propValue) {
          schemaData[propName] = propValue;
        }
      });
      if (Object.keys(schemaData).length > 0) {
        metadata.schemaOrg[itemType] = schemaData;
      }
    }
  });

  // Standard meta tags
  ['description', 'keywords', 'author', 'date', 'published_time', 'modified_time'].forEach(name => {
    const meta = document.querySelector(`meta[name="${name}"], meta[property="${name}"]`);
    if (meta) {
      metadata.metaTags[name] = meta.getAttribute('content');
    }
  });

  return metadata;
}

// Score content elements to identify main content
function scoreContentElement(element) {
  let score = 0;

  // Positive signals - semantic HTML
  if (element.tagName === 'ARTICLE') score += 20;
  if (element.tagName === 'MAIN') score += 15;
  if (element.getAttribute('role') === 'main') score += 15;
  if (element.getAttribute('role') === 'article') score += 15;

  // Positive signals - IDs and classes
  const id = (element.id || '').toLowerCase();
  // className can be a string or DOMTokenList, so convert to string first
  const className = String(element.className || '').toLowerCase();

  const positivePatterns = [
    { pattern: /content|article|post|main|body|text/, weight: 10 },
    { pattern: /entry|story|prose|copy/, weight: 8 },
    { pattern: /product|item|detail/, weight: 5 }
  ];

  positivePatterns.forEach(({ pattern, weight }) => {
    if (pattern.test(id) || pattern.test(className)) {
      score += weight;
    }
  });

  // Negative signals (navigation, ads, etc.)
  const negativePatterns = [
    { pattern: /nav|menu|sidebar|header|footer|aside/, weight: -30 },
    { pattern: /ad|advertisement|promo|sponsor/, weight: -25 },
    { pattern: /filter|sort|facet|breadcrumb/, weight: -20 },
    { pattern: /comment|discussion|reply/, weight: -15 },
    { pattern: /social|share|follow|subscribe/, weight: -15 },
    { pattern: /cookie|consent|gdpr|newsletter/, weight: -15 }
  ];

  negativePatterns.forEach(({ pattern, weight }) => {
    if (pattern.test(id) || pattern.test(className) ||
      element.tagName === 'NAV' || element.tagName === 'HEADER' ||
      element.tagName === 'FOOTER' || element.tagName === 'ASIDE') {
      score += weight;
    }
  });

  // Text density (more text = more likely main content)
  const textLength = (element.textContent || '').trim().length;
  const childCount = element.children.length;

  if (textLength > 100) { // Only consider elements with substantial text
    if (childCount > 0) {
      const textDensity = textLength / childCount;
      score += Math.min(textDensity / 50, 10); // Cap at 10 points
    } else {
      // Leaf node with text - likely content
      score += 5;
    }

    // Bonus for paragraphs (actual descriptive content)
    const paragraphCount = element.querySelectorAll('p').length;
    if (paragraphCount > 0) {
      score += Math.min(paragraphCount * 3, 20); // Increased weight for paragraphs

      // Extra bonus for paragraphs with substantial text (descriptions)
      const paragraphs = Array.from(element.querySelectorAll('p'));
      const longParagraphs = paragraphs.filter(p => (p.textContent || '').trim().length > 100).length;
      if (longParagraphs > 0) {
        score += Math.min(longParagraphs * 2, 15); // Bonus for descriptive paragraphs
      }
    }

    // Strong bonus for elements with large text blocks (likely descriptions)
    // This catches descriptions that might not have paragraph tags
    if (textLength > 500) {
      score += 25; // Strong bonus for large text blocks
    } else if (textLength > 200) {
      score += 15; // Moderate bonus for substantial text
    }

    // Bonus for headings (structured content)
    const headingCount = element.querySelectorAll('h1, h2, h3, h4, h5, h6').length;
    if (headingCount > 0) {
      score += Math.min(headingCount, 10);
    }

    // Bonus for description/info/article keywords in class/id
    if (/description|info|article|text|content|prose|copy|story/.test(id) ||
      /description|info|article|text|content|prose|copy|story/.test(className)) {
      score += 15; // Strong bonus for descriptive content sections
    }
  }

  // Penalty for too many links (likely navigation)
  const linkCount = element.querySelectorAll('a').length;
  const wordCount = (element.textContent || '').split(/\s+/).filter(w => w.length > 0).length;
  if (wordCount > 0 && linkCount / wordCount > 0.3) {
    score -= 20; // More than 30% links = likely navigation
  }

  return score;
}

// Find main content element
function findMainContent(body) {
  let bestElement = body;
  let bestScore = scoreContentElement(body);

  // Check common main content containers with more specific selectors
  const candidateSelectors = [
    'article',
    'main',
    '[role="main"]',
    '[role="article"]',
    '[id*="content"]:not([id*="nav"]):not([id*="menu"]):not([id*="sidebar"])',
    '[id*="article"]',
    '[id*="post"]',
    '[id*="main"]:not([id*="nav"])',
    '[class*="content"]:not([class*="nav"]):not([class*="menu"]):not([class*="sidebar"]):not([class*="filter"])',
    '[class*="article"]:not([class*="nav"])',
    '[class*="post"]:not([class*="nav"])',
    '[class*="main"]:not([class*="nav"]):not([class*="menu"])',
    '[class*="body"]:not([class*="nav"])',
    '[class*="text"]:not([class*="nav"]):not([class*="menu"])'
  ];

  const candidates = new Set();
  candidateSelectors.forEach(selector => {
    try {
      body.querySelectorAll(selector).forEach(el => candidates.add(el));
    } catch (e) {
      // Invalid selector, skip
    }
  });

  candidates.forEach(element => {
    const score = scoreContentElement(element);
    if (score > bestScore) {
      bestScore = score;
      bestElement = element;
    }
  });

  // If we found a good candidate, use it; otherwise fall back to body
  if (bestScore > 0) {
    return bestElement;
  }

  return body;
}

function extractTextToMarkdown() {
  const body = document.body.cloneNode(true);

  // Remove script and style elements
  const scripts = body.querySelectorAll('script, style, noscript, iframe, embed, object');
  scripts.forEach(el => el.remove());

  // FIRST: Identify and preserve large text blocks BEFORE filtering
  // This ensures we don't accidentally remove important descriptions
  const preservedElements = new Set();
  Array.from(body.querySelectorAll('div, section, article, main, p')).forEach(el => {
    const text = (el.textContent || '').trim();
    // Preserve elements with substantial text (likely descriptions)
    if (text.length > 1000) {
      preservedElements.add(el);
    } else if (text.length > 500 && el.querySelectorAll('p').length >= 2) {
      // Preserve elements with multiple paragraphs and substantial text
      preservedElements.add(el);
    }
  });

  // Enhanced noise filtering - but skip preserved elements
  const noiseSelectors = [
    // Navigation and menus
    'nav', 'header', 'footer', 'aside', '[role="navigation"]', '[role="banner"]', '[role="contentinfo"]',
    '[class*="nav"]', '[class*="menu"]', '[class*="sidebar"]', '[class*="breadcrumb"]',
    // Ads and popups
    '[class*="ad"]', '[id*="ad"]', '[class*="advertisement"]', '[class*="popup"]', '[class*="modal"]',
    '[class*="overlay"]', '[class*="dialog"]', '[class*="lightbox"]',
    // Cookie and consent
    '[class*="cookie"]', '[class*="consent"]', '[class*="gdpr"]', '[id*="cookie"]',
    // Social and sharing
    '[class*="share"]', '[class*="social"]', '[class*="follow"]',
    // Newsletter and signup
    '[class*="newsletter"]', '[class*="signup"]', '[class*="subscribe"]',
    // Comments (often noise)
    '[class*="comment"]', '[id*="comment"]', '[class*="discussion"]',
    // Filters and sorting (common noise) - but only if they don't have substantial text
    '[class*="filter"]:not(:has(p))', '[class*="sort"]:not(:has(p))', '[class*="facet"]:not(:has(p))',
    // Language/region selectors
    '[class*="language"]', '[class*="locale"]', '[class*="region"]', '[class*="country"]',
    // Skip links and accessibility
    '[class*="skip"]', '[class*="sr-only"]', '[class*="visually-hidden"]'
  ];

  noiseSelectors.forEach(selector => {
    try {
      body.querySelectorAll(selector).forEach(el => {
        // Don't remove if it's preserved or contains preserved elements
        if (!preservedElements.has(el) && !Array.from(el.querySelectorAll('*')).some(child => preservedElements.has(child))) {
          el.remove();
        }
      });
    } catch (e) {
      // Ignore invalid selectors (like :has() which might not be supported)
      try {
        // Fallback: check manually
        body.querySelectorAll(selector.split(':')[0]).forEach(el => {
          if (!preservedElements.has(el) && !Array.from(el.querySelectorAll('*')).some(child => preservedElements.has(child))) {
            const hasParagraphs = el.querySelectorAll('p').length > 0;
            if (!hasParagraphs) {
              el.remove();
            }
          }
        });
      } catch (e2) {
        // Ignore
      }
    }
  });

  // Find and extract main content
  const mainContent = findMainContent(body);

  // Remove any remaining navigation elements from main content
  mainContent.querySelectorAll('nav, header, footer, aside, [role="navigation"]').forEach(el => el.remove());

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

  // Find and preserve descriptive content sections before cleanup
  // Look for common description/info/article containers - be very aggressive
  const descriptionSelectors = [
    '[class*="description"]',
    '[class*="info"]',
    '[class*="article"]',
    '[class*="text"]',
    '[class*="content"]',
    '[class*="detail"]',
    '[class*="specification"]',
    '[class*="feature"]',
    '[class*="prose"]',
    '[class*="copy"]',
    '[class*="story"]',
    '[id*="description"]',
    '[id*="info"]',
    '[id*="article"]',
    '[id*="text"]',
    '[id*="detail"]',
    '[id*="content"]',
    '[data-testid*="description"]',
    '[data-testid*="info"]',
    '[data-testid*="content"]',
    'article',
    'section[class*="description"]',
    'section[class*="info"]',
    'section[class*="content"]',
    'div[class*="product-description"]',
    'div[class*="product-info"]',
    'div[class*="product-text"]',
    'div[class*="product-detail"]',
    'div[class*="product-content"]',
    // Thomann-specific and similar e-commerce patterns
    'div[class*="component"]',  // Component containers often have descriptions
    'div[class*="children"]',    // Children divs often contain content
    '[itemprop="description"]',
    '[itemprop="articleBody"]',
    '[itemprop="text"]'
  ];

  // Mark descriptive sections to preserve them - be more permissive
  const descriptiveSections = new Set();
  descriptionSelectors.forEach(selector => {
    try {
      mainContent.querySelectorAll(selector).forEach(el => {
        const text = (el.textContent || '').trim();
        // For component/children divs, require more substantial text to avoid noise
        const isComponentOrChildren = selector.includes('component') || selector.includes('children');
        const minLength = isComponentOrChildren ? 1000 : 200; // Higher threshold for generic class names

        // Mark if it has substantial text - don't require paragraph tags
        // Large text blocks are important even without explicit paragraph structure
        if (text.length > minLength) {
          descriptiveSections.add(el);
        } else if (text.length > 200 && (el.querySelectorAll('p').length >= 2)) {
          // Mark sections with multiple paragraphs and substantial text
          descriptiveSections.add(el);
        } else if (text.length > 50 && !isComponentOrChildren && (el.querySelectorAll('p, div, span').length > 0)) {
          // Also mark smaller sections that have structure (but not generic component/children)
          descriptiveSections.add(el);
        }
      });
    } catch (e) {
      // Invalid selector, skip
    }
  });

  // Also find and mark any element with large text blocks (potential descriptions)
  // This catches descriptions in unexpected containers
  Array.from(mainContent.querySelectorAll('div, section, article, main')).forEach(el => {
    if (descriptiveSections.has(el)) return; // Already marked

    const text = (el.textContent || '').trim();
    const hasParagraphs = el.querySelectorAll('p').length > 0;
    const hasLongText = text.length > 500; // Large text block
    const hasSubstantialText = text.length > 200 && text.split(/\s+/).length > 30; // Substantial content

    // Mark if it's a large text block or has substantial content
    if (hasLongText || (hasSubstantialText && hasParagraphs)) {
      descriptiveSections.add(el);
    }
  });

  // Additional aggressive cleanup of main content
  // Remove common noise patterns that might have slipped through
  const noisePatterns = [
    // Remove elements with very little text (likely icons/buttons)
    el => {
      if (descriptiveSections.has(el)) return false; // Don't remove descriptive sections
      const text = (el.textContent || '').trim();
      return text.length < 3 && el.children.length === 0;
    },
    // Remove elements that are mostly links (navigation)
    el => {
      if (descriptiveSections.has(el)) return false; // Don't remove descriptive sections
      const links = el.querySelectorAll('a');
      const text = (el.textContent || '').trim();
      return links.length > 0 && links.length / (text.split(/\s+/).length || 1) > 0.5;
    },
    // Remove elements with only numbers/symbols
    el => {
      if (descriptiveSections.has(el)) return false; // Don't remove descriptive sections
      const text = (el.textContent || '').trim();
      return /^[\d\s\-\.,:;]+$/.test(text) && text.length < 50;
    }
  ];

  noisePatterns.forEach(shouldRemove => {
    Array.from(mainContent.querySelectorAll('*')).forEach(el => {
      if (shouldRemove(el)) {
        el.remove();
      }
    });
  });

  // Remove empty elements (but preserve descriptive sections)
  Array.from(mainContent.querySelectorAll('*')).forEach(el => {
    if (descriptiveSections.has(el)) return; // Don't remove descriptive sections
    const text = (el.textContent || '').trim();
    if (!text && !el.querySelector('img, video, iframe')) {
      el.remove();
    }
  });

  // Ensure paragraphs and descriptive text are preserved
  // Look for paragraphs that might have been orphaned
  const allParagraphs = mainContent.querySelectorAll('p');
  allParagraphs.forEach(p => {
    const text = (p.textContent || '').trim();
    // If paragraph has substantial text, ensure it's not removed
    if (text.length > 50 && !p.closest('nav, header, footer, aside')) {
      // Mark as important content
      p.setAttribute('data-content-type', 'description');
    }
  });

  const markdown = nodeToMarkdown(mainContent).trim();

  // SIMPLIFIED APPROACH: Get ALL text content, then filter minimally
  // This ensures we capture everything, including descriptions in unexpected containers

  // Get the full text content from mainContent
  let plainText = (mainContent.textContent || mainContent.innerText || '').trim();

  // If textContent is too short or seems incomplete, try innerText
  if (plainText.length < 500) {
    const innerText = (mainContent.innerText || '').trim();
    if (innerText.length > plainText.length) {
      plainText = innerText;
    }
  }

  // Also extract structured content to ensure we get everything
  const structuredContent = [];

  // Get all text nodes directly (bypasses any container filtering issues)
  const walker = document.createTreeWalker(
    mainContent,
    NodeFilter.SHOW_TEXT,
    {
      acceptNode: function (node) {
        // Skip if parent is script, style, or hidden
        const parent = node.parentElement;
        if (!parent) return NodeFilter.FILTER_REJECT;
        if (parent.tagName === 'SCRIPT' || parent.tagName === 'STYLE' ||
          parent.tagName === 'NOSCRIPT') return NodeFilter.FILTER_REJECT;
        if (parent.closest('nav, header, footer, aside')) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    }
  );

  const textNodes = [];
  let node;
  while (node = walker.nextNode()) {
    const text = node.textContent.trim();
    if (text.length > 0) {
      textNodes.push(text);
    }
  }

  // Combine all text nodes
  const allTextFromNodes = textNodes.join(' ').trim();
  if (allTextFromNodes.length > plainText.length) {
    plainText = allTextFromNodes;
  }

  // Also get structured elements to preserve formatting
  const paragraphs = Array.from(mainContent.querySelectorAll('p'))
    .map(p => (p.textContent || '').trim())
    .filter(text => text.length > 10);

  const headings = Array.from(mainContent.querySelectorAll('h1, h2, h3, h4, h5, h6'))
    .map(h => (h.textContent || '').trim())
    .filter(text => text.length > 0);

  const listItems = Array.from(mainContent.querySelectorAll('li'))
    .map(li => (li.textContent || '').trim())
    .filter(text => text.length > 5);

  // Extract text from descriptive sections - prioritize these
  const descriptiveTexts = [];
  descriptiveSections.forEach(el => {
    const text = (el.textContent || '').trim();
    if (text.length > 100) {
      // Extract paragraphs from descriptive sections first
      const descParagraphs = Array.from(el.querySelectorAll('p'))
        .map(p => (p.textContent || '').trim())
        .filter(text => text.length > 20);

      if (descParagraphs.length > 0 && descParagraphs.join(' ').length > text.length * 0.7) {
        // If paragraphs cover most of the text, use them (preserves structure)
        descriptiveTexts.push(...descParagraphs);
      } else {
        // If no paragraphs or paragraphs don't cover enough, use the full text
        // This is important for descriptions in divs/spans without paragraph tags
        // Split by double newlines or long whitespace to preserve structure
        const structuredText = text.split(/\n{2,}/).filter(t => t.trim().length > 50);
        if (structuredText.length > 0) {
          descriptiveTexts.push(...structuredText);
        } else {
          descriptiveTexts.push(text);
        }
      }
    }
  });

  // Combine structured content - prioritize descriptive texts
  const structured = [...headings, ...descriptiveTexts, ...paragraphs, ...listItems]
    .filter((text, index, self) => {
      // Remove exact duplicates
      return self.indexOf(text) === index;
    })
    .join('\n\n');

  // Use structured if it's substantial, otherwise use full text
  // Always include structured content (especially descriptive texts) even if shorter
  if (structured.length > 0) {
    // Combine structured with plain text, prioritizing structured
    // This ensures descriptive sections are always included
    if (structured.length > plainText.length * 0.5) {
      // Structured content is substantial, use it as primary
      plainText = structured + '\n\n' + plainText;
    } else {
      // Structured content is smaller but important, prepend it
      plainText = structured + '\n\n' + plainText;
    }
  }

  // Clean up the text: normalize whitespace, but preserve paragraph breaks
  plainText = plainText
    .replace(/[ \t]+/g, ' ')  // Replace multiple spaces/tabs with single space
    .replace(/\n{3,}/g, '\n\n')  // Max 2 consecutive newlines
    .trim();

  // Remove common noise text patterns (but be less aggressive)
  // Only remove lines that are CLEARLY noise, not potentially legitimate content
  const noiseTextPatterns = [
    // Only match if the line STARTS with these and is short (likely UI elements)
    /^(Filter|Sort|Search|Menu|Navigation|Skip to|Cookie|Accept|Reject)$/gmi,
    // Language/country selectors (only if very short lines)
    /^(Deutschland|United Kingdom|Suomi|Österreich|Sverige|Ireland|Nederland|Italia|France|Portugal|España|Danmark|Elláda|Belgium|Luxembourg|Polska|Česko|România|Magyarorszag|Alle|All)$/gmi,
    // Currency selectors (only standalone)
    /^(EUR|€|Euro|GBP|£|British pound|DKK|kr|Danish)$/gmi,
    // Language names (only standalone)
    /^(Deutsch|English|Français|Español|Italiano|Dansk|Svenska|Suomi|Nederlands|Português|Polski|Česky|Română|Magyar)$/gmi,
    // Markdown anchor links (only if they're the entire line)
    /^\[.*\]\(#.*\)$/gm,
    // Filter headings (only if standalone)
    /^## Filter$/gmi,
    // Sort options (only if standalone)
    /^(Beliebtheit|Neuste zuerst|Rate aufsteigend|Rate absteigend)$/gmi
  ];

  // MINIMAL filtering - only remove the most obvious noise
  // Split into lines, filter only single-word noise, rejoin
  let lines = plainText.split(/\n+/);
  lines = lines.filter(line => {
    const trimmed = line.trim();
    if (!trimmed) return false; // Remove empty lines

    // Only remove if it's a VERY short line (1-2 words) AND matches noise pattern exactly
    const words = trimmed.split(/\s+/).filter(w => w.length > 0);
    if (words.length <= 2 && trimmed.length < 30) {
      for (const pattern of noiseTextPatterns) {
        if (pattern.test(trimmed)) {
          return false; // This is clearly noise
        }
      }
    }

    // Remove only single-character lines
    if (trimmed.length < 2) return false;

    // Keep everything else - be very permissive
    return true;
  });

  plainText = lines.join('\n').trim();

  // Ensure we have substantial content - if not, use raw textContent
  if (plainText.length < 1000) {
    // Get raw textContent as fallback
    const rawText = (mainContent.textContent || '').trim();
    if (rawText.length > plainText.length * 1.5) {
      // Raw text is significantly longer, use it with minimal cleanup
      plainText = rawText
        .replace(/[ \t]{2,}/g, ' ')  // Multiple spaces/tabs to single space
        .replace(/\n{4,}/g, '\n\n\n')  // Max 3 consecutive newlines
        .trim();
    }
  }

  // Extract metadata
  const metadata = extractMetadata();

  return {
    text: plainText,
    markdown: markdown,
    metadata: metadata
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
      const { text, markdown, metadata } = extractTextToMarkdown();
      const title = document.title || 'Untitled';
      const url = window.location.href;

      sendResponse({
        success: true,
        data: {
          url,
          title,
          text,
          markdown,
          metadata
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

// Show save confirmation message on page
function showSaveMessage(success, message) {
  // Remove any existing message
  const existing = document.getElementById('cortex-save-message');
  if (existing) {
    existing.remove();
  }

  const messageEl = document.createElement('div');
  messageEl.id = 'cortex-save-message';
  messageEl.style.cssText = `
    position: fixed;
    top: 20px;
    right: 20px;
    background: ${success ? '#4CAF50' : '#f44336'};
    color: white;
    padding: 16px 24px;
    border-radius: 8px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.3);
    z-index: 999999;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    font-size: 14px;
    font-weight: 500;
    max-width: 300px;
    animation: cortexSlideIn 0.3s ease-out;
  `;
  messageEl.textContent = message;

  // Add animation
  const style = document.createElement('style');
  style.textContent = `
    @keyframes cortexSlideIn {
      from {
        transform: translateX(100%);
        opacity: 0;
      }
      to {
        transform: translateX(0);
        opacity: 1;
      }
    }
    @keyframes cortexSlideOut {
      from {
        transform: translateX(0);
        opacity: 1;
      }
      to {
        transform: translateX(100%);
        opacity: 0;
      }
    }
  `;
  if (!document.getElementById('cortex-save-styles')) {
    style.id = 'cortex-save-styles';
    document.head.appendChild(style);
  }

  document.body.appendChild(messageEl);

  // Remove after 3 seconds
  setTimeout(() => {
    messageEl.style.animation = 'cortexSlideOut 0.3s ease-out';
    setTimeout(() => {
      if (messageEl.parentNode) {
        messageEl.remove();
      }
    }, 300);
  }, 3000);
}

// Handle Ctrl+S keyboard shortcut
function handleSaveShortcut(e) {
  // Check for Ctrl+S (or Cmd+S on Mac)
  if ((e.ctrlKey || e.metaKey) && (e.key === 's' || e.keyCode === 83)) {
    e.preventDefault();
    e.stopPropagation();
    e.stopImmediatePropagation();

    console.log('[Cortex] Ctrl+S pressed, saving page...');
    showSaveMessage(false, 'Saving...');

    (async () => {
      try {
        // Check if it's a YouTube page
        const isYouTube = window.location.href.includes('youtube.com/watch') ||
          window.location.href.includes('youtu.be/');

        if (isYouTube) {
          const videoId = extractYouTubeVideoId();
          if (videoId) {
            const result = await chrome.storage.sync.get(['youtubeApiKey']);
            const { title, transcript } = await fetchYouTubeTranscript(videoId, result.youtubeApiKey);
            chrome.runtime.sendMessage({
              action: 'saveYouTube',
              data: { videoId, title, transcript }
            }, (response) => {
              if (chrome.runtime.lastError) {
                console.error('[Cortex] Error:', chrome.runtime.lastError);
                showSaveMessage(false, 'Error: ' + chrome.runtime.lastError.message);
              } else if (response && response.success) {
                console.log('[Cortex] YouTube content saved');
                showSaveMessage(true, '✓ YouTube video saved!');
              } else {
                showSaveMessage(false, 'Error saving video');
              }
            });
          }
        } else {
          // Extract regular page content
          const { text, markdown, metadata } = extractTextToMarkdown();
          const title = document.title || 'Untitled';
          const url = window.location.href;

          chrome.runtime.sendMessage({
            action: 'saveContent',
            data: { url, title, text, markdown, metadata }
          }, (response) => {
            if (chrome.runtime.lastError) {
              console.error('[Cortex] Error:', chrome.runtime.lastError);
              showSaveMessage(false, 'Error: ' + chrome.runtime.lastError.message);
            } else if (response && response.success) {
              console.log('[Cortex] Page content saved');
              showSaveMessage(true, '✓ Page saved!');
            } else {
              showSaveMessage(false, response?.error || 'Error saving page');
            }
          });
        }
      } catch (error) {
        console.error('[Cortex] Error saving page:', error);
        showSaveMessage(false, 'Error: ' + error.message);
      }
    })();

    return false;
  }
}

// Add listeners with highest priority (capture phase)
window.addEventListener('keydown', handleSaveShortcut, true);
document.addEventListener('keydown', handleSaveShortcut, true);

// Also add to document.body when it's ready (for SPAs)
if (document.body) {
  document.body.addEventListener('keydown', handleSaveShortcut, true);
} else {
  document.addEventListener('DOMContentLoaded', () => {
    document.body.addEventListener('keydown', handleSaveShortcut, true);
  });
}

console.log('[Cortex] Keyboard shortcut handler installed');

