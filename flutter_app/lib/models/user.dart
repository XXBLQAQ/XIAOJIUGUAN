/// 用户数据模型
class User {
  final String id;
  final String uid;
  final String phone;
  final String nickname;
  final String? avatar;
  final DateTime createdAt;

  User({
    required this.id,
    required this.uid,
    required this.phone,
    required this.nickname,
    this.avatar,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      uid: json['uid'] as String? ?? json['id'] as String,
      phone: json['phone'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      avatar: json['avatar'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'uid': uid,
        'phone': phone,
        'nickname': nickname,
        'avatar': avatar,
        'createdAt': createdAt.toIso8601String(),
      };
}
