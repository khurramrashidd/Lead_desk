/**
 * Demo data: the sample knowledge base, a demo-class calendar and 30 SAMPLE leads in English,
 * Hindi, Marathi and mixes, across every channel, so the desk and the reports look alive.
 * Every seeded lead has seed: true and is removed by "Clear sample leads".
 * Seeded messages never trigger the AI (they carry seed: true).
 */
import { db, FieldValue, Timestamp, type Lead } from "./db";
import { SAMPLE_KB } from "./kb_sample";
import { computeScore } from "./scoring";
import { decideNextAction } from "./nba";
import { googleCalendarUrl } from "./lang";

const HOUR = 3_600_000;
const IST = 330 * 60_000;

export async function seedKb(): Promise<void> {
  await db.doc("kb/main").set({ ...SAMPLE_KB, updatedAt: FieldValue.serverTimestamp() });
}

function istDate(base: Date, dayOffset: number, hour: number, minute = 0): Date {
  const ist = new Date(base.getTime() + IST);
  const d = new Date(Date.UTC(ist.getUTCFullYear(), ist.getUTCMonth(), ist.getUTCDate() + dayOffset, hour, minute));
  return new Date(d.getTime() - IST);
}

/** Demo classes for the next 7 days + counsellor call / video slots. */
export async function seedSlots(now: Date): Promise<number> {
  const plan: [number, number, string, string, string, "demo" | "call" | "meet", number][] = [
    [11, 0, "Full Stack Java — demo class", "Online live", "fsj", "demo", 12],
    [17, 0, "Python Foundations — demo class", "Classroom, Pimpri-Chinchwad", "py", "demo", 12],
    [19, 0, "Data Science & AI — demo class", "Online live", "ds", "demo", 12],
    [18, 0, "MERN Full Stack — demo class", "Online live", "mern", "demo", 12],
    [12, 30, "Counsellor phone call", "Phone call", "", "call", 3],
    [16, 0, "Counsellor video meeting", "Google Meet", "", "meet", 2],
  ];
  const batch = db.batch();
  let n = 0;
  for (let d = 0; d <= 7; d++) {
    for (const [h, m, title, mode, course, kind, cap] of plan) {
      if (course === "mern" && d % 2 === 1) continue;
      const start = istDate(now, d, h, m);
      if (start.getTime() < now.getTime() + HOUR) continue;
      const ist = new Date(start.getTime() + IST);
      const id = `slot_${ist.toISOString().slice(0, 10).replace(/-/g, "")}_${String(h).padStart(2, "0")}${String(m).padStart(2, "0")}_${kind}${course ? "_" + course : ""}`;
      batch.set(
        db.doc(`slots/${id}`),
        // increment(0) keeps any existing bookings and starts new slots at 0
        { title, mode, courseId: course, kind, startAt: Timestamp.fromDate(start), durationMin: kind === "demo" ? 60 : 20, capacity: cap, booked: FieldValue.increment(0) },
        { merge: true },
      );
      n++;
    }
  }
  await batch.commit();
  return n;
}

type M = [role: "user" | "ai" | "counsellor", text: string, hoursAgo: number];

interface Persona {
  id: string;
  name: string;
  phone: string;
  city: string;
  source: string;
  sources?: string[];
  language: string;
  status: string;
  objections: string[];
  summary: [string, string, string];
  profile: Record<string, string>;
  ai: number; // AI intent read
  counsellor: string;
  rec?: [string, string];
  apt?: "strong" | "intermediate" | "beginner" | "in_progress";
  bookDay?: number; // days from now for a booked demo
  followup: string;
  msgs: M[];
  relation?: string;
  studentName?: string;
}

