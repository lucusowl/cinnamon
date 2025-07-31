import 'dart:collection';
import 'dart:io';

import 'package:cinnamon/fileCompare/model.dart';
import 'package:cinnamon/fileCompare/service.dart';
import 'package:cinnamon/fileCompare/util.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathlib;

/// 커스텀 colors
extension AppColors on ColorScheme {
  Color get highlightSame => (brightness == Brightness.dark) ? const Color(0x2219ff19): const Color(0xffe6ffe6);
  Color get highlightDiff => (brightness == Brightness.dark) ? const Color(0x22ff1919): const Color(0xffffe6e6);
  Color get highlightOther => Colors.transparent;
}

/// 비교 상세 결과 객체
class CompareResult {
  CompareStatus status;
  String base;
  FileItem? group0;
  FileItem? group1;

  CompareResult({
    required this.status,
    required this.base,
    this.group0,
    this.group1,
  });
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
  String group0BasePath = '';
  String group1BasePath = '';
  final HashMap<String, CompareResult> resultHashMap = HashMap();
  final List<CompareResult> resultList = [];
  double progressPercent = -1; // -1은 준비, 0부터 진행률 표시
  int entireItemIndex = 0;     // 전체 개수
  int currentItemIndex = 0;    // 완료 개수
  Stopwatch sw = Stopwatch();  // 시간측정용

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      setState(() => progressPercent = -1);
      try {
        /// 결과
        /// {그룹아이디: [바탕경로, [하위상대경로, ...]}
        var itemStatus = await ServiceFileCompare().compareTaskStart(
          /// 작업 결과 수신, 수신되는 대로 비동기 실행됨, batch 결과구조:`{'상대경로':상태값(-1 ~ -6)}`
          (batch) {
            int batchCnt = 0;
            try {
              (batch as HashMap<String,int>).forEach((path, state) {
                if (state == -1) {
                  // 비교전 -> 추가(group0추가)
                  var currentFilePath = pathlib.join(group0BasePath, path);
                  var currentFileStat = File(currentFilePath).statSync();
                  CompareResult ret = CompareResult(
                    status: CompareStatus.before,
                    base: path,
                    group0: FileItem(
                      fullPath: currentFilePath,
                      relativePath: path,
                      fileSize: currentFileStat.size,
                      modified: currentFileStat.modified,
                      accessed: currentFileStat.accessed
                    ),
                    group1: null
                  );
                  resultHashMap[path] = ret;
                  resultList.add(ret);
                } else if (state == -2) {
                  // 비교완료(같음) -> 변경(상태,group1추가)
                  var currentFilePath = pathlib.join(group1BasePath, path);
                  var currentFileStat = File(currentFilePath).statSync();
                  resultHashMap[path]?.status = CompareStatus.same;
                  resultHashMap[path]?.group1 = FileItem(
                    fullPath: currentFilePath,
                    relativePath: path,
                    fileSize: currentFileStat.size,
                    modified: currentFileStat.modified,
                    accessed: currentFileStat.accessed
                  );
                } else if (state == -3) {
                  // 비교완료(다름) -> 변경(상태,group1추가)
                  var currentFilePath = pathlib.join(group1BasePath, path);
                  var currentFileStat = File(currentFilePath).statSync();
                  resultHashMap[path]?.status = CompareStatus.diff;
                  resultHashMap[path]?.group1 = FileItem(
                    fullPath: currentFilePath,
                    relativePath: path,
                    fileSize: currentFileStat.size,
                    modified: currentFileStat.modified,
                    accessed: currentFileStat.accessed
                  );
                } else if (state == -4) {
                  // 비교완료(only0) -> 변경(상태)
                  resultHashMap[path]?.status = CompareStatus.onlyControl;
                  batchCnt -= 1; // 비교 전에서 이미 카운팅이 되어 상태만 변경한 것이기에 생략
                } else if (state == -5) {
                  // 비교완료(only1) -> 추가(group1추가)
                  var currentFilePath = pathlib.join(group1BasePath, path);
                  var currentFileStat = File(currentFilePath).statSync();
                  CompareResult ret = CompareResult(
                    status: CompareStatus.onlyExperimental,
                    base: path,
                    group0: null,
                    group1: FileItem(
                      fullPath: currentFilePath,
                      relativePath: path,
                      fileSize: currentFileStat.size,
                      modified: currentFileStat.modified,
                      accessed: currentFileStat.accessed
                    )
                  );
                  resultHashMap[path] = ret;
                  resultList.add(ret);
                } else { // 오류 -> 에러띄우기
                  resultHashMap[path]?.status = CompareStatus.error;
                }
                batchCnt += 1;
              });
            } catch (error) {
              showAlert(context, "비교 도중에 아래와 같은 문제가 발생하였습니다.\n\n$error");
            } finally {
              setState(() {
                currentItemIndex += batchCnt;
                progressPercent = currentItemIndex / entireItemIndex;
              });
            }
          },
          /// 작업 에러 발생
          (error) {
            showAlert(context, "비교 도중에 아래와 같은 문제가 발생하여 이전페이지로 이동합니다.\n\n$error").then((_) {
              resultHashMap.clear();
              widget.onBack();
            });
          },
          /// 작업 종료, 취소되는 경우도 고려
          () {
            debugPrint('완료');
            setState(() => sw.stop());
          },
        );
        /// 모든 파일 업로드는 완료, 비교 시작
        setState(() {
          progressPercent = 0;
          group0BasePath = itemStatus[0]?[0]; // 바탕경로
          group1BasePath = itemStatus[1]?[0]; // 바탕경로
          entireItemIndex = itemStatus[0]?[1].length + itemStatus[1]?[1].length; // 양쪽 총 개수
          sw.start();
        });
      } catch (error) {
        showAlert(context, "비교 도중에 아래와 같은 문제가 발생하여 이전페이지로 이동합니다.\n\n$error").then((_) {
          widget.onBack();
        });
      }
    });
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
        default:
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceBright,
          padding: const EdgeInsets.all(8.0),
          child: Wrap(
            spacing: 8.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                "비교 결과: ${resultHashMap.length} cases\n"
                "(동일: ${statusCount[0]}개, "
                "다름: ${statusCount[1]}개, "
                "Group 0만: ${statusCount[2]}개, "
                "Group 1만: ${statusCount[3]}개)",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: resultList.length,
            itemBuilder: (context, index) {
              final CompareResult res = resultList.elementAt(index);
              Color tileColor;
              switch (res.status) {
                case CompareStatus.same:             tileColor = Theme.of(context).colorScheme.highlightSame; break;
                case CompareStatus.diff:             tileColor = Theme.of(context).colorScheme.highlightDiff; break;
                case CompareStatus.onlyControl:
                case CompareStatus.onlyExperimental:
                default: tileColor = Theme.of(context).colorScheme.highlightOther;
              }

              Widget leftTile = ((res.group0 == null)
                ? Expanded(child: Container())
                : Expanded(
                  child: Tooltip(
                    message: '${res.group0!.relativePath}\n'
                      'Accessed: ${res.group0!.accessed}\n'
                      'Modified: ${res.group0!.modified}',
                    child: ListTile(
                      leading: const Icon(Icons.insert_drive_file),
                      title: Text(res.group0!.relativePath),
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
                      title: Text(res.group1!.relativePath, textAlign: TextAlign.right),
                      subtitle: Text('${res.group1!.fileSize} bytes', textAlign: TextAlign.right),
                      trailing: const Icon(Icons.insert_drive_file),
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

  /// 현재 진행률 표시
  Widget _progressWidget() {
    if (progressPercent == -1) {
      return const LinearProgressIndicator();
    } else {
      return LinearProgressIndicator(value: progressPercent);
    }
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
      // 현재 진행률 표시
      _progressWidget(),
      const Divider(height: 8, thickness: 2,),
      // Bottom Action Button Part
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: SizedBox(
          height: 48.0,
          child: Row(
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
              IconButton(onPressed: () {
                debugPrint('$progressPercent|$entireItemIndex|$currentItemIndex|${sw.elapsed}');
              }, icon: const Icon(Icons.science_outlined)),
            ],
          ),
        ),
      ),
    ]);
  }
}