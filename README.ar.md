# Menu Monitor — مراقبة الأداء

<p><a href="README.md"><u>简体中文</u></a> · <a href="README.en.md"><u>English</u></a> · <a href="README.ar.md"><u>العربية</u></a></p>

<div align="center">
  <img src="docs/images/hero-menu-monitor.jpg" alt="Menu Monitor macOS dashboard and menu bar panel" width="100%">
</div>

> أداة macOS أصلية وخفيفة وأنيقة لمراقبة أداء النظام والحرارة والطاقة من شريط القوائم.

[![Platform](https://img.shields.io/badge/macOS-26%2B-111827)](#المتطلبات)
[![Swift](https://img.shields.io/badge/Swift-6.2-f05138)](#البنية-التقنية)
[![Offline](https://img.shields.io/badge/network-offline-2f7d55)](#الخصوصية-والتشغيل-المحلي)
[![Validation](https://img.shields.io/badge/build-GitHub%20Actions-2f7d55)](.github/workflows/validate.yml)
[![License](https://img.shields.io/badge/license-MIT-6f8fb3)](LICENSE)

يعرض Menu Monitor مؤشرات النظام المهمة داخل شريط قوائم macOS. عند الضغط على الأيقونة يمكن الاطلاع على الذاكرة والمعالج والطاقة المقدرة والحرارة والطاقة اللازمة للشحن، مع اتجاهات آخر 60 ثانية، دون فتح نافذة مراقبة كبيرة أو إضافة أيقونة دائمة أخرى إلى Dock.

## حالة جهاز Mac في لمحة

| المؤشر | المعلومات |
| --- | --- |
| Memory | ضغط الذاكرة والمقيم والمضغوط وSwap |
| CPU | الاستخدام الكلي ولكل نواة ومتوسط الحمل |
| System Power | تقدير طاقة CPU / GPU وحرارتهما |
| Charging Power | طاقة الشحن وقدرة المحول وحالة Power bypass |

يدعم شريط القوائم اختيار المؤشرات، ووضعي Compact وLabeled، والتبديل بين الصينية والإنجليزية. وتستخدم عناوين المؤشرات ألوان macOS الدلالية عند الوصول إلى حالة تحذير.

## الواجهة

### لوحة شريط القوائم

<div align="center">
  <img src="docs/images/live-panel.jpg" alt="Menu Monitor live panel on macOS" width="90%">
</div>

يعرض شريط القوائم المؤشرات المهمة، وتفتح اللوحة التفاصيل الكاملة واستخدام الأنوية والحرارة والطاقة ومخطط Swift Charts لآخر 60 ثانية.

### الإعدادات

<div align="center">
  <img src="docs/images/settings.jpg" alt="Menu Monitor preferences window" width="90%">
</div>

- اختيار مؤشرات شريط القوائم.
- التبديل بين Compact وLabeled.
- التبديل بين الصينية والإنجليزية.
- تفعيل أو إيقاف التشغيل عند تسجيل الدخول.

## مميزات الاستخدام

- **Swift 6 + SwiftUI:** واجهة أصلية مبنية خصيصًا لـ macOS مع Swift Charts.
- **حضور خفيف:** تنخفض وتيرة أخذ العينات عند إغلاق اللوحة وتعود عند الحاجة.
- **عمل محلي بالكامل:** بلا طلبات شبكة أو SDK تحليلات أو مزامنة سحابية أو فحص تحديثات.
- **من دون Electron أو WebView:** بنية تطبيق أصلية بلا وقت تشغيل متصفح.
- **جمع محلي:** إشارات النظام من IOKit وIOPS وIOReport.
- **تفاصيل عملية:** حمل كل نواة والحرارة وطاقة الشحن واكتشاف التجاوز وألوان التحذير.

## التنزيل والتثبيت

افتح [أحدث إصدار](https://github.com/origami3521905038-hash/menu-monitor/releases/latest) ونزّل ملف DMG الشامل.

1. افتح ملف DMG.
2. شغّل `MenuMonitor-Installer.pkg`.
3. اتبع خطوات المثبت.
4. يبدأ التطبيق في شريط القوائم ويحاول تسجيل التشغيل عند تسجيل الدخول.

يمكن أيضاً سحب `MenuMonitor.app` إلى مجلد التطبيقات، من دون تسجيل تلقائي لعنصر تسجيل الدخول.

## البناء من المصدر

المتطلبات: macOS 26 أو أحدث، Xcode 26 أو أحدث، Swift 6.2 أو أحدث.

```bash
git clone https://github.com/origami3521905038-hash/menu-monitor.git
cd menu-monitor
swift test -c debug
./install.sh
```

البناء فقط:

```bash
./build.sh
```

إنشاء DMG:

```bash
./package-dmg.sh
```

إنشاء حزمة التثبيت:

```bash
./package-pkg.sh
```

## الخصوصية والتشغيل المحلي

- تُقرأ المؤشرات من واجهات النظام المحلية.
- لا يرسل التطبيق طلبات شبكة ولا يتضمن تحليلات أو مزامنة سحابية.
- جمع المؤشرات لا يتطلب صلاحيات مدير.
- لا يوجد SMC Helper أو خادم خفي أو عملية root دائمة.
- قد يطلب macOS تفويضاً لمرة واحدة عند النسخ إلى `/Applications`، ولا علاقة له بقراءة المؤشرات.

## الاستهلاك المقاس

بيئة الاختبار: macOS 26.5.2 على جهاز Apple Silicon بثماني أنوية.

| القياس | النتيجة |
| --- | --- |
| عينات CPU واللوحة مغلقة | `0.0% / 0.8% / 0.0% / 1.2% / 0.6%` |
| أعلى استخدام CPU | نحو `1.2%` |
| أعلى footprint للعملية | نحو `13 MB` |
| ذاكرة RSS في `ps` | نحو `34–40 MB` مع التعيينات المشتركة |

## معنى بيانات الطاقة

System Power تقدير مشتق من عدادات طاقة CPU وGPU وDRAM عند توفرها. وهو لا يمثل طاقة الجدار أو دخل المحول أو قراءة عداد كهربائي للجهاز كامل.

تتبع الحرارة وقنوات الطاقة وحالة التجاوز الإشارات المتاحة من جهاز Mac وإصدار macOS الحالي.

## البنية التقنية

```text
MenuMonitorApp      تطبيق AppKit وشريط القوائم والإعدادات
MenuMonitorUI       لوحة SwiftUI وSwift Charts
MenuMonitorCore     جامعات المؤشرات وتنسيق أخذ العينات
CIOReportRuntime    وقت تشغيل C معزول لـIOReport
CIOHIDTemperature   وقت تشغيل معزول لحرارة IOHID
MenuMonitorProbe    أداة تحقق من مؤشرات سطر الأوامر
```

## البناء والتحقق من المستودع

```bash
swift build -c debug
python3 tests/validate_repo.py
```

يتضمن المصدر اختبارات لحالات المؤشرات والوقت الأحادي وحالات الطاقة وشروط تجاوز الطاقة وتنسيق القيم، ويمكن تشغيل `swift test -c debug` عبر سلسلة أدوات Xcode المكتملة. يتحقق GitHub Actions من بناء Swift وروابط الوثائق وبنية المستودع.

## الوثائق

- [Project introduction](GITHUB_PROJECT_INTRO.md)
- [Release checklist](GITHUB_RELEASE_CHECKLIST.md)
- [v1.0.1 release notes](RELEASE_NOTES-v1.0.1.md)
- [Security](SECURITY.md)
- [Contributing](CONTRIBUTING.md)

## الترخيص

MIT. راجع [LICENSE](LICENSE).

