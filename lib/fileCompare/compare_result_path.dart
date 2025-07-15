import 'dart:collection';
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
  final HashMap<String, CompareResult> resultHashMap = HashMap();

  @override
  void initState() {
    super.initState();
    controlGroup = widget.controlGroup;
    experimentalGroup = widget.experimentalGroup;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      setState(() => isComparing = true);
      try {
        await _compareWithPath(controlGroup, experimentalGroup);
        setState(() => isComparing = false);
      } catch (e) {
        showAlert(context, "비교 도중에 문제가 발생했습니다.\n$e");
        setState(() => isComparing = false);
      }
    });
  }

  /// 해시 계산 함수
  Future<Digest> _calculateHash(String filePath) async {
    final bytes = File(filePath).readAsBytesSync();
    return md5.convert(bytes);
  }

  /// 비교 프로세스
  Future<void> _compareWithPath(List<FileItem> controlGroup, List<FileItem> experimentalGroup) async {
    final sw = Stopwatch()..start();
    // 대조군 순회
    for (final item in controlGroup) {
      resultHashMap[item.relativePath] = CompareResult(
        status: CompareStatus.onlyControl,
        group0: item,
        group1: null
      );
    }
    // 실험군 순회
    for (final item in experimentalGroup) {
      CompareResult? existing = resultHashMap[item.relativePath];
      if (existing == null) {
        // 같은 경로 없음
        resultHashMap[item.relativePath] = CompareResult(
          status: CompareStatus.onlyExperimental,
          group0: null,
          group1: item
        );
      } else {
        int tmpSize = existing.group0!.fileSize;
        if (tmpSize != item.fileSize) {
          // 파일 크기가 다름
          existing.status = CompareStatus.diff;
          existing.group1 = item;
        } else {
          final List<Digest> hashBuffer = await Future.wait([
            _calculateHash(existing.group0!.fullPath),
            _calculateHash(item.fullPath)
          ]);
          if (hashBuffer[0] != hashBuffer[1]) {
            // 파일 내용도 다름
            existing.status = CompareStatus.diff;
            existing.group1 = item;
          } else {
            // 파일 내용이 같음
            existing.status = CompareStatus.same;
            existing.group1 = item;
          }
        }
      }
    }
    sw.stop();
    debugPrint('경과시간: ${sw.elapsed.toString()}');
  }

  /// 버튼 클릭시 비교전 목록 유지
  Future<void> _onButtonBack() async {
    setState(() {
      resultHashMap.clear();
      widget.onBack();
    });
  }

  /// 버튼 클릭시 비교전 목록 초기화
  Future<void> _onButtonReset() async {
    if (!await showConfirm(context, "정말로 모든 목록을 초기화하시겠습니까?")) return;
    setState(() {
      resultHashMap.clear();
      controlGroup.clear();
      experimentalGroup.clear();
      widget.onReset();
    });
  }

  /// 비교 결과를 표시하는 위젯
  Widget _buildCompareResults() {
    List<int> statusCount = [0,0,0,0];
    for(CompareResult item in resultHashMap.values) {
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
                "비교 결과: ${resultHashMap.length} cases\n"
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
          child: ListView.builder(
            itemCount: resultHashMap.length,
            itemBuilder: (context, index) {
              final CompareResult res = resultHashMap.values.elementAt(index);
              Color tileColor;
              switch (res.status) {
                case CompareStatus.same:             tileColor = Theme.of(context).colorScheme.highlightSame; break;
                case CompareStatus.diff:             tileColor = Theme.of(context).colorScheme.highlightDiff; break;
                case CompareStatus.onlyControl:      tileColor = Theme.of(context).colorScheme.highlightOther; break;
                case CompareStatus.onlyExperimental: tileColor = Theme.of(context).colorScheme.highlightOther; break;
              }

              Widget leftTile = ((res.group0 == null)
                ? Expanded(child: Container())
                : Expanded(
                  child: Tooltip(
                    message: '${res.group0!.relativePath}\n'
                      'Accessed: ${res.group0!.accessed}\n'
                      'Modified: ${res.group0!.modified}',
                    child: ListTile(
                      leading: Icon(Icons.insert_drive_file),
                      title: Text(res.group0!.fileName),
                      subtitle: Text('${res.group0!.fileSize} bytes'),
                    ),
                  ),
                )
              );
              Widget rightTile = ((res.group1 == null)
                ? Expanded(child: Container())
                : Expanded(
                  child: Tooltip(
                    message: '${res.group1!.relativePath}\n'
                      'Accessed: ${res.group1!.accessed}\n'
                      'Modified: ${res.group1!.modified}',
                    child: ListTile(
                      title: Text(res.group1!.fileName, textAlign: TextAlign.right),
                      subtitle: Text('${res.group1!.fileSize} bytes', textAlign: TextAlign.right),
                      trailing: Icon(Icons.insert_drive_file),
                    ),
                  ),
                )
              );

              return Column(
                children: [
                  Container(
                    color: tileColor,
                    child: Row(
                      children: [
                        leftTile,
                        Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)
                          )
                        ),
                        rightTile
                      ]
                    ),
                  ),
                  const Divider(height: 0), // 최 하단에 구분선
                ],
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
            width: 2.0
          ),
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