-- Migration: Add favorites and notes support
-- Run this in your Supabase SQL editor

-- Add is_favorite column to saved_content table
ALTER TABLE saved_content 
ADD COLUMN IF NOT EXISTS is_favorite BOOLEAN DEFAULT false;

-- Create index for favorites filtering
CREATE INDEX IF NOT EXISTS idx_saved_content_is_favorite ON saved_content(is_favorite);

-- Add notes column to summaries table
ALTER TABLE summaries 
ADD COLUMN IF NOT EXISTS notes TEXT;

-- Add comment for documentation
COMMENT ON COLUMN saved_content.is_favorite IS 'Whether this content item is marked as a favorite';
COMMENT ON COLUMN summaries.notes IS 'User-added notes and annotations for this summary';


