import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'database_helper.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart'; // 권한 요청
// Flutter Local Notifications 플러그인 인스턴스 생성
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

/// 백그라운드에서 알람 콜백을 처리할 함수 (최상위 레벨 또는 static 함수여야 함)
@pragma('vm:entry-point') // Release 모드에서 코드 축소를 방지
void alarmCallback(int id, Map<String, dynamic> params) async {
  print("알람 콜백 수신! ID: $id, Params: $params");

  // 백그라운드 isolate에서도 Flutter 및 플러그인 초기화 필요
  WidgetsFlutterBinding.ensureInitialized();

  // DatabaseHelper 초기화 (백그라운드에서 DB 접근 위해)
  final dbHelper = DatabaseHelper();
  await dbHelper.database; // DB 열기 보장

  // 알림 플러그인 초기화 (콜백 내부에서도 필요할 수 있음)
  await _initializeNotifications(); // 아래 정의된 초기화 함수 재사용

  // params에서 약 정보 추출 (scheduleAlarm 시 전달한 정보)
  final String medName = params['medName'] ?? '약';
  final String mealTime = params['mealTime'] ?? '복용 시간';
  final String alarmTime = params['alarmTime'] ?? '';

  // 알림 표시
  await showNotification(id, medName, mealTime, alarmTime);
}

/// 알림 표시 함수
Future<void> showNotification(int id, String medName, String mealTime, String alarmTime) async {
  // Android 알림 채널 설정
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
  AndroidNotificationDetails(
    'high_importance_channel', // 채널 ID (AndroidManifest와 일치시키거나 자유롭게)
    'High Importance Notifications', // 채널 이름
    channelDescription: 'This channel is used for important notifications.', // 채널 설명
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    // 커스텀 사운드 설정 (android/app/src/main/res/raw/alarm_sound.mp3)
    sound: RawResourceAndroidNotificationSound('alarm_sound'), // 'alarm_sound'는 확장자 제외 파일명
    // fullScreenIntent: true, // 전체 화면 인텐트 (잠금 화면 위 & 화면 켜짐) - 신중하게 사용
    ticker: 'ticker',
  );

  const NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
  );

  // 알림 내용 구성
  String title = '💊 복약 시간 알림';
  String body = '$alarmTime - $mealTime 에 $medName 복용할 시간입니다.';

  print("알림 표시 시도: ID=$id, Title=$title, Body=$body");

  try {
    await flutterLocalNotificationsPlugin.show(
      id, // 알람 ID를 알림 ID로 사용
      title,
      body,
      platformChannelSpecifics,
      payload: 'alarm_id_$id', // 알림 클릭 시 전달할 데이터 (선택 사항)
    );
    print("알림 표시 성공: ID=$id");
  } catch (e) {
    print("알림 표시 실패: $e");
  }
}


// 알림 초기화 함수
Future<void> _initializeNotifications() async {
  // Android 초기화 설정
  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher'); // 앱 아이콘 사용


  // 통합 초기화 설정
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  // 플러그인 초기화
  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    // 알림 클릭 시 호출될 콜백 (앱이 실행 중일 때)
    onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) async {
      final String? payload = notificationResponse.payload;
      if (payload != null) {
        print('알림 클릭됨! payload: $payload');
        // TODO: 페이로드를 사용하여 특정 페이지로 이동하거나 작업 수행
      }
    },
    // 백그라운드/종료 상태에서 알림 클릭 시 호출될 콜백
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );
}

// 백그라운드/종료 상태에서 알림 탭 처리 함수 (최상위 레벨 또는 static)
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  // handle action
  print('백그라운드 알림 탭! Payload: ${notificationResponse.payload}');
  // 여기서 앱을 열거나 특정 로직 수행 가능 (main 함수 재실행과 유사)
}

Future<void> main() async {
  // async 추가
  // Flutter 바인딩 초기화 보장
  WidgetsFlutterBinding.ensureInitialized();

  // 데이터베이스 초기화 (파일 열기 및 테이블 생성 시도)
  // 앱 시작 시 딱 한 번 호출되어 DB 준비
  try {
    await DatabaseHelper().database;
    print("Database initialized successfully.");
  } catch (e) {
    print("Error initializing database: $e");
    // 앱 실행을 계속할지, 아니면 오류 메시지를 보여줄지 결정
  }

  // --- 알림 초기화 ---
  await _initializeNotifications();

  // --- Android Alarm Manager 초기화 ---
    try {
      await AndroidAlarmManager.initialize();
      print("Android Alarm Manager initialized.");
    } catch (e) {
      print("Error initializing Android Alarm Manager: $e");
    }

  // --- 권한 요청 ---
  await _requestPermissions(); // 앱 시작 시 권한 요청

  runApp(MyApp());
}

