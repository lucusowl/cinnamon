import 'dart:collection';
import 'dart:io';

import 'package:cinnamon/fileCompare/model.dart';
import 'package:cinnamon/fileCompare/service.dart';
import 'package:cinnamon/fileCompare/util.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  String lastItem = '';        // 마지막 비교 파일명
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
              lastItem = batch.keys.last;
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

  /// 값 변환
  String compactSize(int bytes, [int fractionDigits = 2]) {
    const suffixes = ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB'];
    double size = bytes.toDouble();
    int index = 0;

    while (size >= 1024 && index < suffixes.length - 1) {
      size /= 1024;
      index++;
    }
    return '${size.toStringAsFixed((index == 0)? 0: fractionDigits)} ${suffixes[index]}';
  }

  /// 결과 데이터
  Widget buildRowData(String label, dynamic value, {bool diffValue = false}) {
    TextStyle? textColorStyle;
    if (diffValue) {
      if (value is int) {
        if (value < 0)      textColorStyle = TextStyle(color: Colors.red);
        else if (value > 0) textColorStyle = TextStyle(color: Colors.green);
      } else if (value is Duration) {
        if (value.isNegative) textColorStyle = TextStyle(color: Colors.red);
        else if (value > Duration.zero)  textColorStyle = TextStyle(color: Colors.green);
      }
    }

    String displayText = 'N/A';
    if (value != null) {
      if (value is String) {
        displayText = value;
      } else if (value is int) { // 파일 크기
        var size = NumberFormat.decimalPattern().format(value);
        if (diffValue) {
          if (value > 0)      displayText = '+ ${compactSize(value)} ($size bytes)';
          else if (value < 0) displayText = '- ${compactSize(value.abs())} ($size bytes)';
          else                displayText = '${compactSize(value)} ($size bytes)';
        } else {
          displayText = '${compactSize(value)} ($size bytes)';
        }
      } else if (value is DateTime) { // 시각
        displayText = DateFormat('yyyy년 M월 d일 E a h:m:s.S').format(value);
      } else if (value is Duration) { // 시간차이값
        if (value.isNegative) {
          displayText = '- ' + durationString(value.abs(), verbose: true);
        } else {
          displayText = '+ ' + durationString(value, verbose: true);
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label)),
          Expanded(child: SingleChildScrollView(
            child: Text(
              displayText,
              style: textColorStyle,
            ),
            scrollDirection: Axis.horizontal)
          ),
        ],
      ),
    );
  }

  /// 비교 결과 상세 보기
  void showDetail(CompareResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(32.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 16.0,
                children: [
                  // Top Button Bar
                  Row(
                    children: [
                      Expanded(child: Tooltip(
                        message: result.base,
                        child: Text(
                          result.base,
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        tooltip: "모달 닫기",
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  // Detail elements
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 8.0,
                        children: [
                          ExpansionTile(
                            title: const Text("절대경로"),
                            children: [
                              if(result.group0 != null) buildRowData('Group A', result.group0!.fullPath),
                              if(result.group1 != null) buildRowData('Group B', result.group1!.fullPath),
                            ],
                            initiallyExpanded: true,
                            shape: Border.fromBorderSide(BorderSide.none),
                            childrenPadding: const EdgeInsets.all(16.0),
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            collapsedBackgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                          ),
                          ExpansionTile(
                            title: const Text("파일크기"),
                            children: [
                              if(result.group0 != null) buildRowData('Group A', result.group0!.fileSize),
                              if(result.group0 != null && result.group1 != null) buildRowData('∆', result.group1!.fileSize - result.group0!.fileSize, diffValue: true),
                              if(result.group1 != null) buildRowData('Group B', result.group1!.fileSize),
                            ],
                            shape: Border.fromBorderSide(BorderSide.none),
                            childrenPadding: const EdgeInsets.all(16.0),
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            collapsedBackgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                          ),
                          ExpansionTile(
                            title: const Text("마지막 수정 시각"),
                            children: [
                              if(result.group0 != null) buildRowData('Group A', result.group0!.modified),
                              if(result.group0 != null && result.group1 != null) buildRowData('∆', result.group1!.modified.difference(result.group0!.modified), diffValue: true),
                              if(result.group1 != null) buildRowData('Group B', result.group1!.modified),
                            ],
                            shape: Border.fromBorderSide(BorderSide.none),
                            childrenPadding: const EdgeInsets.all(16.0),
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            collapsedBackgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                          ),
                          ExpansionTile(
                            title: const Text("최근 접근 시각"),
                            children: [
                              if(result.group0 != null) buildRowData('Group A', result.group0!.accessed),
                              if(result.group0 != null && result.group1 != null) buildRowData('∆', result.group1!.accessed.difference(result.group0!.accessed), diffValue: true),
                              if(result.group1 != null) buildRowData('Group B', result.group1!.accessed),
                            ],
                            shape: Border.fromBorderSide(BorderSide.none),
                            childrenPadding: const EdgeInsets.all(16.0),
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            collapsedBackgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                          ),
                        ],
                      ),
                    ),
                  )
                ],
              );
            }
          ),
        );
      }
    );
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
                "총 ${resultHashMap.length} 개 비교결과 "
                "(동일: ${statusCount[0]}개 | "
                "다름: ${statusCount[1]}개 | "
                "Group A에만: ${statusCount[2]}개 | "
                "Group B에만: ${statusCount[3]}개)",
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
              late final Icon tileIcon;
              late final Color tileColor;
              late final String tileTooltip;
              switch (res.status) {
                case CompareStatus.same:
                  tileIcon  = Icon(Icons.done); // Icons.check_circle_outline
                  tileColor = Theme.of(context).colorScheme.highlightSame;
                  tileTooltip = 'Group A:${res.group0!.fullPath}\nGroup B:${res.group1!.fullPath}';
                  break;
                case CompareStatus.diff:
                  tileIcon  = Icon(Icons.difference); // Icons.highlight_remove
                  tileColor = Theme.of(context).colorScheme.highlightDiff;
                  tileTooltip = 'Group A:${res.group0!.fullPath}\nGroup B:${res.group1!.fullPath}';
                  break;
                case CompareStatus.onlyControl:
                  tileIcon  = Icon(Icons.arrow_back); // Icons.arrow_circle_left_outlined
                  tileColor = Theme.of(context).colorScheme.highlightOther;
                  tileTooltip = res.group0!.fullPath;
                  break;
                case CompareStatus.onlyExperimental:
                  tileIcon  = Icon(Icons.arrow_forward); // Icons.arrow_circle_right_outlined
                  tileColor = Theme.of(context).colorScheme.highlightOther;
                  tileTooltip = res.group1!.fullPath;
                  break;
                case CompareStatus.before:
                  tileIcon  = Icon(Icons.circle_outlined);
                  tileColor = Theme.of(context).colorScheme.highlightOther;
                  tileTooltip = '비교중...';
                  break;
                default:
                  tileIcon  = Icon(Icons.error_outline);
                  tileColor = Theme.of(context).colorScheme.highlightOther;
                  tileTooltip = '에러발생!';
              }

              return Column(
                children: [
                  Container(
                    color: tileColor,
                    child: Tooltip(
                      message: tileTooltip,
                      waitDuration: Duration(milliseconds: 500),
                      child: ListTile(
                        leading: tileIcon,
                        title: Text(res.base),
                        onTap: () => showDetail(res),
                      ),
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Text('파일을 불러오고 있는 중입니다...'),
          ),
          const LinearProgressIndicator(minHeight: 8.0),
        ],
      );
    } else if (progressPercent == 1.0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text('${(progressPercent * 100).toStringAsFixed(1)}% ($currentItemIndex/$entireItemIndex) | 경과시간: ${durationString(sw.elapsed)} | 모든 파일 비교 완료.'),
          ),
          LinearProgressIndicator(value: progressPercent, minHeight: 8.0),
        ],
      );
    } else {
      Duration? expected;
      if (currentItemIndex != 0) {
        int t = sw.elapsedMilliseconds;
        expected = Duration(milliseconds: (entireItemIndex/currentItemIndex*t - t).floor());
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Text('${(progressPercent * 100).toStringAsFixed(1)}% ($currentItemIndex/$entireItemIndex) | 경과시간: ${durationString(sw.elapsed)} / 남은예상: ${durationString(expected)} | \"$lastItem\"', overflow: TextOverflow.ellipsis,),
          ),
          LinearProgressIndicator(value: progressPercent, minHeight: 8.0),
        ],
      );
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
      const Divider(height: 0, thickness: 2,),
      // 현재 진행률 표시
      _progressWidget(),
      const Divider(height: 0, thickness: 2,),
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