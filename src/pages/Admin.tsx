import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { UserProfile, Task, PLATFORMS } from '../types';
import { Loader2, Users, ListTodo, ShieldAlert, Trash2, ArrowRight } from 'lucide-react';
import { Link, useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';

export default function Admin() {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState({ users: 0, tasks: 0, activeTasks: 0 });
  const [users, setUsers] = useState<UserProfile[]>([]);
  const [recentTasks, setRecentTasks] = useState<Task[]>([]);

  useEffect(() => {
    checkAdmin();
  }, []);

  const checkAdmin = async () => {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { navigate('/login'); return; }

    const { data: profile } = await supabase.from('profiles').select('role').eq('id', user.id).single();
    
    if (profile?.role !== 'admin') {
      toast.error('غير مصرح لك بالدخول');
      navigate('/dashboard');
      return;
    }

    fetchData();
  };

  const fetchData = async () => {
    setLoading(true);
    
    // Fetch Stats
    const { count: userCount } = await supabase.from('profiles').select('*', { count: 'exact', head: true });
    const { count: taskCount } = await supabase.from('tasks').select('*', { count: 'exact', head: true });
    const { count: activeCount } = await supabase.from('tasks').select('*', { count: 'exact', head: true }).eq('status', 'active');

    setStats({
      users: userCount || 0,
      tasks: taskCount || 0,
      activeTasks: activeCount || 0
    });

    // Fetch Users (Limit 50)
    const { data: usersData } = await supabase.from('profiles').select('*').order('created_at', { ascending: false }).limit(20);
    if (usersData) setUsers(usersData);

    // Fetch Tasks (Limit 50)
    const { data: tasksData } = await supabase.from('tasks').select('*').order('created_at', { ascending: false }).limit(20);
    if (tasksData) setRecentTasks(tasksData);

    setLoading(false);
  };

  const deleteTask = async (id: string) => {
    if(!confirm('حذف هذه المهمة نهائياً؟')) return;
    const { error } = await supabase.from('tasks').delete().eq('id', id);
    if (!error) {
        toast.success('تم الحذف');
        setRecentTasks(prev => prev.filter(t => t.id !== id));
    } else {
        toast.error('فشل الحذف');
    }
  };

  if (loading) return <div className="flex justify-center items-center h-screen"><Loader2 className="animate-spin" /></div>;

  return (
    <div className="p-5 pb-24 bg-gray-50 min-h-screen">
      <div className="flex items-center gap-3 mb-6">
        <Link to="/profile" className="p-2 bg-white rounded-full shadow-sm">
            <ArrowRight size={20} />
        </Link>
        <h1 className="text-2xl font-bold text-gray-900">لوحة التحكم</h1>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-3 gap-3 mb-8">
        <div className="bg-white p-4 rounded-xl shadow-sm border border-gray-100 text-center">
            <Users className="mx-auto text-blue-600 mb-2" size={24} />
            <div className="text-2xl font-bold">{stats.users}</div>
            <div className="text-xs text-gray-500">مستخدم</div>
        </div>
        <div className="bg-white p-4 rounded-xl shadow-sm border border-gray-100 text-center">
            <ListTodo className="mx-auto text-purple-600 mb-2" size={24} />
            <div className="text-2xl font-bold">{stats.tasks}</div>
            <div className="text-xs text-gray-500">مهمة</div>
        </div>
        <div className="bg-white p-4 rounded-xl shadow-sm border border-gray-100 text-center">
            <ShieldAlert className="mx-auto text-green-600 mb-2" size={24} />
            <div className="text-2xl font-bold">{stats.activeTasks}</div>
            <div className="text-xs text-gray-500">نشطة</div>
        </div>
      </div>

      {/* Recent Users */}
      <div className="mb-8">
        <h2 className="text-lg font-bold mb-4">آخر المستخدمين</h2>
        <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
            {users.map(user => (
                <div key={user.id} className="p-3 border-b last:border-0 flex justify-between items-center">
                    <div className="truncate max-w-[200px]">
                        <div className="font-bold text-sm truncate">{user.email}</div>
                        <div className="text-xs text-gray-500">{user.role}</div>
                    </div>
                    <div className="bg-gray-100 px-2 py-1 rounded text-xs font-bold">
                        {user.points} نقطة
                    </div>
                </div>
            ))}
        </div>
      </div>

      {/* Recent Tasks */}
      <div>
        <h2 className="text-lg font-bold mb-4">آخر المهام</h2>
        <div className="space-y-2">
            {recentTasks.map(task => (
                <div key={task.id} className="bg-white p-3 rounded-xl shadow-sm border border-gray-100 flex justify-between items-center">
                    <div className="flex items-center gap-3 overflow-hidden">
                        <div className={`w-8 h-8 rounded-full flex items-center justify-center text-white shrink-0 ${PLATFORMS[task.platform].color}`}>
                            {task.platform[0].toUpperCase()}
                        </div>
                        <div className="truncate">
                            <div className="text-sm font-bold truncate">{task.url}</div>
                            <div className="text-xs text-gray-500">{task.action_type}</div>
                        </div>
                    </div>
                    <button 
                        onClick={() => deleteTask(task.id)}
                        className="text-red-500 p-2 hover:bg-red-50 rounded-lg"
                    >
                        <Trash2 size={18} />
                    </button>
                </div>
            ))}
        </div>
      </div>
    </div>
  );
}
