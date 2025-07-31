import 'dart:io';

import 'package:cinnamon/fileCompare/service.dart';
import 'package:cinnamon/fileCompare/util.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

class ComparePreparePage extends StatefulWidget {
  final void Function() onCompareWithPath;
  final void Function() onCompareWithAll;

  const ComparePreparePage({
    super.key,
    required this.onCompareWithPath,
    required this.onCompareWithAll,
  });

  @override
  State<ComparePreparePage> createState() => ComparePreparePageState();
}

class ComparePreparePageState extends State<ComparePreparePage> {
  late final List<String?> pathGroup;
  final List<TextEditingController> textControllerList = [];
  
  // drag-over 상태 표시용
  final List<bool> isSectionDragging = [];
  final List<bool> isSectionDropping = [];

  @override
  void initState() {
    super.initState();
    pathGroup = ServiceFileCompare().pathGroup;
    // 전달받은 그룹의 수만큼 초기화
    for (var path in pathGroup) {
      textControllerList.add(TextEditingController(text: path));
      isSectionDragging.add(false);
      isSectionDropping.add(false);
    }
  }

  @override
  void dispose() {
    for (final controller in textControllerList) {controller.dispose();}
    super.dispose();
  }

  /// 선택한 URIs -> pathGroup
  Future<void> _onClickedURI(int sectionIndex) async {
    /// TODO: Windows 기준, 폴더 탐색기 열기 -> 우선, 입력완료버튼 으로 구현
    _onSubmittedURI(sectionIndex, textControllerList[sectionIndex].text);
  }
  /// 입력한 경로 -> pathGroup
  Future<void> _onSubmittedURI(int sectionIndex, String uri) async {
    if (await FileSystemEntity.type(uri) == FileSystemEntityType.notFound) {
      showAlert(context, "대상을 찾을 수 없습니다.");
      return;
    }
    // 바로 하위 파일내용 불러오는 작업 시작
    ServiceFileCompare().uploadTaskStart(sectionIndex, uri);
  }
  /// 드롭된 URIs -> pathGroup
  Future<void> _onDroppedURI(int sectionIndex, List<DropItem> uris) async {
    if (uris.length < 1) {
      showAlert(context, "1개 이상의 대상만 업로드가 가능합니다.");
      return;
    }
    else if (uris.length > 1) {
      showAlert(context, "가장 1번째 대상만 업로드됩니다.");
    }
    String uri = uris[0].path;
    if (await FileSystemEntity.type(uri) == FileSystemEntityType.notFound) {
      showAlert(context, "대상을 찾을 수 없습니다.");
      return;
    }
    textControllerList[sectionIndex].text = uri;
    // 바로 하위 파일내용 불러오는 작업 시작
    ServiceFileCompare().uploadTaskStart(sectionIndex, uri);
  }

  /// 해당 집단 목록 비우기
  void clearTargetGroup(int sectionIndex) {
    setState(() {
      ServiceFileCompare().uploadTaskCancel(sectionIndex);
      textControllerList[sectionIndex].clear();
    });
  }

