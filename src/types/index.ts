export type Platform = 'youtube' | 'telegram' | 'facebook' | 'tiktok' | 'instagram';
export type ActionType = 'subscribe' | 'like' | 'comment' | 'view_30' | 'view_300' | 'follow' | 'share' | 'join';

export interface UserProfile {
  id: string;
  email: string;
  points: number;
  role?: 'user' | 'admin';
  social_accounts?: Record<Platform, string>;
}

export interface Task {
  id: string;
  user_id: string;
  platform: Platform;
  action_type: ActionType;
  url: string;
  cost_per_action: number;
  reward_per_action: number;
  target_quantity: number;
  current_quantity: number;
  status: 'active' | 'paused' | 'stopped' | 'finished';
  created_at: string;
}

export const PLATFORMS: Record<Platform, { label: string; color: string; icon: string; placeholder: string }> = {
  youtube: { label: 'يوتيوب', color: 'bg-red-600', icon: 'Youtube', placeholder: 'رابط الفيديو أو القناة' },
  telegram: { label: 'تيليجرام', color: 'bg-blue-500', icon: 'Send', placeholder: 'رابط القناة (t.me/...)' },
  facebook: { label: 'فيسبوك', color: 'bg-blue-700', icon: 'Facebook', placeholder: 'رابط الصفحة أو المنشور' },
  tiktok: { label: 'تيك توك', color: 'bg-black', icon: 'Music2', placeholder: 'رابط الفيديو أو الحساب' },
  instagram: { label: 'إنستغرام', color: 'bg-pink-600', icon: 'Instagram', placeholder: 'رابط المنشور أو الحساب' },
};

// تحديد الإجراءات المتاحة لكل منصة بدقة حسب الطلب
export const PLATFORM_ACTIONS: Record<Platform, ActionType[]> = {
    youtube: ['subscribe', 'like', 'comment', 'view_30', 'view_300'],
    telegram: ['join'],
    tiktok: ['follow', 'like', 'comment'],
    facebook: ['follow', 'like', 'comment'],
    instagram: ['follow', 'like', 'comment']
};

// تحديد الأسعار والمكافآت
// التكلفة (cost) هي ما يدفعه صاحب المهمة
// المكافأة (reward) هي ما يحصل عليه المنفذ
// الفرق يذهب للمنصة كعمولة لضمان استمرار النظام
export const ACTION_TYPES: Record<ActionType, { label: string; cost: number; reward: number }> = {
  subscribe: { label: 'اشتراك', cost: 5, reward: 3 },
  follow: { label: 'متابعة', cost: 5, reward: 3 },
  join: { label: 'انضمام', cost: 5, reward: 3 },
  like: { label: 'لايك', cost: 2, reward: 1 },
  comment: { label: 'تعليق', cost: 3, reward: 2 },
  share: { label: 'مشاركة', cost: 2, reward: 2 },
  
  // الأسعار المحددة للمشاهدات
  view_30: { label: 'مشاهدة 30 ثانية', cost: 2, reward: 1 }, // التكلفة 2، المكافأة 1
  view_300: { label: 'مشاهدة 5 دقائق', cost: 12, reward: 10 }, // التكلفة 12، المكافأة 10
};

export const getTaskRates = (platform: Platform, type: ActionType) => {
    return ACTION_TYPES[type];
};
