/*
  # Fix Database Schema & Functions
  
  ## Metadata:
  - Schema-Category: "Structural"
  - Impact-Level: "High"
  - Requires-Backup: false
  - Reversible: true
  
  ## Description:
  1. Drops existing conflicting functions to fix "cannot change return type" error.
  2. Ensures all tables and columns exist (including social_accounts).
  3. Re-creates secure functions with fixed search_path.
  4. Refreshes RLS policies.
*/

-- 1. Drop conflicting functions explicitly
DROP FUNCTION IF EXISTS public.claim_task_reward(uuid);
DROP FUNCTION IF EXISTS public.claim_ad_reward();

-- 2. Create Tables (if not exist)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID REFERENCES auth.users(id) PRIMARY KEY,
    email TEXT,
    points INTEGER DEFAULT 50,
    role TEXT DEFAULT 'user',
    social_accounts JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Ensure columns exist (Safe Alter)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'social_accounts') THEN
        ALTER TABLE public.profiles ADD COLUMN social_accounts JSONB DEFAULT '{}'::jsonb;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'role') THEN
        ALTER TABLE public.profiles ADD COLUMN role TEXT DEFAULT 'user';
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.tasks (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) NOT NULL,
    platform TEXT NOT NULL,
    action_type TEXT NOT NULL,
    url TEXT NOT NULL,
    cost_per_action INTEGER NOT NULL,
    reward_per_action INTEGER NOT NULL,
    status TEXT DEFAULT 'active',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.task_executions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    task_id UUID REFERENCES public.tasks(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.ads_watched (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ads_watched ENABLE ROW LEVEL SECURITY;

-- 4. Refresh Policies (Drop & Recreate)
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Public tasks are viewable" ON public.tasks;
DROP POLICY IF EXISTS "Users can create tasks" ON public.tasks;
DROP POLICY IF EXISTS "Users can update own tasks" ON public.tasks;
DROP POLICY IF EXISTS "Users can delete own tasks" ON public.tasks;
DROP POLICY IF EXISTS "Admins can view all tasks" ON public.tasks;
DROP POLICY IF EXISTS "Users can view own executions" ON public.task_executions;
DROP POLICY IF EXISTS "Users can view own ads" ON public.ads_watched;

-- Create Policies
CREATE POLICY "Users can view own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Admins can view all profiles" ON public.profiles FOR SELECT USING (
  (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'admin'
);

CREATE POLICY "Public tasks are viewable" ON public.tasks FOR SELECT USING (true);
CREATE POLICY "Users can create tasks" ON public.tasks FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own tasks" ON public.tasks FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own tasks" ON public.tasks FOR DELETE USING (auth.uid() = user_id);
CREATE POLICY "Admins can view all tasks" ON public.tasks FOR SELECT USING (
  (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'admin'
);

CREATE POLICY "Users can view own executions" ON public.task_executions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can view own ads" ON public.ads_watched FOR SELECT USING (auth.uid() = user_id);

-- 5. Recreate Functions (Secure & Fixed)

-- Trigger for new users
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, points, role)
  VALUES (new.id, new.email, 50, 'user');
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function: Claim Task Reward
CREATE OR REPLACE FUNCTION public.claim_task_reward(p_task_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_task_owner_id UUID;
  v_reward INTEGER;
  v_cost INTEGER;
  v_owner_points INTEGER;
  v_already_done BOOLEAN;
BEGIN
  v_user_id := auth.uid();

  -- Check if task exists
  SELECT user_id, reward_per_action, cost_per_action INTO v_task_owner_id, v_reward, v_cost
  FROM public.tasks WHERE id = p_task_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'المهمة غير موجودة');
  END IF;

  -- Prevent self-execution
  IF v_user_id = v_task_owner_id THEN
    RETURN jsonb_build_object('success', false, 'message', 'لا يمكنك كسب نقاط من مهامك الخاصة');
  END IF;

  -- Check if already done
  SELECT EXISTS(SELECT 1 FROM public.task_executions WHERE task_id = p_task_id AND user_id = v_user_id)
  INTO v_already_done;

  IF v_already_done THEN
    RETURN jsonb_build_object('success', false, 'message', 'لقد قمت بهذه المهمة مسبقاً');
  END IF;

  -- Check owner balance
  SELECT points INTO v_owner_points FROM public.profiles WHERE id = v_task_owner_id;

  IF v_owner_points < v_cost THEN
    -- Pause task if no points
    UPDATE public.tasks SET status = 'paused' WHERE id = p_task_id;
    RETURN jsonb_build_object('success', false, 'message', 'نفذت نقاط صاحب المهمة');
  END IF;

  -- Execute Transaction
  INSERT INTO public.task_executions (task_id, user_id) VALUES (p_task_id, v_user_id);
  
  -- Deduct from owner
  UPDATE public.profiles SET points = points - v_cost WHERE id = v_task_owner_id;
  
  -- Add to executor
  UPDATE public.profiles SET points = points + v_reward WHERE id = v_user_id;

  RETURN jsonb_build_object('success', true, 'points', v_reward);
END;
$$;

-- Function: Claim Ad Reward
CREATE OR REPLACE FUNCTION public.claim_ad_reward()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_last_ad_time TIMESTAMP;
BEGIN
  v_user_id := auth.uid();

  -- Rate Limit: Check last ad time (must be > 25 seconds ago)
  SELECT created_at INTO v_last_ad_time 
  FROM public.ads_watched 
  WHERE user_id = v_user_id 
  ORDER BY created_at DESC LIMIT 1;

  IF v_last_ad_time IS NOT NULL AND NOW() - v_last_ad_time < INTERVAL '25 seconds' THEN
    RETURN jsonb_build_object('success', false, 'message', 'يرجى الانتظار قبل مشاهدة إعلان آخر');
  END IF;

  -- Record Ad Watch
  INSERT INTO public.ads_watched (user_id) VALUES (v_user_id);

  -- Add Points (2 Points)
  UPDATE public.profiles SET points = points + 2 WHERE id = v_user_id;

  RETURN jsonb_build_object('success', true, 'points', 2);
END;
$$;
