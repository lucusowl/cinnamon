import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:cinnamon/fileCompare/semaphore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathlib;

/// 서비스 작업 예외 발생
class TaskException implements Exception {
  TaskException(this.message);

  final String message;

  @override
  String toString() => 'TaskException: $message';
}
/// 파일 관련 예외사항
class FileException implements Exception {
  FileException(this.message);

  final String message;

  @override
  String toString() => 'FileException: $message';
}

/// 취소기능과 isolate 내장한 Completer
class TaskCompleter<T> {
  TaskCompleter() :
    isCancel = false,
    completer = Completer<T>();

  bool isCancel;
  Completer<T> completer;
  Isolate? isolate;
  List<ReceivePort?>? ports;

  void closeAllPorts() {
    if (ports != null) {
      for (var port in ports!) port?.close();
      ports = null;
    }
  }
}

/// 업로드 메인 기능
void uploadTaskEntry(List<dynamic> args) async {
  // << [sendPort, path(클로저)]
  // >> [basePath, fileList]
  final SendPort sendPort = args[0] as SendPort;
  final String path = args[1] as String;

  String basePath; // 바탕목록
  List<String> fileList = []; // 파일목록
  final FileSystemEntityType entityType = await FileSystemEntity.type(path);
  if (entityType == FileSystemEntityType.directory) {
    // 폴더인 경우 -> 하위의 모든 파일들을 추가, 바탕경로=입력경로
    basePath = path;
    await for (FileSystemEntity entity in Directory(path).list(recursive: true, followLinks: false)) {
      if (entity is File) {
        fileList.add(pathlib.relative(entity.path, from:path));
      }
    }
  } else if (entityType == FileSystemEntityType.file) {
    // 파일인 경우 -> 현재 파일만 추가, 바탕경로=입력부모경로
    basePath = pathlib.dirname(path);
    fileList.add(pathlib.basename(path));
  } else if (entityType == FileSystemEntityType.notFound) {
    // 존재하지 않는 파일
    throw FileException('존재하지 않음: $path');
  } else {
    // 부적절한 파일 형식
    throw FileException('처리할 수 없는 파일 형식: $path');
  }
  sendPort.send([basePath, fileList]);
}

/// 경로 비교 메인 기능
void compareWithPathTaskEntry(List<dynamic> args) async {
  // << [sendPort, [[바탕경로, [하위상대경로, ...]], ...]]
  // >> {'상대경로': 상태, ...}
  final SendPort sendPort        = args[0];
  final String group0BasePath    = args[1][0][0];
  final List<String> group0Files = args[1][0][1];
  final String group1BasePath    = args[1][1][0];
  final List<String> group1Files = args[1][1][1];
  final sw = Stopwatch()..start();
  int tick = 0;

  HashMap<String,int> groupAMap = HashMap();
  /// {'상대경로': 비교상태}
  /// -1 : 비교전
  /// -2 : 비교후(같음)
  /// -3 : 비교후(다름)
  /// -4 : 비교후(only0)
  /// -5 : 비교후(only1)
  /// -6 : 오류

  // 대조군 순회
  HashMap<String,int> batch = HashMap();
  for (String file in group0Files) {
    batch[file] = -1;
    if(tick < sw.elapsed.inSeconds) {
      sendPort.send(batch);
      groupAMap.addAll(batch);
      batch.clear();
      tick = sw.elapsed.inSeconds;
    }
  }
  sendPort.send(batch);
  groupAMap.addAll(batch);
  batch.clear();

  // 실험군 순회
  for (String file in group1Files) {
    int? existing = groupAMap[file];
    if (existing == null) {
      // 같은 경로가 없음 -> 비교후(only1)
      batch[file] = -5;
    } else {
      var group0file = pathlib.join(group0BasePath, file);
      var group1file = pathlib.join(group1BasePath, file);
      var fileStats = await Future.wait([
        File(group0file).length(),
        File(group1file).length(),
      ]);
      if (fileStats[0] != fileStats[1]) {
        // 파일 크기가 다름 -> 비교후(다름)
        batch[file] = -3;
      } else {
        var fileBytes = await Future.wait([
          File(group0file).readAsBytes(),
          File(group1file).readAsBytes(),
        ]);
        if (md5.convert(fileBytes[0]) != md5.convert(fileBytes[1])) {
          // 파일 내용이 다름 -> 비교후(다름)
          batch[file] = -3;
        } else {
          // 파일 내용이 같음 -> 비교후(같음)
          batch[file] = -2;
        }
      }
    }
    // 초단위 전송
    if(tick < sw.elapsed.inSeconds) {
      sendPort.send(batch);
      groupAMap.addAll(batch);
      batch.clear();
      tick = sw.elapsed.inSeconds;
    }
  }
  // 남은 batch 전체 적용 & 전송
  if (batch.length > 0) {
    sendPort.send(batch);
    groupAMap.addAll(batch);
    batch.clear();
  }
  // 대조군에만 해당하는 내용 적용: 비교중 -> 비교후(only0)
  groupAMap.forEach((path, state) {
    if (state == -1) batch[path] = -4;
  });
  // 적용된 상태 전체 전송
  if (batch.length > 0) {
    sendPort.send(batch);
    batch.clear();
  }
  sw.stop();
}

