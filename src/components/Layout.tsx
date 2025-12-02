import { Outlet, useLocation } from 'react-router-dom';
import BottomNav from './BottomNav';
import { Toaster } from 'react-hot-toast';

export default function Layout() {
  const location = useLocation();
  // Hide nav on auth pages and splash
  const hideNav = ['/', '/login', '/register'].includes(location.pathname);

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col max-w-md mx-auto shadow-2xl overflow-hidden relative">
      <main className="flex-1 overflow-y-auto no-scrollbar pb-20">
        <Outlet />
      </main>
      {!hideNav && <BottomNav />}
      <Toaster position="top-center" toastOptions={{ duration: 3000, style: { fontFamily: 'Cairo' } }} />
    </div>
  );
}
