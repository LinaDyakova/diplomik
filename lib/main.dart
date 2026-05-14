import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vroom/screens/auth/sign_in_screen.dart';
import 'package:vroom/screens/chat/chats_list_screen.dart';
import 'package:vroom/screens/home/main_feed_screen.dart';
import 'package:vroom/screens/events/events_screen.dart';
import 'package:vroom/screens/events/add_event_screen.dart';
import 'package:vroom/screens/profile/profile_screen.dart';
import 'package:vroom/screens/post/post_detail_screen.dart';
import 'package:vroom/supabase/supabase_config.dart';
import 'package:vroom/screens/profile/other_profile_screen.dart';
import 'package:vroom/screens/notifications/notifications_screen.dart';
import 'package:vroom/screens/map/map_screen.dart';
import 'package:vroom/screens/events/event_detail_screen.dart';
import 'package:vroom/screens/welcome_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru', null);
  await SupabaseConfig.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VROOM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.grey,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0.5,
          iconTheme: IconThemeData(color: Colors.black87),
          titleTextStyle: TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        // Нижняя панель без подписей — иконки по центру
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Colors.black87,
          unselectedItemColor: Colors.grey,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black87,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.black, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        colorScheme: ColorScheme.fromSwatch().copyWith(
          secondary: Colors.black87,
        ),
      ),
      initialRoute: '/welcome',
      routes: {
        '/welcome': (context) => const WelcomeScreen(),
        '/signin': (context) => const SignInScreen(),
        '/home': (context) => const MainTabScreen(),
        '/events': (context) => const EventsScreen(),
        '/add_event': (context) => const AddEventScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/notifications': (context) => const NotificationsScreen(),
        '/post_detail': (context) {
          final postId = ModalRoute.of(context)!.settings.arguments as int;
          return PostDetailScreen(postId: postId);
        },
        '/other_profile': (context) {
          final userId = ModalRoute.of(context)!.settings.arguments as String;
          return OtherProfileScreen(userId: userId);
        },
        '/event_detail': (context) {
          final eventId = ModalRoute.of(context)!.settings.arguments as int;
          return EventDetailScreen(eventId: eventId);
        },
      },
    );
  }
}

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({Key? key}) : super(key: key);

  @override
  _MainTabScreenState createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    MainFeedScreen(),
    EventsScreen(),
    ChatsListScreen(),
    ProfileScreen(),
    MapScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _screens[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) => setState(() => _selectedIndex = index),
            iconSize: 28,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: '',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.event_outlined),
                activeIcon: Icon(Icons.event),
                label: '',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.chat_outlined),
                activeIcon: Icon(Icons.chat),
                label: '',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outlined),
                activeIcon: Icon(Icons.person),
                label: '',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.map_outlined),
                activeIcon: Icon(Icons.map),
                label: '',
              ),
            ],
          ),
        ),
      ),
    );
  }
}