import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathlib;

/// 파일 정보를 담기 위한 클래스
class FileItem {
  final String fullPath;
  final String fileName;
  final int fileSize;
  final DateTime accessed;
  final DateTime modified;
  final String relativePath; // 드롭 시 기준 폴더로부터의 상대경로

  FileItem({
    required this.fullPath,
    required this.fileName,
    required this.fileSize,
    required this.accessed,
    required this.modified,
    required this.relativePath,
  });

  @override
  String toString() {
    return "$fileName ($relativePath)";
  }
}

enum CompareStatus {
  same,       // 동일
  diffSize,   // 다름(크기)
  diffHash,   // 다름(내용)
  onlyLeft,   // 왼쪽에만 있음
  onlyRight,  // 오른쪽에만 있음
}
class CompareResult {
  final CompareStatus status;
  final String? leftHash;
  final String? rightHash;
  final FileItem? leftItem;
  final FileItem? rightItem;

  CompareResult({
    required this.status,
    this.leftHash,
    this.rightHash,
    this.leftItem,
    this.rightItem,
  });
}

void main() {
  runApp(const MyApp());
}

/// 드롭 영역과 비교 기능을 포함한 메인 위젯
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '파일 비교 툴',
      home: FileComparePage(),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber,
          brightness: Brightness.dark,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0.0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
          ),
        ),
      ),
    );
  }
}
/// 커스텀 colors
extension AppColors on ColorScheme {
  Color get highlightSame => (brightness == Brightness.dark) ? const Color(0x2219ff19): const Color(0xffe6ffe6);
  Color get highlightDiff => (brightness == Brightness.dark) ? const Color(0x22ff1919): const Color(0xffffe6e6);
  Color get highlightOther => Colors.transparent;
}

class FileComparePage extends StatefulWidget {
  const FileComparePage({super.key});

  @override
  _FileComparePageState createState() => _FileComparePageState();
}

class _FileComparePageState extends State<FileComparePage> {
  // 좌측과 우측 파일 목록 저장
  List<FileItem> leftFiles = [];
  List<FileItem> rightFiles = [];

  // 비교 후 결과 메시지(비교 과정 및 결과)
  List<CompareResult> compareResults = [];

  // 버튼 상태 : 비교 후에는 "reset list" 버튼으로 변경
  bool isComparing = false;
  bool comparisonDone = false;

