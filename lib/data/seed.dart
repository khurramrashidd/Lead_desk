import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/repo.dart';
import '../utils/ist.dart';

/// SAMPLE knowledge base in TechSummitTrainers' style.
/// Replace it with the sponsor's real courses from the Admin screen.
const Map<String, dynamic> sampleKnowledgeBase = {
  'instituteName': 'TechSummitTrainers',
  'city': 'Pune',
  'address': 'Pimpri, Pune (sample address)',
  'courses': [
    {
      'id': 'py',
      'name': 'Python Foundations',
      'durationWeeks': 6,
      'mode': 'Online live or classroom (Pimpri)',
      'feeInr': 12000,
      'emi': {'months': 2, 'perMonthInr': 6000},
      'prerequisites': 'None. Starts from zero.',
      'idealFor': 'Non-CS graduates, career-gap returners and anyone who has never coded.',
      'outcomes': 'Programming basics, problem solving, 2 mini projects. Recommended first step before Full Stack or Data Science.',
      'nextBatch': '27 Oct 2026, weekday evenings',
    },
    {
      'id': 'fsj',
      'name': 'Full Stack Java Developer',
      'durationWeeks': 24,
      'mode': 'Hybrid: classroom + live online, all sessions recorded',
      'feeInr': 65000,
      'emi': {'months': 6, 'perMonthInr': 11000},
      'prerequisites': 'Basic logic. Python Foundations or any coding basics recommended for non-CS learners.',
      'idealFor': 'Freshers and graduates of any stream who can give 3-4 hours a day.',
      'outcomes': 'Core Java, Spring Boot 3, React, MySQL, 3 portfolio projects, interview preparation.',
      'nextBatch': '3 Nov 2026 weekday mornings; 8 Nov 2026 weekends',
    },
    {
      'id': 'mern',
      'name': 'MERN Full Stack (JavaScript)',
      'durationWeeks': 20,
      'mode': 'Hybrid',
      'feeInr': 55000,
      'emi': {'months': 5, 'perMonthInr': 11500},
      'prerequisites': 'Basic HTML or any coding basics.',
      'idealFor': 'Learners who want web development with JavaScript end to end.',
      'outcomes': 'JavaScript, React, Node.js, MongoDB, 3 projects.',
      'nextBatch': '10 Nov 2026',
    },
    {
      'id': 'ds',
      'name': 'Data Science & AI with Python',
      'durationWeeks': 24,
      'mode': 'Hybrid',
      'feeInr': 75000,
      'emi': {'months': 6, 'perMonthInr': 12800},
      'prerequisites': 'Python basics and 12th-standard maths.',
      'idealFor': 'Graduates comfortable with numbers who want analytics or ML roles.',
      'outcomes': 'Python, SQL, statistics, machine learning, GenAI basics, 4 projects.',
      'nextBatch': '17 Nov 2026',
    },
    {
      'id': 'devops',
      'name': 'DevOps & Cloud',
      'durationWeeks': 16,
      'mode': 'Online live',
      'feeInr': 60000,
      'emi': {'months': 6, 'perMonthInr': 10000},
      'prerequisites': 'Basic Linux and any programming language.',
      'idealFor': 'Working professionals and developers moving to DevOps.',
      'outcomes': 'Linux, Git, Docker, Kubernetes, CI/CD, AWS, 2 projects.',
      'nextBatch': '15 Nov 2026 weekends',
    },
    {
      'id': 'qa',
      'name': 'Software Testing (Manual + Selenium)',
      'durationWeeks': 12,
      'mode': 'Classroom (Pimpri) or online live',
      'feeInr': 35000,
      'emi': {'months': 3, 'perMonthInr': 11700},
      'prerequisites': 'None.',
      'idealFor': 'Graduates of any stream who want a quicker entry into IT.',
      'outcomes': 'Manual testing, Selenium with Java, API testing, 1 live project.',
      'nextBatch': '1 Nov 2026',
    },
  ],
  'scholarships': [
    {'id': 'early', 'name': 'Early Bird', 'rule': 'Pay the full fee at least 7 days before the batch starts.', 'amountOffInr': 5000},
    {'id': 'women', 'name': 'Women in Tech', 'rule': 'For women learners in Full Stack Java and Data Science only.', 'percentOff': 10},
    {'id': 'referral', 'name': 'Referral', 'rule': 'When referred by a current or past student.', 'amountOffInr': 3000},
  ],
  'policies': {
    'placement':
        'Placement assistance for learners with 80% attendance who complete all projects: resume building, mock interviews and referrals to hiring partners. We do NOT guarantee a job or a salary.',
    'emi': 'Zero-interest EMI directly with the institute. First instalment at admission.',
    'refund': 'Full refund if you leave within 7 days of the batch start. No refund after that.',
    'demo': 'Free 60-minute demo class, online or at the Pimpri centre. Parents are welcome.',
    'recordings': 'Every session is recorded; recordings stay available for 1 year.',
    'batches': 'Weekday batches: Mon-Fri, 2 hours a day. Weekend batches: Sat-Sun, 4 hours a day.',
    'discounts': 'No discounts other than the listed scholarships. Only one scholarship per learner.',
  },
  'faqs': [
    {'q': 'Can a non-IT or commerce graduate become a developer?', 'a': 'Yes, many do. Start with Python Foundations to build logic, then move to Full Stack. It needs consistent daily practice.'},
    {'q': 'Is there an age limit?', 'a': 'No age limit.'},
    {'q': 'Do I need a laptop?', 'a': 'Yes, any laptop with 8 GB RAM. Classroom learners can use lab machines.'},
  ],
};

