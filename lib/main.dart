import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import 'dashboard_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: TaskPage(),
    );
  }
}

class TaskPage extends StatefulWidget {
  const TaskPage({super.key});

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  Future<void> loadPendingNotificationsFromNative() async {
    try {
      final jsonString = await _settingsChannel.invokeMethod<String>(
        'getPendingNotifications',
      );

      if (jsonString == null || jsonString.isEmpty) return;

      final List<dynamic> decoded = jsonDecode(jsonString);
      if (decoded.isEmpty) return;

      for (final item in decoded) {
        final payload = Map<String, dynamic>.from(item);
        await handleIncomingNotification(payload, fromNativeStorage: true);
      }

      await _settingsChannel.invokeMethod('clearPendingNotifications');
    } catch (e) {
      debugPrint('Failed to load native pending notifications: $e');
    }
  }

  static const MethodChannel _settingsChannel = MethodChannel(
    'notification_listener/settings',
  );
  static const EventChannel _eventsChannel = EventChannel(
    'notification_listener/events',
  );

  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  final TextEditingController controller = TextEditingController();
  final Uuid uuid = const Uuid();

  StreamSubscription? notificationSubscription;

  bool isDarkMode = false;
  bool showInboxOnly = false;

  String selectedFilter = 'All';
  String searchText = '';
  String selectedSort = 'None';

  String selectedCategory = 'General';
  DateTime? selectedDate;
  String selectedPriority = 'Medium';

  final List<String> sortOptions = ['None', 'Due Date', 'Priority'];

  final List<String> filters = [
    'All',
    'Coding',
    'College',
    'Video Editing',
    'Work',
    'High',
  ];

  final List<String> priorities = ['High', 'Medium', 'Low'];

  final List<String> categories = [
    'General',
    'Coding',
    'College',
    'Video Editing',
    'Work',
  ];

  final List<Map<String, dynamic>> tasks = [];
  final List<Map<String, dynamic>> inbox = [];

  final Set<String> allowedPackages = {
    'com.whatsapp',
    'com.google.android.gm',
    'org.telegram.messenger',
    'com.discord',
  };

  @override
  void initState() {
    super.initState();
    loadTheme();
    loadTasks();
    loadInbox();
    initNotifications();
    loadPendingNotificationsFromNative();
    startListeningToNotificationEvents();
  }

  @override
  void dispose() {
    controller.dispose();
    notificationSubscription?.cancel();
    super.dispose();
  }

  Future<void> initNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    await notifications.initialize(settings: settings);

