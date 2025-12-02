import { ArrowRight } from 'lucide-react';
import { Link } from 'react-router-dom';

export default function Privacy() {
  return (
    <div className="p-5 pb-24 bg-white min-h-screen">
      <div className="flex items-center gap-3 mb-6">
        <Link to="/profile" className="p-2 bg-gray-100 rounded-full hover:bg-gray-200">
            <ArrowRight size={20} />
        </Link>
        <h1 className="text-2xl font-bold">سياسة الخصوصية</h1>
      </div>

      <div className="prose prose-sm rtl:text-right text-gray-600 space-y-4">
        <section>
          <h2 className="text-lg font-bold text-gray-900 mb-2">1. جمع المعلومات</h2>
          <p>نقوم بجمع المعلومات التي تقدمها عند التسجيل (البريد الإلكتروني) والبيانات المتعلقة بنشاطك داخل التطبيق مثل المهام المنجزة والنقاط المكتسبة.</p>
        </section>

        <section>
          <h2 className="text-lg font-bold text-gray-900 mb-2">2. استخدام المعلومات</h2>
          <p>نستخدم معلوماتك لإدارة حسابك، التحقق من صحة التفاعلات، ومنع الاحتيال. لا نشارك بياناتك الشخصية مع أطراف ثالثة دون موافقتك.</p>
        </section>

        <section>
          <h2 className="text-lg font-bold text-gray-900 mb-2">3. أمان البيانات</h2>
          <p>نحن نتخذ تدابير أمنية لحماية بياناتك. يتم تشفير كلمات المرور وتأمين الاتصالات عبر بروتوكولات قياسية.</p>
        </section>

        <section>
          <h2 className="text-lg font-bold text-gray-900 mb-2">4. ملفات تعريف الارتباط (Cookies)</h2>
          <p>نستخدم ملفات تعريف الارتباط لتحسين تجربة المستخدم وحفظ جلسة تسجيل الدخول الخاصة بك.</p>
        </section>

        <section>
          <h2 className="text-lg font-bold text-gray-900 mb-2">5. حذف الحساب</h2>
          <p>يمكنك طلب حذف حسابك وجميع بياناتك المرتبطة به في أي وقت عن طريق التواصل مع الدعم الفني.</p>
        </section>
      </div>
    </div>
  );
}
