-- Fix Security Advisories: Set search_path for all functions
-- This prevents malicious code from hijacking function calls

-- 1. Fix claim_task_reward
CREATE OR REPLACE FUNCTION public.claim_task_reward(p_task_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_task_owner_id uuid;
  v_cost int;
  v_reward int;
  v_task_status text;
  v_already_done boolean;
  v_owner_points int;
BEGIN
  -- Get current user
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'message', 'غير مسجل دخول');
  END IF;

  -- Get task details
  SELECT user_id, cost_per_action, reward_per_action, status
  INTO v_task_owner_id, v_cost, v_reward, v_task_status
  FROM public.tasks
  WHERE id = p_task_id;

  -- Validations
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'message', 'المهمة غير موجودة');
  END IF;

  IF v_task_status != 'active' THEN
    RETURN json_build_object('success', false, 'message', 'المهمة متوقفة حالياً');
  END IF;

  IF v_task_owner_id = v_user_id THEN
    RETURN json_build_object('success', false, 'message', 'لا يمكنك تنفيذ مهامك الخاصة');
  END IF;

  -- Check if already done
  SELECT EXISTS (
    SELECT 1 FROM public.task_executions 
    WHERE task_id = p_task_id AND user_id = v_user_id
  ) INTO v_already_done;

  IF v_already_done THEN
    RETURN json_build_object('success', false, 'message', 'لقد قمت بهذه المهمة مسبقاً');
  END IF;

  -- Check owner balance
  SELECT points INTO v_owner_points FROM public.profiles WHERE id = v_task_owner_id;
  
  IF v_owner_points < v_cost THEN
    -- Auto pause task if no points
    UPDATE public.tasks SET status = 'paused' WHERE id = p_task_id;
    RETURN json_build_object('success', false, 'message', 'نفذ رصيد صاحب المهمة');
  END IF;

  -- EXECUTE TRANSACTION
  -- 1. Deduct from owner
  UPDATE public.profiles 
  SET points = points - v_cost 
  WHERE id = v_task_owner_id;

  -- 2. Add to executor
  UPDATE public.profiles 
  SET points = points + v_reward 
  WHERE id = v_user_id;

  -- 3. Log execution
  INSERT INTO public.task_executions (task_id, user_id)
  VALUES (p_task_id, v_user_id);

  RETURN json_build_object('success', true, 'points', v_reward);
END;
$$;

-- 2. Fix claim_ad_reward
CREATE OR REPLACE FUNCTION public.claim_ad_reward()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_last_ad_time timestamptz;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'message', 'غير مسجل دخول');
  END IF;

  -- Rate limiting (prevent spamming)
  SELECT created_at INTO v_last_ad_time
  FROM public.ads_watched
  WHERE user_id = v_user_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_last_ad_time IS NOT NULL AND (EXTRACT(EPOCH FROM (now() - v_last_ad_time)) < 25) THEN
    RETURN json_build_object('success', false, 'message', 'يرجى الانتظار قبل مشاهدة إعلان آخر');
  END IF;

  -- Give reward (2 points)
  UPDATE public.profiles
  SET points = points + 2
  WHERE id = v_user_id;

  -- Log
  INSERT INTO public.ads_watched (user_id, points_earned)
  VALUES (v_user_id, 2);

  RETURN json_build_object('success', true, 'points', 2);
END;
$$;

-- 3. Ensure social_accounts column exists (Idempotent)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'social_accounts') THEN
        ALTER TABLE public.profiles ADD COLUMN social_accounts JSONB;
    END IF;
END $$;
