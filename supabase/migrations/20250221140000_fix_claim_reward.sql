-- Drop existing function to avoid return type conflicts
DROP FUNCTION IF EXISTS claim_task_reward(uuid);

-- Recreate the function with SECURITY DEFINER and better error handling
CREATE OR REPLACE FUNCTION claim_task_reward(p_task_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER -- Allows the function to bypass RLS (Critical for updating other user's points)
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_task RECORD;
  v_owner_points INT;
BEGIN
  -- 1. Get current user
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'يرجى تسجيل الدخول أولاً');
  END IF;

  -- 2. Get Task Details
  SELECT * INTO v_task FROM tasks WHERE id = p_task_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'المهمة غير موجودة');
  END IF;

  -- 3. Validation: Cannot execute own task
  IF v_task.user_id = v_user_id THEN
    RETURN jsonb_build_object('success', false, 'message', 'لا يمكنك تنفيذ مهامك الخاصة');
  END IF;

  -- 4. Validation: Check if already executed
  IF EXISTS (SELECT 1 FROM task_executions WHERE task_id = p_task_id AND user_id = v_user_id) THEN
    RETURN jsonb_build_object('success', false, 'message', 'لقد قمت بتنفيذ هذه المهمة مسبقاً');
  END IF;

  -- 5. Check Owner Points (Lock row to prevent race conditions)
  SELECT points INTO v_owner_points FROM profiles WHERE id = v_task.user_id FOR UPDATE;
  
  IF v_owner_points < v_task.cost_per_action THEN
    -- Auto-pause task if owner has no points
    UPDATE tasks SET status = 'paused' WHERE id = p_task_id;
    RETURN jsonb_build_object('success', false, 'message', 'نفذت نقاط صاحب المهمة (تم إيقافها)');
  END IF;

  -- 6. Execute Transaction
  -- Deduct points from owner
  UPDATE profiles SET points = points - v_task.cost_per_action WHERE id = v_task.user_id;
  
  -- Add points to executor (current user)
  UPDATE profiles SET points = points + v_task.reward_per_action WHERE id = v_user_id;
  
  -- Record execution
  INSERT INTO task_executions (task_id, user_id) VALUES (p_task_id, v_user_id);

  -- Return success
  RETURN jsonb_build_object('success', true, 'points', v_task.reward_per_action);

EXCEPTION WHEN OTHERS THEN
  -- Catch any SQL errors and return them gracefully
  RETURN jsonb_build_object('success', false, 'message', 'خطأ في النظام: ' || SQLERRM);
END;
$$;
