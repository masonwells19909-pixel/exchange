import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { UserProfile, PLATFORMS, Platform } from '../types';
import { LogOut, User as UserIcon, Shield, FileText, List, Lock, Save, Link as LinkIcon } from 'lucide-react';
import { useNavigate, Link } from 'react-router-dom';
import toast from 'react-hot-toast';
import * as Icons from 'lucide-react';

export default function Profile() {
  const navigate = useNavigate();
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [socialInputs, setSocialInputs] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);
  const [showSocialSettings, setShowSocialSettings] = useState(false);

  useEffect(() => {
    getProfile();
  }, []);

  const getProfile = async () => {
    const { data: { user } } = await supabase.auth.getUser();
    if (user) {
      const { data } = await supabase.from('profiles').select('*').eq('id', user.id).single();
      setProfile(data);
      if (data?.social_accounts) {
        setSocialInputs(data.social_accounts);
      }
    }
  };

  const handleSaveSocials = async () => {
    setSaving(true);
    try {
        const { data: { user } } = await supabase.auth.getUser();
        if (!user) throw new Error('يجب تسجيل الدخول أولاً');

        const { error } = await supabase.from('profiles').update({
            social_accounts: socialInputs
        }).eq('id', user.id);

        if (error) throw error;
        
        toast.success('تم حفظ الحسابات بنجاح');
        setShowSocialSettings(false);
        // Update local state
        if (profile) setProfile({ ...profile, social_accounts: socialInputs as any });

    } catch (error: any) {
        console.error('Save error:', error);
        toast.error(error.message || 'حدث خطأ أثناء الحفظ');
    } finally {
        setSaving(false);
    }
  };

  const handleLogout = async () => {
    await supabase.auth.signOut();
    navigate('/login');
    toast.success('تم تسجيل الخروج');
  };

  return (
    <div className="p-5 pb-24">
      <div className="flex flex-col items-center mb-8 pt-8">
        <div className="w-24 h-24 bg-gray-200 rounded-full flex items-center justify-center mb-4 text-gray-400">
            <UserIcon size={48} />
        </div>
        <h2 className="text-xl font-bold">{profile?.email}</h2>
        <div className="mt-2 bg-blue-100 text-blue-800 px-4 py-1 rounded-full font-bold text-sm">
            {profile?.points || 0} نقطة
        </div>
      </div>

      <div className="space-y-3">
        {/* Admin Button */}
        {profile?.role === 'admin' && (
            <Link to="/admin" className="bg-gray-900 text-white p-4 rounded-xl border border-gray-800 flex items-center gap-3 hover:bg-gray-800 transition-colors shadow-md">
                <Lock size={20} className="text-yellow-400" />
                <span className="flex-1 font-bold">لوحة التحكم (Admin)</span>
            </Link>
        )}

        {/* Social Accounts Section */}
        <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
            <button 
                onClick={() => setShowSocialSettings(!showSocialSettings)}
                className="w-full p-4 flex items-center gap-3 hover:bg-gray-50 transition-colors text-left"
            >
                <LinkIcon size={20} className="text-purple-600" />
                <div className="flex-1">
                    <span className="font-bold text-gray-800 block">ربط الحسابات</span>
                    <span className="text-xs text-gray-500">مطلوب لتنفيذ المهام</span>
                </div>
            </button>

            {showSocialSettings && (
                <div className="p-4 bg-gray-50 border-t border-gray-100 space-y-3">
                    <p className="text-xs text-red-500 mb-2 font-bold">
                        * يجب إضافة حسابك في المنصة قبل البدء بتنفيذ المهام الخاصة بها.
                    </p>
                    {Object.entries(PLATFORMS).map(([key, val]) => {
                         const PlatformIcon = Icons[val.icon as keyof typeof Icons] as any;
                         return (
                            <div key={key}>
                                <label className="flex items-center gap-2 text-sm font-bold text-gray-700 mb-1">
                                    <PlatformIcon size={14} /> {val.label}
                                </label>
                                <input 
                                    type="text" 
                                    placeholder={val.placeholder}
                                    value={socialInputs[key] || ''}
                                    onChange={(e) => setSocialInputs({...socialInputs, [key]: e.target.value})}
                                    className="w-full p-2 rounded-lg border border-gray-300 text-sm focus:ring-2 focus:ring-blue-500 outline-none"
                                />
                            </div>
                         );
                    })}
                    <button 
                        onClick={handleSaveSocials}
                        disabled={saving}
                        className="w-full bg-blue-600 text-white py-2 rounded-lg font-bold text-sm mt-2 flex items-center justify-center gap-2"
                    >
                        {saving ? 'جاري الحفظ...' : <><Save size={16} /> حفظ التغييرات</>}
                    </button>
                </div>
            )}
        </div>

        <Link to="/my-tasks" className="bg-white p-4 rounded-xl border border-gray-100 flex items-center gap-3 hover:bg-gray-50 transition-colors">
            <List size={20} className="text-blue-600" />
            <span className="flex-1 font-bold text-gray-800">مهامي</span>
        </Link>

        <Link to="/privacy" className="bg-white p-4 rounded-xl border border-gray-100 flex items-center gap-3 hover:bg-gray-50 transition-colors">
            <Shield size={20} className="text-gray-500" />
            <span className="flex-1">سياسة الخصوصية</span>
        </Link>

        <Link to="/terms" className="bg-white p-4 rounded-xl border border-gray-100 flex items-center gap-3 hover:bg-gray-50 transition-colors">
            <FileText size={20} className="text-gray-500" />
            <span className="flex-1">الشروط والأحكام</span>
        </Link>
        
        <button 
            onClick={handleLogout}
            className="w-full bg-red-50 text-red-600 p-4 rounded-xl border border-red-100 flex items-center gap-3 mt-6 hover:bg-red-100 transition-colors"
        >
            <LogOut size={20} />
            <span className="flex-1 text-right font-bold">تسجيل الخروج</span>
        </button>
      </div>
    </div>
  );
}
