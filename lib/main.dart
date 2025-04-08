import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathlib;

/// 파일 정보를 담기 위한 클래스
class FileItem {
  final String fullPath;
  final String fileName;
  final int fileSize;
  final DateTime modified;
  final String relativePath; // 드롭 시 기준 폴더로부터의 상대경로

  FileItem({
    required this.fullPath,
    required this.fileName,
    required this.fileSize,
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
  final String relativePath;
  final CompareStatus status;
  final String? leftFullPath;
  final String? rightFullPath;
  final int? leftSize;
  final int? rightSize;
  final String? leftHash;
  final String? rightHash;

  CompareResult({
    required this.relativePath,
    required this.status,
    this.leftFullPath,
    this.rightFullPath,
    this.leftSize,
    this.rightSize,
    this.leftHash,
    this.rightHash,
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
    );
  }
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
        title: Text('파일 비교 툴'),
      ),
      body: Column(
        children: [
          Expanded(
            child: (comparisonDone)
              ? Container(
                  margin: EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Colors.grey,
                        width: 2.0),
                  ),
                  child: buildCompareResults(),
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
                                color: leftDragging ? Colors.blue : Colors.grey,
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
                                color: rightDragging ? Colors.blue : Colors.grey,
                                width: 2.0),
                          ),
                          child: _buildFileList(rightFiles, "Right Area"),
                        ),
                      ),
                    ),
                  ],
                ),
          ),
          const Divider(),
          // 비교 버튼 및 결과 표시
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: (isComparing)
              ? const CircularProgressIndicator()
              : ElevatedButton(
                  onPressed: _onButtonPressed,
                  child: Text(comparisonDone ? "Reset List" : "Compare Start"),
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
            fileName: path.split(Platform.pathSeparator).last,
            fileSize: stat.size,
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
          color: Colors.grey[300],
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
            : ListView.builder(
              itemCount: files.length,
              itemBuilder: (context, index) {
                FileItem item = files[index];
                return Tooltip(
                  message: item.relativePath,
                  child: ListTile(
                    leading: Icon(Icons.insert_drive_file),
                    title: Text(item.fileName),
                    subtitle: Text(
                        'Modified: ${item.modified}\nSize: ${item.fileSize} bytes'),
                  ),
                );
              },
            ),
        ),
      ],
    );
  }

  /// 버튼 클릭시 비교 수행 또는 목록 리셋
  Future<void> _onButtonPressed() async {
    if (comparisonDone) {
      // Reset List: 양쪽 파일 목록 초기화
      setState(() {
        leftFiles.clear();
        rightFiles.clear();
        compareResults.clear();
        comparisonDone = false;
      });
    } else {
      // Compare Start: 양쪽에 파일이 있는지 확인
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
            relativePath: key,
            status: CompareStatus.diffSize,
            leftFullPath: leftItem.fullPath,
            rightFullPath: rightItem.fullPath,
            leftSize: leftItem.fileSize,
            rightSize: rightItem.fileSize,
          ));
        } else {
          // 2. MD5 해시 비교 (크기가 동일한 경우)
          final leftHash = await calculateHash(leftItem.fullPath);
          final rightHash = await calculateHash(rightItem.fullPath);
          if (leftHash == rightHash) {
            results.add(CompareResult(
              relativePath: key,
              status: CompareStatus.same,
              leftFullPath: leftItem.fullPath,
              rightFullPath: rightItem.fullPath,
              leftSize: leftItem.fileSize,
              rightSize: rightItem.fileSize,
              leftHash: leftHash,
              rightHash: rightHash,
            ));
          } else {
            results.add(CompareResult(
              relativePath: key,
              status: CompareStatus.diffHash,
              leftFullPath: leftItem.fullPath,
              rightFullPath: rightItem.fullPath,
              leftSize: leftItem.fileSize,
              rightSize: rightItem.fileSize,
              leftHash: leftHash,
              rightHash: rightHash,
            ));
          }
        }
      } else if (leftItem != null && rightItem == null) {
        results.add(CompareResult(
          relativePath: key,
          status: CompareStatus.onlyLeft,
          leftFullPath: leftItem.fullPath,
          leftSize: leftItem.fileSize,
        ));
      } else if (leftItem == null && rightItem != null) {
        results.add(CompareResult(
          relativePath: key,
          status: CompareStatus.onlyRight,
          rightFullPath: rightItem.fullPath,
          rightSize: rightItem.fileSize,
        ));
      }
    }
    return results;
  }

  /// 비교 프로세스 B: 파일 크기로 필터링 후 해시 비교
  /// 알고리즘 일단 현재 미구현
  /// 비교 프로세스 A와 다르게 경로-이름과는 무관하게 크기가 같은 파일이 있다면 동일한 지 조사함
  /// 결과상태: 동일, 왼쪽만 존재, 오른쪽만 존재
  Future<List<CompareResult>> _compareFilesWithSize(List<FileItem> left, List<FileItem> right) async {
    List<CompareResult> results = [];
    return results;
  }

  /// 비교 결과를 표시하는 위젯
  Widget buildCompareResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Colors.grey[300],
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
            separatorBuilder: (context, index) { return const Divider(); },
            itemCount: compareResults.length,
            itemBuilder: (context, index) {
              final res = compareResults[index];
              Color tileColor;
              switch (res.status) {
                case CompareStatus.same:
                  tileColor = Color(0xffe6ffe6);
                  break;
                case CompareStatus.diffSize:
                  tileColor = Color(0xffffe6e6);
                  break;
                case CompareStatus.diffHash:
                  tileColor = Color(0xffffe6e6);
                  break;
                case CompareStatus.onlyLeft:
                  tileColor = Colors.transparent;
                  break;
                case CompareStatus.onlyRight:
                  tileColor = Colors.transparent;
                  break;
              }

              Widget leftTile = ((res.status == CompareStatus.onlyRight)
                ? Expanded(child: Container())
                : Expanded(
                  child: Container(
                    color: tileColor,
                    child: ListTile(
                      leading: Icon(Icons.insert_drive_file),
                      title: Text(res.relativePath),
                      subtitle: Text('${res.leftSize} bytes'),
                    ),
                  ),
                )
              );
              Widget rightTile = ((res.status == CompareStatus.onlyLeft)
                ? Expanded(child: Container())
                : Expanded(
                  child: Container(
                    color: tileColor,
                    child: ListTile(
                      title: Text(res.relativePath, textAlign: TextAlign.right),
                      subtitle: Text('${res.rightSize} bytes', textAlign: TextAlign.right),
                      trailing: Icon(Icons.insert_drive_file),
                    ),
                  ),
                )
              );

              return Row(children: [leftTile, rightTile]);
            },
          ),
        ),
      ]
    );
  }

  /// 경고 메시지 출력 (SnackBar 이용)
  void _showAlert(String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("경고"),
          content: Text(message),
          actions: [
            TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text("확인"))
          ],
        );
      }
    );
  }
}

/// isolate에서 호출할 해시 계산 함수 (동기적으로 파일을 읽어 MD5 해시를 계산)
Future<String> calculateHash(String filePath) async {
  final bytes = File(filePath).readAsBytesSync();
  return md5.convert(bytes).toString();
}
