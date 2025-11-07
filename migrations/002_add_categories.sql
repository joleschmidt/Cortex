-- Migration: Add categories support
-- Run this in your Supabase SQL editor

-- Create categories table
CREATE TABLE IF NOT EXISTS categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    parent_id UUID REFERENCES categories(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create index for parent_id lookups
CREATE INDEX IF NOT EXISTS idx_categories_parent_id ON categories(parent_id);

-- Add category_id column to saved_content table
ALTER TABLE saved_content 
ADD COLUMN IF NOT EXISTS category_id UUID REFERENCES categories(id) ON DELETE SET NULL;

-- Create index for category_id filtering
CREATE INDEX IF NOT EXISTS idx_saved_content_category_id ON saved_content(category_id);

-- Insert some default categories for products
INSERT INTO categories (name, parent_id) VALUES
    ('Cars', NULL),
    ('Clothing', NULL),
    ('Music Instruments', NULL)
ON CONFLICT (name) DO NOTHING;

-- Add comment for documentation
COMMENT ON TABLE categories IS 'User-defined categories for organizing content';
COMMENT ON COLUMN saved_content.category_id IS 'Optional category assignment for content organization';

