import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/about_um_model.dart';

class AboutRepository {
  final SupabaseClient _client;
  AboutRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  Future<AboutUmModel> getAbout() async {
    try {
      final row =
          await _client.from('about_um').select().limit(1).maybeSingle();
      if (row == null) return AboutUmModel.fallback;
      return AboutUmModel.fromMap(row);
    } catch (_) {
      return AboutUmModel.fallback;
    }
  }
}
