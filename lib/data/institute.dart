import 'seed.dart';

/// Content for the SechTummit Trainers public website.
///
/// Courses, fees and batches come from the SAME knowledge base the AI counsellor
/// is allowed to quote (`sampleKnowledgeBase`), so the website and Asha can never
/// disagree — change a fee in Admin and both update together.
class Institute {
  static const name = 'SechTummit Trainers';
  static const tagline = 'Career-focused IT training in Pimpri-Chinchwad, Pune.';
  static const phone = '+91 98765 43210';
  static const email = 'admissions@sechtummit.example';
  static const address = 'Pimpri-Chinchwad, Pune, Maharashtra 411018';
  static const established = 2016;

  static List<Map<String, dynamic>> get courses =>
      (sampleKnowledgeBase['courses'] as List).cast<Map<String, dynamic>>();

  static List<Map<String, dynamic>> get scholarships =>
      (sampleKnowledgeBase['scholarships'] as List).cast<Map<String, dynamic>>();

  static Map<String, dynamic> get policies =>
      (sampleKnowledgeBase['policies'] as Map).cast<String, dynamic>();

  static List<Map<String, dynamic>> get faqs =>
      (sampleKnowledgeBase['faqs'] as List).cast<Map<String, dynamic>>();

  /// Headline numbers. Demo figures for the hackathon prototype.
  static const stats = [
    ('4,200+', 'learners trained'),
    ('180+', 'hiring partners'),
    ('9 yrs', 'training since 2016'),
    ('4.7/5', 'average batch rating'),
  ];

  /// What the AI counsellor changes for an enquiry — the problem statement, in plain words.
  static const aiPromises = [
    (
      '🌙',
      'Answered at 11 PM, not next morning',
      'Asha, our AI admissions counsellor, replies in seconds at any hour. A prospect who waits till morning has usually moved on.',
    ),
    (
      '🗣',
      'English, हिंदी and मराठी — even mixed',
      'Type or send a voice note in whatever language feels natural. Asha replies in the same language and the same tone.',
    ),
    (
      '🤝',
      'Counselling, not a FAQ bot',
      '"I\'m a commerce graduate with a two-year gap — can I really become a developer?" gets an honest answer about what it takes, not a fee list.',
    ),
    (
      '🛡',
      'Never an invented discount or promise',
      'Every reply is checked against this website\'s course data. If it is not published here, Asha will not promise it.',
    ),
  ];

  static const whyUs = [
    ('👨‍🏫', 'Trainers from industry', 'Every trainer has shipped production software. Classes are built around what teams actually do.'),
    ('🧪', 'Build, not just watch', 'Three graded projects per course, reviewed line by line, that you can show in an interview.'),
    ('🕕', 'Batches that fit a job', 'Weekday mornings, weekday evenings and weekend batches. Every session is recorded for a year.'),
    ('🧭', 'Honest counselling first', 'If a course is wrong for you today, we say so and suggest the right first step.'),
    ('💳', 'Zero-interest EMI', 'Pay in monthly instalments directly to the institute. No third-party loan, no interest.'),
    ('📍', 'Classroom or live online', 'Attend at the Pimpri centre or join the same live class from home. Switch any week.'),
  ];

  /// Invented partner names — this is a prototype, not a claim about real companies.
  static const hiringPartners = ['Nexora Labs', 'Veltrix Systems', 'Aarambh Tech', 'Quantside', 'Bluepeak Digital', 'Orvix Software'];

  /// Illustrative student stories written for the prototype demo.
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
