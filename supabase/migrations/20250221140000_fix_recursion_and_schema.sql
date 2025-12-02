-- Start a transaction to ensure atomic updates
BEGIN;

-- 1. Drop existing policies to prevent conflicts and recursion
DROP POLICY IF EXISTS "Users can view own profile" ON profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON profiles;
DROP POLICY IF EXISTS "Tasks are viewable by everyone" ON tasks;
DROP POLICY IF EXISTS "Users can insert own tasks" ON tasks;
DROP POLICY IF EXISTS "Users can update own tasks" ON tasks;
DROP POLICY IF EXISTS "Users can delete own tasks" ON tasks;
DROP POLICY IF EXISTS "Task executions viewable by user" ON task_executions;
DROP POLICY IF EXISTS "Users can insert execution" ON task_executions;

-- 2. Ensure Tables have correct columns
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS social_accounts JSONB DEFAULT '{}'::jsonb;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'user';

ALTER TABLE tasks ADD COLUMN IF NOT EXISTS target_quantity INTEGER DEFAULT 10;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS current_quantity INTEGER DEFAULT 0;

-- 3. Create Simplified Policies (Avoiding Recursion)

-- PROFILES: Users can read all profiles (needed for leaderboards/admin), but only update their own
CREATE POLICY "Profiles are viewable by everyone" 
ON profiles FOR SELECT 
USING (true);

CREATE POLICY "Users can update own profile" 
ON profiles FOR UPDATE 
USING (auth.uid() = id);

-- TASKS: Everyone can see active tasks. Users can manage their own.
CREATE POLICY "Tasks are viewable by everyone" 
ON tasks FOR SELECT 
USING (true);

CREATE POLICY "Users can insert own tasks" 
ON tasks FOR INSERT 
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own tasks" 
ON tasks FOR UPDATE 
USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own tasks" 
ON tasks FOR DELETE 
USING (auth.uid() = user_id);

-- EXECUTIONS: Users can see their own history
CREATE POLICY "Users can view own executions" 
ON task_executions FOR SELECT 
USING (auth.uid() = user_id);

-- 4. Re-create the Reward Function with Quantity Logic & Security Definer
CREATE OR REPLACE FUNCTION claim_task_reward(p_task_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER -- Runs with admin privileges to bypass RLS during point transfer
SET search_path = public -- Security best practice
AS $$
DECLARE
  v_user_id UUID;
  v_task RECORD;
  v_execution_exists BOOLEAN;
  v_creator_points INTEGER;
BEGIN
  v_user_id := auth.uid();
  
  -- Check if user is logged in
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'User not logged in');
  END IF;

  -- Get Task Details
  SELECT * INTO v_task FROM tasks WHERE id = p_task_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Task not found');
  END IF;

  -- Prevent self-execution
  IF v_task.user_id = v_user_id THEN
    RETURN jsonb_build_object('success', false, 'message', 'Cannot execute own task');
  END IF;

  -- Check if task is active and not finished
  IF v_task.status <> 'active' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Task is not active');
  END IF;

  -- Check Quantity Limit
  IF v_task.current_quantity >= v_task.target_quantity THEN
    UPDATE tasks SET status = 'finished' WHERE id = p_task_id;
    RETURN jsonb_build_object('success', false, 'message', 'Task finished');
  END IF;

  -- Check if already executed
  SELECT EXISTS (
    SELECT 1 FROM task_executions WHERE task_id = p_task_id AND user_id = v_user_id
  ) INTO v_execution_exists;

  IF v_execution_exists THEN
    RETURN jsonb_build_object('success', false, 'message', 'Already executed');
  END IF;

  -- Check Creator Balance (Double Check)
  SELECT points INTO v_creator_points FROM profiles WHERE id = v_task.user_id;
  
  IF v_creator_points < v_task.reward_per_action THEN
    -- Pause task if creator is out of points
    UPDATE tasks SET status = 'paused' WHERE id = p_task_id;
    RETURN jsonb_build_object('success', false, 'message', 'Task paused (Insufficent funds)');
  END IF;

  -- EXECUTE TRANSFER
  -- 1. Deduct from Creator (Cost) - Note: We deduct the REWARD amount from creator to give to user. 
  --    Or if we follow the "Cost vs Reward" model: Creator paid 'cost' upfront? 
  --    Model A: Creator pays points when creating task (Escrow). 
  --    Model B: Creator pays points when task is executed.
  --    Current implementation in CreateTask.tsx does NOT deduct upfront. So we deduct NOW.
  
  UPDATE profiles SET points = points - v_task.cost_per_action WHERE id = v_task.user_id;
  
  -- 2. Add to Executor (Reward)
  UPDATE profiles SET points = points + v_task.reward_per_action WHERE id = v_user_id;

  -- 3. Record Execution
  INSERT INTO task_executions (task_id, user_id, platform, action_type, reward_amount)
  VALUES (p_task_id, v_user_id, v_task.platform, v_task.action_type, v_task.reward_per_action);

  -- 4. Update Task Quantity
  UPDATE tasks 
  SET current_quantity = current_quantity + 1,
      status = CASE WHEN current_quantity + 1 >= target_quantity THEN 'finished' ELSE status END
  WHERE id = p_task_id;

  RETURN jsonb_build_object('success', true, 'points', v_task.reward_per_action);
END;
$$;

COMMIT;