/// 전체 비교 메인 기능
void compareWithAllTaskEntry(List args) async {
  // << [sendPort, [[바탕경로, [하위상대경로, ]],]]
  // >> {해시|크기: [Group A 상대경로, ], [Group B 상대경로, ]}
  final SendPort sendPort        = args[0];
  final String group0BasePath    = args[1][0][0];
  final List<String> group0Files = args[1][0][1];
  final String group1BasePath    = args[1][1][0];
  final List<String> group1Files = args[1][1][1];

  HashMap<int,List<List<String>>> sizeCompareMap = HashMap();

  // 1차: 크기 순회
  for (var filePath in group0Files) {
    var fileSize = await File(pathlib.join(group0BasePath, filePath)).length();
    if (sizeCompareMap.containsKey(fileSize)) {
      sizeCompareMap[fileSize]![0].add(filePath);
    } else {
      sizeCompareMap[fileSize] = [[filePath],[]];
    }
  }
  for (var filePath in group1Files) {
    var fileSize = await File(pathlib.join(group1BasePath, filePath)).length();
    if (sizeCompareMap.containsKey(fileSize)) {
      sizeCompareMap[fileSize]![1].add(filePath);
    } else {
      sizeCompareMap[fileSize] = [[],[filePath]];
    }
  }

  // 2차: 해시 순회
  sizeCompareMap.forEach((size, items) async {
    if (items[0].length + items[1].length == 1) {
      // 해당 크기를 가진 파일이 전체에서 1개만 있는 경우
      // -> 바로 결과 전송
      sendPort.send({size: items});
    } else {
      // 해당크기를 가진 파일이 여러개 있는 경우
      // -> 그룹 내에서 hash 비교
      // -> 같이 묶인 결과끼리 묶어 결과 전송
      HashMap<String,List<List<String>>> hashCompareMap = HashMap();

      for (var filePath in items[0]) {
        var hash = md5.convert(
          await File(pathlib.join(group0BasePath, filePath)).readAsBytes()
        ).toString();

        if (hashCompareMap.containsKey(hash)) {
          hashCompareMap[hash]![0].add(filePath);
        } else {
          hashCompareMap[hash] = [[filePath],[]];
        }
      }
      for (var filePath in items[1]) {
        var hash = md5.convert(
          await File(pathlib.join(group1BasePath, filePath)).readAsBytes()
        ).toString();

        if (hashCompareMap.containsKey(hash)) {
          hashCompareMap[hash]![1].add(filePath);
        } else {
          hashCompareMap[hash] = [[],[filePath]];
        }
      }
      sendPort.send(hashCompareMap);
    }
  });
}

/// 추가작업 메인 기능
void compareAfterTaskEntry(List<dynamic> args) async {
  final SendPort sendPort  = args[0];
  final String actionMode  = args[1];
  final String srcPath     = args[2];
  final String? dstPath    = args[3];
  final List<String> files = args[4];

  final semaphore = AsyncSemaphore(10);

  for (final filePath in files) {
    semaphore.run(() async {
      final srcFullPath = pathlib.join(srcPath, filePath);
      try {
        switch (actionMode) {
          case 'move':
            final newPath = pathlib.join(dstPath!, filePath);
            // 경로에 맞는 디렉토리가 없는 경우 생성 후 이동
            var newPathDir = Directory(newPath).parent;
            if (!await newPathDir.exists()) {await newPathDir.create(recursive: true);}
            await File(srcFullPath).rename(newPath);
            break;
          case 'delete':
            await File(srcFullPath).delete();
            break;
          case 'copy':
            final newPath = pathlib.join(dstPath!, filePath);
            // 경로에 맞는 디렉토리가 없는 경우 생성 후 복사
            var newPathDir = Directory(newPath).parent;
            if (!await newPathDir.exists()) {await newPathDir.create(recursive: true);}
            await File(srcFullPath).copy(newPath);
            break;
          default: // 이외의 다른 작업은 무시
        }
        sendPort.send(filePath);
      } on PathNotFoundException catch (_) {
        // 파일이 없을 경우, 무시
      } catch (error) {
        rethrow;
      }
    });
  }
}