const P: Persona[] = [
  {
    id: "s_sneha", name: "Sneha Kulkarni", phone: "9822011223", city: "Wakad", source: "instagram", sources: ["instagram", "web"], language: "marathi-english", status: "demo_booked",
    objections: ["job_fear", "fees"], ai: 84, counsellor: "Priya (sample)", rec: ["py", "B.Com with a 2-year gap and no coding yet: Python Foundations first builds logic, then Full Stack."], apt: "intermediate", bookDay: 1,
    summary: ["B.Com 2022 graduate with a 2-year gap, Wakad.", "Wants to become a developer; worried the gap and fees will hold her back.", "Aptitude intermediate; Python Foundations demo booked for tomorrow 5 PM."],
    profile: { education: "B.Com 2022", gap: "2 years", goal: "Software developer", codingExperience: "none", constraints: "Budget-conscious", familyView: "Supportive" },
    followup: "Sneha, udyacha demo class tumchyasathi ready aahe 😊 Kahi prashna aslyas ithech vichara.",
    msgs: [
      ["user", "Hi, mi B.Com kelay 2022 madhe, 2 years gap aahe. Mala developer banta yeil ka?", 30],
      ["ai", "Ho Sneha, nakki yeil! Gap mule kahi farak padat nahi, daily practice mahatvachi aahe. Tumhi aadhi kadhi coding try kela aahe ka?", 30],
      ["user", "Nahi, kadhich nahi. Ani fees jasta asel tar ghari problem hoil", 29],
      ["ai", "Samajla. Python Foundations ₹12,000 aahe, 2 EMI madhe ₹6,000 pratyeki. Ek chhota aptitude check karuya ka? 2 minutes lagtil.", 29],
      ["user", "B", 28],
      ["ai", "✅ Demo class booked: Python Foundations — demo class. Tumhala reminder milel.", 27],
    ],
  },
  {
    id: "s_amit", name: "Amit Shinde", phone: "9765012345", city: "Chinchwad", source: "whatsapp", language: "en", status: "admitted",
    objections: ["time"], ai: 95, counsellor: "Ayesha (sample)", rec: ["fsj", "Mechanical engineer in sales who can study only weekends: Full Stack Java weekend batch."], apt: "strong",
    summary: ["BE Mechanical, working in sales.", "Could only study on weekends.", "Admitted to Full Stack Java weekend batch."],
    profile: { education: "BE Mechanical", currentWork: "Sales executive", goal: "Full stack developer", timing: "Weekends only", codingExperience: "some" },
    followup: "Welcome aboard, Amit! Your first weekend class is this Saturday.",
    msgs: [
      ["user", "I work in sales Mon-Sat. Is there any weekend batch for Java?", 200],
      ["ai", "Yes Amit — Full Stack Java has a weekend batch starting 8 Nov 2026, Sat-Sun 4 hours a day, all sessions recorded. Shall I book you a demo?", 200],
      ["user", "Yes please, Saturday 11am", 199],
      ["counsellor", "Hi Amit, Ayesha here. Your admission is confirmed — see you Saturday!", 40],
    ],
  },
  {
    id: "s_pooja", name: "Pooja Jadhav", phone: "9890098900", city: "Pimpri", source: "walkin", language: "marathi-english", status: "engaged",
    objections: ["family_approval"], ai: 62, counsellor: "Priya (sample)", rec: ["ds", "B.Sc Maths, comfortable with numbers: Data Science & AI fits her goal."], apt: "strong",
    summary: ["B.Sc Maths, interested in Data Science.", "Father wants to meet the trainer before deciding.", "Next: invite father to the free demo class."],
    profile: { education: "B.Sc Mathematics", goal: "Data analyst", familyView: "Father wants to meet the trainer first" },
    followup: "Pooja, tumchya babanna pan demo class la gheun ya — trainer shi direct bolta yeil.",
    msgs: [
      ["user", "Walk-in: Pooja Jadhav, B.Sc Maths, Data Science madhe interest", 26],
      ["ai", "Pooja, Data Science & AI tumchyasathi chhan fit aahe. Tumchya gharchyanna kahi prashna aahet ka?", 26],
      ["user", "Babanna aadhi trainer la bhetaycha aahe", 20],
    ],
  },
  {
    id: "s_imran", name: "Imran Shaikh", phone: "9970099700", city: "Nigdi", source: "call", language: "hinglish", status: "lost",
    objections: ["fees"], ai: 12, counsellor: "Rohan (sample)",
    summary: ["Looking for a free course.", "Fees too high, not interested in EMI.", "Marked lost."],
    profile: { goal: "Any IT job", budget: "Wants free course" },
    followup: "",
    msgs: [
      ["user", "[Missed call] Imran Shaikh", 300],
      ["ai", "Namaste Imran ji, aapne call kiya tha. Kis course ke baare mein jaanna chahenge?", 300],
      ["user", "Free mein koi course hai kya?", 290],
      ["ai", "Free course toh nahi hai, lekin zero-interest EMI aur listed scholarships hain. Batau?", 290],
    ],
  },
  {
    id: "s_kiran", name: "Kiran More", phone: "9011090110", city: "Akurdi", source: "instagram", language: "en", status: "admitted",
    objections: [], ai: 92, counsellor: "Ayesha (sample)", rec: ["mern", "Final-year BCA who already knows HTML/JS: MERN is the direct path."], apt: "strong",
    summary: ["Final-year BCA, knows HTML and some JavaScript.", "Chose MERN after the demo.", "Admitted, first EMI paid."],
    profile: { education: "BCA final year", codingExperience: "some", goal: "Web developer" },
    followup: "",
    msgs: [
      ["user", "Do you have MERN? I know basic HTML and JS", 400],
      ["ai", "Yes Kiran! MERN Full Stack is 20 weeks, hybrid, ₹55,000 or 5 EMIs of ₹11,500. With your BCA it's a direct fit.", 400],
    ],
  },
  {
    id: "s_neha", name: "Neha Gaikwad", phone: "9637096370", city: "Pune", source: "web", language: "en", status: "engaged",
    objections: ["time"], ai: 58, counsellor: "Ayesha (sample)", rec: ["qa", "Working in a BPO, weekends only: Software Testing is the quickest switch."],
    summary: ["Works night shifts in a BPO.", "Can study only on weekends; wants a testing role.", "Next: share the weekend Testing batch."],
    profile: { currentWork: "BPO, night shift", goal: "QA / testing role", timing: "Weekends" },
    followup: "Hi Neha, the Software Testing course has weekend options and every session is recorded. Want me to share the next batch date?",
    msgs: [
      ["user", "I work night shift. Can I still do a course?", 70],
      ["ai", "Absolutely, Neha. Weekend batches are Sat-Sun, and recordings stay for a year. What kind of role are you aiming for?", 70],
      ["user", "Testing maybe", 60],
    ],
  },
  {
    id: "s_suresh", name: "Suresh Pawar", phone: "9545095450", city: "Pimpri", source: "walkin", language: "mr", status: "admitted",
    objections: ["family_approval"], ai: 90, counsellor: "Priya (sample)", rec: ["qa", "Prefers classroom learning: Software Testing classroom batch."],
    summary: ["Walked in with his father.", "Liked the classroom batch.", "Admitted to Software Testing."],
    profile: { education: "B.A.", goal: "Software tester", familyView: "Father came along, convinced after demo" },
    followup: "",
    msgs: [
      ["user", "[Walk-in] Suresh Pawar · वडिलांसोबत आले", 500],
      ["ai", "नमस्कार सुरेश! सॉफ्टवेअर टेस्टिंग कोर्स क्लासरूममध्येही आहे. डेमो क्लासला वडिलांनाही घेऊन या.", 500],
    ],
  },
  {
    id: "s_rohit", name: "रोहित देशमुख", phone: "9822334455", city: "Hinjewadi", source: "whatsapp", language: "mr", status: "engaged",
    objections: ["fees", "family_approval"], ai: 55, counsellor: "Priya (sample)", rec: ["fsj", "Diploma in IT, some Java in college: Full Stack Java with EMI."], apt: "intermediate",
    summary: ["Diploma in IT, did some Java in college.", "Worried about fees; parents not convinced yet.", "Next: EMI details and invite parents to demo."],
    profile: { education: "Diploma IT", codingExperience: "some", goal: "Java developer", familyView: "Parents unsure", budget: "Needs EMI" },
    followup: "रोहित, फुल स्टॅक जावा ६ EMI मध्ये ₹11,000 दरमहा आहे. आई-वडिलांनाही डेमो क्लासला आणा, ते थेट ट्रेनरशी बोलू शकतील.",
    msgs: [
      ["user", "मला जावा शिकायचं आहे पण फी खूप जास्त वाटते", 48],
      ["ai", "समजलं रोहित. फुल स्टॅक जावा ₹65,000 आहे, पण ६ EMI मध्ये ₹11,000 दरमहा भरता येतं. घरच्यांचं काय मत आहे?", 48],
      ["user", "आई बाबांना अजून पटलं नाही", 47],
    ],
  },
  {
    id: "s_anjali", name: "Anjali Verma", phone: "9876001122", city: "Baner", source: "googleform", language: "hinglish", status: "demo_booked",
    objections: ["job_fear"], ai: 78, counsellor: "Rohan (sample)", rec: ["ds", "B.Tech ECE comfortable with maths: Data Science & AI."], apt: "strong", bookDay: 2,
    summary: ["B.Tech ECE 2024, unemployed for a year.", "Fears she won't get a job after the course.", "Data Science demo booked."],
    profile: { education: "B.Tech ECE 2024", gap: "1 year", goal: "Data scientist", codingExperience: "some" },
    followup: "Anjali ji, demo ke baad placement assistance kaise kaam karta hai woh bhi detail mein samjha denge.",
    msgs: [
      ["user", "[Google Form] Anjali Verma · Interested in: Data Science · Kya course ke baad job milegi?", 20],
      ["ai", "Anjali ji, hum job guarantee nahi dete — lekin resume, mock interviews aur hiring partners ko referrals milte hain. Aapka maths background kaisa hai?", 20],
      ["user", "Maths achha hai, B.Tech ECE kiya hai", 19],
    ],
  },
  {
    id: "s_vikas", name: "Vikas Yadav", phone: "9123456780", city: "Kharadi", source: "telegram", language: "hi", status: "engaged",
    objections: ["trust"], ai: 48, counsellor: "Rohan (sample)",
    summary: ["12th pass, wants to learn coding.", "Not sure if the institute is genuine.", "Next: free demo, meet the trainer."],
    profile: { education: "12th", goal: "Coding job" },
    followup: "विकास जी, फ्री डेमो क्लास में आकर ट्रेनर से मिलिए — फिर फैसला कीजिए।",
    msgs: [
      ["user", "क्या आपका इंस्टिट्यूट असली है? बहुत फ्रॉड चलते हैं", 30],
      ["ai", "आपकी चिंता सही है विकास जी। फ्री डेमो क्लास में आइए, ट्रेनर से मिलिए और फिर फैसला कीजिए। आपकी पढ़ाई कहाँ तक हुई है?", 30],
    ],
  },
  {
    id: "s_priyanka", name: "Priyanka Joshi", phone: "9898989898", city: "Kothrud", source: "web", language: "en", status: "new",
    objections: [], ai: 30, counsellor: "Ayesha (sample)",
    summary: ["Asked about course list.", "No details yet.", "Next: learn background and goal."],
    profile: {},
    followup: "Hi Priyanka! Happy to help you pick the right course — what are you studying or working on right now?",
    msgs: [["user", "Which courses do you have?", 5], ["ai", "Hi Priyanka! We have Python Foundations, Full Stack Java, MERN, Data Science & AI, DevOps and Software Testing. What are you doing currently?", 5]],
  },
  {
    id: "s_mohan", name: "Mohan Patil (father)", phone: "9422011223", city: "Chakan", source: "call", language: "mr", status: "engaged",
    objections: ["family_approval", "job_fear"], ai: 52, counsellor: "Priya (sample)", relation: "parent", studentName: "Omkar Patil",
    summary: ["Father enquiring for son Omkar (B.Sc CS).", "Wants proof that students get jobs.", "Next: invite father and Omkar to demo."],
    profile: { background: "Parent enquiring for son", education: "Son: B.Sc CS", familyView: "Father deciding" },
    followup: "मोहनजी, ओंकारसोबत डेमो क्लासला या — प्लेसमेंट प्रक्रिया आम्ही प्रत्यक्ष दाखवू.",
    msgs: [
      ["user", "[Voicemail] माझ्या मुलासाठी चौकशी करायची आहे, B.Sc CS झालाय", 10],
      ["ai", "नमस्कार मोहनजी! ओंकारसाठी फुल स्टॅक किंवा डेटा सायन्स दोन्ही चांगले पर्याय आहेत. त्याला कोणत्या क्षेत्रात रस आहे?", 10],
    ],
  },
  {
    id: "s_farhan", name: "Farhan Qureshi", phone: "9004400440", city: "Camp", source: "instagram", language: "hinglish", status: "demo_booked",
    objections: [], ai: 80, counsellor: "Rohan (sample)", rec: ["mern", "Freelances on WordPress: MERN turns that into full-stack skills."], apt: "strong", bookDay: 3,
    summary: ["Freelances on WordPress sites.", "Wants proper full-stack skills.", "MERN demo booked."],
    profile: { currentWork: "WordPress freelancer", codingExperience: "some", goal: "Full stack" },
    followup: "Farhan bhai, demo se pehle koi sawaal ho toh poochh lo!",
    msgs: [["user", "Bhai MERN ka next batch kab hai?", 15], ["ai", "Farhan, MERN Full Stack ka next batch 10 Nov 2026 se hai. Demo book kar doon?", 15], ["user", "haan kar do", 14]],
  },
  {
    id: "s_aarti", name: "Aarti Kale", phone: "9763201234", city: "Bhosari", source: "form", language: "en", status: "engaged",
    objections: ["distance"], ai: 50, counsellor: "Ayesha (sample)", rec: ["py", "Lives far from Pimpri: online live Python Foundations."],
    summary: ["Lives in Bhosari, far from the centre.", "Wants online option.", "Next: share online live batch."],
    profile: { goal: "Learn coding", constraints: "Distance from centre" },
    followup: "Hi Aarti, Python Foundations runs online live too — same trainer, same projects. Want the next batch date?",
    msgs: [["user", "[Website form] Aarti Kale · Interested in: Python · I stay far, is online possible?", 40], ["ai", "Yes Aarti, Python Foundations is online live or in classroom. Have you coded before?", 40]],
  },
  {
    id: "s_deepak", name: "Deepak Sharma", phone: "9811122233", city: "Viman Nagar", source: "whatsapp", language: "hi", status: "engaged",
    objections: ["job_fear"], ai: 60, counsellor: "Rohan (sample)", rec: ["devops", "Support engineer with Linux basics: DevOps & Cloud."],
    summary: ["IT support engineer, 3 years.", "Worried about switching at 28.", "Next: explain DevOps path and placement assistance."],
    profile: { currentWork: "IT support, 3 years", codingExperience: "beginner", goal: "DevOps engineer" },
    followup: "दीपक जी, DevOps में support का अनुभव बहुत काम आता है। डेमो क्लास देखना चाहेंगे?",
    msgs: [["user", "28 साल की उम्र में DevOps में switch हो सकता है?", 22], ["ai", "बिल्कुल दीपक जी, कोई उम्र सीमा नहीं है और आपका support अनुभव काम आएगा।", 22]],
  },
  {
    id: "s_shruti", name: "श्रुती पवार", phone: "9850123456", city: "Pimple Saudagar", source: "whatsapp", language: "mr", status: "new",
    objections: [], ai: 35, counsellor: "Priya (sample)",
    summary: ["Asked about Data Science.", "Background not known yet.", "Next: ask education and goal."],
    profile: {},
    followup: "श्रुती, तुमचं शिक्षण कुठपर्यंत झालं आहे? त्यानुसार योग्य कोर्स सुचवते.",
    msgs: [["user", "डेटा सायन्स कोर्सबद्दल माहिती हवी आहे", 3], ["ai", "नक्की श्रुती! तुमचं शिक्षण कुठपर्यंत झालं आहे?", 3]],
  },
  {
    id: "s_arjun", name: "Arjun Nair", phone: "9945012345", city: "Aundh", source: "web", language: "en", status: "demo_booked",
    objections: [], ai: 82, counsellor: "Ayesha (sample)", rec: ["fsj", "B.Tech CS fresher: Full Stack Java for service-company roles."], apt: "strong", bookDay: 1,
    summary: ["B.Tech CS 2026 fresher.", "Wants a Java developer role.", "Full Stack Java demo booked."],
    profile: { education: "B.Tech CS 2026", codingExperience: "some", goal: "Java developer" },
    followup: "See you at the demo, Arjun!",
    msgs: [["user", "I'm a CS fresher, want Java + Spring Boot", 12], ["ai", "Perfect fit, Arjun — Full Stack Java covers Core Java, Spring Boot 3 and React. Shall I book a demo?", 12], ["user", "Yes tomorrow 11", 11]],
  },
  {
    id: "s_meera", name: "Meera Iyer", phone: "9003300330", city: "Hadapsar", source: "googleform", language: "en", status: "lost",
    objections: ["time"], ai: 15, counsellor: "Ayesha (sample)",
    summary: ["Working mother, very little time.", "Postponed to next year.", "Marked lost (keep warm)."],
    profile: { constraints: "Young child, little time" },
    followup: "",
    msgs: [["user", "[Google Form] Meera Iyer · Interested in: Testing · Maybe next year", 260]],
  },
  {
    id: "s_sagar", name: "Sagar Bhosale", phone: "9890112233", city: "Talegaon", source: "telegram", language: "marathi-english", status: "engaged",
    objections: ["fees"], ai: 57, counsellor: "Priya (sample)", rec: ["qa", "Quickest affordable switch: Software Testing."], apt: "beginner",
    summary: ["B.A. graduate, works in a shop.", "Budget is tight.", "Next: EMI and Referral scholarship."],
    profile: { education: "B.A.", currentWork: "Shop assistant", budget: "Tight", codingExperience: "none" },
    followup: "Sagar, Software Testing 3 EMI madhe bharta yeto, ani referral scholarship pan aahe. Detail pathvu ka?",
    msgs: [["user", "Testing course chi fee kiti aahe?", 18], ["ai", "Software Testing ₹35,000 aahe, 3 EMI madhe ₹11,700. Tumhala kuthla role hava aahe?", 18]],
  },
  {
    id: "s_nisha", name: "Nisha Gupta", phone: "9820098200", city: "Wagholi", source: "instagram", language: "hinglish", status: "engaged",
    objections: ["job_fear", "trust"], ai: 46, counsellor: "Rohan (sample)",
    summary: ["MBA HR, wants to move into IT.", "Doubts non-tech people get IT jobs.", "Next: honest counselling + demo."],
    profile: { education: "MBA HR", goal: "Move into IT", codingExperience: "none" },
    followup: "Nisha, non-tech se IT mein aana possible hai — shuruaat Python Foundations se karte hain. Demo dekhna chahogi?",
    msgs: [["user", "MBA HR hoon, kya main IT mein ja sakti hoon?", 28], ["ai", "Haan Nisha, lekin honestly daily practice lagegi. Pehle Python Foundations se logic banate hain.", 28]],
  },
  {
    id: "s_rajesh", name: "Rajesh Kumar", phone: "9765432109", city: "Pimpri", source: "walkin", language: "hi", status: "demo_booked",
    objections: ["family_approval"], ai: 74, counsellor: "Rohan (sample)", rec: ["py", "12th commerce, no coding: Python Foundations."], apt: "beginner", bookDay: 2,
    summary: ["12th commerce, 19 years old.", "Wants parents at the demo.", "Python demo booked with parents."],
    profile: { education: "12th Commerce", codingExperience: "none", familyView: "Parents will attend demo" },
    followup: "राजेश, डेमो क्लास में माता-पिता का स्वागत है!",
    msgs: [["user", "[Walk-in] Rajesh Kumar · माता-पिता के साथ डेमो देखना है", 8]],
  },
  {
    id: "s_tanvi", name: "Tanvi Deshpande", phone: "9881198811", city: "Kothrud", source: "web", language: "en", status: "admitted",
    objections: [], ai: 93, counsellor: "Ayesha (sample)", rec: ["ds", "Statistics graduate: Data Science & AI."], apt: "strong",
    summary: ["M.Sc Statistics.", "Chose Data Science after demo.", "Admitted, Women in Tech scholarship."],
    profile: { education: "M.Sc Statistics", goal: "Data scientist", codingExperience: "some" },
    followup: "",
    msgs: [["user", "Is there any scholarship for women in data science?", 120], ["ai", "Yes Tanvi — the Women in Tech scholarship gives 10% off Data Science & AI.", 120]],
  },
  {
    id: "s_yash", name: "Yash Thakur", phone: "9970011223", city: "Ravet", source: "whatsapp", language: "hinglish", status: "engaged",
    objections: [], ai: 66, counsellor: "Rohan (sample)", apt: "in_progress",
    summary: ["BCA 2nd year.", "Doing the aptitude check now.", "Next: finish check, then recommend."],
    profile: { education: "BCA 2nd year", codingExperience: "beginner", goal: "Developer" },
    followup: "Yash, aptitude check ke 2 sawaal baaki hain — continue karein?",
    msgs: [["user", "haan aptitude check karte hain", 1], ["ai", "Badhiya! Pehla sawaal: What comes next: 3, 6, 12, 24, ?\nA) 36\nB) 48\nC) 30", 1], ["user", "B", 1]],
  },
  {
    id: "s_gauri", name: "Gauri Mane", phone: "9112233445", city: "Nigdi", source: "form", language: "mr", status: "new",
    objections: [], ai: 32, counsellor: "Priya (sample)",
    summary: ["Website form, MERN interest.", "No conversation yet.", "Next: first message."],
    profile: {},
    followup: "गौरी, MERN कोर्सबद्दल काही प्रश्न आहेत का?",
    msgs: [["user", "[Website form] Gauri Mane · Interested in: MERN", 2]],
  },
  {
    id: "s_sameer", name: "Sameer Khan", phone: "9930099300", city: "Kondhwa", source: "call", language: "hinglish", status: "engaged",
    objections: ["fees", "time"], ai: 44, counsellor: "Rohan (sample)",
    summary: ["Delivery job, wants evening classes.", "Fees and time both concerns.", "Next: weekday evening batch + EMI."],
    profile: { currentWork: "Delivery partner", timing: "Evenings", budget: "EMI needed" },
    followup: "Sameer bhai, weekday evening batch hai aur EMI bhi. Details bhejun?",
    msgs: [["user", "[Missed call] Sameer Khan", 36], ["ai", "Sameer ji, aapne call kiya tha. Aap kaunsa course dekh rahe hain?", 36], ["user", "Shaam ko time milta hai sirf", 35]],
  },
  {
    id: "s_kavya", name: "Kavya Reddy", phone: "9000012345", city: "Baner", source: "instagram", language: "en", status: "new",
    objections: [], ai: 28, counsellor: "Ayesha (sample)",
    summary: ["Asked about DevOps from an Instagram ad.", "Background unknown.", "Next: ask background."],
    profile: {},
    followup: "Hi Kavya! Are you working in IT right now? That helps me suggest the right DevOps path.",
    msgs: [["user", "DevOps course details pls", 4]],
  },
  {
    id: "s_om", name: "ओम जाधव", phone: "9850098500", city: "Chinchwad", source: "whatsapp", language: "mr", status: "demo_booked",
    objections: ["fees"], ai: 76, counsellor: "Priya (sample)", rec: ["py", "12th science, new to coding: Python Foundations."], apt: "intermediate", bookDay: 4,
    summary: ["12th science, new to coding.", "Fees a concern; Early Bird interests him.", "Python demo booked."],
    profile: { education: "12th Science", codingExperience: "none", budget: "Wants Early Bird" },
    followup: "ओम, बॅच सुरू होण्याच्या ७ दिवस आधी पूर्ण फी भरल्यास Early Bird मिळतो.",
    msgs: [["user", "पायथन कोर्सला काही डिस्काउंट आहे का?", 16], ["ai", "ओम, फक्त यादीतील शिष्यवृत्ती: Early Bird ₹5,000 सूट — बॅच सुरू होण्याच्या ७ दिवस आधी पूर्ण फी भरल्यास.", 16]],
  },
  {
    id: "s_ritu", name: "Ritu Singh", phone: "9811098110", city: "Hinjewadi", source: "googleform", language: "en", status: "engaged",
    objections: ["job_fear"], ai: 61, counsellor: "Ayesha (sample)", rec: ["qa", "Manual testing at a startup: Selenium automation is the next step."],
    summary: ["Manual tester at a startup.", "Afraid of layoffs, wants automation.", "Next: Selenium module details."],
    profile: { currentWork: "Manual tester", codingExperience: "beginner", goal: "Automation tester" },
    followup: "Hi Ritu, the Testing course covers Selenium with Java and API testing — want to see a demo?",
    msgs: [["user", "[Google Form] Ritu Singh · Interested in: Automation testing", 30]],
  },
  {
    id: "s_aditya", name: "Aditya Kulkarni", phone: "9765098765", city: "Shivajinagar", source: "web", language: "marathi-english", status: "engaged",
    objections: ["family_approval", "fees"], ai: 54, counsellor: "Priya (sample)", rec: ["fsj", "B.E. Civil wants IT: Full Stack Java after Python basics."], apt: "intermediate",
    summary: ["B.E. Civil 2025, wants to switch to IT.", "Parents want him in civil; fees a concern.", "Next: parent at demo + EMI."],
    profile: { education: "B.E. Civil 2025", goal: "Software developer", familyView: "Parents prefer civil", codingExperience: "beginner" },
    followup: "Aditya, aai-babanna demo la gheun ye, ani EMI option pan sangto.",
    msgs: [["user", "Civil engineer aahe, IT madhe jaycha aahe pan gharche nahi mhantat", 50], ["ai", "Samajla Aditya. Gharchyanna demo class la ghevun ya — trainer tyanna career path samjavtil.", 50]],
  },
  {
    id: "s_zoya", name: "Zoya Ansari", phone: "9819098190", city: "Kondhwa", source: "telegram", language: "hinglish", status: "demo_booked",
    objections: [], ai: 79, counsellor: "Rohan (sample)", rec: ["mern", "B.Sc IT with JavaScript basics: MERN."], apt: "strong", bookDay: 5,
    summary: ["B.Sc IT, knows JavaScript basics.", "Wants a web developer job.", "MERN demo booked."],
    profile: { education: "B.Sc IT", codingExperience: "some", goal: "Web developer" },
    followup: "Zoya, demo ke liye ready? 😊",
    msgs: [["user", "MERN ka demo book karna hai", 6], ["ai", "Zoya, kaunsa slot suit karega?", 6], ["user", "Weekend wala", 6]],
  },
];

