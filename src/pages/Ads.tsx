import { useState, useRef, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { Play, Clock, AlertCircle, X, ExternalLink } from 'lucide-react';
import toast from 'react-hot-toast';

const AD_LINKS = [
  "https://otieu.com/4/8179287",
  "https://otieu.com/4/8464568",
  "https://otieu.com/4/9038914",
  "https://otieu.com/4/8179107"
];

export default function Ads() {
  const [watching, setWatching] = useState(false);
  const [timeLeft, setTimeLeft] = useState(30);
  const [currentAdUrl, setCurrentAdUrl] = useState('');
  const [canWatch, setCanWatch] = useState(true);
  
  // استخدام مراجع للحفاظ على القيم داخل العداد
  const timerIntervalRef = useRef<number | null>(null);
  const startTimeRef = useRef<number>(0);

  // تنظيف العداد عند الخروج من الصفحة
  useEffect(() => {
    return () => {
      if (timerIntervalRef.current) clearInterval(timerIntervalRef.current);
    };
  }, []);

  const startAd = (url: string) => {
    if (!canWatch) {
        toast.error('يرجى الانتظار قليلاً قبل مشاهدة إعلان آخر');
        return;
    }
    
    setCurrentAdUrl(url);
    setWatching(true);
    setTimeLeft(30);
    startTimeRef.current = Date.now();
    
    // بدء العداد
    if (timerIntervalRef.current) clearInterval(timerIntervalRef.current);
    
    timerIntervalRef.current = window.setInterval(() => {
      const elapsedSeconds = Math.floor((Date.now() - startTimeRef.current) / 1000);
      const remaining = 30 - elapsedSeconds;
      
      if (remaining <= 0) {
        finishAd();
      } else {
        setTimeLeft(remaining);
      }
    }, 1000);
  };

  const finishAd = async () => {
    // إيقاف العداد
    if (timerIntervalRef.current) {
        clearInterval(timerIntervalRef.current);
        timerIntervalRef.current = null;
    }

    setWatching(false); // إغلاق النافذة تلقائياً

    const toastId = toast.loading('جاري التحقق من المكافأة...');

    try {
        const { data, error } = await supabase.rpc('claim_ad_reward');
        
        toast.dismiss(toastId);

        if (error) {
            console.error(error);
            toast.error('حدث خطأ في الاتصال');
        } else if (data && data.success) {
            toast.success('🎉 مبروك! تم إضافة 2 نقطة');
            setCanWatch(false);
            // فترة انتظار بسيطة لمنع التكرار السريع جداً
            setTimeout(() => setCanWatch(true), 5000);
        } else {
            toast.error(data?.message || 'فشل احتساب النقاط');
        }
    } catch (err) {
        toast.dismiss(toastId);
        toast.error('حدث خطأ غير متوقع');
    }
  };

  const cancelAd = () => {
    if (confirm('هل أنت متأكد؟ ستفقد المكافأة إذا أغلقت الإعلان الآن.')) {
        if (timerIntervalRef.current) clearInterval(timerIntervalRef.current);
        setWatching(false);
        toast('تم إلغاء المشاهدة', { icon: '⚠️' });
    }
  };

  return (
    <div className="p-5 pb-24">
      <h1 className="text-2xl font-bold mb-6">اربح من الإعلانات</h1>

      {watching && (
        <div className="fixed inset-0 z-50 bg-black flex flex-col">
            {/* شريط علوي للعداد */}
            <div className="bg-gray-900 text-white p-4 flex justify-between items-center shadow-lg z-50 safe-area-top">
                <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-full border-2 border-blue-500 flex items-center justify-center font-bold text-lg bg-gray-800">
                        {timeLeft}
                    </div>
                    <div className="text-sm">
                        <p className="font-bold text-blue-400">جاري المشاهدة...</p>
                        <p className="text-gray-400 text-xs">لا تغلق الصفحة</p>
                    </div>
                </div>
                <button 
                    onClick={cancelAd}
                    className="bg-red-500/20 text-red-400 p-2 rounded-full hover:bg-red-500/30 transition-colors"
                >
                    <X size={24} />
                </button>
            </div>

            {/* منطقة الإعلان */}
            <div className="flex-1 relative bg-white w-full h-full">
                <iframe 
                    src={currentAdUrl} 
                    className="w-full h-full border-0"
                    sandbox="allow-scripts allow-same-origin allow-forms allow-popups"
                    title="Advertisement"
                />
                
                {/* زر احتياطي في حالة لم يظهر الإعلان */}
                <div className="absolute bottom-10 left-0 right-0 flex justify-center pointer-events-none">
                    <div className="bg-black/70 text-white px-4 py-2 rounded-full text-xs backdrop-blur-sm pointer-events-auto">
                        إذا لم يظهر الإعلان، <a href={currentAdUrl} target="_blank" rel="noreferrer" className="underline text-blue-300">اضغط هنا</a> لفتحه في نافذة جديدة
                    </div>
                </div>
            </div>
        </div>
      )}

      <div className="grid gap-4">
        <div className="bg-blue-50 p-4 rounded-xl border border-blue-100 flex items-start gap-3">
            <AlertCircle className="text-blue-600 shrink-0" />
            <p className="text-sm text-blue-800">شاهد الإعلان لمدة 30 ثانية كاملة داخل التطبيق لتحصل على المكافأة. سيغلق الإعلان تلقائياً عند الانتهاء.</p>
        </div>

        {AD_LINKS.map((link, idx) => (
            <button
                key={idx}
                onClick={() => startAd(link)}
                disabled={!canWatch}
                className="bg-white p-4 rounded-xl shadow-sm border border-gray-100 flex items-center justify-between hover:bg-gray-50 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
                <div className="flex items-center gap-3">
                    <div className="bg-green-100 text-green-600 w-10 h-10 rounded-full flex items-center justify-center">
                        <Play size={20} fill="currentColor" />
                    </div>
                    <div className="text-right">
                        <h3 className="font-bold">إعلان ممول #{idx + 1}</h3>
                        <p className="text-xs text-gray-500 flex items-center gap-1">
                            <Clock size={12} /> 30 ثانية = 2 نقطة
                        </p>
                    </div>
                </div>
                <div className="bg-gray-100 px-3 py-1 rounded-lg text-sm font-bold text-gray-600">
                    مشاهدة
                </div>
            </button>
        ))}
      </div>
    </div>
  );
}