/// ## 파일 비교 서비스
class ServiceFileCompare {
  /// Singleton Pattern
  static final ServiceFileCompare _instance = ServiceFileCompare._internal();
  factory ServiceFileCompare() => _instance;
  ServiceFileCompare._internal();

  /// 그룹 전체경로
  List<String?> pathGroup = [null, null];
  /// 대상 파일 업로드 작업객체
  List<TaskCompleter<List>?> _uploadTask = [null, null];
  /// 대상 파일 비교 작업객체
  TaskCompleter? _compareTask = null;
  /// 대상 파일 비교후 작업객체
  TaskCompleter? _compareAfterTask = null;

  /// 모든 작업 취소와 저장값 초기화
  void serviceReset({bool restart=false}) {
    // 모든 작업 취소 및 초기화
    uploadTaskCancel(0);
    uploadTaskCancel(1);
    compareWithPathTaskCancel();
    compareWithAllTaskCancel();
    compareAfterTaskCancel();
    if (restart && pathGroup[0] != null && pathGroup[1] != null) {
      // 그룹 재조사
      uploadTaskStart(0, pathGroup[0]!);
      uploadTaskStart(1, pathGroup[1]!);
    } else {
      // 그룹 초기화
      pathGroup = [null, null];
    }
    debugPrint('작업과 대상 모두 초기화 완료');
  }

  /// 파일 업로드 취소
  void uploadTaskCancel(int groupIndex) async {
    TaskCompleter? task = _uploadTask[groupIndex];
    if (task != null) {
      task.isCancel = true;
      if (task.isolate != null) {
        task.isolate!.kill(priority: Isolate.immediate);
        task.isolate = null;
        debugPrint('isolate 존재하여 kill 요청');
      }
      task.closeAllPorts();
      task = null;
      debugPrint('업로드작업 취소완료');
    }
  }
  /// 파일 업로드 시작
  void uploadTaskStart(int groupIndex, String path) async {
    // 인자 검증
    if (groupIndex > 1) throw RangeError('해당하는 그룹이 없습니다.');
    // 이미 진행중이거나 완료된 작업이 있으면 덮어씌기
    if (_uploadTask[groupIndex] != null) uploadTaskCancel(groupIndex);

    // 업로드 경로와 task 등록
    pathGroup[groupIndex] = path;
    TaskCompleter<List> task = TaskCompleter();
    _uploadTask[groupIndex] = task;
    // isolate listener 등록
    final dataPort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    dataPort.listen((event) {
      if (event is List) {
        // 작업종료 -> [바탕경로, [하위상대경로, ...]]
        if (!task.isCancel) {
          debugPrint('업로드작업 완료:$groupIndex:${task.isCancel}:$path');
          task.completer.complete(event);
        }
      } else {
        // 작업에러, 부적절한 반환값
        if (!task.isCancel) {
          debugPrint('업로드작업 오류:부적절한 반환값:$groupIndex:$path');
          task.completer.completeError(TaskException(event));
        }
      }
    });
    errorPort.listen((error) {
      if (!task.isCancel) {
        debugPrint('업로드작업 오류:작업내 오류:$groupIndex:$path');
        task.completer.completeError(TaskException(error));
      }
    });
    exitPort.listen((_) => task.closeAllPorts());
    task.ports = [dataPort, errorPort, exitPort];
    // isolate 등록 & 시작
    task.isolate = await Isolate.spawn(
      uploadTaskEntry,
      [dataPort.sendPort, path],
      onError: errorPort.sendPort,
      onExit: exitPort.sendPort,
    );
  }

  /// 파일 경로 비교 취소
  void compareWithPathTaskCancel() async {
    TaskCompleter? task = _compareTask;
    if (task != null) {
      task.isCancel = true;
      if (task.isolate != null) {
        task.isolate!.kill(priority: Isolate.immediate);
        task.isolate = null;
        debugPrint('isolate 존재하여 kill 요청');
      }
      task.closeAllPorts();
      task = null;
      debugPrint('취소작업 완료');
    }
  }
  /// 파일 경로 비교 시작
  Future<Map<int,List>> compareWithPathTaskStart(
    void Function(dynamic) eventCallback,      // 작업 결과(sendPort 포함) 처리
    void Function(dynamic) eventErrorCallback, // 작업 에러 처리
    void Function() eventDoneCallback          // 작업 완료 처리
  ) async {
    // 모든 upload Task 완료까지 대기
    List<Future<List>> futures = [];
    if (_uploadTask[0] == null) {throw TaskException('Group 0 에 업로드된 파일이 없습니다.');}
    else {futures.add(_uploadTask[0]!.completer.future);}
    if (_uploadTask[1] == null) {throw TaskException('Group 1 에 업로드된 파일이 없습니다.');}
    else {futures.add(_uploadTask[1]!.completer.future);}
    List<List> uploadResults = await Future.wait(futures); // [[바탕경로, [하위상대경로, ...]], ...]

    // task 등록
    TaskCompleter task = TaskCompleter();
    _compareTask = task;
    // isolate listener 등록
    final dataPort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    dataPort.listen(eventCallback);
    errorPort.listen(eventErrorCallback);
    exitPort.listen((event) {
      eventDoneCallback();
      task.closeAllPorts();
    });
    task.ports = [dataPort, errorPort, exitPort];
    // isolate compare 등록 & 시작
    task.isolate = await Isolate.spawn(
      compareWithPathTaskEntry,
      [dataPort.sendPort, uploadResults],
      onError: errorPort.sendPort,
      onExit: exitPort.sendPort,
    );

    // 결과 정리
    Map<int,List> ret = Map();
    int i = 0;
    for (var groupItem in uploadResults) {
      ret[i++] = groupItem;
    }
    return ret;
  }

