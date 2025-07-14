import 'dart:io';

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

class CompareResultPathPage extends StatefulWidget {
  final List<FileItem> controlGroup;
  final List<FileItem> experimentalGroup;
  final void Function() onBack;
  final void Function() onReset;

  const CompareResultPathPage({
    super.key,
    required this.controlGroup,
    required this.experimentalGroup,
    required this.onBack,
    required this.onReset,
  });

  @override
  State<CompareResultPathPage> createState() => _CompareResultPathPageState();
}

class _CompareResultPathPageState extends State<CompareResultPathPage> {
  bool isComparing = false;
  late final List<FileItem> controlGroup;
  late final List<FileItem> experimentalGroup;
  List<CompareResult> compareResults = [];

  @override
  void initState() {
    super.initState();
    controlGroup = widget.controlGroup;
    experimentalGroup = widget.experimentalGroup;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      setState(() => isComparing = true);
      try {
        final results = await _compareFilesWithPath(controlGroup, experimentalGroup);
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
  Future<List<CompareResult>> _compareFilesWithPath(List<FileItem> controlGroup, List<FileItem> experimentalGroup) async {
    // 각각을 relativePath를 key로 하는 맵으로 변환합니다.
    Map<String, FileItem> controlGroupMap = { for (var item in controlGroup) item.relativePath: item };
    Map<String, FileItem> experimentalGroupMap = { for (var item in experimentalGroup) item.relativePath: item };

    // 모든 key의 집합
    final Set<String> allKeys = {...controlGroupMap.keys, ...experimentalGroupMap.keys};
    final List<CompareResult> results = [];

    for (String key in allKeys) {
      final controlGroupItem = controlGroupMap[key];
      final experimentalGroupItem = experimentalGroupMap[key];
      if (controlGroupItem != null && experimentalGroupItem != null) {
        // 1. 파일 크기 비교
        if (controlGroupItem.fileSize != experimentalGroupItem.fileSize) {
          results.add(CompareResult(
            status: CompareStatus.diff,
            controlGroupItem: controlGroupItem,
            experimentalGroupItem: experimentalGroupItem,
          ));
        } else {
          // 2. MD5 해시 비교 (크기가 동일한 경우)
          final controlGroupHash = await _calculateHash(controlGroupItem.fullPath);
          final experimentalGroupHash = await _calculateHash(experimentalGroupItem.fullPath);
          if (controlGroupHash == experimentalGroupHash) {
            results.add(CompareResult(
              status: CompareStatus.same,
              controlGroupHash: controlGroupHash,
              experimentalGroupHash: experimentalGroupHash,
              controlGroupItem: controlGroupItem,
              experimentalGroupItem: experimentalGroupItem,
            ));
          } else {
            results.add(CompareResult(
              status: CompareStatus.diff,
              controlGroupHash: controlGroupHash,
              experimentalGroupHash: experimentalGroupHash,
              controlGroupItem: controlGroupItem,
              experimentalGroupItem: experimentalGroupItem,
            ));
          }
        }
      } else if (controlGroupItem != null && experimentalGroupItem == null) {
        results.add(CompareResult(
          status: CompareStatus.onlyControl,
          controlGroupItem: controlGroupItem,
        ));
      } else if (controlGroupItem == null && experimentalGroupItem != null) {
        results.add(CompareResult(
          status: CompareStatus.onlyExperimental,
          experimentalGroupItem: experimentalGroupItem,
        ));
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
      controlGroup.clear();
      experimentalGroup.clear();
      widget.onReset();
    });
  }

  /// 비교 결과를 표시하는 위젯
  Widget _buildCompareResults() {
    List<int> statusCount = [0,0,0,0];
    for(CompareResult item in compareResults) {
      switch (item.status) {
        case CompareStatus.same:             statusCount[0]++; break;
        case CompareStatus.diff:             statusCount[1]++; break;
        case CompareStatus.onlyControl:      statusCount[2]++; break;
        case CompareStatus.onlyExperimental: statusCount[3]++; break;
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
                "비교 결과: ${compareResults.length} cases\n"
                "(동일: ${statusCount[0]}개, "
                "다름: ${statusCount[1]}개, "
                "왼쪽만: ${statusCount[2]}개, "
                "오른쪽만: ${statusCount[3]}개)",
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
                case CompareStatus.diff:
                  tileColor = Theme.of(context).colorScheme.highlightDiff;
                  break;
                case CompareStatus.onlyControl:
                  tileColor = Theme.of(context).colorScheme.highlightOther;
                  break;
                case CompareStatus.onlyExperimental:
                  tileColor = Theme.of(context).colorScheme.highlightOther;
                  break;
              }

              Widget leftTile = ((res.controlGroupItem == null)
                ? Expanded(child: Container())
                : Expanded(
                  child: Tooltip(
                    message: '${res.controlGroupItem!.relativePath}\nAccessed: ${res.controlGroupItem!.accessed}\nModified: ${res.controlGroupItem!.modified}',
                    child: ListTile(
                      leading: Icon(Icons.insert_drive_file),
                      title: Text(res.controlGroupItem!.fileName),
                      subtitle: Text('${res.controlGroupItem!.fileSize} bytes'),
                    ),
                  ),
                )
              );
              Widget rightTile = ((res.experimentalGroupItem == null)
                ? Expanded(child: Container())
                : Expanded(
                  child: Tooltip(
                    message: '${res.experimentalGroupItem!.relativePath}\nAccessed: ${res.experimentalGroupItem!.accessed}\nModified: ${res.experimentalGroupItem!.modified}',
                    child: ListTile(
                      title: Text(res.experimentalGroupItem!.fileName, textAlign: TextAlign.right),
                      subtitle: Text('${res.experimentalGroupItem!.fileSize} bytes', textAlign: TextAlign.right),
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
        margin: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 2.0),
        ),
        child: _buildCompareResults(),
      )),
      const Divider(height: 8, thickness: 2,),
      // Bottom Action Button Part
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: SizedBox(
          height: 48.0,
          child: (isComparing)
          ? const CircularProgressIndicator() // 비교 중
          : Row( // After 비교 - 결과 출력
              spacing: 8.0,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: ElevatedButton.icon(
                  onPressed: _onButtonBack,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text("돌아가기")
                )),
                Expanded(child: ElevatedButton.icon(
                  onPressed: _onButtonReset,
                  icon: const Icon(Icons.refresh),
                  label: const Text("초기화"),
                )),
              ],
            ),
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