// 권한 요청 함수
Future<void> _requestPermissions() async {
    PermissionStatus notificationStatus = await Permission.notification.request(); // 요청하고 상태 받기
    print("알림 권한 상태: $notificationStatus");

    // 정확한 알람 권한 확인
    PermissionStatus exactAlarmStatus = await Permission.scheduleExactAlarm.status;
    print("정확한 알람 권한 상태 (초기): $exactAlarmStatus");
    if (exactAlarmStatus.isDenied) { // isDenied 또는 isPermanentlyDenied 등
      print("정확한 알람 권한이 필요합니다. 앱 설정에서 '알람 및 리마인더'를 허용해주세요.");
      // 여기서 바로 설정 열기를 유도할 수도 있음
      // await openAppSettings();
    }
  // Windows 권한은 일반적으로 필요 없음
}

// (임시) 초기 데이터 기반 알람 스케줄링 함수
Future<void> scheduleInitialAlarms() async {
  final dbHelper = DatabaseHelper();
  // 예시: t@example.com 사용자의 모든 알람 가져오기
  try {
    List<Map<String, dynamic>> alarms = await dbHelper.getAllAlarmsForUser('t@example.com');
    print("DB에서 가져온 알람 수: ${alarms.length}");

    for (var alarm in alarms) {
      int alarmId = alarm['alarm_id'];
      String medName = alarm['MED_NAME'];
      String mealTime = alarm['MEAL_TIME']; // 'MORNING', 'LUNCH', 'DINNER' 등
      String alarmTimeString = alarm['ALARM_TIME']; // "HH:mm" 형식 (예: "09:00")
      // String startDateString = alarm['START_DATE'];
      // String? endDateString = alarm['END_DATE'];
      // TODO: 시작/종료 날짜 고려 로직 추가

      print("스케줄링 시도: ID=$alarmId, 약=$medName, 시간=$alarmTimeString");
      await scheduleAlarm(alarmId, alarmTimeString, medName, mealTime);
    }
  } catch (e) {
    print("초기 알람 스케줄링 중 오류: $e");
  }
}

// 기존 scheduleInitialAlarms 함수를 특정 사용자에 대해 실행하도록 수정
Future<void> scheduleInitialAlarmsForUser(String userEmail) async {
  final dbHelper = DatabaseHelper();
  try {
    List<Map<String, dynamic>> alarms = await dbHelper.getAllAlarmsForUser(userEmail);
    print("'$userEmail' 사용자의 알람 스케줄링 시작 (${alarms.length}개)");

    for (var alarm in alarms) {
      int alarmId = alarm['alarm_id'];
      String medName = alarm['MED_NAME'];
      String mealTime = alarm['MEAL_TIME'];
      String alarmTimeString = alarm['ALARM_TIME'];
      // TODO: 시작/종료 날짜 고려 로직 추가

      print("스케줄링 시도 (HomeScreen): ID=$alarmId, 약=$medName, 시간=$alarmTimeString");
      await scheduleAlarm(alarmId, alarmTimeString, medName, mealTime); // 기존 스케줄링 함수 호출
    }
  } catch (e) {
    print("초기 알람 스케줄링 중 오류 (HomeScreen): $e");
  }
}

