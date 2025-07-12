import 'dart:io';

import 'package:cinnamon/fileCompare/file_compare.dart';
import 'package:cinnamon/fileCompare/model.dart';
import 'package:cinnamon/fileCompare/util.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

/// 커스텀 colors
extension AppColors on ColorScheme {
  Color get highlightSame => (brightness == Brightness.dark) ? const Color(0x2219ff19): const Color(0xffe6ffe6);
  Color get highlightDiff => (brightness == Brightness.dark) ? const Color(0x22ff1919): const Color(0xffffe6e6);
  Color get highlightOther => Colors.transparent;
}

class CompareResultPage extends StatefulWidget {
  final CompareMode compareMode;
  final List<FileItem> leftFiles;
  final List<FileItem> rightFiles;
  final Function() onBack;
  final Function() onReset;

  const CompareResultPage({
    super.key,
    required this.compareMode,
    required this.leftFiles,
    required this.rightFiles,
    required this.onBack,
    required this.onReset,
  });

  @override
  State<CompareResultPage> createState() => _CompareResultPageState();
}

class _CompareResultPageState extends State<CompareResultPage> {
  bool isComparing = false;
  late final List<FileItem> leftFiles;
  late final List<FileItem> rightFiles;
  List<CompareResult> compareResults = [];

