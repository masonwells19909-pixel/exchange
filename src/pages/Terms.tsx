import { ArrowRight } from 'lucide-react';
import { Link } from 'react-router-dom';

export default function Terms() {
  return (
    <div className="p-5 pb-24 bg-white min-h-screen">
      <div className="flex items-center gap-3 mb-6">
        <Link to="/profile" className="p-2 bg-gray-100 rounded-full hover:bg-gray-200">
            <ArrowRight size={20} />
        </Link>
        <h1 className="text-2xl font-bold">الشروط والأحكام</h1>
      </div>

      <div className="prose prose-sm rtl:text-right text-gray-600 space-y-4">
        <section>
          <h2 className="text-lg font-bold text-gray-900 mb-2">1. القبول بالشروط</h2>
          <p>باستخدامك لتطبيق "تبادل"، فإنك توافق على الالتزام بهذه الشروط والأحكام. إذا كنت لا توافق عليها، يرجى عدم استخدام التطبيق.</p>
        </section>

        <section>
          <h2 className="text-lg font-bold text-gray-900 mb-2">2. سياسة الاستخدام العادل (مكافحة الغش)</h2>
          <ul className="list-disc list-inside space-y-1">
            <li>يمنع استخدام برامج الروبوت (Bots) أو السكربتات لتنفيذ المهام.</li>
            <li>يمنع إنشاء حسابات متعددة لنفس الشخص لغرض جمع النقاط.</li>
            <li>يمنع إلغاء الاشتراك أو الإعجاب بعد الحصول على النقاط. سيتم حظر الحسابات المخالفة.</li>
            <li>يجب أن تكون الروابط المضافة متوافقة مع سياسات المنصات المعنية (يوتيوب، فيسبوك، إلخ).</li>
          </ul>
        </section>

        <section>
          <h2 className="text-lg font-bold text-gray-900 mb-2">3. النقاط والمكافآت</h2>
          <p>النقاط داخل التطبيق ليس لها قيمة نقدية ولا يمكن استبدالها بمال حقيقي. تستخدم فقط لتبادل التفاعلات داخل المنصة.</p>
        </section>

        <section>
          <h2 className="text-lg font-bold text-gray-900 mb-2">4. إخلاء المسؤولية</h2>
          <p>التطبيق غير مسؤول عن أي إجراءات تتخذها منصات التواصل الاجتماعي ضد حساباتك نتيجة لاستخدامك لخدمات التبادل.</p>
        </section>
      </div>
    </div>
  );
}
