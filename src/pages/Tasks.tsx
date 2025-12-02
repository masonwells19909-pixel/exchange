import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Task, PLATFORMS, ACTION_TYPES, UserProfile } from '../types';
import { CheckCircle2, Loader2, AlertTriangle, Clock } from 'lucide-react';
import toast from 'react-hot-toast';
import * as Icons from 'lucide-react';
import { Link } from 'react-router-dom';

export default function Tasks() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [processingId, setProcessingId] = useState<string | null>(null);
  const [filter, setFilter] = useState<string>('all');
  const [userProfile, setUserProfile] = useState<UserProfile | null>(null);

  useEffect(() => {
    fetchTasks();
  }, []);

  const fetchTasks = async () => {
    setLoading(true);
    
    const { data: { user } } = await supabase.auth.getUser();
    if (user) {
        const { data: profile } = await supabase.from('profiles').select('*').eq('id', user.id).single();
        setUserProfile(profile);
    }

    const { data, error } = await supabase
      .from('tasks')
      .select('*')
      .eq('status', 'active')
      .order('created_at', { ascending: false });

    if (error) {
      toast.error('فشل تحميل المهام');
    } else {
      // Filter out own tasks
      const filtered = data?.filter(t => t.user_id !== user?.id) || [];
      
      // Filter out already executed tasks
      if (user) {
          const { data: executions } = await supabase.from('task_executions').select('task_id').eq('user_id', user.id);
          const doneIds = new Set(executions?.map(e => e.task_id));
          setTasks(filtered.filter(t => !doneIds.has(t.id)));
      } else {
          setTasks(filtered);
      }
    }
    setLoading(false);
  };

  const handleExecute = async (task: Task) => {
    const linkedAccount = userProfile?.social_accounts?.[task.platform];
    
    if (!linkedAccount || linkedAccount.trim() === '') {
        toast.error(`يجب ربط حساب ${PLATFORMS[task.platform].label} أولاً من صفحة البروفايل`);
        return;
    }

    setProcessingId(task.id);
    
    let urlToOpen = task.url;
    if (task.platform === 'telegram') {
        const usernameMatch = task.url.match(/(?:t\.me|telegram\.me|telegram\.dog)\/([^/?\s]+)/);
        if (usernameMatch && usernameMatch[1]) {
            urlToOpen = `tg://resolve?domain=${usernameMatch[1]}`;
        }
    }

    window.open(urlToOpen, '_blank');

    // تحديد وقت الانتظار بناءً على نوع المهمة
    let waitTime = 15000; // الافتراضي 15 ثانية للتفاعل
    if (task.action_type === 'view_30') waitTime = 30000;
    if (task.action_type === 'view_300') waitTime = 300000; // 5 دقائق

    const toastId = toast.loading(
        `جاري التحقق... يرجى الانتظار ${waitTime / 1000} ثانية`
    );

    setTimeout(async () => {
        try {
            const { data, error } = await supabase.rpc('claim_task_reward', { p_task_id: task.id });
            
            toast.dismiss(toastId);
            setProcessingId(null);

            if (error) {
                toast.error(`خطأ: ${error.message}`);
            } else if (data && data.success) {
                toast.success(`تمت المهمة! +${data.points} نقطة`);
                setTasks(prev => prev.filter(t => t.id !== task.id));
            } else {
                toast.error(data?.message || 'فشل التحقق من المهمة');
            }
        } catch (err: any) {
            toast.dismiss(toastId);
            setProcessingId(null);
            toast.error('حدث خطأ غير متوقع');
        }
    }, waitTime);
  };

  const filteredTasks = filter === 'all' ? tasks : tasks.filter(t => t.platform === filter);

  return (
    <div className="p-5 pb-24">
      <div className="flex justify-between items-center mb-4">
        <h1 className="text-2xl font-bold">المهام المتاحة</h1>
        {!userProfile?.social_accounts && (
            <Link to="/profile" className="text-xs text-red-500 font-bold flex items-center gap-1 bg-red-50 px-2 py-1 rounded-lg">
                <AlertTriangle size={12} />
                اربط حساباتك
            </Link>
        )}
      </div>
      
      <div className="flex gap-2 overflow-x-auto no-scrollbar mb-6 pb-2">
        <button 
            onClick={() => setFilter('all')}
            className={`px-4 py-2 rounded-full text-sm font-bold whitespace-nowrap ${filter === 'all' ? 'bg-gray-900 text-white' : 'bg-white text-gray-600 border'}`}
        >
            الكل
        </button>
        {Object.entries(PLATFORMS).map(([key, val]) => (
            <button 
                key={key}
                onClick={() => setFilter(key)}
                className={`px-4 py-2 rounded-full text-sm font-bold whitespace-nowrap flex items-center gap-2 ${filter === key ? val.color + ' text-white' : 'bg-white text-gray-600 border'}`}
            >
                {val.label}
            </button>
        ))}
      </div>

      {loading ? (
        <div className="flex justify-center py-10"><Loader2 className="animate-spin text-blue-600" /></div>
      ) : filteredTasks.length === 0 ? (
        <div className="text-center py-10 text-gray-500">
            <CheckCircle2 size={48} className="mx-auto mb-3 text-gray-300" />
            <p>لا توجد مهام متاحة حالياً</p>
        </div>
      ) : (
        <div className="space-y-3">
            {filteredTasks.map(task => {
                const PlatformIcon = Icons[PLATFORMS[task.platform].icon as keyof typeof Icons] as any;
                const actionInfo = ACTION_TYPES[task.action_type];
                
                return (
                    <div key={task.id} className="bg-white p-4 rounded-xl shadow-sm border border-gray-100 flex items-center justify-between">
                        <div className="flex items-center gap-3">
                            <div className={`w-10 h-10 rounded-full flex items-center justify-center text-white ${PLATFORMS[task.platform].color}`}>
                                <PlatformIcon size={20} />
                            </div>
                            <div>
                                <h3 className="font-bold text-sm">{actionInfo.label}</h3>
                                <div className="flex items-center gap-2 text-xs text-gray-500">
                                    <span>{PLATFORMS[task.platform].label}</span>
                                    {task.action_type.includes('view') && (
                                        <span className="flex items-center gap-1 bg-gray-100 px-1 rounded">
                                            <Clock size={10} />
                                            {task.action_type === 'view_30' ? '30ث' : '5د'}
                                        </span>
                                    )}
                                </div>
                            </div>
                        </div>
                        
                        <button 
                            onClick={() => handleExecute(task)}
                            disabled={processingId !== null}
                            className="bg-blue-50 text-blue-600 px-4 py-2 rounded-lg font-bold text-sm flex items-center gap-2 hover:bg-blue-100 disabled:opacity-50"
                        >
                            {processingId === task.id ? <Loader2 size={16} className="animate-spin" /> : `+${task.reward_per_action} نقطة`}
                        </button>
                    </div>
                );
            })}
        </div>
      )}
    </div>
  );
}