/// 알람 스케줄링 함수
Future<void> scheduleAlarm(int alarmId, String alarmTimeString, String medName, String mealTime) async {
  // --- 시간 계산 ---
  // DateTime 사용으로 되돌릴 수 있음 (TZDateTime 불필요)
  final now = DateTime.now();
  final parts = alarmTimeString.split(':');
  if (parts.length != 2) {
    print("잘못된 알람 시간 형식: $alarmTimeString");
    return;
  }
  final hour = int.parse(parts[0]);
  final minute = int.parse(parts[1]);
  DateTime scheduledDateTime = DateTime(now.year, now.month, now.day, hour, minute);
  if (scheduledDateTime.isBefore(now)) {
    scheduledDateTime = scheduledDateTime.add(const Duration(days: 1));
  }
  print("계산된 알람 시간 ($alarmId): $scheduledDateTime");

  // *** 스케줄링 직전에 권한 재확인 ***
  bool exactAlarmGranted = await Permission.scheduleExactAlarm.isGranted;
  if (!exactAlarmGranted) {
    print("scheduleAlarm: 권한 없음! ID=$alarmId 스케줄링 중단.");
    // 여기서 사용자에게 알림을 다시 보내거나 로깅할 수 있습니다.
    return; // 권한 없으면 스케줄링 시도 안 함
  }
  print("scheduleAlarm: 권한 확인됨. ID=$alarmId 스케줄링 진행.");

  try {
    final result = await AndroidAlarmManager.oneShotAt(
        scheduledDateTime, // DateTime 사용
        alarmId,
        alarmCallback,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
        params: {
          'medName': medName,
          'mealTime': mealTime,
          'alarmTime': alarmTimeString,
        }
    );

    if (result) {
      print("Android 알람 예약 성공: ID=$alarmId at $scheduledDateTime");
    } else {
      print("Android 알람 예약 실패: ID=$alarmId.");
    }
  } catch (e) {
    print("Android 알람 스케줄링 중 오류 발생 (ID: $alarmId): $e");
  }
}


class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '복약 알림 앱',
      theme: ThemeData(fontFamily: 'Pretendard'),
      home: LoginScreen(),
    );
  }
}

class LoginScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFFDFEFE),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Image.asset('assets/logo.png', height: 150, width: 500),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => EmailLoginPage()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        backgroundColor: Colors.teal,
                      ),
                      child: Text(
                        '로그인',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => SignUpPage()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        backgroundColor: Colors.grey.shade400,
                      ),
                      child: Text(
                        '회원가입',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmailLoginPage extends StatelessWidget {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final dbHelper = DatabaseHelper();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFFDFEFE),
      appBar: AppBar(title: Text('로그인'), backgroundColor: Color(0xFFFDFEFE)),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: emailController,
              decoration: InputDecoration(labelText: '이메일'),
            ),
            TextField(
              controller: passwordController,
              decoration: InputDecoration(labelText: '비밀번호'),
              obscureText: true,
            ),
            SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  String email = emailController.text.trim();
                  String password = passwordController.text; // 비밀번호 가져오기

                  // 이메일, 비밀번호 입력 확인
                  if (email.isEmpty || password.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('이메일과 비밀번호를 모두 입력해주세요.')),
                    );
                    return;
                  }

                  try {
                    // DB에서 이메일과 비밀번호 검증
                    Map<String, dynamic>? member = await dbHelper.verifyMember(
                      email,
                      password,
                    );

                    if (member != null) {
                      // 로그인 성공
                      print(
                        '로그인 성공: ${member['email']}, 이름: ${member['member_name']}',
                      );

                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => HomeScreen(
                                userEmail: member['email'] as String,
                              ),
                        ),
                      );
                    } else {
                      // 로그인 실패 (이메일 없거나 비밀번호 틀림)
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('이메일 또는 비밀번호가 잘못되었습니다.'),
                        ), // 구체적인 실패 사유 숨김
                      );
                    }
                  } catch (e) {
                    print('로그인 오류: $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('로그인 중 오류가 발생했습니다.')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: Colors.teal,
                ),
                child: Text(
                  '로그인',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 회원가입 화면
class SignUpPage extends StatelessWidget {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final dbHelper = DatabaseHelper();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFFDFEFE),
      appBar: AppBar(title: Text('회원가입'), backgroundColor: Color(0xFFFDFEFE)),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: '이름'),
            ),
            TextField(
              controller: emailController,
              decoration: InputDecoration(labelText: '이메일'),
            ),
            TextField(
              controller: passwordController,
              decoration: InputDecoration(labelText: '비밀번호'),
              obscureText: true,
            ),
            //TextField(
            //  controller: passwordController,
            //  decoration: InputDecoration(labelText: '보호자 이메일'),
            //  obscureText: true,
            //),
            SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  String name = nameController.text.trim();
                  String email = emailController.text.trim();
                  String password = passwordController.text;
                  if (name.isEmpty || email.isEmpty || password.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('이름, 이메일, 비밀번호를 모두 입력해주세요.')),
                    );
                    return;
                  }
                  if (!email.contains('@')) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('유효한 이메일 형식이 아닙니다.')),
                    );
                    return;
                  }
                  Map<String, dynamic> newMember = {
                    'member_name': name,
                    'email': email,
                    'password': password, // 비밀번호 추가
                  };
                  try {
                    // insertMember는 이제 비밀번호를 포함하여 호출됨
                    int id = await dbHelper.insertMember(newMember);
                    if (id != 0) {
                      print('회원가입 성공: $id, $name, $email');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('회원가입 성공! 로그인해주세요.')),
                      );
                      Navigator.pop(context);
                    }
                  } catch (e) {
                    print('회원가입 오류: $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('회원가입 중 오류 발생: 이미 사용 중인 이메일일 수 있습니다.'),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: Colors.teal,
                ),
                child: Text(
                  '회원가입',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final String userEmail;
  HomeScreen({Key? key, required this.userEmail}) : super(key: key);
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    // initState에서 widget.userEmail을 사용하여 페이지 목록 초기화
    _pages = [
      MainPage(userEmail: widget.userEmail),
      CalendarPage(userEmail: widget.userEmail),
      PillPage(userEmail: widget.userEmail), // userEmail 전달
      MyPage(userEmail: widget.userEmail), // userEmail 전달
    ];
    _scheduleAlarmsAfterPermissionCheck(); // 임시로 알람 호출
  }

  Future<void> _scheduleAlarmsAfterPermissionCheck() async {
    bool exactAlarmGranted = await Permission.scheduleExactAlarm.isGranted;
    bool notificationGranted = await Permission.notification.isGranted;

    print("HomeScreen initState: 정확한 알람 권한 상태: $exactAlarmGranted");
    print("HomeScreen initState: 알림 권한 상태: $notificationGranted");

    if (exactAlarmGranted) {
      await scheduleInitialAlarmsForUser(widget.userEmail);
    } else {
      print("HomeScreen initState: 정확한 알람 권한이 없어 스케줄링을 건너<0xEB><0x9B><0x81>니다.");
      if (mounted) { // initState에서 context 사용 시 mounted 확인 권장
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('정확한 복약 알람을 위해 앱 설정에서 "알람 및 리마인더" 권한을 허용해주세요.'),
            action: SnackBarAction(
              label: '설정 열기',
              onPressed: openAppSettings,
            ),
          ),
        );
      }
    }
  }


  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFFDFEFE),
      body: IndexedStack(
        // 페이지 상태 유지를 위해 IndexedStack 사용 고려
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.teal,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed, // 아이템 4개 이상일 때 라벨 보이게
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: '달력',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.medical_services_outlined),
            label: '복약목록', // 아이콘 변경
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '마이페이지'),
        ],
      ),
    );
  }
}

