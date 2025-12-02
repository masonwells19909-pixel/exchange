-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- 1. PROFILES TABLE
create table if not exists public.profiles (
  id uuid references auth.users on delete cascade not null primary key,
  email text,
  points int default 50,
  created_at timestamptz default now()
);
alter table public.profiles enable row level security;

-- Safely recreate policies for profiles
drop policy if exists "Users can view own profile" on public.profiles;
create policy "Users can view own profile" on public.profiles for select using (auth.uid() = id);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile" on public.profiles for update using (auth.uid() = id);

-- 2. TASKS TABLE
create table if not exists public.tasks (
  id uuid default uuid_generate_v4() primary key,
  user_id uuid references public.profiles(id) not null,
  platform text not null,
  action_type text not null,
  url text not null,
  cost_per_action int not null,
  reward_per_action int not null,
  status text default 'active' check (status in ('active', 'paused', 'stopped')),
  created_at timestamptz default now()
);
alter table public.tasks enable row level security;

-- Safely recreate policies for tasks
drop policy if exists "Anyone can view active tasks" on public.tasks;
create policy "Anyone can view active tasks" on public.tasks for select using (status = 'active');

drop policy if exists "Users can view own tasks" on public.tasks;
create policy "Users can view own tasks" on public.tasks for select using (auth.uid() = user_id);

drop policy if exists "Users can insert own tasks" on public.tasks;
create policy "Users can insert own tasks" on public.tasks for insert with check (auth.uid() = user_id);

drop policy if exists "Users can update own tasks" on public.tasks;
create policy "Users can update own tasks" on public.tasks for update using (auth.uid() = user_id);

drop policy if exists "Users can delete own tasks" on public.tasks;
create policy "Users can delete own tasks" on public.tasks for delete using (auth.uid() = user_id);

-- 3. TASK EXECUTIONS TABLE
create table if not exists public.task_executions (
  id uuid default uuid_generate_v4() primary key,
  task_id uuid references public.tasks(id) on delete cascade,
  user_id uuid references public.profiles(id),
  created_at timestamptz default now(),
  unique(task_id, user_id)
);
alter table public.task_executions enable row level security;

drop policy if exists "Users can view own executions" on public.task_executions;
create policy "Users can view own executions" on public.task_executions for select using (auth.uid() = user_id);

-- 4. ADS WATCHED TABLE
create table if not exists public.ads_watched (
  id uuid default uuid_generate_v4() primary key,
  user_id uuid references public.profiles(id),
  created_at timestamptz default now()
);
alter table public.ads_watched enable row level security;

drop policy if exists "Users can view own ads history" on public.ads_watched;
create policy "Users can view own ads history" on public.ads_watched for select using (auth.uid() = user_id);

-- 5. FUNCTIONS & TRIGGERS

-- Handle New User Trigger
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, points)
  values (new.id, new.email, 50)
  on conflict (id) do nothing; -- Prevent error if profile exists
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Claim Task Reward Function (Anti-Cheat Logic)
create or replace function claim_task_reward(p_task_id uuid)
returns json as $$
declare
  v_task record;
  v_user_points int;
  v_creator_points int;
  v_already_done boolean;
begin
  -- Get Task Info
  select * into v_task from public.tasks where id = p_task_id;
  
  if not found then
    return json_build_object('success', false, 'message', 'المهمة غير موجودة');
  end if;

  if v_task.status != 'active' then
    return json_build_object('success', false, 'message', 'المهمة غير نشطة حالياً');
  end if;

  if v_task.user_id = auth.uid() then
    return json_build_object('success', false, 'message', 'لا يمكنك تنفيذ مهامك الخاصة');
  end if;

  -- Check if already done
  select exists(select 1 from public.task_executions where task_id = p_task_id and user_id = auth.uid()) into v_already_done;
  if v_already_done then
    return json_build_object('success', false, 'message', 'لقد قمت بهذه المهمة مسبقاً');
  end if;

  -- Check Creator Balance
  select points into v_creator_points from public.profiles where id = v_task.user_id;
  if v_creator_points < v_task.cost_per_action then
    -- Pause task if no funds
    update public.tasks set status = 'paused' where id = p_task_id;
    return json_build_object('success', false, 'message', 'نفذ رصيد صاحب المهمة');
  end if;

  -- Execute Transaction
  update public.profiles set points = points - v_task.cost_per_action where id = v_task.user_id;
  update public.profiles set points = points + v_task.reward_per_action where id = auth.uid();
  
  insert into public.task_executions (task_id, user_id) values (p_task_id, auth.uid());

  return json_build_object('success', true, 'points', v_task.reward_per_action);
end;
$$ language plpgsql security definer;

-- Claim Ad Reward Function
create or replace function claim_ad_reward()
returns json as $$
declare
  v_last_watch timestamptz;
begin
  -- Check rate limit (30 seconds)
  select created_at into v_last_watch from public.ads_watched where user_id = auth.uid() order by created_at desc limit 1;
  
  if v_last_watch is not null and now() - v_last_watch < interval '30 seconds' then
    return json_build_object('success', false, 'message', 'يرجى الانتظار قبل مشاهدة إعلان آخر');
  end if;

  -- Give points
  update public.profiles set points = points + 2 where id = auth.uid();
  insert into public.ads_watched (user_id) values (auth.uid());

  return json_build_object('success', true);
end;
$$ language plpgsql security definer;
