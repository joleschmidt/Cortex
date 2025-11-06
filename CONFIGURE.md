# Quick Configuration

## What You Need

From the Supabase dashboard, I can see:
- ✅ **Project URL**: `https://uymrpsfrzjkhsofnouqn.supabase.co` (confirmed)

Still needed:
- ⚠️ **Anon Key** (full key - the one shown may be truncated)
- ⚠️ **Service Role Key** (for macOS app)

## How to Get the Keys

### Step 1: Get Anon Key (for Chrome Extension)

1. Go to: https://supabase.com/dashboard/project/uymrpsfrzjkhsofnouqn/settings/api
2. In the "Project API" section, find **"API Key"** with label **"anon public"**
3. Click the **"Copy"** button next to it
4. ⚠️ Make sure you copy the FULL key (it might look truncated in the UI)

### Step 2: Get Service Role Key (for macOS App)

1. On the same page (API settings), look for the note that says:
   > "You may also use the service key which can be found **here**"
2. Click the **"here"** link
3. This will show the **service_role** key
4. Click **"Copy"** to copy it
5. ⚠️ **Keep this secret!** This key bypasses RLS and has full access

## Quick Setup Options

### Option A: Manual Configuration (Recommended)

1. **Chrome Extension:**
   - Click Cortex icon → ⚙️ settings
   - Paste Project URL and Anon Key
   - Save

2. **macOS App:**
   - Open app → ⚙️ settings
   - Paste Project URL and Service Role Key
   - Save

### Option B: Use Configuration Script

I can create a script to help configure both automatically. Just provide:
- Full anon key
- Full service_role key

Then run:
```bash
./configure.sh
```

## Current Status

✅ Project URL: `https://uymrpsfrzjkhsofnouqn.supabase.co`  
⏳ Anon Key: Need full key (copy from dashboard)  
⏳ Service Role Key: Need to get from dashboard

## Next Steps

1. Copy the **full anon key** from the dashboard
2. Click the "here" link to get the **service_role key**
3. Configure both apps (or let me know if you want a helper script)

Once you have both keys, you're ready to configure and test!

