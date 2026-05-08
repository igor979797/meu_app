import "dart:convert";
import "dart:io";

import "package:crypto/crypto.dart";
import "package:flutter/material.dart";
import "package:http/http.dart" as http;
import "package:image_picker/image_picker.dart";
import "package:path/path.dart" as p;
import "package:shared_preferences/shared_preferences.dart";
import "package:sqflite/sqflite.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();
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
  String? _token;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final userId = await SessionStore.getUserId();
    final token = await SessionStore.getToken();

    if (!mounted) return;

    setState(() {
      _userId = userId;
      _token = token;
      _loading = false;
    });
  }

  Future<void> _onAuthenticated(
    int userId,
    String token,
  ) async {
    await SessionStore.setUserId(userId);
    await SessionStore.setToken(token);

    if (!mounted) return;

    setState(() {
      _userId = userId;
      _token = token;
    });
  }

  Future<void> _onLogout() async {
    await SessionStore.clearSession();

    if (!mounted) return;

    setState(() {
      _userId = null;
      _token = null;
    });
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
          ? const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            )
          : (_userId == null
              ? AuthScreen(
                  onAuthenticated: _onAuthenticated,
                )
              : (_token == null
                  ? AuthScreen(
                      onAuthenticated: _onAuthenticated,
                    )
                  : HomeScreen(
                      userId: _userId!,
                      token: _token!,
                      onLogout: _onLogout,
                    ))),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.onAuthenticated,
  });

  final Future<void> Function(
    int userId,
    String token,
  ) onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _busy = false;
  String _feedback = "";

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _feedback = "";
    });

    try {
      final response = await http.post(
        Uri.parse(
          "https://mobile-ios-login.zani0x03.eti.br/api/auth/login",
        ),
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "username": _emailController.text.trim(),
          "password": _passwordController.text.trim(),
          "sistemaId":
              "d7f0bddd-ac36-4cdf-8dba-7c752ace6ec6",
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final token = data["access_token"];

        await widget.onAuthenticated(
          1,
          token,
        );
      } else {
        setState(() {
          _feedback = "Login inválido";
        });
      }
    } catch (e) {
      setState(() {
        _feedback = "Erro API";
      });
    }

    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 420,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.eco,
                          color: Color(0xFF59C58A),
                          size: 36,
                        ),
                        SizedBox(width: 10),
                        Text(
                          "PRIMEDIET",
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF59C58A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: "Usuário",
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: "Senha",
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed:
                            _busy ? null : _submit,
                        child: _busy
                            ? const CircularProgressIndicator()
                            : const Text("Entrar"),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _feedback,
                      style: const TextStyle(
                        color: Colors.redAccent,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Login:\nztiago\nSenha:\n123456",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white54,
                      ),
                    ),
                  ],
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
  const HomeScreen({
    super.key,
    required this.userId,
    required this.token,
    required this.onLogout,
  });

  final int userId;
  final String token;
  final Future<void> Function() onLogout;

  @override
  State<HomeScreen> createState() =>
      _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Meal> _meals = [];
  int _waterMl = 1500;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final meals =
        await AppDatabase.instance.getTodayMeals(
      widget.userId,
    );

    final water =
        await SessionStore.getWaterMl(widget.userId);

    setState(() {
      _meals = meals;
      _waterMl = water;
    });
  }

  Future<void> _addWater() async {
    final next = _waterMl + 250;

    await SessionStore.setWaterMl(
      widget.userId,
      next,
    );

    setState(() {
      _waterMl = next;
    });
  }

  Future<void> _openMealForm() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MealFormScreen(
          userId: widget.userId,
        ),
      ),
    );

    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final totalCalories = _meals.fold<int>(
      0,
      (sum, meal) => sum + meal.calories,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Prime Diet"),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    token: widget.token,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.smart_toy),
          ),
          IconButton(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor:
            const Color(0xFF59C58A),
        onPressed: _openMealForm,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Text("Calorias"),
                  const SizedBox(height: 8),
                  Text(
                    "$totalCalories kcal",
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment
                        .spaceBetween,
                children: [
                  Text(
                    "Água: ${(_waterMl / 1000).toStringAsFixed(1)}L",
                  ),
                  FilledButton(
                    onPressed: _addWater,
                    child: const Text(
                      "+250ml",
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            "Refeições",
            style: TextStyle(
              fontSize: 22,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ..._meals.map(
            (meal) => Card(
              child: ListTile(
                title: Text(meal.name),
                subtitle: Text(
                  "${meal.calories} kcal",
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.token,
  });

  final String token;

  @override
  State<ChatScreen> createState() =>
      _ChatScreenState();
}

class _ChatScreenState
    extends State<ChatScreen> {
  final _controller =
      TextEditingController();

  final List<String> _messages = [];

  bool _loadingChat = false;

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();

    if (text.isEmpty || _loadingChat) return;

    setState(() {
      _messages.add("Você: $text");
      _loadingChat = true;
    });

    _controller.clear();

    try {
      final response = await http
          .post(
            Uri.parse(
              "https://mobile-ios-ia.zani0x03.eti.br/api/ai/chat",
            ),
            headers: {
              "Content-Type":
                  "application/json",
              "Authorization":
                  "Bearer ${widget.token}",
            },
            body: jsonEncode({
              "prompt": text,
            }),
          )
          .timeout(
            const Duration(seconds: 20),
          );

      if (response.statusCode == 200) {
        final data =
            jsonDecode(response.body);

        final resposta =
            data["response"] ??
                data["message"] ??
                "Sem resposta";

        setState(() {
          _messages.add(
            "IA: $resposta",
          );
        });
      } else {
        setState(() {
          _messages.add(
            "IA erro ${response.statusCode}",
          );
        });
      }
    } catch (e) {
      setState(() {
        _messages.add(
          "Erro ao conectar IA",
        );
      });
    }

    if (mounted) {
      setState(() {
        _loadingChat = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "IA Nutricional",
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding:
                  const EdgeInsets.all(16),
              itemCount:
                  _messages.length,
              itemBuilder:
                  (context, index) {
                return Card(
                  child: Padding(
                    padding:
                        const EdgeInsets.all(
                      12,
                    ),
                    child: Text(
                      _messages[index],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller:
                        _controller,
                    decoration:
                        const InputDecoration(
                      hintText:
                          "Pergunte algo...",
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed:
                      _sendMessage,
                  child: _loadingChat
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.send,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MealFormScreen extends StatefulWidget {
  const MealFormScreen({
    super.key,
    required this.userId,
  });

  final int userId;

  @override
  State<MealFormScreen> createState() =>
      _MealFormScreenState();
}

class _MealFormScreenState
    extends State<MealFormScreen> {
  final _nameController =
      TextEditingController();

  final _caloriesController =
      TextEditingController();

  String? _photoPath;

  Future<void> _pickImage() async {
    final picker = ImagePicker();

    final file = await picker.pickImage(
      source: ImageSource.gallery,
    );

    if (file == null) return;

    setState(() {
      _photoPath = file.path;
    });
  }

  Future<void> _save() async {
    final meal = Meal(
      userId: widget.userId,
      name: _nameController.text,
      calories: int.tryParse(
            _caloriesController.text,
          ) ??
          0,
      mealType: "Meal",
      photoPath: _photoPath,
      createdAt:
          DateTime.now().toIso8601String(),
    );

    await AppDatabase.instance.insertMeal(
      meal,
    );

    if (!mounted) return;

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text("Nova refeição"),
      ),
      body: Padding(
        padding:
            const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration:
                  const InputDecoration(
                labelText: "Nome",
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller:
                  _caloriesController,
              decoration:
                  const InputDecoration(
                labelText: "Calorias",
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _pickImage,
              child:
                  const Text("Escolher foto"),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              child:
                  const Text("Salvar"),
            ),
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

  factory Meal.fromMap(
    Map<String, Object?> map,
  ) {
    return Meal(
      id: map["id"] as int?,
      userId: map["user_id"] as int,
      name: map["name"] as String,
      calories: map["calories"] as int,
      mealType: map["meal_type"] as String,
      photoPath:
          map["photo_path"] as String?,
      createdAt:
          map["created_at"] as String,
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

  static final AppDatabase instance =
      AppDatabase._();

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;

    final dbPath =
        await getDatabasesPath();

    final path = p.join(
      dbPath,
      "prime_diet_flutter.db",
    );

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute("""
          CREATE TABLE meals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            name TEXT,
            calories INTEGER,
            meal_type TEXT,
            photo_path TEXT,
            created_at TEXT
          )
        """);
      },
    );
  }

  Future<Database> get database async {
    await init();
    return _db!;
  }

  Future<void> insertMeal(Meal meal) async {
    final db = await database;

    await db.insert(
      "meals",
      meal.toMap(),
    );
  }

  Future<List<Meal>> getTodayMeals(
    int userId,
  ) async {
    final db = await database;

    final rows = await db.query(
      "meals",
      where: "user_id = ?",
      whereArgs: [userId],
    );

    return rows
        .map((e) => Meal.fromMap(e))
        .toList();
  }
}

class SessionStore {
  static const _sessionUserIdKey =
      "prime_diet_session_user_id";

  static const _tokenKey =
      "prime_diet_token";

  static const _waterPrefix =
      "prime_diet_water_ml_";

  static Future<void> setUserId(
    int userId,
  ) async {
    final prefs =
        await SharedPreferences
            .getInstance();

    await prefs.setInt(
      _sessionUserIdKey,
      userId,
    );
  }

  static Future<int?> getUserId() async {
    final prefs =
        await SharedPreferences
            .getInstance();

    return prefs.getInt(
      _sessionUserIdKey,
    );
  }

  static Future<void> setToken(
    String token,
  ) async {
    final prefs =
        await SharedPreferences
            .getInstance();

    await prefs.setString(
      _tokenKey,
      token,
    );
  }

  static Future<String?> getToken() async {
    final prefs =
        await SharedPreferences
            .getInstance();

    return prefs.getString(
      _tokenKey,
    );
  }

  static Future<void> clearSession() async {
    final prefs =
        await SharedPreferences
            .getInstance();

    await prefs.clear();
  }

  static Future<int> getWaterMl(
    int userId,
  ) async {
    final prefs =
        await SharedPreferences
            .getInstance();

    return prefs.getInt(
          "$_waterPrefix$userId",
        ) ??
        1500;
  }

  static Future<void> setWaterMl(
    int userId,
    int value,
  ) async {
    final prefs =
        await SharedPreferences
            .getInstance();

    await prefs.setInt(
      "$_waterPrefix$userId",
      value,
    );
  }
}