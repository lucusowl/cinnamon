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
        content: SelectableText(message),
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

String durationString(Duration? time, {bool verbose = false}) {
  StringBuffer ret = StringBuffer();
  if (time == null) {
    ret.write('-');
  } else {
    // if (time.isNegative) time = time.abs();
    if (time.inDays > 0)    {ret.write(time.inDays); ret.write((verbose)? '일 ': ':');}
    if (time.inHours > 0)   {ret.write(time.inHours % Duration.hoursPerDay); ret.write((verbose)? '시간 ': ':');}
    if (time.inMinutes > 0) {
      if (time.inMinutes < 10) ret.write('0');
      ret.write(time.inMinutes % Duration.minutesPerHour);
      ret.write((verbose)? '분 ': ':');
    }

    if (time.inSeconds != 0 && time.inSeconds < 10) {ret.write('0');}
    ret.write(time.inSeconds % Duration.secondsPerMinute);
    ret.write((verbose)? '초': '.');
    if (time.inMilliseconds < 100) {ret.write('0');}
    if (time.inMilliseconds < 10)  {ret.write('0');}
    if (!verbose || (time.inMilliseconds % 1000 != 0)) {
      ret.write('.');
      ret.write(time.inMilliseconds % 1000);
    }
  }
  return ret.toString();
}