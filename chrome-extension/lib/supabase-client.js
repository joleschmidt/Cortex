// Supabase client wrapper for Chrome extension
class SupabaseClient {
  constructor() {
    this.supabaseUrl = null;
    this.supabaseKey = null;
  }

  async init() {
    const config = await chrome.storage.sync.get(['supabaseUrl', 'supabaseKey']);
    this.supabaseUrl = config.supabaseUrl;
    this.supabaseKey = config.supabaseKey;
    
    if (!this.supabaseUrl || !this.supabaseKey) {
      throw new Error('Supabase configuration not found. Please set up in extension settings.');
    }
  }

  async _request(method, endpoint, data = null) {
    await this.init();
    
    const url = `${this.supabaseUrl}/rest/v1${endpoint}`;
    const options = {
      method,
      headers: {
        'apikey': this.supabaseKey,
        'Authorization': `Bearer ${this.supabaseKey}`,
        'Content-Type': 'application/json',
        'Prefer': 'return=representation'
      }
    };

    if (data) {
      options.body = JSON.stringify(data);
    }

    const response = await fetch(url, options);
    
    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Supabase request failed: ${response.status} ${error}`);
    }

    if (response.status === 204 || response.headers.get('content-length') === '0') {
      return null;
    }

    return await response.json();
  }

  async saveWebsiteContent(url, title, text, markdown, metadata = {}) {
    const data = {
      url,
      title,
      content_text: text,
      content_markdown: markdown || text,
      metadata,
      status: 'pending'
    };

    const result = await this._request('POST', '/saved_content', data);
    
    // Also add to processing queue
    if (result && result[0]) {
      await this._request('POST', '/processing_queue', {
        content_id: result[0].id,
        status: 'pending'
      });
    }

    return result;
  }

  async saveYouTubeVideo(videoId, title, transcript, metadata = {}) {
    const url = `https://www.youtube.com/watch?v=${videoId}`;
    const data = {
      url,
      title,
      content_text: transcript,
      content_markdown: transcript,
      video_id: videoId,
      metadata: {
        ...metadata,
        type: 'youtube',
        video_id: videoId
      },
      status: 'pending'
    };

    const result = await this._request('POST', '/saved_content', data);
    
    // Also add to processing queue
    if (result && result[0]) {
      await this._request('POST', '/processing_queue', {
        content_id: result[0].id,
        status: 'pending'
      });
    }

    return result;
  }

  async getSummaries(limit = 20) {
    const endpoint = `/summaries?order=created_at.desc&limit=${limit}&select=*,saved_content(id,url,title,created_at)`;
    return await this._request('GET', endpoint);
  }

  async getContentStatus(contentId) {
    const endpoint = `/saved_content?id=eq.${contentId}&select=id,status,processed_at`;
    const result = await this._request('GET', endpoint);
    return result && result[0] ? result[0] : null;
  }

  async getRecentContent(limit = 20) {
    const endpoint = `/saved_content?order=created_at.desc&limit=${limit}&select=id,url,title,status,created_at`;
    return await this._request('GET', endpoint);
  }

  async getSummaryForContent(contentId) {
    const endpoint = `/summaries?content_id=eq.${contentId}&select=*`;
    const result = await this._request('GET', endpoint);
    return result && result.length > 0 ? result[0] : null;
  }
}

// Export singleton instance
const supabaseClient = new SupabaseClient();

