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
  final void Function() onBack;
  final void Function() onReset;

  const CompareResultPathPage({
    super.key,
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

  bool isAfterActionMode = false;     // 현재 추가작업모드 여부
  bool isAfterActionOngoing = false;  // 추가작업 진행중 여부
  String afterActionDirection = 'AB'; // 적용방향
  List<bool> afterActionTargetStatus = [false, false, false, false]; // 적용대상

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
                  // batchCnt += 0;
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
                  batchCnt += 2;
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
                  batchCnt += 2;
                } else if (state == -4) {
                  // 비교완료(only0) -> 변경(상태)
                  resultHashMap[path]?.status = CompareStatus.onlyA;
                  batchCnt += 1;
                } else if (state == -5) {
                  // 비교완료(only1) -> 추가(group1추가)
                  var currentFilePath = pathlib.join(group1BasePath, path);
                  var currentFileStat = File(currentFilePath).statSync();
                  CompareResult ret = CompareResult(
                    status: CompareStatus.onlyB,
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
                  batchCnt += 1;
                } else { // 오류 -> 에러띄우기
                  resultHashMap[path]?.status = CompareStatus.error;
                  batchCnt += 1;
                }
              });
              if (batch.length > 0) lastItem = batch.keys.last;
            } catch (error) {
              showAlert(context, "비교 도중에 아래와 같은 문제가 발생하였습니다.\n\n$error");
            } finally {
              setState(() {
                currentItemIndex += batchCnt;
                progressPercent = (entireItemIndex > 0)? currentItemIndex / entireItemIndex: 0.0;
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
            debugPrint('비교 완료');
            setState(() => sw.stop());
          },
        );
        /// 모든 파일 업로드는 완료, 비교 시작
        setState(() {
          progressPercent = 0;
          group0BasePath = itemStatus[0]?[0]; // 바탕경로
          group1BasePath = itemStatus[1]?[0]; // 바탕경로
          entireItemIndex = itemStatus[0]?[1].length + itemStatus[1]?[1].length; // 양쪽 총 개수
          currentItemIndex = 0;
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
  String _compactSize(int bytes, [int fractionDigits = 2]) {
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
  Widget _buildRowData(String label, dynamic value, {bool diffValue = false}) {
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
          if (value > 0)      displayText = '+ ${_compactSize(value)} ($size bytes)';
          else if (value < 0) displayText = '- ${_compactSize(value.abs())} ($size bytes)';
          else                displayText = '${_compactSize(value)} ($size bytes)';
        } else {
          displayText = '${_compactSize(value)} ($size bytes)';
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
  void _showDetail(CompareResult result) {
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
                              if(result.group0 != null) _buildRowData('Group A', result.group0!.fullPath),
                              if(result.group1 != null) _buildRowData('Group B', result.group1!.fullPath),
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
                              if(result.group0 != null) _buildRowData('Group A', result.group0!.fileSize),
                              if(result.group0 != null && result.group1 != null) _buildRowData('∆', result.group1!.fileSize - result.group0!.fileSize, diffValue: true),
                              if(result.group1 != null) _buildRowData('Group B', result.group1!.fileSize),
                            ],
                            shape: Border.fromBorderSide(BorderSide.none),
                            childrenPadding: const EdgeInsets.all(16.0),
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            collapsedBackgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                          ),
                          ExpansionTile(
                            title: const Text("마지막 수정 시각"),
                            children: [
                              if(result.group0 != null) _buildRowData('Group A', result.group0!.modified),
                              if(result.group0 != null && result.group1 != null) _buildRowData('∆', result.group1!.modified.difference(result.group0!.modified), diffValue: true),
                              if(result.group1 != null) _buildRowData('Group B', result.group1!.modified),
                            ],
                            shape: Border.fromBorderSide(BorderSide.none),
                            childrenPadding: const EdgeInsets.all(16.0),
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            collapsedBackgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                          ),
                          ExpansionTile(
                            title: const Text("최근 접근 시각"),
                            children: [
                              if(result.group0 != null) _buildRowData('Group A', result.group0!.accessed),
                              if(result.group0 != null && result.group1 != null) _buildRowData('∆', result.group1!.accessed.difference(result.group0!.accessed), diffValue: true),
                              if(result.group1 != null) _buildRowData('Group B', result.group1!.accessed),
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
        case CompareStatus.same:  statusCount[0]++; break;
        case CompareStatus.diff:  statusCount[1]++; break;
        case CompareStatus.onlyA: statusCount[2]++; break;
        case CompareStatus.onlyB: statusCount[3]++; break;
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
                "Group A만: ${statusCount[2]}개 | "
                "Group B만: ${statusCount[3]}개)",
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
                case CompareStatus.onlyA:
                  tileIcon  = Icon(Icons.arrow_back); // Icons.arrow_circle_left_outlined
                  tileColor = Theme.of(context).colorScheme.highlightOther;
                  tileTooltip = res.group0!.fullPath;
                  break;
                case CompareStatus.onlyB:
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
                        title: Text(res.base, overflow: TextOverflow.ellipsis,),
                        onTap: () => _showDetail(res),
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
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Text('대상을 불러오고 있는 중입니다...'),
          ),
          LinearProgressIndicator(minHeight: 8.0),
        ],
      );
    } else if (progressPercent == 1.0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text('${(progressPercent * 100).toStringAsFixed(1)}% ($currentItemIndex/$entireItemIndex) | 경과시간: ${durationString(sw.elapsed)} | 모든 작업 완료.'),
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

  /// 선택지 위젯 (라디오 버튼)
  Widget _buildRadioSelection(String label, String selectedValue) {
    return Expanded(child: InkWell(
      onTap: () {setState(() => afterActionDirection = selectedValue);},
      child: Row(
        children: [
          Radio<String>(
            value: selectedValue,
            groupValue:afterActionDirection,
            onChanged: (value) {setState(() => afterActionDirection = value ?? selectedValue);}
          ),
          Text(label),
        ],
      )),
    );
  }
  /// 선택지 위젯 (체크박스 버튼)
  Widget _buildCheckboxSelection(String label, int selectedIndex) {
    return Expanded(child: InkWell(
      onTap: () {setState(() => afterActionTargetStatus[selectedIndex] = !afterActionTargetStatus[selectedIndex]);},
      child: Row(
        children: [
          Checkbox(
            value: afterActionTargetStatus[selectedIndex],
            onChanged: (checked) {setState(() => afterActionTargetStatus[selectedIndex] = !afterActionTargetStatus[selectedIndex]);}
          ),
          Text(label),
        ],
      )),
    );
  }

  /// 추가작업 수행
  void _afterActionInit(String actionType) async { // move, delete, copy
    // 1. 현재 인자 검증
    late final bool isFromGroupA;
    late final String srcPath;
    late final String dstPath;
    if (afterActionDirection == 'AB') {
      srcPath = group0BasePath;
      dstPath = group1BasePath;
      isFromGroupA = true;
    } else if (afterActionDirection == 'BA') {
      srcPath = group1BasePath;
      dstPath = group0BasePath;
      isFromGroupA = false;
    } else {
      showAlert(context, '부적절한 적용방향이 전달되었습니다. 다시 시도해주세요.');
      return;
    }
    // 2. 순회하며 대상 필터링
    List<bool> targetStatus = [];
    for (bool flag in afterActionTargetStatus) {targetStatus.add(flag);}
    List<String> targets = [];
    resultHashMap.forEach((path, itemCase) {
      final itemStatus = itemCase.status;
      if (
        (itemStatus == CompareStatus.same && targetStatus[0])
        || (itemStatus == CompareStatus.diff && targetStatus[1])
        || (itemStatus == CompareStatus.onlyA && targetStatus[2])
        || (itemStatus == CompareStatus.onlyB && targetStatus[3])
      ) {
        targets.add(itemCase.base);
      }
    });

    if (actionType == 'move') {
      if(!await showConfirm(context, '총 ${targets.length}개의 파일이 이동합니다.\n같은 이름의 파일은 덮어씌워집니다.\n정말로 병합하시겠습니까?')) return;
    } else if (actionType == 'delete') {
      if(!await showConfirm(context, '총 ${targets.length}개의 파일이 삭제됩니다.\n삭제한 파일들은 복구할 수 없습니다.\n정말로 삭제하시겠습니까?')) return;
    } else if (actionType == 'copy') {
      if(!await showConfirm(context, '총 ${targets.length}개의 파일이 복사합니다.\n파일을 복사하시겠습니까?')) return;
    } else {
      showAlert(context, '부적절한 작업방식이 전달되었습니다. 다시 시도해주세요.');
      return;
    }
    setState(() {
      isAfterActionOngoing = true;
      progressPercent = -1;
    });
    // 3. isolate 시작 호출 + 응답 정의
    /// actionType
    /// srcPath, dstPath
    /// targets
    await ServiceFileCompare().compareAfterTaskStart(
      actionType, srcPath, dstPath, targets,
      // 작업결과 수신, 수신되는 대로 비동기실행 고려, batch구조: ['상대경로', ...]
      (item) {
        try {
          /// 작업에 따라 상태 변경: 원래상태 + 작업종류 -> 이후상태
          /// 
          /// |        | move AB | delete A | copy AB | move BA | delete B | copy AB |
          /// | ------ | ------- | -------- | ------- | ------- | -------- | ------- |
          /// | same   | onlyB   | onlyB    | same    | onlyA   | onlyA    | same    |
          /// | diff   | onlyB   | onlyB    | same    | onlyA   | onlyA    | same    |
          /// | onlyA  | onlyB   | (x)      | same    | onlyA   | onlyA    | onlyA   |
          /// | onlyB  | onlyB   | onlyB    | onlyB   | onlyA   | (x)      | same    |
          /// 
          CompareResult? resultItem = resultHashMap[item];
          if (resultItem == null) {
            /// 도중에 삭제된 상태임 -> 오류
          } else {
            if (isFromGroupA && resultItem.status == CompareStatus.onlyB
              || !isFromGroupA && resultItem.status == CompareStatus.onlyA) {
              // 추가작업 후에도 상태 변화가 없는 경우
            } else if (actionType == 'copy') {
              // 복사작업 후 상태가 변경된 경우 (양쪽이 같은 파일을 가짐)
              resultItem.status = CompareStatus.same;
              if (resultItem.group0 == null) {
                var currentFilePath = pathlib.join(group0BasePath, item);
                var currentFileStat = File(currentFilePath).statSync();
                resultItem.group0 = FileItem(
                  fullPath: currentFilePath,
                  relativePath: item,
                  fileSize: currentFileStat.size,
                  modified: currentFileStat.modified,
                  accessed: currentFileStat.accessed
                );
              }
              if (resultItem.group1 == null) {
                var currentFilePath = pathlib.join(group1BasePath, item);
                var currentFileStat = File(currentFilePath).statSync();
                resultItem.group1 = FileItem(
                  fullPath: currentFilePath,
                  relativePath: item,
                  fileSize: currentFileStat.size,
                  modified: currentFileStat.modified,
                  accessed: currentFileStat.accessed
                );
              }
            } else if (actionType == 'delete'
              && (isFromGroupA && resultItem.status == CompareStatus.onlyA
                || !isFromGroupA && resultItem.status == CompareStatus.onlyB)) {
              // 삭제작업 후 상태가 변경된 경우 (파일없앰)
              resultList.remove(resultItem);
              resultHashMap.remove(item);
            } else {
              // 이외 모든 상태 변경 (받는쪽만 파일존재)
              if (isFromGroupA) {
                resultItem.status = CompareStatus.onlyB;
                if (resultItem.group0 != null) {resultItem.group0 = null;}
                if (resultItem.group1 == null) {
                  var currentFilePath = pathlib.join(group1BasePath, item);
                  var currentFileStat = File(currentFilePath).statSync();
                  resultItem.group1 = FileItem(
                    fullPath: currentFilePath,
                    relativePath: item,
                    fileSize: currentFileStat.size,
                    modified: currentFileStat.modified,
                    accessed: currentFileStat.accessed
                  );
                }
              } else {
                resultItem.status = CompareStatus.onlyA;
                if (resultItem.group0== null) {
                  var currentFilePath = pathlib.join(group0BasePath, item);
                  var currentFileStat = File(currentFilePath).statSync();
                  resultItem.group0 = FileItem(
                    fullPath: currentFilePath,
                    relativePath: item,
                    fileSize: currentFileStat.size,
                    modified: currentFileStat.modified,
                    accessed: currentFileStat.accessed
                  );
                }
                if (resultItem.group1 != null) {resultItem.group1 = null;}
              }
            }
          }
        } catch (error) {
          showAlert(context, "추가작업 결과를 반영하던 중에 아래와 같은 문제가 발생하였습니다.\n\n$error");
        } finally {
          setState(() {
            currentItemIndex += 1;
            progressPercent = (entireItemIndex > 0)? currentItemIndex / entireItemIndex: 0.0;
          });
        }
      },
      // 작업 에러 발생
      (error) {
        showAlert(context, "추가작업 도중에 아래와 같은 문제가 발생하였습니다.\n\n$error");
      },
      // 작업 종료, 취소/에러되는 경우도 고려
      () {
        debugPrint('추가 작업 완료');
        setState(() {
          isAfterActionOngoing = false;
          sw.stop();
        });
      },
    );
    /// 추가작업 시작
    setState(() {
      progressPercent = 0;
      entireItemIndex = targets.length;
      currentItemIndex = 0;
      sw.reset();
      sw.start();
    });
  }

  /// 추가작업 취소
  void _afterActionCancel() {
    // 1. isolate 취소 호출
    ServiceFileCompare().compareAfterTaskCancel();
    // 2. 추가작업 상태자 변경, 타이머 정지
    setState(() {
      isAfterActionOngoing = false;
      sw.stop();
      if (progressPercent == -1) {progressPercent = 1.0;}
    });
    showAlert(context, '작업이 취소되었습니다.\n일부 중단된 내용들은 위 리스트에 상태가 반영되지 않았을 수도 있습니다. 내용을 확인해주세요.');
  }

  /// 작업에 따른 하단 버튼바
  Widget _buildBottomActionBar() {
    if (isAfterActionMode) {
      return Column(
        spacing: 8.0,
        children: [
          if(!isAfterActionOngoing) Row(
            spacing: 8.0,
            children: [
              const SizedBox(width: 80, child: Text('대상그룹', textAlign: TextAlign.center,)),
              _buildRadioSelection('Group A', 'AB'),
              _buildRadioSelection('Group B', 'BA'),
            ]
          ),
          if(!isAfterActionOngoing) Row(
            spacing: 8.0,
            children: [
              const SizedBox(width: 80, child: Text('대상상태', textAlign: TextAlign.center)),
              _buildCheckboxSelection('동일', 0),
              _buildCheckboxSelection('다름', 1),
              _buildCheckboxSelection('Group A만', 2),
              _buildCheckboxSelection('Group B만', 3),
            ]
          ),
          SizedBox(
            height: 48.0,
            child: Row(
              spacing: 8.0,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: Tooltip(
                  message: '지정한 대상그룹의 파일 중에\n선택한 상태의 파일만 "반대쪽 그룹"으로 이동합니다.\n같은 이름일 경우 덮어 씌워집니다.',
                  child: ElevatedButton.icon(
                    onPressed: (isAfterActionOngoing)? null: () {_afterActionInit('move');}, // 이동 작업 시작
                    icon: const Icon(Icons.drive_file_move),
                    label: const Text("병합(이동)")
                  ),
                )),
                Expanded(child: Tooltip(
                  message: '지정한 대상그룹의 파일 중에\n선택한 상태의 파일만 삭제합니다.',
                  child: ElevatedButton.icon(
                    onPressed: (isAfterActionOngoing)? null: () {_afterActionInit('delete');}, // 삭제 작업 시작
                    icon: const Icon(Icons.delete),
                    label: const Text("삭제"),
                  ),
                )),
                Expanded(child: Tooltip(
                  message: '지정한 대상그룹의 파일 중에\n선택한 상태의 파일만 "반대쪽 그룹"으로 복사합니다.\n같은 이름일 경우 덮어 씌워집니다.',
                  child: ElevatedButton.icon(
                    onPressed: (isAfterActionOngoing)? null: () {_afterActionInit('copy');}, // 복사 작업 시작
                    icon: const Icon(Icons.file_copy),
                    label: const Text("복사"),
                  ),
                )),
                Expanded(child: ElevatedButton.icon(
                  onPressed: (isAfterActionOngoing)
                    ? _afterActionCancel // 작업 취소
                    : () => setState(() {isAfterActionMode = false; isAfterActionOngoing = false;}),
                  icon: const Icon(Icons.cancel),
                  label: const Text("추가작업 취소"),
                )),
              ]
            ),
          ),
        ],
      );
    } else {
      return SizedBox(
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
            Expanded(child: ElevatedButton.icon(
              onPressed: (progressPercent == 1.0)? () {setState(() {isAfterActionMode = true; isAfterActionOngoing = false;});}: null,
              icon: const Icon(Icons.forward),
              label: const Text("추가작업"),
            )),
          ],
        ),
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
        child: _buildBottomActionBar(),
      ),
    ]);
  }
}