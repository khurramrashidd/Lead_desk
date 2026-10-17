import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Website + chat language: English, हिंदी, मराठी. The counsellor desk stays in English.
/// Asha mirrors whatever language the prospect actually writes in, whatever is picked here.
enum AppLang { en, hi, mr }

class L10n {
  L10n._();

  static final lang = ValueNotifier<AppLang>(AppLang.en);
  static const _key = 'site_lang';

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key);
      lang.value = AppLang.values.firstWhere((l) => l.name == v, orElse: () => AppLang.en);
    } catch (_) {}
  }

  static Future<void> set(AppLang l) async {
    lang.value = l;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, l.name);
    } catch (_) {}
  }

  static String label(AppLang l) => switch (l) {
        AppLang.en => 'EN',
        AppLang.hi => 'हिं',
        AppLang.mr => 'मरा',
      };

  static String name(AppLang l) => switch (l) {
        AppLang.en => 'English',
        AppLang.hi => 'हिंदी',
        AppLang.mr => 'मराठी',
      };
}

/// tr('key') → text in the current site language (falls back to English).
String tr(String key) {
  final row = _strings[key];
  if (row == null) return key;
  return row[L10n.lang.value.index].isEmpty ? row[0] : row[L10n.lang.value.index];
}

// [English, Hindi, Marathi]
const Map<String, List<String>> _strings = {
  // ---- navigation
  'nav.courses': ['Courses', 'कोर्स', 'कोर्सेस'],
  'nav.batches': ['Batches', 'बैच', 'बॅचेस'],
  'nav.placement': ['Placement', 'प्लेसमेंट', 'प्लेसमेंट'],
  'nav.faq': ['FAQ', 'सवाल', 'प्रश्न'],
  'nav.staff': ['Staff', 'स्टाफ', 'स्टाफ'],
  'nav.talk': ['Talk to Asha', 'आशा से बात करें', 'आशाशी बोला'],
  'nav.demo': ['Judges', 'जज', 'परीक्षक'],
  'nav.home': ['Home', 'होम', 'मुख्यपृष्ठ'],
  'nav.about': ['Why us & Asha', 'हम क्यों और आशा', 'आम्ही का आणि आशा'],
  'nav.stories': ['Student stories', 'स्टूडेंट्स की कहानियाँ', 'विद्यार्थ्यांच्या कथा'],
  'nav.contact': ['Contact & QR codes', 'संपर्क और QR कोड', 'संपर्क आणि QR कोड'],
  'nav.menu': ['Menu', 'मेनू', 'मेनू'],
  'menu.language': ['Language', 'भाषा', 'भाषा'],
  'menu.dark': ['Dark mode', 'डार्क मोड', 'डार्क मोड'],
  'menu.staff': ['Staff sign in', 'स्टाफ लॉगिन', 'स्टाफ लॉगिन'],
  'menu.judges': ['Demo hub (judges)', 'डेमो हब (जज)', 'डेमो हब (परीक्षक)'],

  // ---- WhatsApp / Telegram / Google Form
  'talk.whatsapp': ['Talk on WhatsApp', 'WhatsApp पर बात करें', 'WhatsApp वर बोला'],
  'talk.telegram': ['Talk on Telegram', 'Telegram पर बात करें', 'Telegram वर बोला'],
  'talk.title': ['Chat where you like', 'जहाँ चाहें वहाँ चैट करें', 'हवं तिथे चॅट करा'],
  'talk.sub': [
    'Asha answers on WhatsApp and Telegram too, and your counsellor sees one conversation.',
    'आशा WhatsApp और Telegram पर भी जवाब देती है, और काउंसलर को एक ही बातचीत दिखती है।',
    'आशा WhatsApp आणि Telegram वरही उत्तर देते, आणि समुपदेशकाला एकच संवाद दिसतो.',
  ],
  'qr.form': ['Google Form', 'Google फॉर्म', 'Google फॉर्म'],
  'qr.formOpen': ['Open the enquiry form', 'एनक्वायरी फॉर्म खोलें', 'चौकशी फॉर्म उघडा'],
  'qr.open': ['Open', 'खोलें', 'उघडा'],
  'qr.wa.sub': ['Scan → WhatsApp opens with a message to Asha. Tap Send.', 'स्कैन करें → WhatsApp में आशा को मैसेज तैयार। Send दबाएँ।', 'स्कॅन करा → WhatsApp मध्ये आशासाठी मेसेज तयार. Send दाबा.'],
  'qr.tg.sub': ['Scan → Telegram opens the bot. Tap Start.', 'स्कैन करें → Telegram में बॉट खुलेगा। Start दबाएँ।', 'स्कॅन करा → Telegram मध्ये बॉट उघडेल. Start दाबा.'],
  'qr.form.sub': ['Prefer a form? Fill it in 1 minute; Asha follows up.', 'फॉर्म पसंद है? 1 मिनट में भरें; आशा संपर्क करेगी।', 'फॉर्म आवडतो? 1 मिनिटात भरा; आशा संपर्क करेल.'],
  'scan.eyebrow': ['Scan to chat', 'स्कैन करके चैट', 'स्कॅन करून चॅट'],
  'scan.title': ['Chat on your phone, your way', 'अपने फ़ोन पर, अपने तरीके से चैट करें', 'तुमच्या फोनवर, तुमच्या पद्धतीने चॅट करा'],
  'scan.sub': [
    'Point your phone camera at a code: WhatsApp or Telegram opens with Asha, or the enquiry form. Every channel lands in the same counsellor desk.',
    'फ़ोन का कैमरा कोड पर रखें: WhatsApp या Telegram पर आशा खुलेगी, या एनक्वायरी फॉर्म। हर चैनल एक ही काउंसलर डेस्क में आता है।',
    'फोनचा कॅमेरा कोडवर धरा: WhatsApp किंवा Telegram वर आशा उघडेल, किंवा चौकशी फॉर्म. प्रत्येक चॅनल एकाच समुपदेशक डेस्कमध्ये येतो.',
  ],
  'scan.subPhone': [
    'One tap opens WhatsApp or Telegram with Asha, or the enquiry form.',
    'एक टैप में WhatsApp या Telegram पर आशा, या एनक्वायरी फॉर्म।',
    'एका टॅपमध्ये WhatsApp किंवा Telegram वर आशा, किंवा चौकशी फॉर्म.',
  ],
  'scan.showQr': ['Show QR codes (to share)', 'QR कोड दिखाएँ (शेयर करने के लिए)', 'QR कोड दाखवा (शेअर करण्यासाठी)'],
  'scan.hideQr': ['Hide QR codes', 'QR कोड छुपाएँ', 'QR कोड लपवा'],
  'home.courses': ['Courses and fees', 'कोर्स और फीस', 'कोर्सेस आणि फी'],
  'home.allCourses': ['All course details', 'सभी कोर्स की जानकारी', 'सर्व कोर्सची माहिती'],
  'courses.tell': ['Tell me about', 'इसके बारे में बताइए:', 'याबद्दल सांगा:'],
  'courses.askShort': ['Ask Asha', 'आशा से पूछें', 'आशाला विचारा'],

  // ---- hero
  'hero.eyebrow': ['Admissions open · Pune', 'एडमिशन शुरू · पुणे', 'प्रवेश सुरू · पुणे'],
  'hero.title1': ['Not sure where to start?', 'शुरुआत कहाँ से करें?', 'सुरुवात कुठून करायची?'],
  'hero.title2': ['Ask Asha, any time.', 'आशा से पूछिए, कभी भी।', 'आशाला विचारा, कधीही.'],
  'hero.sub': [
    'Career-focused IT training in Pimpri-Chinchwad. Our AI admissions counsellor answers at 11 PM too — in English, हिंदी or मराठी, by text or voice note.',
    'पिंपरी-चिंचवड में करियर-केंद्रित IT ट्रेनिंग। हमारी AI एडमिशन काउंसलर रात 11 बजे भी जवाब देती है — English, हिंदी या मराठी में, टेक्स्ट या वॉइस नोट से।',
    'पिंपरी-चिंचवडमध्ये करिअर-केंद्रित IT प्रशिक्षण. आमची AI प्रवेश समुपदेशक रात्री 11 वाजताही उत्तर देते — English, हिंदी किंवा मराठीत, मजकूर किंवा व्हॉइस नोटने.',
  ],
  'hero.chat': ['Chat with Asha', 'आशा से चैट करें', 'आशाशी चॅट करा'],
  'hero.short': [
    'Our AI admissions counsellor answers in seconds, day or night, in English, हिंदी or मराठी, by text or voice note. Honest advice, real fees, a free demo class.',
    'हमारी AI एडमिशन काउंसलर दिन हो या रात, सेकंडों में जवाब देती है: English, हिंदी या मराठी में, टेक्स्ट या वॉइस नोट से। सच्ची सलाह, असली फीस, फ्री डेमो क्लास।',
    'आमची AI प्रवेश समुपदेशक दिवस असो वा रात्र, काही सेकंदांत उत्तर देते: English, हिंदी किंवा मराठीत, मजकूर किंवा व्हॉइस नोटने. प्रामाणिक सल्ला, खरी फी, मोफत डेमो क्लास.',
  ],
  'hero.form': ['Enquiry form', 'एनक्वायरी फॉर्म', 'चौकशी फॉर्म'],
  'hero.call': ['Talk to a human', 'इंसान से बात करें', 'माणसाशी बोला'],
  'hero.trust1': ['Replies in seconds, 24×7', 'सेकंडों में जवाब, 24×7', 'काही सेकंदांत उत्तर, 24×7'],
  'hero.trust2': ['Only published fees — no fake offers', 'सिर्फ़ प्रकाशित फीस — कोई झूठा ऑफ़र नहीं', 'फक्त प्रकाशित फी — खोट्या ऑफर नाहीत'],
  'hero.trust3': ['Free demo class, parents welcome', 'फ्री डेमो क्लास, माता-पिता का स्वागत', 'मोफत डेमो क्लास, पालकांचं स्वागत'],
  'hero.card.q': [
    'I\'m a commerce graduate with a two-year gap — can I really become a developer?',
    'मैं कॉमर्स ग्रेजुएट हूँ, 2 साल का गैप है — क्या मैं सच में डेवलपर बन सकता हूँ?',
    'मी कॉमर्स ग्रॅज्युएट आहे, 2 वर्षांचा गॅप आहे — मी खरंच डेव्हलपर होऊ शकतो का?',
  ],
  'hero.card.a': [
    'Yes — many of our learners started exactly there. It takes steady daily practice. Have you ever written any code? I can run a 2-minute aptitude check to find your right first step.',
    'हाँ — हमारे कई स्टूडेंट्स यहीं से शुरू हुए। रोज़ प्रैक्टिस चाहिए। क्या आपने कभी कोडिंग की है? 2 मिनट का एप्टीट्यूड चेक करके सही पहला कदम बताती हूँ।',
    'हो — आमचे अनेक विद्यार्थी इथूनच सुरू झाले. रोज सराव लागतो. तुम्ही कधी कोडिंग केलं आहे का? 2 मिनिटांचा अ‍ॅप्टिट्यूड चेक करून योग्य पहिलं पाऊल सांगते.',
  ],

  // ---- AI section
  'ai.eyebrow': ['Why Asha is different', 'आशा अलग क्यों है', 'आशा वेगळी का'],
  'ai.title': ['Counselling, not a FAQ bot', 'काउंसलिंग, FAQ बॉट नहीं', 'समुपदेशन, FAQ बॉट नाही'],
  'ai.sub': [
    'Every enquiry gets an honest conversation about your background, goals and worries.',
    'हर सवाल पर आपकी पढ़ाई, लक्ष्य और चिंता के बारे में ईमानदार बातचीत।',
    'प्रत्येक चौकशीवर तुमचं शिक्षण, ध्येय आणि काळजी याबद्दल प्रामाणिक संवाद.',
  ],
  'ai.p1.t': ['Answered at 11 PM', 'रात 11 बजे भी जवाब', 'रात्री 11 वाजताही उत्तर'],
  'ai.p1.d': ['No waiting till morning. Asha replies in seconds, any hour.', 'सुबह तक इंतज़ार नहीं। आशा कभी भी सेकंडों में जवाब देती है।', 'सकाळपर्यंत थांबायची गरज नाही. आशा कधीही काही सेकंदांत उत्तर देते.'],
  'ai.p2.t': ['Your language, even mixed', 'आपकी भाषा, मिली-जुली भी', 'तुमची भाषा, मिश्रही चालेल'],
  'ai.p2.d': ['Type or send a voice note in English, हिंदी or मराठी — Hinglish too.', 'English, हिंदी या मराठी में लिखिए या वॉइस नोट भेजिए — Hinglish भी।', 'English, हिंदी किंवा मराठीत लिहा किंवा व्हॉइस नोट पाठवा — मिश्रही.'],
  'ai.p3.t': ['A 2-minute aptitude check', '2 मिनट का एप्टीट्यूड चेक', '2 मिनिटांचा अ‍ॅप्टिट्यूड चेक'],
  'ai.p3.d': ['Four adaptive questions, then an honest course recommendation.', 'चार एडैप्टिव सवाल, फिर ईमानदार कोर्स सलाह।', 'चार अ‍ॅडॅप्टिव्ह प्रश्न, मग प्रामाणिक कोर्स सल्ला.'],
  'ai.p4.t': ['No invented offers', 'कोई झूठा ऑफ़र नहीं', 'खोट्या ऑफर नाहीत'],
  'ai.p4.d': ['Fees and policies come only from this page. No fake discounts or job guarantees.', 'फीस और नियम सिर्फ़ इसी पेज से। कोई नकली छूट या जॉब गारंटी नहीं।', 'फी आणि नियम फक्त याच पानावरून. खोटी सूट किंवा नोकरीची हमी नाही.'],

  // ---- courses
  'courses.eyebrow': ['Programs', 'प्रोग्राम', 'प्रोग्राम'],
  'courses.title': ['Pick a track — or let Asha help you pick', 'ट्रैक चुनिए — या आशा से मदद लीजिए', 'ट्रॅक निवडा — किंवा आशाची मदत घ्या'],
  'courses.sub': ['Fees and batches below are the same data Asha is allowed to quote.', 'नीचे की फीस और बैच वही हैं जो आशा बता सकती है।', 'खालील फी आणि बॅचेस तेच आहेत जे आशा सांगू शकते.'],
  'courses.weeks': ['weeks', 'हफ़्ते', 'आठवडे'],
  'courses.emi': ['EMI', 'EMI', 'EMI'],
  'courses.next': ['Next batch', 'अगला बैच', 'पुढची बॅच'],
  'courses.ask': ['Is this right for me?', 'क्या यह मेरे लिए सही है?', 'हे माझ्यासाठी योग्य आहे का?'],
  'courses.enquire': ['Enquire', 'पूछताछ', 'चौकशी'],
  'courses.idealFor': ['Ideal for', 'किसके लिए', 'कोणासाठी'],

  // ---- placement / why
  'why.eyebrow': ['How we teach', 'हम कैसे पढ़ाते हैं', 'आम्ही कसं शिकवतो'],
  'why.title': ['Built around people with jobs, gaps and families', 'नौकरी, गैप और परिवार वालों के लिए बना', 'नोकरी, गॅप आणि कुटुंब असणाऱ्यांसाठी'],
  'placement.eyebrow': ['Placement assistance', 'प्लेसमेंट सहायता', 'प्लेसमेंट सहाय्य'],
  'placement.title': ['Honest help, no fake guarantees', 'ईमानदार मदद, कोई झूठी गारंटी नहीं', 'प्रामाणिक मदत, खोटी हमी नाही'],
  'batches.eyebrow': ['Upcoming', 'आने वाले', 'येणाऱ्या'],
  'batches.title': ['Next batches', 'अगले बैच', 'पुढच्या बॅचेस'],
  'stories.eyebrow': ['Learners', 'स्टूडेंट्स', 'विद्यार्थी'],
  'stories.title': ['They started where you are', 'वे वहीं से शुरू हुए जहाँ आप हैं', 'ते तिथूनच सुरू झाले जिथे तुम्ही आहात'],
  'faq.eyebrow': ['Questions', 'सवाल', 'प्रश्न'],
  'faq.title': ['Asked every day', 'रोज़ पूछे जाने वाले', 'रोज विचारले जाणारे'],
  'faq.more': ['Ask Asha anything else', 'आशा से कुछ और पूछिए', 'आशाला अजून काही विचारा'],
  'cta.title': ['Your first step takes two minutes', 'आपका पहला कदम दो मिनट का है', 'तुमचं पहिलं पाऊल दोन मिनिटांचं'],
  'cta.sub': ['Tell Asha about yourself. She will be honest about what fits.', 'आशा को अपने बारे में बताइए। वह सच बताएगी कि क्या सही है।', 'आशाला तुमच्याबद्दल सांगा. काय योग्य आहे ते ती प्रामाणिकपणे सांगेल.'],
  'sample.note': [
    'Prototype for the hackathon: brand, courses, fees, partners and stories are SAMPLE content, editable in Admin.',
    'हैकथॉन प्रोटोटाइप: ब्रांड, कोर्स, फीस और कहानियाँ सैंपल हैं, Admin में बदली जा सकती हैं।',
    'हॅकॅथॉन प्रोटोटाइप: ब्रँड, कोर्स, फी आणि कथा नमुना आहेत, Admin मध्ये बदलता येतात.',
  ],

  // ---- chat
  'chat.status': ['Admissions counsellor · replies 24×7', 'एडमिशन काउंसलर · 24×7 जवाब', 'प्रवेश समुपदेशक · 24×7 उत्तर'],
  'chat.greeting': [
    'Namaste 🙏 I am Asha, admissions counsellor at SechTummit Trainers.\n\nAsk me anything — courses, fees, batches, or whether this is right for you. Type or send a voice note in English, हिंदी or मराठी.',
    'नमस्ते 🙏 मैं आशा हूँ, SechTummit Trainers की एडमिशन काउंसलर।\n\nकोर्स, फीस, बैच — या यह आपके लिए सही है या नहीं, कुछ भी पूछिए। English, हिंदी या मराठी में लिखिए या वॉइस नोट भेजिए।',
    'नमस्कार 🙏 मी आशा, SechTummit Trainers ची प्रवेश समुपदेशक.\n\nकोर्स, फी, बॅचेस — किंवा हे तुमच्यासाठी योग्य आहे का, काहीही विचारा. English, हिंदी किंवा मराठीत लिहा किंवा व्हॉइस नोट पाठवा.',
  ],
  'chat.try': ['TRY ASKING', 'ऐसे पूछिए', 'असं विचारा'],
  'chat.s1': ['I\'m a commerce graduate with a 2-year gap — can I really become a developer?', 'मैं कॉमर्स ग्रेजुएट हूँ, 2 साल का गैप है — क्या मैं डेवलपर बन सकता हूँ?', 'मी कॉमर्स ग्रॅज्युएट आहे, 2 वर्षांचा गॅप आहे — मी डेव्हलपर होऊ शकतो का?'],
  'chat.s2': ['Full Stack Java ki fees kitni hai?', 'फुल स्टैक जावा की फीस कितनी है?', 'फुल स्टॅक जावाची फी किती आहे?'],
  'chat.s3': ['My father wants to talk to someone before I join', 'मेरे पापा जॉइन करने से पहले किसी से बात करना चाहते हैं', 'माझ्या बाबांना प्रवेशाआधी कोणाशी तरी बोलायचं आहे'],
  'chat.s4': ['Book a free demo class', 'फ्री डेमो क्लास बुक करनी है', 'मोफत डेमो क्लास बुक करायचा आहे'],
  'chat.hint': ['Type in English, हिंदी or मराठी…', 'English, हिंदी या मराठी में लिखिए…', 'English, हिंदी किंवा मराठीत लिहा…'],
  'chat.listening': ['Listening…', 'सुन रही हूँ…', 'ऐकते आहे…'],
  'chat.left': ['s left', 'सेकंड बाकी', 'सेकंद बाकी'],
  'chat.send': ['Send', 'भेजें', 'पाठवा'],
  'chat.cancel': ['Cancel', 'रद्द करें', 'रद्द करा'],
  'chat.typing': ['Asha is typing…', 'आशा लिख रही है…', 'आशा लिहित आहे…'],
  'chat.privacy': ['Your chat reaches our counsellors only.', 'आपकी चैट सिर्फ़ हमारे काउंसलर देखते हैं।', 'तुमची चॅट फक्त आमचे समुपदेशक पाहतात.'],
  'chat.pick': ['Tap your answer', 'अपना जवाब चुनिए', 'तुमचं उत्तर निवडा'],
  'chat.human': ['Talk to a human', 'इंसान से बात करें', 'माणसाशी बोला'],
  'chat.mic': ['Please allow microphone access to send a voice note.', 'वॉइस नोट के लिए माइक्रोफ़ोन की अनुमति दीजिए।', 'व्हॉइस नोटसाठी मायक्रोफोनची परवानगी द्या.'],
  'chat.short': ['That note was too short or too long.', 'वॉइस नोट बहुत छोटा या बहुत लंबा था।', 'व्हॉइस नोट खूप लहान किंवा खूप मोठा होता.'],
  'chat.failed': ['Could not send. Check your internet and try again.', 'भेज नहीं पाए। इंटरनेट देखकर फिर कोशिश करें।', 'पाठवता आलं नाही. इंटरनेट तपासून पुन्हा प्रयत्न करा.'],
  'chat.calendar': ['Add to Google Calendar', 'Google Calendar में जोड़ें', 'Google Calendar मध्ये जोडा'],
  'chat.who': ['Who is this enquiry for?', 'यह पूछताछ किसके लिए है?', 'ही चौकशी कोणासाठी आहे?'],
  'chat.rel.self': ['I\'m the student', 'मैं स्टूडेंट हूँ', 'मी विद्यार्थी आहे'],
  'chat.rel.parent': ['I\'m a parent', 'मैं पैरेंट हूँ', 'मी पालक आहे'],
  'chat.rel.friend': ['For a friend', 'दोस्त के लिए', 'मित्रासाठी'],
  'chat.orAsk': ['OR JUST ASK', 'या सीधे पूछिए', 'किंवा थेट विचारा'],
  'chat.slow': [
    'Asha is taking longer than usual… still working on it.',
    'आशा को सामान्य से ज़्यादा समय लग रहा है… जवाब आ रहा है।',
    'आशाला नेहमीपेक्षा जास्त वेळ लागतोय… उत्तर येत आहे.',
  ],
  'chat.retrying': [
    'Asha will reply here automatically in a few minutes. You can also reach a counsellor now:',
    'आशा कुछ मिनट में यहीं अपने आप जवाब देगी। आप अभी काउंसलर से भी संपर्क कर सकते हैं:',
    'आशा काही मिनिटांत इथेच आपोआप उत्तर देईल. तुम्ही आत्ता समुपदेशकाशीही संपर्क करू शकता:',
  ],
  'chat.pickOne': ['Tap one', 'एक चुनिए', 'एक निवडा'],
  'chat.humanWait': [
    'A counsellor has joined this chat and will reply here shortly.',
    'एक काउंसलर इस चैट में जुड़ गए हैं और जल्द ही यहीं जवाब देंगे।',
    'एक समुपदेशक या चॅटमध्ये आले आहेत आणि लवकरच इथेच उत्तर देतील.',
  ],
  'chat.other': ['WhatsApp / Telegram', 'WhatsApp / Telegram', 'WhatsApp / Telegram'],
  'voice.preview': ['Voice note ready: listen, then send', 'वॉइस नोट तैयार: सुनें, फिर भेजें', 'व्हॉइस नोट तयार: ऐका, मग पाठवा'],
  'voice.play': ['Play', 'चलाएँ', 'ऐका'],
  'voice.pause': ['Pause', 'रोकें', 'थांबवा'],
  'voice.delete': ['Delete', 'हटाएँ', 'काढा'],
  'voice.stop': ['Stop', 'रोकें', 'थांबवा'],
  'chat.pickLang': ['Choose your language', 'अपनी भाषा चुनें', 'तुमची भाषा निवडा'],
  'chat.pickLangSub': [
    'Asha will chat with you in this language. You can change it any time.',
    'आशा इसी भाषा में आपसे बात करेगी। आप इसे कभी भी बदल सकते हैं।',
    'आशा याच भाषेत तुमच्याशी बोलेल. तुम्ही ती कधीही बदलू शकता.',
  ],
  'chat.restart': ['Restart chat', 'चैट फिर से शुरू करें', 'चॅट पुन्हा सुरू करा'],
  'chat.restartAsk': ['Start a fresh conversation?', 'नई बातचीत शुरू करें?', 'नवीन संभाषण सुरू करायचं?'],
  'chat.yes': ['Yes, restart', 'हाँ, फिर से शुरू करें', 'हो, पुन्हा सुरू करा'],
  'chat.no': ['Cancel', 'रद्द करें', 'रद्द करा'],
  'chat.closed': [
    'This chat is closed. Start again to ask anything.',
    'यह चैट बंद है। कुछ भी पूछने के लिए फिर से शुरू करें।',
    'ही चॅट बंद आहे. काहीही विचारण्यासाठी पुन्हा सुरू करा.',
  ],
  'chat.startAgain': ['Start again', 'फिर से शुरू करें', 'पुन्हा सुरू करा'],
  'pay.title': ['Pay the registration fee', 'रजिस्ट्रेशन फीस भरें', 'नोंदणी फी भरा'],
  'pay.scan': ['Scan with any UPI app', 'किसी भी UPI ऐप से स्कैन करें', 'कोणत्याही UPI ॲपने स्कॅन करा'],
  'pay.open': ['Open UPI app', 'UPI ऐप खोलें', 'UPI ॲप उघडा'],
  'pay.upload': ['Upload payment receipt', 'पेमेंट रसीद अपलोड करें', 'पेमेंट पावती अपलोड करा'],
  'pay.copied': ['UPI ID copied', 'UPI ID कॉपी हो गई', 'UPI ID कॉपी झाला'],
  'pay.big': [
    'That photo is too large. Please send a screenshot.',
    'यह फोटो बहुत बड़ी है। कृपया स्क्रीनशॉट भेजें।',
    'हा फोटो खूप मोठा आहे. कृपया स्क्रीनशॉट पाठवा.',
  ],
  'pay.done': ['Receipt sent', 'रसीद भेज दी', 'पावती पाठवली'],
  'chat.intent': [
    'Would you like to know about our courses first, or do you already know which course you want to join?',
    'क्या आप पहले हमारे कोर्स के बारे में जानना चाहेंगे, या आपको पता है कि कौन सा कोर्स जॉइन करना है?',
    'आधी आमच्या कोर्सबद्दल जाणून घ्यायचं आहे, की कोणता कोर्स करायचा हे तुम्हाला माहिती आहे?',
  ],
  'chat.intentAsk': ['💬 Ask about courses first', '💬 पहले कोर्स के बारे में पूछें', '💬 आधी कोर्सबद्दल विचारा'],
  'chat.intentEnroll': ['✅ I know my course: enroll', '✅ कोर्स पता है: एनरोल करें', '✅ कोर्स ठरला आहे: प्रवेश घ्या'],
};
