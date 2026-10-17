import 'seed.dart';

/// Content for the SechTummit Trainers public website (a stand-in brand for the hackathon).
///
/// Courses, fees, batches, policies and FAQs are NOT hard-coded here: the website reads the
/// same Firestore document the AI counsellor is allowed to quote (kb/main), so the site and
/// Asha can never disagree. [Kb] wraps that document; `sampleKnowledgeBase` is only the
/// fallback shown before the first load.
class Institute {
  static const name = 'SechTummit Trainers';
  static const tagline = 'Career-focused IT training in Pimpri-Chinchwad, Pune.';
  static const phone = '+91 98765 43210';
  static const email = 'admissions@sechtummit.example';
  static const address = 'Pimpri-Chinchwad, Pune, Maharashtra 411018 (sample)';
  static const established = 2016;

  // Older call sites read the sample directly.
  static List<Map<String, dynamic>> get courses => Kb.sample.courses;
  static List<Map<String, dynamic>> get scholarships => Kb.sample.scholarships;
  static Map<String, dynamic> get policies => Kb.sample.policies;
  static List<Map<String, dynamic>> get faqs => Kb.sample.faqs;

  /// Headline numbers. Demo figures for the hackathon prototype.
  static const stats = [
    ('4,200+', 'learners trained'),
    ('180+', 'hiring partners'),
    ('9 yrs', 'training since 2016'),
    ('4.7/5', 'average batch rating'),
  ];

  static const whyUs = [
    ('👨‍🏫', 'Trainers from industry', 'Every trainer has shipped production software. Classes are built around what teams actually do.'),
    ('🧪', 'Build, not just watch', 'Three graded projects per course, reviewed line by line, that you can show in an interview.'),
    ('🕕', 'Batches that fit a job', 'Weekday mornings, weekday evenings and weekend batches. Every session is recorded for a year.'),
    ('🧭', 'Honest counselling first', 'If a course is wrong for you today, we say so and suggest the right first step.'),
    ('💳', 'Zero-interest EMI', 'Pay in monthly instalments directly to the institute. No third-party loan, no interest.'),
    ('📍', 'Classroom or live online', 'Attend at the Pimpri-Chinchwad centre or join the same live class from home. Switch any week.'),
  ];

  /// Invented partner names: this is a prototype, not a claim about real companies.
  static const hiringPartners = ['Nexora Labs', 'Veltrix Systems', 'Aarambh Tech', 'Quantside', 'Bluepeak Digital', 'Orvix Software'];

  /// Illustrative learner stories written for the prototype demo.
  static const stories = [
    (
      'Sneha K.',
      'B.Com 2022 · now Junior Developer',
      'I had a two-year gap and thought it was over for me. They started me on Python instead of selling me the big course, and six months later I had three projects to show.',
    ),
    (
      'Amit S.',
      'Mechanical engineer · now Full Stack Developer',
      'I kept my sales job through the weekend batch. The recordings meant a missed Sunday was not a lost week.',
    ),
    (
      'Pooja J.',
      'B.Sc · now Data Analyst',
      'My father came with me to the demo class and asked all his questions. That is what made the decision easy at home.',
    ),
  ];

  static const placementSupport = [
    'Resume built from your real projects, not adjectives',
    'Mock interviews with the trainers who reviewed your code',
    'Referrals to our hiring partners when you are interview-ready',
    'Aptitude and communication practice every Saturday',
  ];
}

/// Typed view of the knowledge-base document (kb/main).
class Kb {
  Kb(this.raw);
  final Map<String, dynamic> raw;

  static final sample = Kb(sampleKnowledgeBase);

  static Kb from(Map<String, dynamic>? data) => (data == null || data['courses'] is! List) ? sample : Kb(data);

  String get instituteName => '${raw['instituteName'] ?? Institute.name}';
  String get city => '${raw['city'] ?? 'Pune'}';
  bool get isSample => raw['sample'] == true || identical(raw, sampleKnowledgeBase);

  List<Map<String, dynamic>> _list(String k) =>
      ((raw[k] as List?) ?? const []).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();

  List<Map<String, dynamic>> get courses => _list('courses');
  List<Map<String, dynamic>> get scholarships => _list('scholarships');
  List<Map<String, dynamic>> get faqs => _list('faqs');
  Map<String, dynamic> get policies => ((raw['policies'] as Map?) ?? const {}).cast<String, dynamic>();

  Map<String, dynamic>? course(String? id) {
    for (final c in courses) {
      if (c['id'] == id) return c;
    }
    return null;
  }
}
