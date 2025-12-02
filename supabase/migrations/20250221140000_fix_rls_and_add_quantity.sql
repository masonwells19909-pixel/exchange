-- 1. Fix Infinite Recursion in Profiles Policy
-- Drop existing policies to start fresh
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;

-- Create simple, non-recursive policies
-- Allow anyone to read profiles (needed for leaderboards/tasks validation)
CREATE POLICY "Public profiles are viewable by everyone" 
ON profiles FOR SELECT 
USING (true);

-- Allow users to insert their own profile
CREATE POLICY "Users can insert their own profile" 
ON profiles FOR INSERT 
WITH CHECK (auth.uid() = id);

-- Allow users to update ONLY their own profile
CREATE POLICY "Users can update own profile" 
ON profiles FOR UPDATE 
USING (auth.uid() = id);

-- 2. Add Quantity Column to Tasks
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS target_quantity INTEGER DEFAULT 0;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS current_quantity INTEGER DEFAULT 0;

-- 3. Update Task Reward Function to respect Quantity
CREATE OR REPLACE FUNCTION claim_task_reward(p_task_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_task RECORD;
  v_user_id UUID;
  v_user_points INTEGER;
  v_already_done BOOLEAN;
BEGIN
  -- Get current user
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'يجب تسجيل الدخول');
  END IF;

  -- Get task details
  SELECT * INTO v_task FROM tasks WHERE id = p_task_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'المهمة غير موجودة');
  END IF;

  -- Check if task is active
  IF v_task.status != 'active' THEN
    RETURN jsonb_build_object('success', false, 'message', 'المهمة متوقفة');
  END IF;

  -- Check if owner has points
  SELECT points INTO v_user_points FROM profiles WHERE id = v_task.user_id;
  
  IF v_user_points < v_task.cost_per_action THEN
    -- Auto pause task if no points
    UPDATE tasks SET status = 'paused' WHERE id = p_task_id;
    RETURN jsonb_build_object('success', false, 'message', 'نفذت نقاط صاحب المهمة');
  END IF;

  -- Check quantity limit (if set)
  IF v_task.target_quantity > 0 AND v_task.current_quantity >= v_task.target_quantity THEN
     UPDATE tasks SET status = 'finished' WHERE id = p_task_id;
     RETURN jsonb_build_object('success', false, 'message', 'اكتمل العدد المطلوب لهذه المهمة');
  END IF;

  -- Check if user is owner
  IF v_task.user_id = v_user_id THEN
    RETURN jsonb_build_object('success', false, 'message', 'لا يمكنك تنفيذ مهامك الخاصة');
  END IF;

  -- Check if already done
  SELECT EXISTS (
    SELECT 1 FROM task_executions 
    WHERE task_id = p_task_id AND user_id = v_user_id
  ) INTO v_already_done;

  IF v_already_done THEN
    RETURN jsonb_build_object('success', false, 'message', 'لقد قمت بهذه المهمة مسبقاً');
  END IF;

  -- EXECUTE TRANSACTION
  -- 1. Deduct from owner
  UPDATE profiles SET points = points - v_task.cost_per_action WHERE id = v_task.user_id;
  
  -- 2. Add to executor
  UPDATE profiles SET points = points + v_task.reward_per_action WHERE id = v_user_id;
  
  -- 3. Record execution
  INSERT INTO task_executions (task_id, user_id) VALUES (p_task_id, v_user_id);

  -- 4. Update task quantity stats
  UPDATE tasks SET current_quantity = current_quantity + 1 WHERE id = p_task_id;

  RETURN jsonb_build_object('success', true, 'points', v_task.reward_per_action);
END;
$$;
