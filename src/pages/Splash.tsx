import { useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { motion } from 'framer-motion';
import { RefreshCw } from 'lucide-react';
import { supabase } from '../lib/supabase';

export default function Splash() {
  const navigate = useNavigate();

  useEffect(() => {
    const checkSession = async () => {
      const { data: { session } } = await supabase.auth.getSession();
      setTimeout(() => {
        if (session) {
          navigate('/dashboard');
        } else {
          navigate('/login');
        }
      }, 2000);
    };
    checkSession();
  }, [navigate]);

  return (
    <div className="h-screen flex flex-col items-center justify-center bg-gradient-to-br from-blue-600 to-purple-700 text-white">
      <motion.div
        initial={{ scale: 0.5, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ duration: 0.5 }}
        className="flex flex-col items-center"
      >
        <div className="bg-white/20 p-6 rounded-3xl backdrop-blur-sm mb-4">
            <RefreshCw size={64} className="animate-spin-slow" />
        </div>
        <h1 className="text-4xl font-bold mb-2">تبادل</h1>
        <p className="text-blue-100 text-lg">منصة التفاعل الاجتماعي</p>
      </motion.div>
      
      <div className="absolute bottom-10 text-sm text-blue-200">
        جاري التحميل...
      </div>
    </div>
  );
}
