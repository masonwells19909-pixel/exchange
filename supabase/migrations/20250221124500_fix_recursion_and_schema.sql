-- 1. Drop existing policies to fix Infinite Recursion
DROP POLICY IF EXISTS "Users can read all profiles" ON profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
DROP POLICY IF EXISTS "Users can read active tasks" ON tasks;
DROP POLICY IF EXISTS "Users can insert own tasks" ON tasks;
DROP POLICY IF EXISTS "Users can update own tasks" ON tasks;
DROP POLICY IF EXISTS "Users can delete own tasks" ON tasks;
DROP POLICY IF EXISTS "Users can read own executions" ON task_executions;
DROP POLICY IF EXISTS "Users can insert own executions" ON task_executions;

-- 2. Recreate simplified policies (Non-recursive)
-- Profiles: Everyone can read (needed for leaderboards/checks), only owner can update
CREATE POLICY "Public read profiles" ON profiles FOR SELECT USING (true);
CREATE POLICY "Owner update profiles" ON profiles FOR UPDATE USING (auth.uid() = id);

-- Tasks: Active tasks are public, owner has full control over their own
CREATE POLICY "Public read tasks" ON tasks FOR SELECT USING (status = 'active' OR auth.uid() = user_id);
CREATE POLICY "Owner insert tasks" ON tasks FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Owner update tasks" ON tasks FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Owner delete tasks" ON tasks FOR DELETE USING (auth.uid() = user_id);

-- Executions: Owner can insert and read
CREATE POLICY "Owner read executions" ON task_executions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Owner insert executions" ON task_executions FOR INSERT WITH CHECK (auth.uid() = user_id);

-- 3. Update Schema for Quantity System
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS target_quantity INTEGER DEFAULT 10;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS current_quantity INTEGER DEFAULT 0;

-- 4. Update Reward Function to handle quantity limits
CREATE OR REPLACE FUNCTION claim_task_reward(p_task_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_task RECORD;
  v_points_to_add INT;
  v_already_done BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  
  -- Get task details
  SELECT * INTO v_task FROM tasks WHERE id = p_task_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'المهمة غير موجودة');
  END IF;

  -- Prevent self-execution
  IF v_task.user_id = v_user_id THEN
    RETURN jsonb_build_object('success', false, 'message', 'لا يمكنك تنفيذ مهامك الخاصة');
  END IF;

  -- Check if task is finished
  IF v_task.status != 'active' OR v_task.current_quantity >= v_task.target_quantity THEN
    RETURN jsonb_build_object('success', false, 'message', 'انتهت هذه المهمة');
  END IF;

  -- Check if already executed
  SELECT EXISTS (SELECT 1 FROM task_executions WHERE task_id = p_task_id AND user_id = v_user_id) INTO v_already_done;
  IF v_already_done THEN
    RETURN jsonb_build_object('success', false, 'message', 'لقد نفذت هذه المهمة مسبقاً');
  END IF;

  -- Record execution
  INSERT INTO task_executions (task_id, user_id) VALUES (p_task_id, v_user_id);

  -- Transfer points (Reward the executor)
  -- Note: The cost was already deducted from the creator when creating the task (or reserved).
  -- In this model, we assume points are deducted from creator *upon creation* or *held*.
  -- To keep it simple and safe: We deduct from creator NOW if not already deducted, OR we assume the creator paid upfront.
  -- Let's assume "Pay as you go" model for better UX: Deduct from creator now.
  
  -- Check creator balance
  IF (SELECT points FROM profiles WHERE id = v_task.user_id) < v_task.reward_per_action THEN
     -- Pause task if creator has no points
     UPDATE tasks SET status = 'paused' WHERE id = p_task_id;
     RETURN jsonb_build_object('success', false, 'message', 'رصيد صاحب المهمة نفذ');
  END IF;

  -- Deduct from creator
  UPDATE profiles SET points = points - v_task.reward_per_action WHERE id = v_task.user_id;
  
  -- Add to executor
  UPDATE profiles SET points = points + v_task.reward_per_action WHERE id = v_user_id;

  -- Update task quantity
  UPDATE tasks 
  SET current_quantity = current_quantity + 1,
      status = CASE WHEN current_quantity + 1 >= target_quantity THEN 'finished' ELSE status END
  WHERE id = p_task_id;

  RETURN jsonb_build_object('success', true, 'points', v_task.reward_per_action);
END;
$$;
