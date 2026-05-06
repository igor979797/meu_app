import "dart:convert";
import "dart:io";

import "package:crypto/crypto.dart";
import "package:flutter/material.dart";
import "package:image_picker/image_picker.dart";
import "package:path/path.dart" as p;
import "package:shared_preferences/shared_preferences.dart";
import "package:sqflite/sqflite.dart";
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit(); // 🔥 inicializa SQLite no desktop
  databaseFactory = databaseFactoryFfi;

  runApp(const PrimeDietApp());
}

class PrimeDietApp extends StatefulWidget {
  const PrimeDietApp({super.key});

  @override
  State<PrimeDietApp> createState() => _PrimeDietAppState();
}

class _PrimeDietAppState extends State<PrimeDietApp> {
  int? _userId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final userId = await SessionStore.getUserId();
    if (!mounted) return;
    setState(() {
      _userId = userId;
      _loading = false;
    });
  }

  Future<void> _onAuthenticated(int userId) async {
    await SessionStore.setUserId(userId);
    if (!mounted) return;
    setState(() => _userId = userId);
  }

  Future<void> _onLogout() async {
    await SessionStore.clearSession();
    if (!mounted) return;
    setState(() => _userId = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Prime Diet",
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF59C58A),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF101217),
      ),
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (_userId == null
                ? AuthScreen(onAuthenticated: _onAuthenticated)
                : HomeScreen(userId: _userId!, onLogout: _onLogout)),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onAuthenticated});

  final Future<void> Function(int userId) onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  String _feedback = "";
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final db = AppDatabase.instance;
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.length < 4 || (!_isLogin && name.isEmpty)) {
      setState(() {
        _feedback = "Preencha os campos corretamente.";
        _busy = false;
      });
      return;
    }

    if (_isLogin) {
      final userId = await db.login(email, password);
      if (userId == null) {
        setState(() {
          _feedback = "Credenciais invalidas.";
          _busy = false;
        });
        return;
      }
      await widget.onAuthenticated(userId);
    } else {
      final ok = await db.register(name, email, password);
      setState(() {
        _feedback = ok ? "Conta criada. Faca login." : "Email ja cadastrado.";
        if (ok) _isLogin = true;
        _busy = false;
      });
      return;
    }

    if (mounted) {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        "PRIMEDIET",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF79D89E),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: true, label: Text("Login")),
                          ButtonSegment(value: false, label: Text("Cadastro")),
                        ],
                        selected: {_isLogin},
                        onSelectionChanged: (values) {
                          setState(() {
                            _isLogin = values.first;
                            _feedback = "";
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      if (!_isLogin) ...[
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(labelText: "Nome"),
                        ),
                        const SizedBox(height: 10),
                      ],
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: "Email"),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: "Senha"),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Text(_isLogin ? "Entrar" : "Criar conta"),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _feedback,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.userId, required this.onLogout});

  final int userId;
  final Future<void> Function() onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Meal> _meals = [];
  int _waterMl = 1500;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final db = AppDatabase.instance;
    final meals = await db.getTodayMeals(widget.userId);
    final water = await SessionStore.getWaterMl(widget.userId);
    if (!mounted) return;
    setState(() {
      _meals = meals;
      _waterMl = water;
      _loading = false;
    });
  }

  Future<void> _addWater() async {
    final next = _waterMl + 250;
    await SessionStore.setWaterMl(widget.userId, next);
    if (!mounted) return;
    setState(() => _waterMl = next);
  }

  Future<void> _deleteMeal(Meal meal) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Excluir refeicao"),
        content: const Text("Deseja realmente excluir esta refeicao?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Excluir"),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await AppDatabase.instance.deleteMeal(widget.userId, meal.id!);
    await _refresh();
  }

  Future<void> _openMealForm({Meal? meal}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MealFormScreen(userId: widget.userId, meal: meal),
      ),
    );
    if (changed == true) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalCalories = _meals.fold<int>(0, (sum, meal) => sum + meal.calories);
    final caloriesProgress = (totalCalories / 2000).clamp(0, 1).toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Prime Diet - Hoje"),
        actions: [
          IconButton(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
            tooltip: "Sair",
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openMealForm(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _MetricCard(
                    title: "Calorias",
                    value: "$totalCalories / 2000",
                    trailing: LinearProgressIndicator(value: caloriesProgress),
                  ),
                  const SizedBox(height: 12),
                  _MetricCard(
                    title: "Agua",
                    value: "${(_waterMl / 1000).toStringAsFixed(2)} L",
                    trailing: OutlinedButton(
                      onPressed: _addWater,
                      child: const Text("+250ml"),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    "Refeicoes do dia",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (_meals.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text("Nenhuma refeicao registrada hoje."),
                      ),
                    ),
                  ..._meals.map(
                    (meal) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (meal.photoPath != null && meal.photoPath!.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  File(meal.photoPath!),
                                  height: 120,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                ),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              "${meal.mealType}: ${meal.name} (${meal.calories} kcal)",
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _openMealForm(meal: meal),
                                  icon: const Icon(Icons.edit),
                                  label: const Text("Editar"),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _deleteMeal(meal),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text("Excluir"),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class MealFormScreen extends StatefulWidget {
  const MealFormScreen({super.key, required this.userId, this.meal});

  final int userId;
  final Meal? meal;

  @override
  State<MealFormScreen> createState() => _MealFormScreenState();
}

class _MealFormScreenState extends State<MealFormScreen> {
  final _nameController = TextEditingController();
  final _caloriesController = TextEditingController();
  String _mealType = "Cafe da manha";
  String? _photoPath;
  bool _busy = false;

  bool get _isEditing => widget.meal != null;

  @override
  void initState() {
    super.initState();
    final meal = widget.meal;
    if (meal != null) {
      _nameController.text = meal.name;
      _caloriesController.text = meal.calories.toString();
      _mealType = meal.mealType;
      _photoPath = meal.photoPath;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _caloriesController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (!mounted) return;
    if (file == null) return;
    setState(() => _photoPath = file.path);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final calories = int.tryParse(_caloriesController.text.trim()) ?? 0;
    if (name.isEmpty || calories <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Preencha nome e calorias corretamente.")),
      );
      return;
    }

    setState(() => _busy = true);
    final db = AppDatabase.instance;
    if (_isEditing) {
      await db.updateMeal(
        widget.userId,
        Meal(
          id: widget.meal!.id,
          userId: widget.userId,
          name: name,
          calories: calories,
          mealType: _mealType,
          photoPath: _photoPath,
          createdAt: widget.meal!.createdAt,
        ),
      );
    } else {
      await db.insertMeal(
        Meal(
          userId: widget.userId,
          name: name,
          calories: calories,
          mealType: _mealType,
          photoPath: _photoPath,
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? "Editar refeicao" : "Nova refeicao")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: "Nome"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _caloriesController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Calorias"),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _mealType,
            items: const [
              DropdownMenuItem(value: "Cafe da manha", child: Text("Cafe da manha")),
              DropdownMenuItem(value: "Almoco", child: Text("Almoco")),
              DropdownMenuItem(value: "Jantar", child: Text("Jantar")),
              DropdownMenuItem(value: "Lanche", child: Text("Lanche")),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _mealType = value);
            },
            decoration: const InputDecoration(labelText: "Tipo"),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text("Escolher foto da galeria"),
          ),
          if (_photoPath != null && _photoPath!.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_photoPath!),
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Text("Nao foi possivel abrir a imagem."),
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_isEditing ? "Atualizar" : "Salvar"),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.trailing,
  });

  final String title;
  final String value;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            trailing,
          ],
        ),
      ),
    );
  }
}