  /// 해당 집단 목록 영역
  Widget _targetPathList(int sectionIndex) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: Container(
              padding: EdgeInsets.all(32.0),
              constraints: BoxConstraints(maxWidth: 1200),
              child: TextField(
                controller: textControllerList[sectionIndex],
                onSubmitted: (value) async {
                  setState(() => isSectionDropping[sectionIndex] = true);
                  await _onSubmittedURI(sectionIndex, value);
                  setState(() => isSectionDropping[sectionIndex] = false);
                },
                decoration: InputDecoration(
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                  border: OutlineInputBorder(),
                  hintText: "(Group $sectionIndex) 여기에 파일/디렉토리를 드래그 하거나 경로를 입력하세요...",
                  hintStyle: TextStyle(color: Theme.of(context).colorScheme.outlineVariant),
                  prefixIcon: IconButton(
                    onPressed: () async {
                      setState(() => isSectionDropping[sectionIndex] = true);
                      await _onClickedURI(sectionIndex);
                      setState(() => isSectionDropping[sectionIndex] = false);
                    },
                    tooltip: "폴더 직접 선택",
                    icon: Icon(Icons.file_open)
                  ),
                  suffixIcon: (pathGroup[sectionIndex] == null)
                  ? null
                  : IconButton(
                    onPressed: () => clearTargetGroup(sectionIndex),
                    tooltip: "대상에서 제외",
                    icon: const Icon(Icons.delete),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 대상 집단 설정 영역
  Widget _selectTargetPathSection(int sectionIndex) {
    return DropTarget(
      onDragDone: (details) async {
        setState(() => isSectionDropping[sectionIndex] = true);
        await _onDroppedURI(sectionIndex, details.files);
        setState(() => isSectionDropping[sectionIndex] = false);
      },
      onDragEntered: (_) => setState(() => isSectionDragging[sectionIndex] = true),
      onDragExited: (_) => setState(() => isSectionDragging[sectionIndex] = false),
      child: Container(
        decoration: BoxDecoration(
          color: (isSectionDragging[sectionIndex])
            ? Theme.of(context).colorScheme.outlineVariant
            : null,
          border: Border.all(
            color: (isSectionDragging[sectionIndex])
              ? Theme.of(context).colorScheme.outline
              : Theme.of(context).colorScheme.outlineVariant,
            width: 2.0
          ),
        ),
        child: _targetPathList(sectionIndex),
      ),
    );
  }

  /// 버튼 클릭시 비교 수행, 경로 기반 비교
  Future<void> _onButtonCompareWithPath() async {
    for (final path in pathGroup) {
      if (path == null) {
        showAlert(context, "모든 Group에 비교할 대상을 업로드해주세요.");
        return;
      }
    }
    if (mounted) {
      try {
        widget.onCompareWithPath();
      } on FileException catch (e) {
        // 변환도중 오류 발생
        showAlert(context, "아래와 같은 에러가 발생했습니다.\n${e.message}");
      } catch (e) {
        showAlert(context, "아래와 같은 예상치 못한 에러가 발생했습니다.\n$e");
      }
    }
  }
  /// 버튼 클릭시 비교 수행, 중복 파일 검사
  Future<void> _onButtonCompareWithAll() async {
    for (final path in pathGroup) {
      if (path == null) {
        showAlert(context, "모든 Group에 비교할 대상을 업로드해주세요.");
        return;
      }
    }
    if (mounted) {
      try {
        widget.onCompareWithAll();
      } on FileException catch (e) {
        // 변환도중 오류 발생
        showAlert(context, "아래와 같은 에러가 발생했습니다.\n${e.message}");
      } catch (e) {
        showAlert(context, "아래와 같은 예상치 못한 에러가 발생했습니다.\n$e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          spacing: 8.0,
          children: [
            // 대조군 드롭 영역, Section0
            Expanded(child: _selectTargetPathSection(0)),
            // 실험군 드롭 영역, Section1
            Expanded(child: _selectTargetPathSection(1)),
          ],
        ),
      )),
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
              Expanded(child: Tooltip(
                message: '파일의 경로와 내용이 같아야 동일\n파일 경로는 상대경로(입력 위치가 최상위 경로)를 기준',
                waitDuration: Duration(milliseconds: 500),
                child: ElevatedButton.icon(
                  onPressed: _onButtonCompareWithPath,
                  icon: const Icon(Icons.manage_search),
                  label: const Text("경로 기반 비교")
                ),
              )),
              Expanded(child: Tooltip(
                message: '파일의 경로와 상관없이 내용만 같아도 동일',
                waitDuration: Duration(milliseconds: 500),
                child: ElevatedButton.icon(
                  onPressed: _onButtonCompareWithAll,
                  icon: const Icon(Icons.search),
                  label: const Text("중복 파일 검사"),
                ),
              )),
            ],
          ),
        ),
      ),
    ]);
  }
}