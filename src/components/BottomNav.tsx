import { Home, PlusCircle, User, ListTodo, DollarSign } from 'lucide-react';
import { Link, useLocation } from 'react-router-dom';
import { clsx } from 'clsx';

export default function BottomNav() {
  const location = useLocation();
  
  const navItems = [
    { path: '/dashboard', icon: Home, label: 'الرئيسية' },
    { path: '/tasks', icon: ListTodo, label: 'المهام' },
    { path: '/create', icon: PlusCircle, label: 'إضافة', highlight: true },
    { path: '/ads', icon: DollarSign, label: 'اربح' },
    { path: '/profile', icon: User, label: 'حسابي' },
  ];

  return (
    <div className="fixed bottom-0 left-0 right-0 bg-white border-t border-gray-200 pb-safe safe-area-bottom z-50">
      <div className="flex justify-around items-center h-16 px-2">
        {navItems.map((item) => {
          const isActive = location.pathname === item.path;
          return (
            <Link
              key={item.path}
              to={item.path}
              className={clsx(
                "flex flex-col items-center justify-center w-full h-full transition-colors",
                isActive ? "text-blue-600" : "text-gray-500 hover:text-gray-700"
              )}
            >
              {item.highlight ? (
                <div className="bg-blue-600 text-white p-3 rounded-full -mt-6 shadow-lg border-4 border-gray-50">
                  <item.icon size={24} />
                </div>
              ) : (
                <item.icon size={24} strokeWidth={isActive ? 2.5 : 2} />
              )}
              <span className={clsx("text-xs mt-1", item.highlight && "font-bold text-blue-600")}>
                {item.label}
              </span>
            </Link>
          );
        })}
      </div>
    </div>
  );
}
