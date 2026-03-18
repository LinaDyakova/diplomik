import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String supabaseUrl = 'https://nghsldpyskuxnkzvjufi.supabase.co';
  static const String supabaseKey = 'sb_publishable_tZ4FkGsYAtVSL0b7sAMKWg_pYNPjfF3';
  
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseKey,
    );
  }
  
  static SupabaseClient get client => Supabase.instance.client;
  
  static GoTrueClient get auth => Supabase.instance.client.auth;
}