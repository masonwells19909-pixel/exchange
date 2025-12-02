import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Task, PLATFORMS, ACTION_TYPES } from '../types';
import { Loader2, Trash2, PauseCircle, PlayCircle, ArrowRight } from 'lucide-react';
import toast from 'react-hot-toast';
import { Link } from 'react-router-dom';

export default function MyTasks() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchMyTasks();
  }, []);

  const fetchMyTasks = async () => {
    const { data: { user } } = await supabase.auth.getUser();
    if (user) {
      const { data, error } = await supabase
        .from('tasks')
        .select('*')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false });
      
      if (!error && data) setTasks(data);
    }
    setLoading(false);
  };

  const toggleStatus = async (task: Task) => {
    const newStatus = task.status === 'active' ? 'paused' : 'active';
    const { error } = await supabase
      .from('tasks')
      .update({ status: newStatus })
      .eq('id', task.id);

    if (error) {
      toast.error('فشل تحديث الحالة');
    } else {
      setTasks(tasks.map(t => t.id === task.id ? { ...t, status: newStatus } : t));
      toast.success(newStatus === 'active' ? 'تم تفعيل المهمة' : 'تم إيقاف المهمة');
    }
  };

  const deleteTask = async (id: string) => {
    if (!confirm('هل أنت متأكد من حذف هذه المهمة؟')) return;

    const { error } = await supabase.from('tasks').delete().eq('id', id);
    if (error) {
      toast.error('فشل الحذف');
    } else {
      setTasks(tasks.filter(t => t.id !== id));
      toast.success('تم الحذف بنجاح');
    }
  };

  return (
    <div className="p-5 pb-24">
      <div className="flex items-center gap-3 mb-6">
        <Link to="/profile" className="p-2 bg-gray-100 rounded-full hover:bg-gray-200">
            <ArrowRight size={20} />
        </Link>
        <h1 className="text-2xl font-bold">مهامي</h1>
      </div>

      {loading ? (
        <div className="flex justify-center py-10"><Loader2 className="animate-spin" /></div>
      ) : tasks.length === 0 ? (
        <div className="text-center py-10 text-gray-500">
            <p>لم تقم بإضافة أي مهام بعد</p>
            <Link to="/create" className="text-blue-600 font-bold mt-2 inline-block">أضف مهمة جديدة</Link>
        </div>
      ) : (
        <div className="space-y-3">
            {tasks.map(task => (
                <div key={task.id} className="bg-white p-4 rounded-xl shadow-sm border border-gray-100">
                    <div className="flex justify-between items-start mb-2">
                        <div>
                            <span className={`text-xs font-bold px-2 py-1 rounded-md ${task.status === 'active' ? 'bg-green-100 text-green-700' : 'bg-yellow-100 text-yellow-700'}`}>
                                {task.status === 'active' ? 'نشط' : 'متوقف'}
                            </span>
                            <h3 className="font-bold mt-1">{PLATFORMS[task.platform].label} - {ACTION_TYPES[task.action_type].label}</h3>
                        </div>
                        <div className="text-left">
                            <span className="text-sm font-bold text-red-500">-{task.cost_per_action} نقطة</span>
                        </div>
                    </div>
                    <p className="text-xs text-gray-400 truncate mb-4">{task.url}</p>
                    
                    <div className="flex gap-2 border-t pt-3">
                        <button 
                            onClick={() => toggleStatus(task)}
                            className="flex-1 py-2 rounded-lg bg-gray-50 hover:bg-gray-100 text-gray-700 text-sm font-bold flex items-center justify-center gap-2"
                        >
                            {task.status === 'active' ? <><PauseCircle size={16} /> إيقاف</> : <><PlayCircle size={16} /> تفعيل</>}
                        </button>
                        <button 
                            onClick={() => deleteTask(task.id)}
                            className="flex-1 py-2 rounded-lg bg-red-50 hover:bg-red-100 text-red-600 text-sm font-bold flex items-center justify-center gap-2"
                        >
                            <Trash2 size={16} /> حذف
                        </button>
                    </div>
                </div>
            ))}
        </div>
      )}
    </div>
  );
}
