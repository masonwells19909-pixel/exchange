/*
  # Social Exchange App Schema
  
  ## Query Description:
  Creates the full database structure for the Social Exchange app, including users, tasks, executions, and ad tracking.
  Includes secure functions for point transactions.

  ## Metadata:
  - Schema-Category: Structural
  - Impact-Level: High
  - Requires-Backup: false
  - Reversible: true
*/

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. PROFILES TABLE (Extends auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT,
    points INTEGER DEFAULT 50, -- Start with 50 bonus points
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. TASKS TABLE
CREATE TABLE IF NOT EXISTS public.tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    platform TEXT NOT NULL, -- 'youtube', 'telegram', 'facebook', 'tiktok', 'instagram'
    action_type TEXT NOT NULL, -- 'subscribe', 'like', 'comment', 'view', 'follow', 'share', 'join'
    url TEXT NOT NULL,
    cost_per_action INTEGER NOT NULL, -- Points deducted from creator
    reward_per_action INTEGER NOT NULL, -- Points given to doer
    status TEXT DEFAULT 'active', -- 'active', 'paused', 'stopped'
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. TASK EXECUTIONS (History & Anti-Cheat)
CREATE TABLE IF NOT EXISTS public.task_executions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_id UUID REFERENCES public.tasks(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(task_id, user_id) -- Prevent doing same task twice
);

-- 4. ADS WATCHED
CREATE TABLE IF NOT EXISTS public.ads_watched (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS POLICIES
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ads_watched ENABLE ROW LEVEL SECURITY;

-- Profiles Policies
CREATE POLICY "Users can view own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Tasks Policies
CREATE POLICY "Anyone can view active tasks" ON public.tasks FOR SELECT USING (status = 'active');
CREATE POLICY "Users can view own tasks" ON public.tasks FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can create tasks" ON public.tasks FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own tasks" ON public.tasks FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own tasks" ON public.tasks FOR DELETE USING (auth.uid() = user_id);

-- Task Executions Policies
CREATE POLICY "Users can view own executions" ON public.task_executions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "System can insert executions" ON public.task_executions FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Ads Policies
CREATE POLICY "Users can view own ad history" ON public.ads_watched FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert ad history" ON public.ads_watched FOR INSERT WITH CHECK (auth.uid() = user_id);


-- TRIGGER: Create Profile on Signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, points)
  VALUES (new.id, new.email, 50);
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- FUNCTION: Execute Task (Transactional Point Swap)
CREATE OR REPLACE FUNCTION public.claim_task_reward(
  p_task_id UUID
) RETURNS JSONB AS $$
DECLARE
  v_user_id UUID;
  v_task RECORD;
  v_creator_points INTEGER;
BEGIN
  v_user_id := auth.uid();
  
  -- 1. Get Task Details
  SELECT * INTO v_task FROM public.tasks WHERE id = p_task_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'المهمة غير موجودة');
  END IF;

  -- 2. Check if user is creator (Cannot do own task)
  IF v_task.user_id = v_user_id THEN
    RETURN jsonb_build_object('success', false, 'message', 'لا يمكنك تنفيذ مهامك الخاصة');
  END IF;

  -- 3. Check if already done
  IF EXISTS (SELECT 1 FROM public.task_executions WHERE task_id = p_task_id AND user_id = v_user_id) THEN
    RETURN jsonb_build_object('success', false, 'message', 'لقد قمت بهذه المهمة مسبقاً');
  END IF;

  -- 4. Check Creator Balance
  SELECT points INTO v_creator_points FROM public.profiles WHERE id = v_task.user_id;
  
  IF v_creator_points < v_task.cost_per_action THEN
    -- Auto pause task if insufficient funds
    UPDATE public.tasks SET status = 'paused' WHERE id = p_task_id;
    RETURN jsonb_build_object('success', false, 'message', 'عذراً، انتهت نقاط صاحب المهمة');
  END IF;

  -- 5. EXECUTE TRANSACTION
  -- Deduct from Creator
  UPDATE public.profiles SET points = points - v_task.cost_per_action WHERE id = v_task.user_id;
  
  -- Add to Doer
  UPDATE public.profiles SET points = points + v_task.reward_per_action WHERE id = v_user_id;
  
  -- Log Execution
  INSERT INTO public.task_executions (task_id, user_id) VALUES (p_task_id, v_user_id);

  RETURN jsonb_build_object('success', true, 'message', 'تم احتساب النقاط بنجاح', 'points', v_task.reward_per_action);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- FUNCTION: Watch Ad Reward
CREATE OR REPLACE FUNCTION public.claim_ad_reward() 
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID;
  v_last_ad TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();

  -- Rate Limit: Check if watched in last 30 seconds
  SELECT created_at INTO v_last_ad FROM public.ads_watched 
  WHERE user_id = v_user_id 
  ORDER BY created_at DESC LIMIT 1;

  IF v_last_ad IS NOT NULL AND NOW() - v_last_ad < INTERVAL '30 seconds' THEN
     RETURN jsonb_build_object('success', false, 'message', 'يرجى الانتظار قبل مشاهدة إعلان آخر');
  END IF;

  -- Add Points (2 points)
  UPDATE public.profiles SET points = points + 2 WHERE id = v_user_id;
  
  -- Log
  INSERT INTO public.ads_watched (user_id) VALUES (v_user_id);

  RETURN jsonb_build_object('success', true, 'message', 'تم إضافة 2 نقطة لرصيدك');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
