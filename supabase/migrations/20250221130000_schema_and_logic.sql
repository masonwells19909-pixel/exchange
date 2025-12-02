/*
  # Social Exchange App Schema & Logic
  
  ## Structure
  - profiles: Stores user points and basic info. Linked to auth.users.
  - tasks: Stores links/content users want to promote.
  - task_executions: Records who did what task to prevent duplicates.
  - ads_watched: Logs ad views for cooldowns.

  ## Logic (RPC Functions)
  - claim_task_reward: Handles the transaction of points between users safely.
  - claim_ad_reward: Awards points for watching ads with time checks.
  
  ## Security
  - RLS enabled on all tables.
  - Functions use 'security definer' to perform privileged actions safely.
  - Search path set to public to prevent search_path hijacking.
*/

-- 1. PROFILES TABLE
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    email TEXT,
    points INTEGER DEFAULT 50, -- Bonus for new users
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public profiles are viewable by everyone" 
ON public.profiles FOR SELECT USING (true);

CREATE POLICY "Users can update own profile" 
ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- 2. TASKS TABLE
CREATE TABLE IF NOT EXISTS public.tasks (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    platform TEXT NOT NULL, -- youtube, facebook, etc.
    action_type TEXT NOT NULL, -- like, subscribe, etc.
    url TEXT NOT NULL,
    cost_per_action INTEGER NOT NULL,
    reward_per_action INTEGER NOT NULL,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'paused', 'stopped')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Active tasks are viewable by everyone" 
ON public.tasks FOR SELECT USING (status = 'active' OR auth.uid() = user_id);

CREATE POLICY "Users can insert own tasks" 
ON public.tasks FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own tasks" 
ON public.tasks FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own tasks" 
ON public.tasks FOR DELETE USING (auth.uid() = user_id);

-- 3. TASK EXECUTIONS TABLE (Anti-Cheat / History)
CREATE TABLE IF NOT EXISTS public.task_executions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    task_id UUID REFERENCES public.tasks(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(task_id, user_id) -- Prevent doing same task twice
);

ALTER TABLE public.task_executions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own executions" 
ON public.task_executions FOR SELECT USING (auth.uid() = user_id);

-- 4. ADS WATCHED TABLE
CREATE TABLE IF NOT EXISTS public.ads_watched (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    points_earned INTEGER DEFAULT 2,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.ads_watched ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own ad history" 
ON public.ads_watched FOR SELECT USING (auth.uid() = user_id);

-- 5. TRIGGER FOR NEW USERS
CREATE OR REPLACE FUNCTION public.handle_new_user() 
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, points)
  VALUES (new.id, new.email, 50);
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Drop trigger if exists to prevent duplicates during dev
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- 6. RPC: CLAIM TASK REWARD
CREATE OR REPLACE FUNCTION public.claim_task_reward(p_task_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_task RECORD;
  v_owner_points INTEGER;
  v_execution_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  
  -- 1. Check if user is logged in
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Not authenticated');
  END IF;

  -- 2. Get Task Details
  SELECT * INTO v_task FROM public.tasks WHERE id = p_task_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Task not found');
  END IF;

  -- 3. Anti-Cheat: Cannot do own task
  IF v_task.user_id = v_user_id THEN
    RETURN jsonb_build_object('success', false, 'message', 'Cannot perform your own task');
  END IF;

  -- 4. Anti-Cheat: Already executed?
  IF EXISTS (SELECT 1 FROM public.task_executions WHERE task_id = p_task_id AND user_id = v_user_id) THEN
    RETURN jsonb_build_object('success', false, 'message', 'Task already completed');
  END IF;

  -- 5. Anti-Cheat: Rate Limit (Max 10 tasks per minute)
  SELECT COUNT(*) INTO v_execution_count 
  FROM public.task_executions 
  WHERE user_id = v_user_id AND created_at > (NOW() - INTERVAL '1 minute');
  
  IF v_execution_count >= 10 THEN
    RETURN jsonb_build_object('success', false, 'message', 'Rate limit exceeded. Please wait a moment.');
  END IF;

  -- 6. Check Owner Balance
  SELECT points INTO v_owner_points FROM public.profiles WHERE id = v_task.user_id;
  
  IF v_owner_points < v_task.cost_per_action THEN
    -- Pause task if owner has no points
    UPDATE public.tasks SET status = 'paused' WHERE id = p_task_id;
    RETURN jsonb_build_object('success', false, 'message', 'Task owner ran out of points');
  END IF;

  -- 7. EXECUTE TRANSACTION
  -- Deduct from owner
  UPDATE public.profiles SET points = points - v_task.cost_per_action WHERE id = v_task.user_id;
  
  -- Add to executor
  UPDATE public.profiles SET points = points + v_task.reward_per_action WHERE id = v_user_id;
  
  -- Log execution
  INSERT INTO public.task_executions (task_id, user_id) VALUES (p_task_id, v_user_id);

  RETURN jsonb_build_object('success', true, 'points', v_task.reward_per_action);
END;
$$;

-- 7. RPC: CLAIM AD REWARD
CREATE OR REPLACE FUNCTION public.claim_ad_reward()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_last_ad_time TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Not authenticated');
  END IF;

  -- Anti-Cheat: Check last ad time (Must be at least 30 seconds ago)
  SELECT created_at INTO v_last_ad_time 
  FROM public.ads_watched 
  WHERE user_id = v_user_id 
  ORDER BY created_at DESC 
  LIMIT 1;

  IF v_last_ad_time IS NOT NULL AND v_last_ad_time > (NOW() - INTERVAL '30 seconds') THEN
    RETURN jsonb_build_object('success', false, 'message', 'Please wait before watching another ad');
  END IF;

  -- Award Points (2 points)
  UPDATE public.profiles SET points = points + 2 WHERE id = v_user_id;
  
  -- Log Ad
  INSERT INTO public.ads_watched (user_id, points_earned) VALUES (v_user_id, 2);

  RETURN jsonb_build_object('success', true, 'points', 2);
END;
$$;
