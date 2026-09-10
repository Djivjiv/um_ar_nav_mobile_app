import '../../core/utils/json_utils.dart';

class AboutUmModel {
  final String id;
  final String? mission;
  final String? vision;
  final List<String> coreValues;
  final String? founded;
  final String? campusSize;
  final String? location;
  final String? ranking;
  final String? phone;
  final String? email;
  final String? website;
  final String? facebook;
  final String? instagram;
  final String? twitter;

  const AboutUmModel({
    required this.id,
    this.mission,
    this.vision,
    this.coreValues = const [],
    this.founded,
    this.campusSize,
    this.location,
    this.ranking,
    this.phone,
    this.email,
    this.website,
    this.facebook,
    this.instagram,
    this.twitter,
  });

  factory AboutUmModel.fromMap(Map<String, dynamic> m) {
    return AboutUmModel(
      id: J.strOr(m['id']),
      mission: J.str(m['mission']),
      vision: J.str(m['vision']),
      coreValues: J.strList(m['core_values']),
      founded: J.str(m['founded']),
      campusSize: J.str(m['campus_size']),
      location: J.str(m['location']),
      ranking: J.str(m['ranking']),
      phone: J.str(m['phone']),
      email: J.str(m['email']),
      website: J.str(m['website']),
      facebook: J.str(m['facebook']),
      instagram: J.str(m['instagram']),
      twitter: J.str(m['twitter']),
    );
  }

  static const AboutUmModel fallback = AboutUmModel(
    id: 'fallback',
    mission:
        'To provide quality, affordable, and relevant education to help learners '
        'become globally competitive and socially responsible citizens.',
    vision:
        'A leading institution committed to producing empowered graduates who '
        'contribute to nation-building.',
    coreValues: ['Excellence', 'Integrity', 'Service', 'Innovation'],
    founded: '1946',
    campusSize: 'Matina Campus',
    location: 'Matina, Davao City, Philippines',
    ranking: 'Among the largest universities in Mindanao',
    phone: '+63 82 305 0645',
    email: 'info@umindanao.edu.ph',
    website: 'https://www.umindanao.edu.ph',
    facebook: 'https://www.facebook.com/UMindanaoOfficial',
  );
}