/** Creates or refreshes the 30 sample leads. */
export async function seedLeads(now: Date): Promise<number> {
  let n = 0;
  const slots = await db.collection("slots").where("startAt", ">", Timestamp.fromDate(now)).orderBy("startAt").limit(60).get();
  const demoSlots = slots.docs.filter((d) => (d.get("kind") ?? "demo") === "demo");
  for (const p of P) {
    const ref = db.doc(`leads/${p.id}`);
    const lastHours = p.msgs.length ? Math.min(...p.msgs.map((m) => m[2])) : 24;
    const firstHours = p.msgs.length ? Math.max(...p.msgs.map((m) => m[2])) : 24;
    const userCount = p.msgs.filter((m) => m[0] === "user").length;
    let booking: Lead["booking"] | undefined;
    if (p.bookDay !== undefined) {
      const slot = demoSlots.find((d) => {
        const at = (d.get("startAt") as Timestamp).toDate();
        return at.getTime() > now.getTime() + p.bookDay! * 20 * HOUR && (d.get("courseId") === p.rec?.[0] || !p.rec);
      }) ?? demoSlots[0];
      if (slot) {
        const s = slot.data();
        const start = (s.startAt as Timestamp).toDate();
        booking = {
          slotId: slot.id,
          startAt: s.startAt as Timestamp,
          title: String(s.title),
          calendarUrl: googleCalendarUrl(`Demo class: ${s.title}`, start, Number(s.durationMin ?? 60), "SechTummit Trainers free demo class", "Pimpri-Chinchwad, Pune"),
          reminded24: false,
          reminded1: false,
        };
      }
    }
    const aptitude =
      p.apt === "in_progress"
        ? { status: "in_progress", asked: ["m1"], answers: [], current: "m1", level: 2, correct: 0, points: 0 }
        : p.apt
          ? {
              status: "done",
              asked: ["m1", "h1", "h2", "h3"],
              answers: [],
              level: p.apt === "strong" ? 3 : p.apt === "intermediate" ? 2 : 1,
              correct: p.apt === "strong" ? 4 : p.apt === "intermediate" ? 2 : 1,
              points: p.apt === "strong" ? 11 : p.apt === "intermediate" ? 5 : 2,
              band: p.apt,
              result: p.apt === "strong" ? "4/4 correct, reached hard level, 11/11 points (strong)." : p.apt === "intermediate" ? "2/4 correct, reached medium level, 5/11 points (intermediate)." : "1/4 correct, stayed at easy level, 2/11 points (beginner).",
            }
          : { status: "not_started", asked: [], answers: [], level: 2, correct: 0, points: 0 };
    const sources = (p.sources ?? [p.source]) as Lead["sources"];
    const lead: Lead = {
      name: p.name,
      phone: p.phone,
      city: p.city,
      language: p.language,
      status: p.status,
      objections: p.objections,
      profile: p.profile,
      sources,
      firstSource: p.source as Lead["firstSource"],
      lastChannel: p.source as Lead["lastChannel"],
      userMessages: userCount,
      recommendation: p.rec ? { courseId: p.rec[0], courseName: SAMPLE_COURSE_NAMES[p.rec[0]] ?? p.rec[0], reason: p.rec[1] } : undefined,
      aptitude: aptitude as Lead["aptitude"],
      booking,
      lastInboundAt: Timestamp.fromDate(new Date(now.getTime() - lastHours * HOUR)),
      lastMessageAt: Timestamp.fromDate(new Date(now.getTime() - lastHours * HOUR)),
      aiScore: p.ai,
      summary: p.summary,
      ...(p.source === "whatsapp" ? { waId: `sim:91${p.phone}` } : {}),
      ...(p.source === "telegram" ? { telegramId: `sim:${p.phone}` } : {}),
      ...(p.source === "instagram" ? { igId: `sim:${p.id}` } : {}),
    };
    const sc = computeScore({ lead, aiScore: p.ai, userTexts: p.msgs.filter((m) => m[0] === "user").map((m) => m[1]), now });
    lead.score = sc.score;
    const na = p.followup ? decideNextAction({ lead, now, aiMessage: p.followup }) : null;
    const doc: Record<string, unknown> = {
      ...JSON.parse(JSON.stringify({ ...lead, booking: undefined, lastInboundAt: undefined, lastMessageAt: undefined })),
      ...(booking ? { booking } : {}),
      lastInboundAt: lead.lastInboundAt,
      lastMessageAt: lead.lastMessageAt,
      nameLatin: p.name,
      score: sc.score,
      temperature: sc.temperature,
      scoreBreakdown: sc.breakdown,
      suggestedMessage: p.followup,
      assignedTo: p.counsellor,
      contacts: [{ name: p.name, phone: p.phone, relation: p.relation ?? "self", channel: p.source, isPrimary: true }],
      contactPhones: [p.phone],
      ...(p.studentName ? { studentName: p.studentName } : {}),
      seed: true,
      createdAt: Timestamp.fromDate(new Date(now.getTime() - firstHours * HOUR)),
    };
    if (na) doc.nextAction = na;
    await ref.set(doc);
    const old = await ref.collection("messages").get();
    const batch = db.batch();
    old.docs.forEach((d) => batch.delete(d.ref));
    p.msgs.forEach((m, i) => {
      batch.set(ref.collection("messages").doc(`seed_${i}`), {
        role: m[0],
        channel: p.source,
        text: m[1],
        seed: true,
        createdAt: Timestamp.fromDate(new Date(now.getTime() - m[2] * HOUR + i * 1000)),
        meta: m[0] === "counsellor" ? { by: p.counsellor } : {},
      });
    });
    await batch.commit();
    n++;
  }
  return n;
}

const SAMPLE_COURSE_NAMES: Record<string, string> = Object.fromEntries(SAMPLE_KB.courses.map((c) => [c.id, c.name]));

export async function clearSeed(): Promise<number> {
  const snap = await db.collection("leads").where("seed", "==", true).limit(200).get();
  for (const d of snap.docs) {
    const msgs = await d.ref.collection("messages").get();
    const batch = db.batch();
    msgs.docs.forEach((m) => batch.delete(m.ref));
    batch.delete(d.ref);
    await batch.commit();
  }
  return snap.size;
}