  @override
  void initState() {
    super.initState();
    leftFiles = widget.leftFiles;
    rightFiles = widget.rightFiles;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      setState(() => isComparing = true);
      try {
        late final results;
        if (widget.compareMode == CompareMode.path) {
          results = await _compareFilesWithPath(leftFiles, rightFiles);
        } else {
          results = await _compareFilesWithAll(leftFiles, rightFiles);
        }
        setState(() {
          compareResults = results;
          isComparing = false;
        });
      } catch (e) {
        showAlert(context, "비교 도중에 문제가 발생했습니다.\n$e");
        setState(() => isComparing = false);
      }
    });
  }

  /// 비교 프로세스 A: relativePath를 기반으로 필터링 후 해시 비교
  Future<List<CompareResult>> _compareFilesWithPath(List<FileItem> left, List<FileItem> right) async {
    // 각각을 relativePath를 key로 하는 맵으로 변환합니다.
    Map<String, FileItem> leftMap = { for (var item in left) item.relativePath: item };
    Map<String, FileItem> rightMap = { for (var item in right) item.relativePath: item };

    // 모든 key의 집합
    final Set<String> allKeys = {...leftMap.keys, ...rightMap.keys};
    final List<CompareResult> results = [];

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

  /// 비교 프로세스 B: 전체 파일을 대상으로 해시 비교
  Future<List<CompareResult>> _compareFilesWithAll(List<FileItem> left, List<FileItem> right) async {
    // 그룹화: 해시값 -> 파일 목록
    final Map<String, List<FileItem>> leftGroups = {};
    final Map<String, List<FileItem>> rightGroups = {};
    for (final file in left) {
      final hash = await _calculateHash(file.fullPath);
      leftGroups.putIfAbsent(hash, () => []).add(file);
    }
    for (final file in right) {
      final hash = await _calculateHash(file.fullPath);
      rightGroups.putIfAbsent(hash, () => []).add(file);
    }

    final Set<String> allHashes = {...leftGroups.keys, ...rightGroups.keys};
    final List<CompareResult> results = [];

    for (final hash in allHashes) {
      final leftGroup = leftGroups[hash] ?? [];
      final rightGroup = rightGroups[hash] ?? [];

      if (leftGroup.isEmpty) {
        // 오른쪽에만 존재 (onlyRight)
        for (FileItem item in rightGroup) {
          results.add(
            CompareResult(
              status: CompareStatus.onlyRight,
              rightHash: hash,
              rightItem: item,
            ),
          );
        }
      } else if (rightGroup.isEmpty) {
        // 왼쪽에만 존재 (onlyLeft)
        for (FileItem item in leftGroup) {
          results.add(
            CompareResult(
              status: CompareStatus.onlyLeft,
              leftHash: hash,
              leftItem: item,
            ),
          );
        }
      } else {
        // 양쪽에 동일한 내용의 파일 존재 (same)
        final minCount = leftGroup.length < rightGroup.length
            ? leftGroup.length
            : rightGroup.length;

        // 공통 파일 (same)
        for (int i = 0; i < minCount; i++) {
          results.add(
            CompareResult(
              status: CompareStatus.same,
              leftHash: hash,
              rightHash: hash,
              leftItem: leftGroup[i],
              rightItem: rightGroup[i],
            ),
          );
        }
        // 남은 파일들, 위와 동일하지만 표시할 때 매칭이 없음
        for (int i = minCount; i < leftGroup.length; i++) {
          results.add(
            CompareResult(
              status: CompareStatus.same,
              leftHash: hash,
              rightHash: hash,
              leftItem: leftGroup[i],
              rightItem: null,
            ),
          );
        }
        for (int i = minCount; i < rightGroup.length; i++) {
          results.add(
            CompareResult(
              status: CompareStatus.same,
              leftHash: hash,
              rightHash: hash,
              leftItem: null,
              rightItem: rightGroup[i],
            ),
          );
        }
      }
    }
    return results;
  }

  /// 버튼 클릭시 비교전 목록 유지
  Future<void> _onButtonBack() async {
    setState(() {
      compareResults.clear();
      widget.onBack();
    });
  }

  /// 버튼 클릭시 비교전 목록 초기화
  Future<void> _onButtonReset() async {
    if (!await showConfirm(context, "정말로 모든 목록을 초기화하시겠습니까?")) return;
    setState(() {
      compareResults.clear();
      leftFiles.clear();
      rightFiles.clear();
      widget.onReset();
    });
  }

  /// 비교 결과를 표시하는 위젯
  Widget _buildCompareResults() {
    List<int> statusCount = [0,0,0,0,0];
    for(CompareResult item in compareResults) {
      switch (item.status) {
        case CompareStatus.same:      statusCount[0]++; break;
        case CompareStatus.diffSize:  statusCount[1]++; break;
        case CompareStatus.diffHash:  statusCount[2]++; break;
        case CompareStatus.onlyLeft:  statusCount[3]++; break;
        case CompareStatus.onlyRight: statusCount[4]++; break;
      }
    }
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
                "비교 결과: ${compareResults.length} cases"
                "\n(동일: ${statusCount[0]}개, "
                "${(widget.compareMode == CompareMode.path)
                  ? '다름: ${statusCount[1]+statusCount[2]}개, '
                  : ''}"
                "왼쪽만: ${statusCount[3]}개, "
                "오른쪽만: ${statusCount[4]}개)",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            separatorBuilder: (context, index) { return const Divider(height: 0); },
            itemCount: compareResults.length+1,
            itemBuilder: (context, index) {
              if (index == compareResults.length) { return const Divider(height: 0); } // 최 하단에 구분선
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

              Widget leftTile = ((res.leftItem == null)
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
              Widget rightTile = ((res.rightItem == null)
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
                child: IntrinsicHeight(child: Row(children: [
                  leftTile,
                  const VerticalDivider(thickness: 1.0, indent: 5.0, endIndent: 5.0,),
                  rightTile
                ]))
              );
            },
          ),
        ),
      ]
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // 결과 목록 표시 공간
      Expanded(child: Container(
        margin: EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 2.0),
        ),
        child: _buildCompareResults(),
      )),
      const Divider(height: 8, thickness: 2,),
      // 비교 버튼 및 결과 표시
      Padding(
        padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 16.0),
        child: (isComparing)
        ? const CircularProgressIndicator() // 비교 중
        : Column( // After 비교 - 결과 출력
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
        ),
      ),
    ]);
  }
}

/// isolate에서 호출할 해시 계산 함수 (동기적으로 파일을 읽어 MD5 해시를 계산)
Future<String> _calculateHash(String filePath) async {
  final bytes = File(filePath).readAsBytesSync();
  return md5.convert(bytes).toString();
}