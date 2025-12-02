import { useState, useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { supabase } from '../lib/supabase';
import { PLATFORMS, ACTION_TYPES, PLATFORM_ACTIONS, getTaskRates, Platform, ActionType } from '../types';
import toast from 'react-hot-toast';
import { useNavigate } from 'react-router-dom';
import { Loader2, Info, Coins, AlertCircle } from 'lucide-react';

export default function CreateTask() {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(false);
  const [userPoints, setUserPoints] = useState(0);
  
  const { register, handleSubmit, watch, setValue, reset } = useForm({
    defaultValues: {
        platform: 'youtube' as Platform,
        action_type: 'subscribe' as ActionType,
        url: '',
        quantity: 10
    }
  });
  
  const selectedPlatform = watch('platform');
  const selectedType = watch('action_type');
  const quantity = watch('quantity');

  // تحديث نوع التفاعل الافتراضي عند تغيير المنصة
  useEffect(() => {
    const availableActions = PLATFORM_ACTIONS[selectedPlatform];
    if (availableActions && availableActions.length > 0) {
        setValue('action_type', availableActions[0]);
    }
  }, [selectedPlatform, setValue]);

  // جلب رصيد المستخدم
  useEffect(() => {
    const fetchPoints = async () => {
        const { data: { user } } = await supabase.auth.getUser();
        if (user) {
            const { data } = await supabase.from('profiles').select('points').eq('id', user.id).single();
            if (data) setUserPoints(data.points);
        }
    };
    fetchPoints();
  }, []);

  const rates = (selectedPlatform && selectedType) ? getTaskRates(selectedPlatform, selectedType) : null;
  const totalCost = rates ? rates.cost * quantity : 0;
  const canAfford = userPoints >= totalCost;

  const onSubmit = async (data: any) => {
    if (!canAfford) {
        toast.error('رصيدك لا يكفي لإتمام هذه العملية');
        return;
    }

    setLoading(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('يجب تسجيل الدخول');

      // التحقق من رابط تيليجرام
      if (data.platform === 'telegram' && !data.url.toLowerCase().includes('t.me')) {
        toast.error('يرجى إدخال رابط تيليجرام صحيح (t.me/...)');
        setLoading(false);
        return;
      }

      const rates = getTaskRates(data.platform, data.action_type);

      const { error } = await supabase.from('tasks').insert({
        user_id: user.id,
        platform: data.platform,
        action_type: data.action_type,
        url: data.url,
        cost_per_action: rates.cost,
        reward_per_action: rates.reward,
        target_quantity: data.quantity,
        current_quantity: 0,
        status: 'active'
      });

      if (error) throw error;
      toast.success('تم إضافة المهمة بنجاح');
      navigate('/dashboard');
    } catch (error: any) {
      toast.error(error.message || 'حدث خطأ');
    } finally {
      setLoading(false);
    }
  };

  // قائمة الإجراءات المتاحة للمنصة المختارة
  const availableActions = PLATFORM_ACTIONS[selectedPlatform] || [];

  return (
    <div className="p-5 pb-24">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-2xl font-bold">إضافة مهمة جديدة</h1>
        <div className="bg-yellow-100 text-yellow-800 px-3 py-1 rounded-full font-bold text-sm flex items-center gap-1">
            <Coins size={16} />
            {userPoints}
        </div>
      </div>
      
      <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
        
        {/* Platform Select */}
        <div>
            <label className="block text-sm font-bold mb-2 text-gray-700">اختر المنصة</label>
            <div className="grid grid-cols-3 gap-3">
                {Object.entries(PLATFORMS).map(([key, val]) => (
                    <label key={key} className={`cursor-pointer border rounded-xl p-3 flex flex-col items-center gap-2 transition-all ${selectedPlatform === key ? 'border-blue-500 bg-blue-50 text-blue-600 ring-1 ring-blue-500' : 'border-gray-200 hover:bg-gray-50'}`}>
                        <input type="radio" value={key} {...register('platform')} className="hidden" />
                        <span className="text-sm font-bold">{val.label}</span>
                    </label>
                ))}
            </div>
        </div>

        {/* Action Type Select */}
        <div className="bg-white p-4 rounded-xl border border-gray-200 shadow-sm">
            <label className="block text-sm font-bold mb-3 text-gray-700">نوع التفاعل المطلوب</label>
            <div className="grid grid-cols-2 gap-2">
                {availableActions.map((actionKey) => {
                    const action = ACTION_TYPES[actionKey];
                    return (
                        <label key={actionKey} className={`cursor-pointer border rounded-lg p-3 flex items-center justify-between transition-all ${selectedType === actionKey ? 'border-green-500 bg-green-50 text-green-700 ring-1 ring-green-500' : 'border-gray-200'}`}>
                            <div className="flex items-center gap-2">
                                <input type="radio" value={actionKey} {...register('action_type')} className="hidden" />
                                <span className="font-bold text-sm">{action.label}</span>
                            </div>
                            <span className="text-xs bg-white px-2 py-1 rounded border shadow-sm">{action.cost} نقطة</span>
                        </label>
                    );
                })}
            </div>
        </div>

        {/* URL Input */}
        <div>
            <label className="block text-sm font-bold mb-2 text-gray-700">رابط المهمة</label>
            <input 
                {...register('url', { required: true })}
                type="url" 
                placeholder={PLATFORMS[selectedPlatform].placeholder} 
                className="w-full p-3 rounded-xl border border-gray-300 focus:ring-2 focus:ring-blue-500 outline-none transition-all"
            />
            {selectedPlatform === 'telegram' && (
                <div className="flex items-center gap-2 mt-2 text-xs text-blue-600 bg-blue-50 p-2 rounded-lg">
                    <Info size={14} />
                    <span>تأكد من استخدام رابط يبدأ بـ https://t.me</span>
                </div>
            )}
        </div>

        {/* Quantity Input */}
        <div>
            <label className="block text-sm font-bold mb-2 text-gray-700">العدد المطلوب (كم شخص؟)</label>
            <div className="flex items-center gap-3">
                <input 
                    {...register('quantity', { required: true, min: 1 })}
                    type="number" 
                    min="1"
                    className="w-full p-3 rounded-xl border border-gray-300 focus:ring-2 focus:ring-blue-500 outline-none text-center font-bold text-lg"
                />
                <span className="text-gray-500 font-bold text-sm whitespace-nowrap">شخص</span>
            </div>
        </div>

        {/* Cost Summary */}
        {rates && (
            <div className={`p-4 rounded-xl border ${canAfford ? 'bg-gray-50 border-gray-200' : 'bg-red-50 border-red-200'}`}>
                <div className="flex justify-between items-center mb-2 text-sm">
                    <span className="text-gray-600">سعر التفاعل الواحد:</span>
                    <span className="font-bold">{rates.cost} نقطة</span>
                </div>
                <div className="flex justify-between items-center mb-2 text-sm">
                    <span className="text-gray-600">العدد المطلوب:</span>
                    <span className="font-bold">{quantity}</span>
                </div>
                <div className="border-t border-gray-200 my-2"></div>
                <div className="flex justify-between items-center">
                    <span className="font-bold text-gray-800">التكلفة الإجمالية:</span>
                    <span className={`font-bold text-xl ${canAfford ? 'text-blue-600' : 'text-red-600'}`}>
                        {totalCost} نقطة
                    </span>
                </div>
                
                {!canAfford && (
                    <div className="mt-3 flex items-center gap-2 text-red-600 text-sm font-bold bg-red-100 p-2 rounded-lg justify-center">
                        <AlertCircle size={16} />
                        <span>رصيدك لا يكفي! (لديك {userPoints} نقطة)</span>
                    </div>
                )}
            </div>
        )}

        <button 
            type="submit" 
            disabled={loading || !canAfford || !rates}
            className="w-full bg-blue-600 text-white py-4 rounded-xl font-bold hover:bg-blue-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center shadow-lg shadow-blue-200"
        >
            {loading ? <Loader2 className="animate-spin" /> : 'نشر المهمة وخصم النقاط لاحقاً'}
        </button>
        <p className="text-center text-xs text-gray-400 mt-2">سيتم خصم النقاط تدريجياً عند تنفيذ كل شخص للمهمة</p>

      </form>
    </div>
  );
}
