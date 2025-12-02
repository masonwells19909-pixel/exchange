/*
  # Fix Database Schema & Functions
  
  ## Query Description: 
  This migration fixes the "Function Return Type" and "Policy Exists" errors by:
  1. Dropping conflicting functions and policies first.
  2. Re-creating the tables (if they don't exist).
  3. Re-defining the logic functions for Points and Rewards.
  4. Re-applying the Security Policies (RLS).
  
  ## Metadata:
  - Schema-Category: "Safe"
  - Impact-Level: "Medium" (Resets logic functions)
  - Reversible: true
*/

-- 1. DROP FUNCTIONS (Fixes 42P13 Error)
DROP FUNCTION IF EXISTS claim_task_reward(uuid);
DROP FUNCTION IF EXISTS claim_ad_reward();

-- 2. CREATE TABLES (If not exist)
CREATE TABLE IF NOT EXISTS profiles (
  id UUID REFERENCES auth.users(id) PRIMARY KEY,
  email TEXT,
  points INTEGER DEFAULT 50,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS tasks (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) NOT NULL,
  platform TEXT NOT NULL,
  action_type TEXT NOT NULL,
  url TEXT NOT NULL,
  cost_per_action INTEGER NOT NULL,
  reward_per_action INTEGER NOT NULL,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'paused', 'stopped')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS task_executions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  task_id UUID REFERENCES tasks(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id),
  executed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(task_id, user_id)
);

CREATE TABLE IF NOT EXISTS ads_watched (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id),
  watched_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. CLEANUP POLICIES (Fixes 42710 Error)
-- We drop them first to ensure we can re-create them without conflict
DROP POLICY IF EXISTS "Users can view own profile" ON profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
DROP POLICY IF EXISTS "Anyone can view active tasks" ON tasks;
DROP POLICY IF EXISTS "Users can create tasks" ON tasks;
DROP POLICY IF EXISTS "Users can update own tasks" ON tasks;
DROP POLICY IF EXISTS "Users can delete own tasks" ON tasks;
DROP POLICY IF EXISTS "Users can view own executions" ON task_executions;
DROP POLICY IF EXISTS "Users can view own ad history" ON ads_watched;

-- 4. ENABLE RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ads_watched ENABLE ROW LEVEL SECURITY;

-- 5. RE-CREATE POLICIES
CREATE POLICY "Users can view own profile" ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Anyone can view active tasks" ON tasks FOR SELECT USING (status = 'active');
CREATE POLICY "Users can create tasks" ON tasks FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own tasks" ON tasks FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own tasks" ON tasks FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "Users can view own executions" ON task_executions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can view own ad history" ON ads_watched FOR SELECT USING (auth.uid() = user_id);

-- 6. RE-CREATE LOGIC FUNCTIONS
-- Task Reward Function
CREATE OR REPLACE FUNCTION claim_task_reward(p_task_id UUID)
RETURNS TABLE (success BOOLEAN, message TEXT, points INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
  v_task_owner_id UUID;
  v_reward INTEGER;
  v_cost INTEGER;
  v_owner_points INTEGER;
  v_task_status TEXT;
BEGIN
  v_user_id := auth.uid();
  
  -- Check if task exists and get details
  SELECT user_id, reward_per_action, cost_per_action, status 
  INTO v_task_owner_id, v_reward, v_cost, v_task_status
  FROM tasks WHERE id = p_task_id;
  
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'المهمة غير موجودة', 0;
    RETURN;
  END IF;

  -- Check if self-execution
  IF v_user_id = v_task_owner_id THEN
    RETURN QUERY SELECT false, 'لا يمكنك تنفيذ مهامك الخاصة', 0;
    RETURN;
  END IF;

  -- Check status
  IF v_task_status != 'active' THEN
    RETURN QUERY SELECT false, 'المهمة غير نشطة', 0;
    RETURN;
  END IF;

  -- Check if already executed
  IF EXISTS (SELECT 1 FROM task_executions WHERE task_id = p_task_id AND user_id = v_user_id) THEN
    RETURN QUERY SELECT false, 'لقد قمت بهذه المهمة مسبقاً', 0;
    RETURN;
  END IF;

  -- Check owner balance
  SELECT points INTO v_owner_points FROM profiles WHERE id = v_task_owner_id;
  
  IF v_owner_points < v_cost THEN
    -- Pause task if no funds
    UPDATE tasks SET status = 'paused' WHERE id = p_task_id;
    RETURN QUERY SELECT false, 'نفذ رصيد صاحب المهمة', 0;
    RETURN;
  END IF;

  -- Execute Transaction
  INSERT INTO task_executions (task_id, user_id) VALUES (p_task_id, v_user_id);
  
  -- Deduct from owner
  UPDATE profiles SET points = points - v_cost WHERE id = v_task_owner_id;
  
  -- Add to executor
  UPDATE profiles SET points = points + v_reward WHERE id = v_user_id;
  
  RETURN QUERY SELECT true, 'تمت العملية بنجاح', v_reward;
END;
$$;

-- Ad Reward Function
CREATE OR REPLACE FUNCTION claim_ad_reward()
RETURNS TABLE (success BOOLEAN, message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
  v_last_watch TIMESTAMP WITH TIME ZONE;
BEGIN
  v_user_id := auth.uid();
  
  -- Check rate limit (30 seconds)
  SELECT watched_at INTO v_last_watch 
  FROM ads_watched 
  WHERE user_id = v_user_id 
  ORDER BY watched_at DESC 
  LIMIT 1;
  
  IF v_last_watch IS NOT NULL AND NOW() - v_last_watch < INTERVAL '30 seconds' THEN
    RETURN QUERY SELECT false, 'يرجى الانتظار قبل مشاهدة إعلان آخر';
    RETURN;
  END IF;

  -- Record watch
  INSERT INTO ads_watched (user_id) VALUES (v_user_id);
  
  -- Add points (2 points)
  UPDATE profiles SET points = points + 2 WHERE id = v_user_id;
  
  RETURN QUERY SELECT true, 'تم إضافة النقاط';
END;
$$;

-- 7. USER CREATION TRIGGER
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, points)
  VALUES (new.id, new.email, 50);
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();
