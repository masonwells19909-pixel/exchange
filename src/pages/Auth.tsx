import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { supabase } from '../lib/supabase';
import { useNavigate, Link } from 'react-router-dom';
import toast from 'react-hot-toast';
import { Loader2, Mail, Lock } from 'lucide-react';

const schema = z.object({
  email: z.string().email('البريد الإلكتروني غير صحيح'),
  password: z.string().min(6, 'كلمة المرور يجب أن تكون 6 أحرف على الأقل'),
});

type FormData = z.infer<typeof schema>;

export default function Auth({ type }: { type: 'login' | 'register' }) {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(false);
  const { register, handleSubmit, formState: { errors } } = useForm<FormData>({
    resolver: zodResolver(schema),
  });

  const onSubmit = async (data: FormData) => {
    setLoading(true);
    try {
      if (type === 'register') {
        const { error } = await supabase.auth.signUp({
          email: data.email,
          password: data.password,
        });
        if (error) throw error;
        toast.success('تم إنشاء الحساب بنجاح! قم بتسجيل الدخول.');
        navigate('/login');
      } else {
        const { error } = await supabase.auth.signInWithPassword({
          email: data.email,
          password: data.password,
        });
        if (error) throw error;
        toast.success('تم تسجيل الدخول بنجاح');
        navigate('/dashboard');
      }
    } catch (error: any) {
      toast.error(error.message || 'حدث خطأ ما');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex flex-col justify-center px-6 bg-white">
      <div className="mb-8 text-center">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">
          {type === 'login' ? 'تسجيل الدخول' : 'إنشاء حساب جديد'}
        </h1>
        <p className="text-gray-500">
          {type === 'login' ? 'مرحباً بعودتك! أدخل بياناتك للمتابعة' : 'انضم إلينا وابدأ في زيادة تفاعلاتك'}
        </p>
      </div>

      <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">البريد الإلكتروني</label>
          <div className="relative">
            <Mail className="absolute right-3 top-3 text-gray-400" size={20} />
            <input
              {...register('email')}
              type="email"
              className="w-full pr-10 pl-4 py-2.5 rounded-xl border border-gray-300 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-all"
              placeholder="name@example.com"
            />
          </div>
          {errors.email && <p className="text-red-500 text-xs mt-1">{errors.email.message}</p>}
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">كلمة المرور</label>
          <div className="relative">
            <Lock className="absolute right-3 top-3 text-gray-400" size={20} />
            <input
              {...register('password')}
              type="password"
              className="w-full pr-10 pl-4 py-2.5 rounded-xl border border-gray-300 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-all"
              placeholder="••••••••"
            />
          </div>
          {errors.password && <p className="text-red-500 text-xs mt-1">{errors.password.message}</p>}
        </div>

        {type === 'login' && (
          <div className="flex justify-end">
            <button type="button" className="text-sm text-blue-600 hover:underline">
              هل نسيت كلمة السر؟
            </button>
          </div>
        )}

        <button
          type="submit"
          disabled={loading}
          className="w-full bg-blue-600 text-white py-3 rounded-xl font-bold hover:bg-blue-700 transition-colors flex items-center justify-center disabled:opacity-70"
        >
          {loading ? <Loader2 className="animate-spin" /> : (type === 'login' ? 'دخول' : 'تسجيل')}
        </button>
      </form>

      <div className="mt-6 text-center text-sm text-gray-600">
        {type === 'login' ? (
          <>
            ليس لديك حساب؟{' '}
            <Link to="/register" className="text-blue-600 font-bold hover:underline">
              أنشئ حساب الآن
            </Link>
          </>
        ) : (
          <>
            لديك حساب بالفعل؟{' '}
            <Link to="/login" className="text-blue-600 font-bold hover:underline">
              سجل دخول
            </Link>
          </>
        )}
      </div>
    </div>
  );
}