  // drag-over 상태 표시용 (UI 개선)
  bool leftDragging = false;
  bool rightDragging = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('파일 비교'),
      ),
      body: Column(
        children: [
          Expanded(
            child: (comparisonDone)
              ? Container(
                  margin: EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        width: 2.0),
                  ),
                  child: _buildCompareResults(),
                )
              : Row(
                  children: [
                    // 좌측 드롭 영역
                    Expanded(
                      child: DropTarget(
                        onDragDone: (details) async {
                          await _processDroppedItems(details.files, isLeft: true);
                        },
                        onDragEntered: (_) {
                          setState(() {
                            leftDragging = true;
                          });
                        },
                        onDragExited: (_) {
                          setState(() {
                            leftDragging = false;
                          });
                        },
                        child: Container(
                          margin: EdgeInsets.all(8.0),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: leftDragging
                                  ? Theme.of(context).colorScheme.outline
                                  : Theme.of(context).colorScheme.outlineVariant,
                                width: 2.0),
                          ),
                          child: _buildFileList(leftFiles, "Left Area"),
                        ),
                      ),
                    ),
                    // 우측 드롭 영역
                    Expanded(
                      child: DropTarget(
                        onDragDone: (details) async {
                          await _processDroppedItems(details.files, isLeft: false);
                        },
                        onDragEntered: (_) {
                          setState(() {
                            rightDragging = true;
                          });
                        },
                        onDragExited: (_) {
                          setState(() {
                            rightDragging = false;
                          });
                        },
                        child: Container(
                          margin: EdgeInsets.all(8.0),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: rightDragging
                                  ? Theme.of(context).colorScheme.outline
                                  : Theme.of(context).colorScheme.outlineVariant,
                                width: 2.0),
                          ),
                          child: _buildFileList(rightFiles, "Right Area"),
                        ),
                      ),
                    ),
                  ],
                ),
          ),
          const Divider(height: 8, thickness: 2,),
          // 비교 버튼 및 결과 표시
          Padding(
            padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 16.0),
            child: (isComparing)
              ? const CircularProgressIndicator() // 비교 중
              : (comparisonDone)
                ? Column( // After 비교 - 결과 출력
                    spacing: 8.0,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _onButtonBack,
                          child: Text("돌아가기"),
                        )
                      ),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _onButtonReset,
                          child: Text("초기화"),
                        )
                      ),
                    ],
                  )
                : Column( // Before 비교
                    spacing: 8.0,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _onButtonCompareWithPath,
                          child: Text("경로 기반 비교"),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _onButtonCompareWithSize,
                          child: Text("동일 파일 조사"),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// 드롭된 URL(파일/디렉토리 경로)를 처리하여 파일 목록에 추가
  Future<void> _processDroppedItems(List<DropItem> urls, {required bool isLeft}) async {
    List<FileItem> newFiles = [];
    List<FileItem> targetFiles = (isLeft ? leftFiles: rightFiles);
    List<String> existingPaths = targetFiles.map((file) => file.relativePath).toList();
    List<FileItem> duplicateFiles = [];
    for (var uri in urls) {
      String path = uri.path;
      final fileEntity = FileSystemEntity.typeSync(path);
      if (fileEntity == FileSystemEntityType.directory) {
        // 디렉토리인 경우 재귀적으로 파일 목록화
        await for (FileSystemEntity entity in Directory(path).list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              var stat = await entity.stat();
              final newFileItem = FileItem(
                fullPath: entity.path,
                fileName: entity.uri.pathSegments.last,
                fileSize: stat.size,
                accessed: stat.accessed,
                modified: stat.modified,
                relativePath: pathlib.relative(entity.path, from: path),
              );
              if (existingPaths.contains(newFileItem.relativePath)) {
                duplicateFiles.add(newFileItem);
              } else {
                newFiles.add(newFileItem);
              }
            } catch (e) {
              // 오류 무시
            }
          }
        }
      } else if (fileEntity == FileSystemEntityType.file) {
        try {
          var stat = await File(path).stat();
          final newFileItem = FileItem(
            fullPath: path,
            fileName: pathlib.basename(path),
            fileSize: stat.size,
            accessed: stat.accessed,
            modified: stat.modified,
            relativePath: pathlib.relative(path, from: pathlib.dirname(path)),
          );
          if (existingPaths.contains(newFileItem.relativePath)) {
            duplicateFiles.add(newFileItem);
          } else {
            newFiles.add(newFileItem);
          }
        } catch (e) {
          // 오류 무시
        }
      }
    }

    if (duplicateFiles.isNotEmpty) {
      _showAlert("${duplicateFiles.length}개의 파일이 이미 업로드 되어있습니다.\n\n--- 중복된 파일 목록---\n${duplicateFiles.join('\n')}");
    }
    setState(() {
      targetFiles.addAll(newFiles);
    });
  }

  /// 좌측/우측 파일 목록을 보여주는 위젯
  Widget _buildFileList(List<FileItem> files, String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceBright,
          padding: EdgeInsets.all(8.0),
          child: Wrap(
            spacing: 8.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () => setState(() {files.clear();}),
                child: Text("Clear"),
              ),
              Text(
                "${files.length} files",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Expanded(
          child: files.isEmpty
            ? Container(
                padding: EdgeInsets.all(8.0),
                child: Text("여기에 파일 또는 디렉토리를 드래그하세요."),
              )
            : ListView.separated(
            separatorBuilder: (context, index) { return const Divider(height: 0); },
              itemCount: files.length,
              itemBuilder: (context, index) {
                FileItem item = files[index];
                return Tooltip(
                  message: '${item.relativePath}\nAccessed: ${item.accessed}\nModified: ${item.modified}',
                  child: ListTile(
                    leading: Icon(Icons.insert_drive_file),
                    title: Text(item.fileName),
                    subtitle: Text('${item.fileSize} bytes'),
                  ),
                );
              },
            ),
        ),
      ],
    );
  }

  /// 버튼 클릭시 비교전 목록 유지
  Future<void> _onButtonBack() async {
    if (!comparisonDone) {
      _showAlert("비 정상적인 접근입니다.\n비교 이후 다시 시도 해주세요.");
      return;
    }
    setState(() {
      compareResults.clear();
      comparisonDone = false;
    });
  }
  /// 버튼 클릭시 비교전 목록 초기화
  Future<void> _onButtonReset() async {
    if (!await _showConfirm("정말로 모든 목록을 초기화하시겠습니까?")) return;
    if (!comparisonDone) {
      _showAlert("비 정상적인 접근입니다.\n비교 이후 다시 시도 해주세요.");
      return;
    }
    setState(() {
      leftFiles.clear();
      rightFiles.clear();
      compareResults.clear();
      comparisonDone = false;
    });
  }
  /// 버튼 클릭시 비교 수행, 경로 기반 비교
  Future<void> _onButtonCompareWithPath() async {
    if (leftFiles.isEmpty || rightFiles.isEmpty) {
      _showAlert("양쪽 모두 업로드해주세요.");
      return;
    }
    setState(() {
      isComparing = true;
    });
    final results = await _compareFilesWithPath(leftFiles, rightFiles);
    setState(() {
      compareResults = results;
      isComparing = false;
      comparisonDone = true;
    });
  }
  /// 버튼 클릭시 비교 수행, 동일 파일 조사
  Future<void> _onButtonCompareWithSize() async {
    if (leftFiles.isEmpty || rightFiles.isEmpty) {
      _showAlert("양쪽 모두 업로드해주세요.");
      return;
    }
    setState(() {
      isComparing = true;
    });
    final results = await _compareFilesWithSize(leftFiles, rightFiles);
    setState(() {
      compareResults = results;
      isComparing = false;
      comparisonDone = true;
    });
  }

  /// 비교 프로세스 A: relativePath를 기반으로 필터링 후 해시 비교
  Future<List<CompareResult>> _compareFilesWithPath(List<FileItem> left, List<FileItem> right) async {
    // 각각을 relativePath를 key로 하는 맵으로 변환합니다.
    Map<String, FileItem> leftMap = { for (var item in left) item.relativePath: item };
    Map<String, FileItem> rightMap = { for (var item in right) item.relativePath: item };

    // 모든 key의 집합
    final allKeys = <String>{
      ...leftMap.keys,
      ...rightMap.keys,
    };

    List<CompareResult> results = [];

    for (String key in allKeys) {
      final leftItem = leftMap[key];
      final rightItem = rightMap[key];
      if (leftItem != null && rightItem != null) {
        // 1. 파일 크기 비교
        if (leftItem.fileSize != rightItem.fileSize) {
          results.add(CompareResult(
            status: CompareStatus.diffSize,
            leftItem: leftItem,
            rightItem: rightItem,
          ));
        } else {
          // 2. MD5 해시 비교 (크기가 동일한 경우)
          final leftHash = await _calculateHash(leftItem.fullPath);
          final rightHash = await _calculateHash(rightItem.fullPath);
          if (leftHash == rightHash) {
            results.add(CompareResult(
              status: CompareStatus.same,
              leftHash: leftHash,
              rightHash: rightHash,
              leftItem: leftItem,
              rightItem: rightItem,
            ));
          } else {
            results.add(CompareResult(
              status: CompareStatus.diffHash,
              leftHash: leftHash,
              rightHash: rightHash,
              leftItem: leftItem,
              rightItem: rightItem,
            ));
          }
        }
      } else if (leftItem != null && rightItem == null) {
        results.add(CompareResult(
          status: CompareStatus.onlyLeft,
          leftItem: leftItem,
        ));
      } else if (leftItem == null && rightItem != null) {
        results.add(CompareResult(
          status: CompareStatus.onlyRight,
          rightItem: rightItem,
        ));
      }
    }
    return results;
  }

  /// 비교 프로세스 B: 파일 크기로 필터링 후 해시 비교
  Future<List<CompareResult>> _compareFilesWithSize(List<FileItem> left, List<FileItem> right) async {
    // 각각을 file Size를 key로 하는 맵으로 변환합니다.
    Map<int, List<FileItem>> leftGroups = {};
    Map<int, List<FileItem>> rightGroups = {};
    for (var file in left) {
      leftGroups.putIfAbsent(file.fileSize, () => []).add(file);
    }
    for (var file in right) {
      rightGroups.putIfAbsent(file.fileSize, () => []).add(file);
    }

    List<CompareResult> results = [];

    for (var size in leftGroups.keys) {
      if(!rightGroups.containsKey(size)) continue; // 왼쪽만 있음
      List<FileItem> leftGroup = leftGroups[size]!;
      List<FileItem> rightGroup = rightGroups[size]!;

      Map<String, FileItem> leftHashes = {};
      for (var leftItem in leftGroup) {
        String hash = await compute(_calculateHash, leftItem.fullPath);
        leftHashes[hash] = leftItem;
      }
      for (var rightItem in rightGroup) {
        String hash = await compute(_calculateHash, rightItem.fullPath);
        if (leftHashes.containsKey(hash)) {
          // 동일한 파일 존재
          // 이름만 다르지 동일한 내용을 가질 수도 있음
          final leftItem = leftHashes[hash]!;
          results.add(CompareResult(
            status: CompareStatus.same,
            leftHash: hash,
            rightHash: hash,
            leftItem: leftItem,
            rightItem: rightItem,
          ));
        }
      }
    }
    return results;
  }

  /// 비교 결과를 표시하는 위젯
  Widget _buildCompareResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceBright,
          padding: EdgeInsets.all(8.0),
          child: Wrap(
            spacing: 8.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                "비교 결과: ${compareResults.length} cases",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            separatorBuilder: (context, index) { return const Divider(height: 0); },
            itemCount: compareResults.length,
            itemBuilder: (context, index) {
              final res = compareResults[index];
              Color tileColor;
              switch (res.status) {
                case CompareStatus.same:
                  tileColor = Theme.of(context).colorScheme.highlightSame;
                  break;
                case CompareStatus.diffSize:
                  tileColor = Theme.of(context).colorScheme.highlightDiff;
                  break;
                case CompareStatus.diffHash:
                  tileColor = Theme.of(context).colorScheme.highlightDiff;
                  break;
                case CompareStatus.onlyLeft:
                  tileColor = Theme.of(context).colorScheme.highlightOther;
                  break;
                case CompareStatus.onlyRight:
                  tileColor = Theme.of(context).colorScheme.highlightOther;
                  break;
              }

              Widget leftTile = ((res.status == CompareStatus.onlyRight)
                ? Expanded(child: Container())
                : Expanded(
                  child: Tooltip(
                    message: '${res.leftItem!.relativePath}\nAccessed: ${res.leftItem!.accessed}\nModified: ${res.leftItem!.modified}',
                    child: ListTile(
                      leading: Icon(Icons.insert_drive_file),
                      title: Text(res.leftItem!.fileName),
                      subtitle: Text('${res.leftItem!.fileSize} bytes'),
                    ),
                  ),
                )
              );
              Widget rightTile = ((res.status == CompareStatus.onlyLeft)
                ? Expanded(child: Container())
                : Expanded(
                  child: Tooltip(
                    message: '${res.rightItem!.relativePath}\nAccessed: ${res.rightItem!.accessed}\nModified: ${res.rightItem!.modified}',
                    child: ListTile(
                      title: Text(res.rightItem!.fileName, textAlign: TextAlign.right),
                      subtitle: Text('${res.rightItem!.fileSize} bytes', textAlign: TextAlign.right),
                      trailing: Icon(Icons.insert_drive_file),
                    ),
                  ),
                )
              );

              return Container(
                color: tileColor,
                child: Row(children: [leftTile, rightTile])
              );
            },
          ),
        ),
      ]
    );
  }

  /// 경고 메시지 출력
  Future<void> _showAlert(String message) async {
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
  Future<bool> _showConfirm(String message) async {
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
}

/// isolate에서 호출할 해시 계산 함수 (동기적으로 파일을 읽어 MD5 해시를 계산)
Future<String> _calculateHash(String filePath) async {
  final bytes = File(filePath).readAsBytesSync();
  return md5.convert(bytes).toString();
}