class MainPage extends StatelessWidget {
  final String userEmail;
  final List<String> days = ['월', '화', '수', '목', '금', '토', '일'];
  MainPage({Key? key, required this.userEmail}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF8F8F8),
      body: Column(
        children: [
          Container(
            color: Color(0xFFFDFEFE),
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 30),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Image.asset('assets/logo.png', height: 50),
                Row(
                  children: [
                    Icon(Icons.emoji_emotions_outlined, color: Colors.black),
                    SizedBox(width: 8),
                    Icon(Icons.notifications_none, color: Colors.black),
                  ],
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
            ),
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {},
                        child: Container(
                          height: 170,
                          decoration: BoxDecoration(
                            color: Colors.teal,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey,
                                spreadRadius: 1,
                                blurRadius: 6,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.camera_alt,
                                size: 50,
                                color: Colors.white,
                              ),
                              SizedBox(height: 8),
                              Text(
                                '처방전 촬영',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 20),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {},
                        child: Container(
                          height: 170,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey,
                                spreadRadius: 1,
                                blurRadius: 6,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.upload_file,
                                size: 50,
                                color: Colors.teal,
                              ),
                              SizedBox(height: 8),
                              Text(
                                '처방전 업로드',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children:
                      days.map((day) {
                        return Column(
                          children: [
                            Text(day, style: TextStyle(fontSize: 16)),
                            SizedBox(height: 8),
                            Icon(
                              Icons.check_circle_outline,
                              color: Colors.grey,
                            ),
                          ],
                        );
                      }).toList(),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: Color(0xFFF8F8F8),
              width: double.infinity,
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '오늘의 복약 정보',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 10),
                  ListTile(title: Text('오전: 종합비타민')),
                  ListTile(title: Text('저녁: 위장약')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CalendarPage extends StatefulWidget {
  final String userEmail;
  CalendarPage({Key? key, required this.userEmail}) : super(key: key);
  @override
  _CalendarPageState createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime focusedDay = DateTime.now();
  DateTime? selectedDay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF8F8F8),
      body: Column(
        children: [
          Container(
            color: Color(0xFFFDFEFE),
            padding: EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '복약 달력',
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.emoji_emotions_outlined, color: Colors.black),
                    SizedBox(width: 8),
                    Icon(Icons.notifications_none, color: Colors.black),
                  ],
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Color(0xFFFDFEFE),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
            ),
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: TableCalendar(
              firstDay: DateTime(2020),
              lastDay: DateTime(2030),
              focusedDay: focusedDay,
              selectedDayPredicate: (day) => isSameDay(selectedDay, day),
              onDaySelected: (selected, focused) {
                setState(() {
                  selectedDay = selected;
                  focusedDay = focused;
                });
              },
              calendarStyle: CalendarStyle(
                selectedDecoration: BoxDecoration(
                  color: Colors.teal,
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
              ),
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
              ),
              calendarFormat: CalendarFormat.month,
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              color: Color(0xFFF8F8F8),
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${DateFormat('yyyy.MM.dd').format(selectedDay ?? focusedDay)} 복약정보',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 10),
                  ListTile(title: Text('오전: 종합비타민')),
                  ListTile(title: Text('저녁: 위장약')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PillPage extends StatefulWidget {
  // StatelessWidget -> StatefulWidget 변경
  final String userEmail;
  PillPage({Key? key, required this.userEmail}) : super(key: key);
  @override
  _PillPageState createState() => _PillPageState();
}

class _PillPageState extends State<PillPage> {
  // State 클래스 생성
  final dbHelper = DatabaseHelper();
  late Future<List<Map<String, dynamic>>> _alarmsFuture; // Future 상태 변수

  @override
  void initState() {
    super.initState();
    _loadAlarms(); // 초기 데이터 로드
  }

  // 알람 데이터를 로드하는 함수
  void _loadAlarms() {
    setState(() {
      // FutureBuilder가 re-build 되도록 setState 호출
      _alarmsFuture = dbHelper.getAllAlarmsForUser(widget.userEmail);
    });
  }

  // 알람 취소 함수 (예시)
  Future<void> cancelAlarm(int alarmId) async {
      try {
        final result = await AndroidAlarmManager.cancel(alarmId);
        if (result) {
          print("알람 취소 성공: ID=$alarmId");
        } else {
          print("알람 취소 실패: ID=$alarmId (이미 취소되었거나 존재하지 않음)");
        }
      } catch (e) {
        print("알람 취소 중 오류: $e");
      }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFFDFEFE),
      appBar: AppBar(
        // AppBar 추가 (선택적)
        title: Text('복약 목록'),
        backgroundColor: Color(0xFFFDFEFE),
        elevation: 0, // 그림자 제거
        titleTextStyle: TextStyle(
          color: Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: Column(
        children: [
          SizedBox(height: 20),
          // FutureBuilder를 사용하여 비동기 데이터 로드 및 UI 구성
          Expanded(
            // 스크롤 가능한 영역을 만들기 위해 Expanded 추가
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _alarmsFuture, // dbHelper 호출 결과를 Future로 사용
              builder: (context, snapshot) {
                // 데이터 로딩 중
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }
                // 에러 발생 시
                else if (snapshot.hasError) {
                  return Center(child: Text('오류 발생: ${snapshot.error}'));
                }
                // 데이터가 없거나 비어있을 시
                else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(child: Text('등록된 복약 알람이 없습니다.'));
                }
                // 데이터 로드 성공 시
                else {
                  final alarms = snapshot.data!; // 로드된 알람 데이터
                  // DataTable을 스크롤 가능하게 SingleChildScrollView 사용
                  return SingleChildScrollView(
                    // 스크롤 방향은 수직이어야 함 (기본값)
                    // scrollDirection: Axis.horizontal, // 가로 스크롤은 필요 없음
                    child: SizedBox(
                      // DataTable 너비 강제 위해 SizedBox 사용
                      width: double.infinity, // 화면 너비만큼
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('약 이름')),
                          DataColumn(label: Text('식사 시간')), // 컬럼 변경
                          DataColumn(label: Text('알람 시간')), // 컬럼 변경
                        ],
                        // alarms 리스트를 DataRow 리스트로 변환
                        rows:
                            alarms
                                .map(
                                  (alarm) => DataRow(
                                    cells: [
                                      DataCell(
                                        Text(alarm['MED_NAME'] ?? 'N/A'),
                                      ), // null 체크
                                      DataCell(
                                        Text(alarm['MEAL_TIME'] ?? 'N/A'),
                                      ),
                                      DataCell(
                                        Text(alarm['ALARM_TIME'] ?? 'N/A'),
                                      ),
                                    ],
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // async 추가
          // TODO: 약/알람 추가 페이지로 이동하는 로직 구현
          // 예시: Navigator.push(context, MaterialPageRoute(builder: (_) => AddAlarmPage(userEmail: widget.userEmail)))
          //      .then((_) => _loadAlarms()); // 추가 후 목록 새로고침
          print('약 추가 버튼 클릭됨');
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('약 추가 기능은 아직 구현되지 않았습니다.')));
        },
        child: Icon(Icons.add),
        backgroundColor: Colors.teal,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

class MyPage extends StatefulWidget {
  // StatelessWidget -> StatefulWidget 변경
  final String userEmail;

  MyPage({Key? key, required this.userEmail}) : super(key: key);

  @override
  _MyPageState createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  // State 클래스 생성
  final dbHelper = DatabaseHelper();
  // 사용자 정보를 담을 Future 또는 직접 변수 선언 (FutureBuilder 사용 권장)
  late Future<Map<String, dynamic>?> _memberFuture;

  @override
  void initState() {
    super.initState();
    _memberFuture = dbHelper.getMemberByEmail(widget.userEmail); // 사용자 정보 로드
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF8F8F8),
      body: SafeArea(
        // FutureBuilder를 사용하여 사용자 정보 로드
        child: FutureBuilder<Map<String, dynamic>?>(
          future: _memberFuture,
          builder: (context, snapshot) {
            // 로딩 중 또는 에러 시 표시할 위젯 (선택적)
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text('사용자 정보 로드 오류'));
            }

            // 사용자 정보 (null일 수도 있음)
            final memberData = snapshot.data;
            final memberName =
                memberData?['member_name'] ?? '사용자'; // null 이면 기본값
            final memberEmail = memberData?['email'] ?? '이메일 정보 없음';

            // 기본 Column 구조는 유지
            return Column(
              children: [
                SizedBox(height: 40),
                // 프로필 아이콘
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person,
                    size: 40,
                    color: Colors.teal,
                  ), // 색상 변경
                ),
                SizedBox(height: 20),

                // 이름 (DB에서 가져온 값 사용)
                Text(
                  memberName,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),

                // 이메일 (DB에서 가져온 값 사용)
                Text(
                  memberEmail,
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),

                SizedBox(height: 30),
                Divider(thickness: 1, color: Colors.grey[300]),
                settingTile('환경설정'),
                settingTile('서비스 이용약관'),
                settingTile('회원 탈퇴'), // TODO: 회원 탈퇴 로직 구현 필요 (DB 삭제 등)
                Divider(thickness: 1, color: Colors.grey[300]),
                Spacer(),

                // 로그아웃 버튼
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 30,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      // ... 기존 로그아웃 버튼 스타일 및 onPressed 로직 유지 ...
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: () {
                        // TODO: 실제 로그아웃 처리 (예: 저장된 로그인 정보 삭제)
                        Navigator.pushAndRemoveUntil(
                          // 로그인 화면으로 가고 뒤 스택 모두 제거
                          context,
                          MaterialPageRoute(
                            builder: (context) => LoginScreen(),
                          ),
                          (Route<dynamic> route) => false, // 모든 이전 라우트 제거
                        );
                      },
                      child: Text(
                        '로그아웃',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // 설정 버튼 모양 위젯
  Widget settingTile(String title) {
    return ListTile(
      title: Text(title, style: TextStyle(fontSize: 16)),
      trailing: Icon(Icons.chevron_right),
      onTap: () {
        // 원하는 화면 이동 추가 가능
      },
    );
  }
}