    final android = notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  Future<void> saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final taskList = tasks.map((task) => jsonEncode(task)).toList();
    await prefs.setStringList('tasks', taskList);
  }

  Future<void> loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final taskList = prefs.getStringList('tasks');

    if (taskList != null) {
      setState(() {
        tasks
          ..clear()
          ..addAll(
            taskList.map((task) {
              final item = Map<String, dynamic>.from(jsonDecode(task));
              item.putIfAbsent('category', () => 'General');
              item.putIfAbsent('priority', () => 'Medium');
              item.putIfAbsent('date', () => null);
              item.putIfAbsent('done', () => false);
              item.putIfAbsent('autoCreated', () => false);
              item.putIfAbsent('sourceApp', () => 'Manual');
              item.putIfAbsent('sourceSender', () => '');
              item.putIfAbsent('rawText', () => '');
              item.putIfAbsent('confidence', () => 1.0);
              item.putIfAbsent(
                'createdAt',
                () => DateTime.now().toIso8601String(),
              );
              return item;
            }),
          );
      });
    }
  }

  Future<void> saveInbox() async {
    final prefs = await SharedPreferences.getInstance();
    final inboxList = inbox.map((item) => jsonEncode(item)).toList();
    await prefs.setStringList('inbox', inboxList);
  }

  Future<void> loadInbox() async {
    final prefs = await SharedPreferences.getInstance();
    final inboxList = prefs.getStringList('inbox');

    if (inboxList != null) {
      setState(() {
        inbox
          ..clear()
          ..addAll(
            inboxList.map(
              (item) => Map<String, dynamic>.from(jsonDecode(item)),
            ),
          );
      });
    }
  }

  Future<void> saveTheme() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', isDarkMode);
  }

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = prefs.getBool('darkMode') ?? false;
    });
  }

  Future<void> openNotificationAccessSettings() async {
    await _settingsChannel.invokeMethod('openNotificationAccessSettings');
  }

  void startListeningToNotificationEvents() {
    notificationSubscription = _eventsChannel.receiveBroadcastStream().listen((
      dynamic event,
    ) async {
      if (event is Map) {
        final payload = Map<String, dynamic>.from(event);
        await handleIncomingNotification(payload);
      }
    });
  }

  Future<void> handleIncomingNotification(
    Map<String, dynamic> payload, {
    bool fromNativeStorage = false,
  }) async {
    final packageName = (payload['packageName'] ?? '').toString();
    final title = (payload['title'] ?? '').toString();
    final body = (payload['body'] ?? '').toString();
    final postedAt =
        payload['postedAt'] ?? DateTime.now().millisecondsSinceEpoch;

    if (!allowedPackages.contains(packageName)) return;
    if (title.trim().isEmpty && body.trim().isEmpty) return;

    final result = TaskExtractor.extract(
      packageName: packageName,
      sender: title,
      body: body,
    );

    if (!result.isActionable || result.title == null) return;
    if (isDuplicate(result.title!, packageName, body)) return;

    final candidate = {
      'id': uuid.v4(),
      'title': result.title,
      'done': false,
      'category': result.category,
      'priority': result.priority,
      'date': result.dueDate?.toIso8601String(),
      'sourceApp': appNameFromPackage(packageName),
      'sourceSender': title,
      'rawText': body,
      'confidence': result.confidence,
      'autoCreated': true,
      'createdAt': DateTime.fromMillisecondsSinceEpoch(
        postedAt,
      ).toIso8601String(),
    };

    setState(() {
      inbox.insert(0, candidate);
    });

    await saveInbox();

    if (!fromNativeStorage) {
      await showDetectedNotification(candidate['title'].toString());
    }
  }

  bool isDuplicate(String title, String sourceAppPackage, String rawText) {
    final normalizedTitle = title.toLowerCase().trim();
    final normalizedBody = rawText.toLowerCase().trim();

    bool matches(Map<String, dynamic> item) {
      final itemTitle = (item['title'] ?? '').toString().toLowerCase().trim();
      final itemBody = (item['rawText'] ?? '').toString().toLowerCase().trim();
      final itemApp = (item['sourceApp'] ?? '').toString().toLowerCase().trim();

      return itemTitle == normalizedTitle &&
          itemBody == normalizedBody &&
          itemApp == appNameFromPackage(sourceAppPackage).toLowerCase();
    }

    return tasks.any(matches) || inbox.any(matches);
  }

  String appNameFromPackage(String packageName) {
    switch (packageName) {
      case 'com.whatsapp':
        return 'WhatsApp';
      case 'com.google.android.gm':
        return 'Gmail';
      case 'org.telegram.messenger':
        return 'Telegram';
      case 'com.discord':
        return 'Discord';
      default:
        return packageName;
    }
  }

  Future<void> showDetectedNotification(String title) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'tasks',
        'Task Reminder',
        importance: Importance.max,
        priority: Priority.high,
      ),
    );

    await notifications.show(
      id: title.hashCode,
      title: 'Task detected',
      body: title,
      notificationDetails: details,
    );
  }

  Future<void> scheduleNotification(String title, DateTime dueDate) async {
    final scheduledDate = tz.TZDateTime.from(dueDate, tz.local);
    await notifications.zonedSchedule(
      id: dueDate.hashCode,
      title: 'Task Reminder',
      body: '$title is due soon!',
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'tasks',
          'Task Reminder',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  void addManualTask() {
    if (controller.text.trim().isEmpty) return;

    final item = {
      'id': uuid.v4(),
      'title': controller.text.trim(),
      'done': false,
      'category': selectedCategory,
      'priority': selectedPriority,
      'date': selectedDate?.toIso8601String(),
      'sourceApp': 'Manual',
      'sourceSender': '',
      'rawText': '',
      'confidence': 1.0,
      'autoCreated': false,
      'createdAt': DateTime.now().toIso8601String(),
    };

    setState(() {
      tasks.insert(0, item);
    });

    if (selectedDate != null) {
      scheduleNotification(controller.text.trim(), selectedDate!);
    }

    saveTasks();
    controller.clear();

    setState(() {
      selectedDate = null;
      selectedCategory = 'General';
      selectedPriority = 'Medium';
    });
  }

  Future<void> approveInboxItem(Map<String, dynamic> item) async {
    setState(() {
      inbox.remove(item);
      tasks.insert(0, item);
    });

    if (item['date'] != null) {
      final dueDate = DateTime.tryParse(item['date']);
      if (dueDate != null && dueDate.isAfter(DateTime.now())) {
        await scheduleNotification(item['title'], dueDate);
      }
    }

    await saveInbox();
    await saveTasks();
  }

  Future<void> deleteInboxItem(Map<String, dynamic> item) async {
    setState(() {
      inbox.remove(item);
    });
    await saveInbox();
  }

  Future<void> deleteTask(Map<String, dynamic> item) async {
    setState(() {
      tasks.remove(item);
    });
    await saveTasks();
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  List<Map<String, dynamic>> get filteredTasks {
    final result = tasks.where((task) {
      final title = (task['title'] ?? '').toString().toLowerCase();
      final category = (task['category'] ?? '').toString();
      final priority = (task['priority'] ?? '').toString();

      final matchesSearch = title.contains(searchText.toLowerCase());
      final matchesFilter =
          selectedFilter == 'All' ||
          category == selectedFilter ||
          (selectedFilter == 'High' && priority == 'High');

      return matchesSearch && matchesFilter;
    }).toList();

    if (selectedSort == 'Due Date') {
      result.sort((a, b) {
        final dateA = DateTime.tryParse((a['date'] ?? '').toString());
        final dateB = DateTime.tryParse((b['date'] ?? '').toString());

        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateA.compareTo(dateB);
      });
    }

    if (selectedSort == 'Priority') {
      const priorityOrder = {'High': 0, 'Medium': 1, 'Low': 2};
      result.sort((a, b) {
        return (priorityOrder[a['priority']] ?? 99).compareTo(
          priorityOrder[b['priority']] ?? 99,
        );
      });
    }

    return result;
  }

  String formatDate(String? iso) {
    if (iso == null) return 'No Date';
    final date = DateTime.tryParse(iso);
    if (date == null) return 'No Date';
    return DateFormat('dd MMM yyyy').format(date);
  }

  Color priorityColor(String priority) {
    switch (priority) {
      case 'High':
        return Colors.red;
      case 'Medium':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = isDarkMode ? ThemeData.dark() : ThemeData.light();

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: Text(showInboxOnly ? 'Detected Tasks Inbox' : 'Task Manager'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: Badge(
                isLabelVisible: inbox.isNotEmpty,
                label: Text(inbox.length.toString()),
                child: Icon(showInboxOnly ? Icons.list : Icons.inbox),
              ),
              onPressed: () {
                setState(() {
                  showInboxOnly = !showInboxOnly;
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings_input_antenna),
              onPressed: openNotificationAccessSettings,
            ),
            IconButton(
              icon: const Icon(Icons.dashboard),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DashboardPage(tasks: tasks),
                  ),
                );
              },
            ),
            IconButton(
              icon: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode),
              onPressed: () {
                setState(() {
                  isDarkMode = !isDarkMode;
                });
                saveTheme();
              },
            ),
          ],
        ),
        body: showInboxOnly ? buildInboxView() : buildTaskView(),
      ),
    );
  }

  Widget buildTaskView() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: controller,
                onSubmitted: (_) => addManualTask(),
                decoration: InputDecoration(
                  hintText: 'Enter Task',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: addManualTask,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonFormField<String>(
                value: selectedCategory,
                items: categories
                    .map(
                      (category) => DropdownMenuItem<String>(
                        value: category,
                        child: Text(category),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    selectedCategory = value!;
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: ElevatedButton.icon(
                onPressed: pickDate,
                icon: const Icon(Icons.calendar_month),
                label: Text(
                  selectedDate == null
                      ? 'Select Due Date'
                      : DateFormat('dd MMM yyyy').format(selectedDate!),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonFormField<String>(
                value: selectedPriority,
                decoration: const InputDecoration(
                  labelText: 'Priority',
                  border: OutlineInputBorder(),
                ),
                items: priorities
                    .map(
                      (priority) => DropdownMenuItem<String>(
                        value: priority,
                        child: Text(priority),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    selectedPriority = value!;
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search tasks...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    searchText = value;
                  });
                },
              ),
            ),
            SizedBox(
              height: 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: filters.length,
                itemBuilder: (context, index) {
                  final filter = filters[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: ChoiceChip(
                      label: Text(filter),
                      selected: selectedFilter == filter,
                      onSelected: (_) {
                        setState(() {
                          selectedFilter = filter;
                        });
                      },
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: DropdownButtonFormField<String>(
                value: selectedSort,
                decoration: const InputDecoration(
                  labelText: 'Sort By',
                  border: OutlineInputBorder(),
                ),
                items: sortOptions
                    .map(
                      (sort) => DropdownMenuItem<String>(
                        value: sort,
                        child: Text(sort),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    selectedSort = value!;
                  });
                },
              ),
            ),

            filteredTasks.isEmpty
                ? const Center(
                    child: Text(
                      'No tasks added yet',
                      style: TextStyle(fontSize: 18),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredTasks.length,
                    itemBuilder: (context, index) {
                      final task = filteredTasks[index];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        child: CheckboxListTile(
                          title: Text(
                            task['title'],
                            style: TextStyle(
                              decoration: task['done']
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(task['category'] ?? 'General'),
                              Text(
                                task['priority'] ?? 'Medium',
                                style: TextStyle(
                                  color: priorityColor(
                                    task['priority'] ?? 'Low',
                                  ),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(formatDate(task['date'])),
                              Text(
                                'Source: ${task['sourceApp']}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          value: task['done'],
                          onChanged: (value) {
                            setState(() {
                              task['done'] = value ?? false;
                            });
                            saveTasks();
                          },
                          secondary: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (task['autoCreated'] == true)
                                const Icon(
                                  Icons.auto_awesome,
                                  color: Colors.blue,
                                ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () => deleteTask(task),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  Widget buildInboxView() {
    if (inbox.isEmpty) {
      return const Center(
        child: Text(
          'No detected tasks yet.\nTurn on notification access and wait for messages.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
        ),
      );
    }

    return ListView.builder(
      itemCount: inbox.length,
      itemBuilder: (context, index) {
        final item = inbox[index];

        return Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['title'] ?? 'Untitled',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Due: ${formatDate(item['date'])}'),
                Text('Priority: ${item['priority']}'),
                Text('Category: ${item['category']}'),
                Text('Source App: ${item['sourceApp']}'),
                Text('Sender: ${item['sourceSender']}'),
                Text(
                  'Confidence: ${((item['confidence'] ?? 0.0) * 100).toStringAsFixed(0)}%',
                ),
                const SizedBox(height: 8),
                Text(
                  'Raw Message: ${item['rawText']}',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => approveInboxItem(item),
                        icon: const Icon(Icons.check),
                        label: const Text('Add'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => deleteInboxItem(item),
                        icon: const Icon(Icons.close),
                        label: const Text('Ignore'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ExtractionResult {
  final bool isActionable;
  final String? title;
  final DateTime? dueDate;
  final String priority;
  final String category;
  final double confidence;

  ExtractionResult({
    required this.isActionable,
    this.title,
    this.dueDate,
    required this.priority,
    required this.category,
    required this.confidence,
  });
}

class TaskExtractor {
  static final List<String> ignoreWords = [
    'hi',
    'hello',
    'lol',
    'ok',
    'okay',
    'thanks',
    'thank you',
    'good morning',
    'good night',
    'see you',
  ];

  static final List<String> actionWords = [
    'submit',
    'send',
    'finish',
    'complete',
    'prepare',
    'meeting',
    'exam',
    'deadline',
    'due',
    'need',
    'invoice',
    'call',
    'tomorrow',
    'today',
    'friday',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'saturday',
    'sunday',
  ];

  static ExtractionResult extract({
    required String packageName,
    required String sender,
    required String body,
  }) {
    final text = '$sender $body'.trim().toLowerCase();

    if (text.isEmpty) {
      return ExtractionResult(
        isActionable: false,
        priority: 'Low',
        category: 'General',
        confidence: 0.0,
      );
    }

    if (ignoreWords.contains(text)) {
      return ExtractionResult(
        isActionable: false,
        priority: 'Low',
        category: 'General',
        confidence: 0.0,
      );
    }

    final hasAction = actionWords.any((word) => text.contains(word));
    if (!hasAction) {
      return ExtractionResult(
        isActionable: false,
        priority: 'Low',
        category: 'General',
        confidence: 0.25,
      );
    }

    final dueDate = DateParser.parse(text);
    final category = _detectCategory(text);
    final priority = _detectPriority(text, dueDate);
    final title = _buildTaskTitle(text);
    final confidence = dueDate != null ? 0.90 : 0.72;

    return ExtractionResult(
      isActionable: true,
      title: title,
      dueDate: dueDate,
      priority: priority,
      category: category,
      confidence: confidence,
    );
  }

  static String _detectCategory(String text) {
    if (text.contains('exam') ||
        text.contains('assignment') ||
        text.contains('class') ||
        text.contains('college') ||
        text.contains('semester')) {
      return 'College';
    }

    if (text.contains('reel') ||
        text.contains('edit') ||
        text.contains('client') ||
        text.contains('video')) {
      return 'Video Editing';
    }

    if (text.contains('bug') ||
        text.contains('deploy') ||
        text.contains('code') ||
        text.contains('app')) {
      return 'Coding';
    }

    if (text.contains('meeting') ||
        text.contains('invoice') ||
        text.contains('work') ||
        text.contains('project')) {
      return 'Work';
    }

    return 'General';
  }

  static String _detectPriority(String text, DateTime? dueDate) {
    if (text.contains('urgent') ||
        text.contains('asap') ||
        text.contains('today') ||
        text.contains('tonight')) {
      return 'High';
    }

    if (text.contains('tomorrow')) {
      return 'High';
    }

    if (dueDate != null) {
      final diff = dueDate.difference(DateTime.now()).inDays;
      if (diff <= 1) return 'High';
      if (diff <= 3) return 'Medium';
      return 'Low';
    }

    return 'Medium';
  }

  static String _buildTaskTitle(String text) {
    if (text.contains('dbms') && text.contains('assignment')) {
      return 'Submit DBMS assignment';
    }
    if (text.contains('assignment')) return 'Submit assignment';
    if (text.contains('exam')) return 'Prepare for exam';
    if (text.contains('meeting')) return 'Attend meeting';
    if (text.contains('invoice')) return 'Send invoice';
    if (text.contains('reel')) return 'Finish reel editing';
    if (text.contains('client') && text.contains('edit')) {
      return 'Finish client editing work';
    }
    if (text.contains('submit')) return 'Submit requested work';
    if (text.contains('send')) return 'Send requested item';
    if (text.contains('call')) return 'Return call';
    return 'Follow up task';
  }
}

class DateParser {
  static DateTime? parse(String text) {
    final now = DateTime.now();
    final lower = text.toLowerCase();

    if (lower.contains('today')) {
      return DateTime(now.year, now.month, now.day, 18, 0);
    }

    if (lower.contains('tomorrow evening')) {
      final tomorrow = now.add(const Duration(days: 1));
      return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 18, 0);
    }

    if (lower.contains('tomorrow')) {
      final tomorrow = now.add(const Duration(days: 1));
      return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 18, 0);
    }

    final weekdayMap = {
      'monday': DateTime.monday,
      'tuesday': DateTime.tuesday,
      'wednesday': DateTime.wednesday,
      'thursday': DateTime.thursday,
      'friday': DateTime.friday,
      'saturday': DateTime.saturday,
      'sunday': DateTime.sunday,
    };

    for (final entry in weekdayMap.entries) {
      if (lower.contains(entry.key)) {
        final target = _nextWeekday(now, entry.value);
        return DateTime(target.year, target.month, target.day, 18, 0);
      }
    }

    final dayMonthPattern = RegExp(
      r'(\d{1,2})(st|nd|rd|th)?\s+(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)',
      caseSensitive: false,
    );

    final match = dayMonthPattern.firstMatch(lower);
    if (match != null) {
      final day = int.tryParse(match.group(1)!);
      final monthText = match.group(3)!;
      final month = _monthFromText(monthText);
      if (day != null && month != null) {
        var year = now.year;
        var parsed = DateTime(year, month, day, 18, 0);
        if (parsed.isBefore(now)) {
          year += 1;
          parsed = DateTime(year, month, day, 18, 0);
        }
        return parsed;
      }
    }

    final timePattern = RegExp(r'(\d{1,2})\s*(am|pm)', caseSensitive: false);
    final timeMatch = timePattern.firstMatch(lower);
    if (timeMatch != null && lower.contains('today')) {
      final hour = int.parse(timeMatch.group(1)!);
      final meridiem = timeMatch.group(2)!.toLowerCase();
      int finalHour = hour % 12;
      if (meridiem == 'pm') finalHour += 12;
      return DateTime(now.year, now.month, now.day, finalHour, 0);
    }

    return null;
  }

  static DateTime _nextWeekday(DateTime from, int weekday) {
    DateTime date = from;
    while (date.weekday != weekday) {
      date = date.add(const Duration(days: 1));
    }
    if (_sameDate(date, from)) {
      date = date.add(const Duration(days: 7));
    }
    return date;
  }

  static bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static int? _monthFromText(String text) {
    switch (text.substring(0, 3).toLowerCase()) {
      case 'jan':
        return 1;
      case 'feb':
        return 2;
      case 'mar':
        return 3;
      case 'apr':
        return 4;
      case 'may':
        return 5;
      case 'jun':
        return 6;
      case 'jul':
        return 7;
      case 'aug':
        return 8;
      case 'sep':
        return 9;
      case 'oct':
        return 10;
      case 'nov':
        return 11;
      case 'dec':
        return 12;
      default:
        return null;
    }
  }
}
