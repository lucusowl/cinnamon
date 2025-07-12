import 'package:flutter/material.dart';

/// 경고 메시지 출력
Future<void> showAlert(BuildContext context, String message) async {
  await showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8.0))),
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.all(32.0),
        actionsPadding: EdgeInsets.zero,
        content: Text(message),
        actions: [
          SizedBox(
            width: double.infinity,
            height: 40.0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: ElevatedButton.icon(
                  autofocus: true,
                  onPressed: () {Navigator.of(context).pop();},
                  icon: const Icon(Icons.check),
                  label: const Text("확인"),
                )),
              ],
            ),
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
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8.0))),
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.all(32.0),
        actionsPadding: EdgeInsets.zero,
        content: Text(message),
        actions: [
          SizedBox(
            width: double.infinity,
            height: 40.0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: ElevatedButton.icon(
                  onPressed: () {Navigator.of(context).pop();},
                  icon: const Icon(Icons.cancel),
                  label: const Text("취소"),
                )),
                Expanded(child: ElevatedButton.icon(
                  autofocus: true,
                  onPressed: () {Navigator.of(context).pop(true);},
                  icon: const Icon(Icons.check),
                  label: const Text("확인"),
                )),
              ],
            ),
          ),
        ],
      );
    }
  );
  return (result == true);
}