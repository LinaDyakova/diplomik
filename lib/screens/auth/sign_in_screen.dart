import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vroom/supabase/supabase_config.dart';

// Необходимо убедиться, что в таблице profiles есть уникальное ограничение на поле username.
// Выполните в SQL-редакторе Supabase:
// CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_key ON profiles (username);

class SignInScreen extends StatefulWidget {
  const SignInScreen({Key? key}) : super(key: key);

  @override
  _SignInScreenState createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();

  bool _isLoading = false;
  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _isCheckingUsername = false;

  String? _emailError;
  String? _passwordError;
  String? _usernameError;

  // ========== Валидация ==========
  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Введите email';
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) return 'Введите корректный email (например, name@example.com)';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.trim().isEmpty) return 'Введите пароль';
    if (value.trim().length < 6) return 'Пароль должен содержать не менее 6 символов';
    return null;
  }

  String? _validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) return 'Введите имя пользователя';
    if (value.trim().length < 3) return 'Имя пользователя должно содержать не менее 3 символов';
    return null;
  }

  bool _validateFields() {
    setState(() {
      _emailError = _validateEmail(_emailController.text);
      _passwordError = _validatePassword(_passwordController.text);
      if (_isSignUp) {
        _usernameError = _validateUsername(_usernameController.text);
      } else {
        _usernameError = null;
      }
    });
    return _emailError == null && _passwordError == null && _usernameError == null;
  }

  // Простая проверка уникальности (не надёжна из-за RLS, но оставлена как есть)
  Future<bool> _isUsernameUnique(String username) async {
    final response = await SupabaseConfig.client
        .from('profiles')
        .select('username')
        .eq('username', username.trim())
        .maybeSingle();
    return response == null;
  }

  void _onEmailChanged(String _) {
    if (_emailError != null) setState(() => _emailError = _validateEmail(_emailController.text));
  }

  void _onPasswordChanged(String _) {
    if (_passwordError != null) setState(() => _passwordError = _validatePassword(_passwordController.text));
  }

  void _onUsernameChanged(String _) {
    if (_usernameError != null && _isSignUp) {
      setState(() => _usernameError = _validateUsername(_usernameController.text));
    }
  }

  // ========== Вход ==========
  Future<void> _signIn() async {
    if (!_validateFields()) return;
    setState(() => _isLoading = true);
    try {
      await SupabaseConfig.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } on AuthException catch (error) {
      String message = error.message;
      if (message.contains('Invalid login credentials')) {
        setState(() => _passwordError = 'Неверный email или пароль');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ========== Регистрация с обработкой дубликата username ==========
  Future<void> _signUp() async {
    // 1. Валидация полей
    if (!_validateFields()) return;

    // 2. Проверка уникальности (может не сработать из-за RLS, но лишней не будет)
    setState(() {
      _isCheckingUsername = true;
      _usernameError = null;
    });
    final username = _usernameController.text.trim();
    final isUnique = await _isUsernameUnique(username);
    if (!isUnique) {
      setState(() {
        _usernameError = 'Пользователь с именем "$username" уже существует';
        _isCheckingUsername = false;
      });
      return;
    }
    setState(() => _isCheckingUsername = false);

    setState(() => _isLoading = true);
    try {
      // 3. Создание аутентификационной записи
      final response = await SupabaseConfig.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (response.user != null) {
        // 4. Создание профиля (может выбросить PostgrestException при дубликате username)
        try {
          await SupabaseConfig.client.from('profiles').upsert({
            'id': response.user!.id,
            'username': username,
            'bio': '',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
        } on PostgrestException catch (insertError) {
          // Если нарушено уникальное ограничение (дубликат username)
          if (insertError.message.contains('duplicate key') ||
              insertError.message.contains('unique constraint')) {
            setState(() => _usernameError = 'Это имя пользователя уже занято');
            // Удаляем только что созданного пользователя, чтобы не было "сирот"
            await SupabaseConfig.auth.admin.deleteUser(response.user!.id);
            if (mounted) setState(() => _isLoading = false);
            return;
          } else {
            // Другая ошибка – пробрасываем дальше
            rethrow;
          }
        }

        // Успешная регистрация
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Регистрация успешна! Теперь войдите.')),
        );
        setState(() {
          _isSignUp = false;
          _passwordController.clear();
          _emailError = null;
          _passwordError = null;
          _usernameError = null;
        });
      }
    } on AuthException catch (error) {
      String message = error.message;
      if (message.contains('User already registered')) {
        setState(() => _emailError = 'Пользователь с таким email уже зарегистрирован');
      } else if (message.contains('password')) {
        setState(() => _passwordError = message);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } on PostgrestException catch (error) {
      // Любые другие ошибки базы данных (не связанные с уникальностью)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка базы данных: ${error.message}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ========== Интерфейс (минималистичный дизайн) ==========
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  // Логотип
                  const Icon(
                    Icons.directions_car,
                    size: 72,
                    color: Colors.black87,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Vroom',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    _isSignUp ? 'Создайте аккаунт' : 'Войдите в аккаунт',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_isSignUp)
                    _buildTextField(
                      controller: _usernameController,
                      label: 'Имя пользователя',
                      icon: Icons.person_outline,
                      errorText: _usernameError,
                      onChanged: _onUsernameChanged,
                    ),
                  _buildTextField(
                    controller: _emailController,
                    label: 'Email',
                    icon: Icons.email_outlined,
                    errorText: _emailError,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: _onEmailChanged,
                  ),
                  _buildTextField(
                    controller: _passwordController,
                    label: 'Пароль',
                    icon: Icons.lock_outline,
                    errorText: _passwordError,
                    obscureText: _obscurePassword,
                    onChanged: _onPasswordChanged,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else
                    ElevatedButton(
                      onPressed: _isSignUp ? _signUp : _signIn,
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _isSignUp ? 'Зарегистрироваться' : 'Войти',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isSignUp = !_isSignUp;
                        _emailError = null;
                        _passwordError = null;
                        _usernameError = null;
                      });
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.black87),
                    child: Text(
                      _isSignUp
                          ? 'Уже есть аккаунт? Войти'
                          : 'Нет аккаунта? Зарегистрироваться',
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Виджет для поля ввода в едином стиле
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? errorText,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.black54),
          suffixIcon: suffixIcon,
          errorText: errorText,
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.black, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        style: const TextStyle(fontSize: 16),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }
}