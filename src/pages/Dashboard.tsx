import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { UserProfile } from '../types';
import { Coins, TrendingUp, Users, Activity } from 'lucide-react';
import { Link } from 'react-router-dom';

export default function Dashboard() {
  const [profile, setProfile] = useState<UserProfile | null>(null);

  useEffect(() => {
    getProfile();
  }, []);

  const getProfile = async () => {
    const { data: { user } } = await supabase.auth.getUser();
    if (user) {
      const { data } = await supabase.from('profiles').select('*').eq('id', user.id).single();
      setProfile(data);
    }
  };

  return (
    <div className="p-5 space-y-6">
      {/* Header */}
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">مرحباً بك 👋</h1>
          <p className="text-gray-500 text-sm">جاهز لزيادة تفاعلاتك؟</p>
        </div>
        <div className="bg-yellow-100 text-yellow-800 px-4 py-2 rounded-full font-bold flex items-center gap-2 border border-yellow-200">
          <Coins size={20} className="text-yellow-600" />
          <span>{profile?.points || 0}</span>
        </div>
      </div>

      {/* Quick Stats */}
      <div className="grid grid-cols-2 gap-4">
        <Link to="/tasks" className="bg-blue-600 text-white p-4 rounded-2xl shadow-lg shadow-blue-200 active:scale-95 transition-transform">
          <div className="bg-white/20 w-10 h-10 rounded-full flex items-center justify-center mb-3">
            <TrendingUp size={20} />
          </div>
          <h3 className="font-bold text-lg">تجميع النقاط</h3>
          <p className="text-blue-100 text-sm">نفذ مهام واربح</p>
        </Link>
        <Link to="/create" className="bg-purple-600 text-white p-4 rounded-2xl shadow-lg shadow-purple-200 active:scale-95 transition-transform">
          <div className="bg-white/20 w-10 h-10 rounded-full flex items-center justify-center mb-3">
            <Users size={20} />
          </div>
          <h3 className="font-bold text-lg">إضافة رابط</h3>
          <p className="text-purple-100 text-sm">زد متابعينك الآن</p>
        </Link>
      </div>

      {/* Ad Banner */}
      <div className="bg-gradient-to-r from-orange-400 to-pink-500 rounded-2xl p-5 text-white relative overflow-hidden">
        <div className="relative z-10">
          <h3 className="font-bold text-xl mb-1">شاهد واربح!</h3>
          <p className="text-white/90 text-sm mb-3">احصل على نقاط مجانية بمشاهدة الإعلانات</p>
          <Link to="/ads" className="bg-white text-orange-500 px-4 py-2 rounded-lg text-sm font-bold inline-block">
            شاهد الآن
          </Link>
        </div>
        <Activity className="absolute -bottom-4 -left-4 text-white/20 w-32 h-32 rotate-12" />
      </div>

      {/* Recent Activity Placeholder */}
      <div>
        <h2 className="font-bold text-lg mb-3">آخر النشاطات</h2>
        <div className="bg-white rounded-xl p-4 shadow-sm border border-gray-100 text-center text-gray-500 py-8">
          لا توجد نشاطات حديثة
        </div>
      </div>
    </div>
  );
}
