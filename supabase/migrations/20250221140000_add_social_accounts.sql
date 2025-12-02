/*
  # Add Social Accounts Column
  
  Adds a JSONB column to store the user's linked social media usernames/links.
  This is required to verify/track who is performing the tasks.
*/

ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS social_accounts JSONB DEFAULT '{}'::jsonb;

-- Ensure the column is updatable by the user (RLS is already set for update own profile, but good to double check)
-- No new policy needed as existing "Users can update own profile" covers all columns.
