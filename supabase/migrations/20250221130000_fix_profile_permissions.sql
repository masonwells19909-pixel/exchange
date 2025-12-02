/*
  # Fix Profile Permissions
  
  ## Query Description:
  1. Ensures 'social_accounts' column exists in 'profiles' table.
  2. Fixes RLS policies to allow users to UPDATE their own profile.
  
  ## Metadata:
  - Schema-Category: "Safe"
  - Impact-Level: "Medium"
*/

-- 1. Ensure column exists
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS social_accounts JSONB DEFAULT '{}'::jsonb;

-- 2. Ensure RLS is enabled
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- 3. Drop existing conflicting policies (to be safe)
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.profiles;

-- 4. Re-create Policies

-- Allow users to view any profile (needed for tasks verification later) or just restrict to own? 
-- For now, let's allow users to see their own profile.
CREATE POLICY "Users can view own profile" ON public.profiles 
    FOR SELECT 
    USING (auth.uid() = id);

-- CRITICAL: Allow users to UPDATE their own profile
CREATE POLICY "Users can update own profile" ON public.profiles 
    FOR UPDATE 
    TO authenticated 
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- Allow inserting (usually handled by trigger, but good to have for safety)
CREATE POLICY "Users can insert own profile" ON public.profiles 
    FOR INSERT 
    WITH CHECK (auth.uid() = id);

-- 5. Grant permissions
GRANT ALL ON TABLE public.profiles TO authenticated;
GRANT ALL ON TABLE public.profiles TO service_role;
