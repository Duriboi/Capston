import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'medication_alarms_app.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      // 외래 키 제약 조건 활성화 (중요!)
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE members (
         email       TEXT PRIMARY KEY,
         member_name TEXT NOT NULL,
         password    TEXT NOT NULL,
         guardian_email TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE medications (
         med_name    TEXT PRIMARY KEY,
         description TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE MEDICATION_ALARMS (
          alarm_id     INTEGER PRIMARY KEY AUTOINCREMENT,
          EMAIL        TEXT NOT NULL,
          MED_NAME     TEXT NOT NULL,
          MEAL_TIME    TEXT NOT NULL,
          ALARM_TIME   TEXT NOT NULL,
          START_DATE   TEXT NOT NULL,
          END_DATE     TEXT,
          UNIQUE (EMAIL, MED_NAME, MEAL_TIME),
          FOREIGN KEY (EMAIL) REFERENCES members(EMAIL) ON DELETE CASCADE, -- 회원 탈퇴 시 알람도 삭제되도록 CASCADE 추가 (선택적)
          FOREIGN KEY (MED_NAME) REFERENCES medications(MED_NAME) ON DELETE CASCADE, -- 약 정보 삭제 시 알람도 삭제 (선택적)
          CHECK (MEAL_TIME IN ('MORNING', 'LUNCH', 'DINNER')),
          CHECK (END_DATE IS NULL OR END_DATE >= START_DATE)
      );
    ''');

    await _insertInitialData(db);
  }

  // (선택적) 초기 데이터 삽입 예시
  Future<void> _insertInitialData(Database db) async {
     // 비밀번호가 없으므로 바로 members 삽입
     await db.insert('members', {'email': 't@example.com', 'member_name': '홍길동', 'password': '12345'});
     await db.insert('medications', {'med_name': '종합비타민', 'description': '아침 식후 복용'});
     await db.insert('MEDICATION_ALARMS', {
       'EMAIL': 't@example.com',
       'MED_NAME': '종합비타민',
       'MEAL_TIME': 'MORNING',
       'ALARM_TIME': '13:37',
       'START_DATE': '2025-04-27', // 실제 날짜 형식으로 저장
       'END_DATE': null
     });
  }

  // --- CRUD 메서드들 ---

  // 회원 가입 (멤버 추가)
  Future<int> insertMember(Map<String, dynamic> row) async {
    Database db = await database;
    if (!row.containsKey('email') ||
        !row.containsKey('member_name') ||
        !row.containsKey('password')) {
      throw ArgumentError(
        "Member data must contain 'email', 'member_name', and 'password'",
      );
    }

    print(
      "Inserting member: ${row['email']} with password (plain): ${row['password']}",
    ); // 디버깅용
    return await db.insert(
      'members',
      row,
      conflictAlgorithm: ConflictAlgorithm.fail,
    ); // 중복 email이면 에러 발생
  }

  // 이메일로 회원 정보 가져오기
  Future<Map<String, dynamic>?> getMemberByEmail(String email) async {
    Database db = await database;
    List<Map<String, dynamic>> results = await db.query(
      'members',
      where: 'email = ?',
      whereArgs: [email],
    );
    if (results.isNotEmpty) {
      return results.first;
    }
    return null;
  }

  // 로그인 검증 (이메일과 비밀번호 확인)
  Future<Map<String, dynamic>?> verifyMember(
    String email,
    String password,
  ) async {
    Database db = await database;
    List<Map<String, dynamic>> results = await db.query(
      'members',
      where: 'email = ?',
      whereArgs: [email],
    );

    if (results.isNotEmpty) {
      var member = results.first;
      String storedPassword = member['password']; // DB에 저장된 비밀번호

      // 현재는 평문 비교
      if (storedPassword == password) {
        print("Password verification successful for $email");
        return member; // 비밀번호 일치 시 회원 정보 반환
      } else {
        print(
          "Password verification failed for $email. Stored: $storedPassword, Input: $password",
        );
      }
    } else {
      print("Member with email $email not found.");
    }
    return null; // 이메일이 없거나 비밀번호 불일치 시 null 반환
  }

  // 특정 사용자의 모든 알람 정보 가져오기
  Future<List<Map<String, dynamic>>> getAllAlarmsForUser(String email) async {
    Database db = await database;
    // 예시: MEDICATION_ALARMS 테이블만 조회 (필요시 medications 테이블과 JOIN)
    return await db.query(
      'MEDICATION_ALARMS',
      where: 'EMAIL = ?',
      whereArgs: [email],
      orderBy: 'ALARM_TIME ASC', // 시간순 정렬
    );
  }

  // --- 약(Medication) 및 알람(Alarm) 추가/수정/삭제 메서드는 필요에 따라 여기에 추가 ---
  // Future<int> insertMedication(Map<String, dynamic> row) async { ... }
  // Future<int> insertAlarm(Map<String, dynamic> row) async { ... }
  // Future<int> updateAlarm(...) async { ... }
  // 알람 삭제 메서드 (예시)
  Future<int> deleteAlarm(int alarmId) async {
    Database db = await database;
    return await db.delete(
      'MEDICATION_ALARMS',
      where: 'alarm_id = ?',
      whereArgs: [alarmId],
    );
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
