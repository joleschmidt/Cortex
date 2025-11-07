-- Migration: Add key_points and reviews columns to summaries table
-- Run this in your Supabase SQL editor

-- Add key_points column (array of text)
ALTER TABLE summaries 
ADD COLUMN IF NOT EXISTS key_points TEXT[];

-- Add reviews column (array of text)
ALTER TABLE summaries 
ADD COLUMN IF NOT EXISTS reviews TEXT[];

-- Create indexes for array queries
CREATE INDEX IF NOT EXISTS idx_summaries_key_points ON summaries USING GIN (key_points);
CREATE INDEX IF NOT EXISTS idx_summaries_reviews ON summaries USING GIN (reviews);

-- Add comments for documentation
COMMENT ON COLUMN summaries.key_points IS 'Array of short key points (price, specs, features) extracted from content';
COMMENT ON COLUMN summaries.reviews IS 'Array of customer reviews extracted from content';

-- Migrate existing data from extracted_data JSONB to new columns (if any exists)
UPDATE summaries 
SET 
    key_points = CASE 
        WHEN extracted_data->'key_points' IS NOT NULL 
        THEN ARRAY(SELECT jsonb_array_elements_text(extracted_data->'key_points'))
        ELSE NULL
    END,
    reviews = CASE 
        WHEN extracted_data->'reviews' IS NOT NULL 
        THEN ARRAY(SELECT jsonb_array_elements_text(extracted_data->'reviews'))
        ELSE NULL
    END
WHERE extracted_data IS NOT NULL 
  AND (extracted_data->'key_points' IS NOT NULL OR extracted_data->'reviews' IS NOT NULL);

