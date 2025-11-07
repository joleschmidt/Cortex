-- Migration: Add content_type to saved_content and extracted_data to summaries
-- Run this in your Supabase SQL editor

-- Add content_type column to saved_content table
ALTER TABLE saved_content 
ADD COLUMN IF NOT EXISTS content_type TEXT;

-- Create index for content_type filtering
CREATE INDEX IF NOT EXISTS idx_saved_content_content_type ON saved_content(content_type);

-- Add extracted_data JSONB column to summaries table
ALTER TABLE summaries 
ADD COLUMN IF NOT EXISTS extracted_data JSONB;

-- Create index for extracted_data JSONB queries (GIN index for efficient JSON queries)
CREATE INDEX IF NOT EXISTS idx_summaries_extracted_data ON summaries USING GIN (extracted_data);

-- Add comment for documentation
COMMENT ON COLUMN saved_content.content_type IS 'Content type: product, article, video, listing, or general';
COMMENT ON COLUMN summaries.extracted_data IS 'AI-optimized structured data: type, structured_data, key_points, actionable_insights, metadata';

