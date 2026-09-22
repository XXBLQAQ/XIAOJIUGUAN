import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/chat_message.dart';

/// 聊天消息的本地持久化层。
class LocalChatDatabase {
  static const _databaseName = 'chat_game.db';
  static const _version = 3;
  Database? _database;
  Future<void> _operationQueue = Future<void>.value();
  bool _closing = false;
  String? _userId;

  Future<Database> get _db async {
    if (_closing) throw StateError('本地数据库正在关闭');
    if (_database != null && _database!.isOpen) return _database!;
    final path = '${await getDatabasesPath()}/$_databaseName';
    _database = await openDatabase(
      path,
      version: _version,
      onCreate: (db, _) => _createTables(db),
      onUpgrade: (db, oldVersion, _) async {
        await _createTables(db);
        if (oldVersion < 3) {
          await db.execute(
              'ALTER TABLE outbox ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0');
        }
      },
      onOpen: _createTables,
    );
    return _database!;
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conversations (
        chat_key TEXT PRIMARY KEY,
        is_group INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        row_id INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_key TEXT NOT NULL,
        server_id TEXT,
        client_message_id TEXT,
        message_seq INTEGER,
        created_at INTEGER NOT NULL,
        payload TEXT NOT NULL,
        UNIQUE(chat_key, server_id),
        UNIQUE(chat_key, client_message_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_state (
        chat_key TEXT PRIMARY KEY,
        last_seq INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS outbox (
        client_message_id TEXT PRIMARY KEY,
        chat_key TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        retry_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_chat_created '
        'ON messages(chat_key, created_at)');
  }

  String _key(String key) => '${_userId ?? 'anonymous'}::$key';

  Future<void> setUserId(dynamic id) async {
    final next = id?.toString();
    if (next == _userId) return;
    _userId = next;
    if (next == null || next.isEmpty) return;
    // 旧版本未记录缓存所属账号，不能将匿名缓存强行归属给新账号。
    await _enqueue(() async {
      await _db;
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _operationQueue.then((_) => action());
    _operationQueue = result.then<void>((_) {}, onError: (_, __) {});
    return result;
  }

  Future<List<ChatMessage>> messagesFor(String key) async {
    try {
      final rows = await (await _db).query('messages',
          where: 'chat_key = ?',
          whereArgs: [_key(key)],
          orderBy: 'message_seq IS NULL, message_seq, created_at, row_id');
      return rows.map((row) {
        final value = jsonDecode(row['payload']! as String);
        return ChatMessage.fromJson(Map<String, dynamic>.from(value as Map));
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> upsertMessages(String key, Iterable<ChatMessage> messages,
          {bool group = false}) =>
      _enqueue(() async {
        final db = await _db;
        final scopedKey = _key(key);
        await db.transaction((txn) async {
          await txn.insert(
              'conversations',
              {
                'chat_key': scopedKey,
                'is_group': group ? 1 : 0,
                'updated_at': DateTime.now().millisecondsSinceEpoch,
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
          for (final message in messages) {
            final existing = await txn.query('messages',
                columns: ['row_id'],
                where: '''chat_key = ? AND ((client_message_id IS NOT NULL AND
                    client_message_id = ?) OR (server_id IS NOT NULL AND server_id = ?))''',
                whereArgs: [
                  scopedKey,
                  message.clientMessageId,
                  message.id?.toString()
                ],
                limit: 1);
            final values = {
              'chat_key': scopedKey,
              'server_id': message.id?.toString(),
              'client_message_id': message.clientMessageId,
              'message_seq': message.messageSeq,
              'created_at': message.createdAt.millisecondsSinceEpoch,
              'payload': jsonEncode(message.toJson()),
            };
            if (existing.isEmpty) {
              await txn.insert('messages', values);
            } else {
              await txn.update('messages', values,
                  where: 'row_id = ?', whereArgs: [existing.first['row_id']]);
            }
          }
          await _trim(txn, scopedKey);
        });
      });

  Future<void> _trim(Transaction txn, String key) async {
    await txn.execute(
        '''DELETE FROM messages WHERE chat_key = ? AND row_id NOT IN
      (SELECT row_id FROM messages WHERE chat_key = ? ORDER BY message_seq IS NULL,
       message_seq DESC, created_at DESC, row_id DESC LIMIT 500)''',
        [key, key]);
  }

  Future<int> syncSequence(String key) async {
    final rows = await (await _db).query('sync_state',
        columns: ['last_seq'], where: 'chat_key = ?', whereArgs: [_key(key)]);
    return rows.isEmpty ? 0 : (rows.first['last_seq'] as int? ?? 0);
  }

  Future<void> saveSyncSequence(String key, int sequence) => _enqueue(() async {
        await (await _db).insert(
            'sync_state', {'chat_key': _key(key), 'last_seq': sequence},
            conflictAlgorithm: ConflictAlgorithm.replace);
      });

  Future<void> saveOutbox(ChatMessage message, String key,
          {String status = 'pending', int retryCount = 0}) =>
      _enqueue(() async {
        await (await _db).insert(
            'outbox',
            {
              'client_message_id': message.clientMessageId,
              'chat_key': _key(key),
              'payload': jsonEncode(message.toJson()),
              'created_at': message.createdAt.millisecondsSinceEpoch,
              'status': status,
              'retry_count': retryCount,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      });

  Future<void> removeOutbox(String clientMessageId) => _enqueue(() async {
        await (await _db).delete('outbox',
            where: 'client_message_id = ?', whereArgs: [clientMessageId]);
      });

  Future<List<ChatMessage>> pendingOutbox() async {
    final rows = await (await _db).query('outbox',
        where: 'chat_key LIKE ? AND status = ?',
        whereArgs: ['${_userId ?? 'anonymous'}::%', 'pending'],
        orderBy: 'created_at');
    return rows.map((row) {
      final value = jsonDecode(row['payload']! as String);
      return ChatMessage.fromJson(Map<String, dynamic>.from(value as Map));
    }).toList();
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    await _operationQueue;
    final database = _database;
    _database = null;
    await database?.close();
  }
}