class Meal {
  const Meal({
    this.id,
    required this.userId,
    required this.name,
    required this.calories,
    required this.mealType,
    required this.photoPath,
    required this.createdAt,
  });

  final int? id;
  final int userId;
  final String name;
  final int calories;
  final String mealType;
  final String? photoPath;
  final String createdAt;

  factory Meal.fromMap(Map<String, Object?> map) {
    return Meal(
      id: map["id"] as int?,
      userId: map["user_id"] as int,
      name: map["name"] as String,
      calories: map["calories"] as int,
      mealType: map["meal_type"] as String,
      photoPath: map["photo_path"] as String?,
      createdAt: map["created_at"] as String,
    );
  }

  Map<String, Object?> toMap() {
    return {
      "id": id,
      "user_id": userId,
      "name": name,
      "calories": calories,
      "meal_type": mealType,
      "photo_path": photoPath,
      "created_at": createdAt,
    };
  }
}

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();
  Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, "prime_diet_flutter.db");
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute("""
          CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        """);
        await db.execute("""
          CREATE TABLE meals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            calories INTEGER NOT NULL,
            meal_type TEXT NOT NULL,
            photo_path TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY(user_id) REFERENCES users(id)
          )
        """);
      },
    );
  }

  Future<Database> get database async {
    await init();
    return _db!;
  }

  Future<bool> register(String name, String email, String password) async {
    final db = await database;
    final existing = await db.query(
      "users",
      columns: ["id"],
      where: "email = ?",
      whereArgs: [email],
      limit: 1,
    );
    if (existing.isNotEmpty) return false;

    await db.insert("users", {
      "name": name,
      "email": email,
      "password_hash": _hash(password),
      "created_at": DateTime.now().toIso8601String(),
    });
    return true;
  }

  Future<int?> login(String email, String password) async {
    final db = await database;
    final rows = await db.query(
      "users",
      columns: ["id", "password_hash"],
      where: "email = ?",
      whereArgs: [email],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    if (row["password_hash"] != _hash(password)) return null;
    return row["id"] as int;
  }

  Future<List<Meal>> getTodayMeals(int userId) async {
    final db = await database;
    final rows = await db.query(
      "meals",
      where: "user_id = ?",
      whereArgs: [userId],
      orderBy: "created_at DESC",
    );

    final now = DateTime.now();
    return rows
        .map(Meal.fromMap)
        .where((meal) {
          final parsed = DateTime.tryParse(meal.createdAt);
          return parsed != null && DateUtils.isSameDay(parsed, now);
        })
        .toList();
  }

  Future<void> insertMeal(Meal meal) async {
    final db = await database;
    await db.insert("meals", meal.toMap()..remove("id"));
  }

  Future<void> updateMeal(int userId, Meal meal) async {
    final db = await database;
    await db.update(
      "meals",
      meal.toMap()..remove("id"),
      where: "id = ? AND user_id = ?",
      whereArgs: [meal.id, userId],
    );
  }

  Future<void> deleteMeal(int userId, int mealId) async {
    final db = await database;
    await db.delete(
      "meals",
      where: "id = ? AND user_id = ?",
      whereArgs: [mealId, userId],
    );
  }

  String _hash(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }
}

class SessionStore {
  static const _sessionUserIdKey = "prime_diet_session_user_id";
  static const _waterPrefix = "prime_diet_water_ml_";

  static Future<void> setUserId(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sessionUserIdKey, userId);
  }

  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_sessionUserIdKey);
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionUserIdKey);
  }

  static Future<int> getWaterMl(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt("$_waterPrefix$userId") ?? 1500;
  }

  static Future<void> setWaterMl(int userId, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt("$_waterPrefix$userId", value);
  }
}