  /// 파일 전체 비교 취소
  void compareWithAllTaskCancel() async {
    TaskCompleter? task = _compareTask;
    if (task != null) {
      task.isCancel = true;
      if (task.isolate != null) {
        task.isolate!.kill(priority: Isolate.immediate);
        task.isolate = null;
        debugPrint('isolate 존재하여 kill 요청');
      }
      task.closeAllPorts();
      task = null;
      debugPrint('취소작업 완료');
    }
  }
  /// 파일 전체 비교 시작
  Future<List> compareWithAllTaskStart(
    void Function(dynamic) eventCallback,      // 작업 결과(sendPort 포함) 처리
    void Function(dynamic) eventErrorCallback, // 작업 에러 처리
    void Function() eventDoneCallback          // 작업 완료 처리
  ) async {
    // 모든 upload Task 완료까지 대기
    List<Future<List>> futures = [];
    if (_uploadTask[0] == null) {throw TaskException('Group 0 에 업로드된 파일이 없습니다.');}
    else {futures.add(_uploadTask[0]!.completer.future);}
    if (_uploadTask[1] == null) {throw TaskException('Group 1 에 업로드된 파일이 없습니다.');}
    else {futures.add(_uploadTask[1]!.completer.future);}
    List<List> uploadResults = await Future.wait(futures); // [[바탕경로, [하위상대경로, ...]], ...]

    // task 등록
    TaskCompleter task = TaskCompleter();
    _compareTask = task;
    // isolate listener 등록
    final dataPort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    dataPort.listen(eventCallback);
    errorPort.listen(eventErrorCallback);
    exitPort.listen((event) {
      eventDoneCallback();
      task.closeAllPorts();
    });
    task.ports = [dataPort, errorPort, exitPort];
    // isolate compare 등록 & 시작
    task.isolate = await Isolate.spawn(
      compareWithAllTaskEntry,
      [dataPort.sendPort, uploadResults],
      onError: errorPort.sendPort,
      onExit: exitPort.sendPort,
    );

    return uploadResults;
  }

  /// 파일 추가작업 취소
  void compareAfterTaskCancel() {
    TaskCompleter? task = _compareAfterTask;
    if (task != null) {
      task.isCancel = true;
      if (task.isolate != null) {
        task.isolate!.kill(priority: Isolate.immediate);
        task.isolate = null;
        debugPrint('isolate 존재하여 kill 요청');
      }
      task.closeAllPorts();
      task = null;
      debugPrint('취소작업 완료');
    }
  }
  /// 파일 추가작업 시작
  Future<void> compareAfterTaskStart(
    String actionMode,                         // 작업 종류 (이동,삭제,복사)
    String srcPath,                            // 출발지
    String? dstPath,                           // 도착지
    List<String> targetList,                   // 작업 대상 목록
    void Function(dynamic) eventCallback,      // 작업 결과(sendPort 포함) 처리
    void Function(dynamic) eventErrorCallback, // 작업 에러 처리
    void Function() eventDoneCallback          // 작업 완료 처리
  ) async {
    TaskCompleter task = TaskCompleter();
    _compareAfterTask = task;
    // isolate listener 등록
    final dataPort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    dataPort.listen(eventCallback);
    errorPort.listen(eventErrorCallback);
    exitPort.listen((event) {
      eventDoneCallback();
      task.closeAllPorts();
    });
    task.ports = [dataPort, errorPort, exitPort];
    // isolate compare 등록 & 시작
    task.isolate = await Isolate.spawn(
      compareAfterTaskEntry,
      [dataPort.sendPort, actionMode, srcPath, dstPath, targetList],
      onError: errorPort.sendPort,
      onExit: exitPort.sendPort,
    );
  }
}