class Seed {
  /// IST wall-clock time -> real UTC instant.
  static DateTime _istToUtc(DateTime istDay, int hour, int minute) =>
      DateTime.utc(istDay.year, istDay.month, istDay.day, hour, minute).subtract(const Duration(hours: 5, minutes: 30));

  static Future<void> loadKnowledgeBase() =>
      Repo.db.doc('kb/main').set({...sampleKnowledgeBase, 'updatedAt': FieldValue.serverTimestamp()});

  /// Demo-class calendar for the next 7 days (capacity-limited, no double booking).
  static Future<int> loadSlots() async {
    final batch = Repo.db.batch();
    final today = Ist.now();
    var count = 0;
    final plan = <List<Object>>[
      [11, 0, 'Full Stack Java — demo class', 'Online live', 'fsj'],
      [17, 0, 'Python Foundations — demo class', 'Classroom, Pimpri', 'py'],
      [19, 0, 'Data Science & AI — demo class', 'Online live', 'ds'],
    ];
    for (var d = 0; d <= 7; d++) {
      final day = DateTime.utc(today.year, today.month, today.day).add(Duration(days: d));
      for (final p in plan) {
        final start = _istToUtc(day, p[0] as int, p[1] as int);
        if (start.isBefore(DateTime.now().add(const Duration(hours: 1)))) continue;
        final id = 'slot_${day.year}${_pad2(day.month)}${_pad2(day.day)}_${_pad2(p[0] as int)}${_pad2(p[1] as int)}';
        batch.set(Repo.db.collection('slots').doc(id), {
          'title': p[2],
          'mode': p[3],
          'courseId': p[4],
          'startAt': Timestamp.fromDate(start),
          'durationMin': 60,
          'capacity': 10,
          'booked': 0,
        });
        count++;
      }
    }
    await batch.commit();
    return count;
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  /// Realistic demo leads so the dashboard and reports look alive.
  static Future<void> loadDemoLeads() async {
    final now = DateTime.now();
    Timestamp ago(int hours) => Timestamp.fromDate(now.subtract(Duration(hours: hours)));
    final leads = <String, Map<String, dynamic>>{
      'demo_rahul_form': {
        'name': 'Rahul Patil', 'phone': '9876543210', 'firstSource': 'form', 'sources': ['form'],
        'status': 'new', 'score': 35, 'temperature': 'cold', 'city': 'Pimpri',
        'summary': ['Filled the website form for Full Stack Java.', 'No conversation yet.', 'Next: first call or WhatsApp.'],
        'objections': <String>[], 'createdAt': ago(30), 'lastMessageAt': ago(30), 'assignedTo': 'Priya',
      },
      'demo_sneha': {
        'name': 'Sneha Kulkarni', 'phone': '9822011223', 'firstSource': 'instagram', 'sources': ['instagram', 'web'],
        'status': 'demo_booked', 'score': 82, 'temperature': 'hot', 'city': 'Wakad', 'language': 'marathi-english',
        'summary': ['BCom 2022, 2-year gap, wants to become a developer.', 'Worried about the gap and fees; parents supportive.', 'Demo booked for Python Foundations.'],
        'objections': ['fees', 'job_fear'], 'createdAt': ago(50), 'lastMessageAt': ago(3), 'assignedTo': 'Priya',
        'suggestedMessage': 'Sneha, tumcha demo udya aahe. Kahi prashna aslyas nakki vichara!',
      },
      'demo_amit': {
        'name': 'Amit Shinde', 'phone': '9765012345', 'firstSource': 'whatsapp', 'sources': ['whatsapp'],
        'status': 'admitted', 'score': 95, 'temperature': 'hot', 'city': 'Chinchwad',
        'summary': ['BE Mechanical, working in sales.', 'Wanted weekend batch.', 'Admitted to Full Stack Java (weekend).'],
        'objections': ['time'], 'createdAt': ago(200), 'lastMessageAt': ago(40), 'assignedTo': 'Amit',
      },
      'demo_pooja': {
        'name': 'Pooja Jadhav', 'phone': '9890098900', 'firstSource': 'walkin', 'sources': ['walkin'],
        'status': 'engaged', 'score': 58, 'temperature': 'warm', 'city': 'Pimpri',
        'summary': ['12th + BSc, interested in Data Science.', 'Father wants to meet the trainer first.', 'Next: invite father to demo.'],
        'objections': ['family_approval'], 'createdAt': ago(26), 'lastMessageAt': ago(20), 'assignedTo': 'Amit',
      },
      'demo_imran': {
        'name': 'Imran Shaikh', 'phone': '9970099700', 'firstSource': 'call', 'sources': ['call'],
        'status': 'lost', 'score': 15, 'temperature': 'cold', 'city': 'Nigdi',
        'summary': ['Looking for a free course.', 'Fees too high, no EMI interest.', 'Marked lost.'],
        'objections': ['fees'], 'createdAt': ago(300), 'lastMessageAt': ago(250), 'assignedTo': 'Priya',
      },
      'demo_kiran': {
        'name': 'Kiran More', 'phone': '9011090110', 'firstSource': 'instagram', 'sources': ['instagram'],
        'status': 'admitted', 'score': 90, 'temperature': 'hot', 'city': 'Akurdi',
        'summary': ['Final-year BCA.', 'Chose MERN after demo.', 'Admitted, paid first EMI.'],
        'objections': <String>[], 'createdAt': ago(400), 'lastMessageAt': ago(100), 'assignedTo': 'Priya',
      },
      'demo_neha': {
        'name': 'Neha Gaikwad', 'phone': '9637096370', 'firstSource': 'web', 'sources': ['web'],
        'status': 'engaged', 'score': 64, 'temperature': 'warm', 'city': 'Pune',
        'summary': ['Working in BPO, wants testing role.', 'Can study only on weekends.', 'Next: share weekend Testing batch.'],
        'objections': ['time'], 'createdAt': ago(70), 'lastMessageAt': ago(60), 'assignedTo': 'Amit',
      },
      'demo_suresh': {
        'name': 'Suresh Pawar', 'phone': '9545095450', 'firstSource': 'walkin', 'sources': ['walkin'],
        'status': 'admitted', 'score': 88, 'temperature': 'hot', 'city': 'Pimpri',
        'summary': ['Walked in with his father.', 'Liked classroom batch.', 'Admitted to Software Testing.'],
        'objections': ['family_approval'], 'createdAt': ago(500), 'lastMessageAt': ago(300), 'assignedTo': 'Amit',
      },
    };
    final batch = Repo.db.batch();
    leads.forEach((id, data) => batch.set(Repo.leads.doc(id), {...data, 'demo': true, 'lastChannel': 'web'}));
    await batch.commit();
  }
}
