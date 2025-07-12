import 'package:flutter/material.dart';

/// 경고 메시지 출력
Future<void> showAlert(BuildContext context, String message) async {
  await showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text("주의"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {Navigator.of(context).pop();},
            child: const Text("확인"),
          ),
        ],
      );
    }
  );
}

/// 경고 확인 메세지 출력
Future<bool> showConfirm(BuildContext context, String message) async {
  final bool? result = await showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {Navigator.of(context).pop(true);},
            child: const Text("확인"),
          ),
          TextButton(
            onPressed: () {Navigator.of(context).pop();},
            child: const Text("취소"),
          )
        ],
      );
    }
  );
  return (result == true);
}