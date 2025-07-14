import 'dart:io';

import 'package:cinnamon/fileCompare/model.dart';
import 'package:cinnamon/fileCompare/util.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathlib;

class ComparePreparePage extends StatefulWidget {
  final List<List<String>> pathGroupList;
  final void Function() onCompareWithPath;
  final void Function() onCompareWithAll;
  

  const ComparePreparePage({
    super.key,
    required this.pathGroupList,
    required this.onCompareWithPath,
    required this.onCompareWithAll,
  });

  @override
  State<ComparePreparePage> createState() => ComparePreparePageState();
}

class ComparePreparePageState extends State<ComparePreparePage> {
  late final List<List<String>> pathGroupList;
  final List<TextEditingController> textControllerList = [];
  
  // drag-over 상태 표시용
  final List<bool> isSectionDragging = [];
  final List<bool> isSectionDropping = [];

  @override
  void initState() {
    super.initState();
    pathGroupList = widget.pathGroupList;
    // 전달받은 그룹의 수만큼 초기화
    for (var _ in pathGroupList) {
      textControllerList.add(TextEditingController());
      isSectionDragging.add(false);
      isSectionDropping.add(false);
    }
  }

  @override
  void dispose() {
    for (final controller in textControllerList) {controller.dispose();}
    super.dispose();
  }

  /// 중복된 영역이 있는 지 확인
  bool _isSubPath(String path1, String path2) {
    final normalizedPath1 = pathlib.normalize(pathlib.absolute(path1));
    final normalizedPath2 = pathlib.normalize(pathlib.absolute(path2));
    return normalizedPath1 == normalizedPath2 // 동일하거나
      || pathlib.isWithin(normalizedPath1, normalizedPath2) // 한쪽이 다른쪽에 포함된 경우
      || pathlib.isWithin(normalizedPath2, normalizedPath1);
  }

  /// 선택한 URIs -> pathGroupList
  Future<void> _onClickedURI(int sectionIndex) async {
    /// TODO: Windows 기준, 폴더 탐색기 열기
    /// 우선, 입력완료버튼 으로 구현
    _onSubmittedURI(sectionIndex, textControllerList[sectionIndex].text);
  }
  /// 입력한 경로 -> pathGroupList
  Future<void> _onSubmittedURI(int sectionIndex, String uri) async {
    if (await FileSystemEntity.type(uri) == FileSystemEntityType.notFound) {
      showAlert(context, "대상을 찾을 수 없습니다.");
      return;
    }
    final List<String> targetGroup = pathGroupList[sectionIndex];
    bool isDuplicated = false;
    // 같은 그룹에 중복된 내용이 있는 지 확인
    for (final targetPath in targetGroup) {
      // 한 쪽이 다른 쪽에 포함되는 절대경로를 가진 경우
      if (_isSubPath(targetPath, uri)) {
        isDuplicated = true;
        break;
      }
    }
    if (isDuplicated) {
      showAlert(context, "이미 업로드된 대상과 겹칩니다.");
    } else {
      targetGroup.add(uri);
    }
  }
  /// 드롭된 URIs -> pathGroupList
  Future<void> _onDroppedURI(int sectionIndex, List<DropItem> uris) async {
    final List<String> targetGroup = pathGroupList[sectionIndex];
    final List<String> noExistsGroup = [];
    final List<String> duplicateGroup = [];
    for (var uri in uris) {
      final String currentPath = uri.path;
      // 존재하는 파일/폴더인 지 확인
      if (await FileSystemEntity.type(currentPath) == FileSystemEntityType.notFound) {
        noExistsGroup.add(currentPath);
        continue;
      }
      bool isDuplicated = false;
      // 같은 그룹에 중복된 내용이 있는 지 확인
      for (final targetPath in targetGroup) {
        if (_isSubPath(targetPath, currentPath)) {
          isDuplicated = true;
          duplicateGroup.add(currentPath);
          break;
        }
      }
      if (isDuplicated) {
        continue; // 중복된 내용은 제외
      } else {
        targetGroup.add(currentPath);
      }
    }
    // 중복된 내용 알림
    if (noExistsGroup.isNotEmpty) {
      showAlert(context,
        "아래의 대상들은 찾을 수 없어 업로드되지 않았습니다.\n\n"
        "--- 찾을 수 없는 대상 목록---\n* ${noExistsGroup.join('\n* ')}"
      );
    }
    if (duplicateGroup.isNotEmpty) {
      showAlert(context,
        "이미 업로드되어 있는 대상들과 겹칩니다.\n"
        "겹치지 않는 대상들은 업로드가 완료되었습니다.\n\n"
        "--- 중복된 목록 (${duplicateGroup.length}개)---\n* ${duplicateGroup.join('\n* ')}"
      );
    }
  }

  /// 해당 집단 목록 비우기
  void clearTargetGroup(int sectionIndex) {
    setState(() => pathGroupList[sectionIndex].clear());
  }
  /// 해당 집단 목록에서 삭제
  void removeFromTargetGroup(int sectionIndex, int pathIndex) {
    setState(() => pathGroupList[sectionIndex].removeAt(pathIndex));
  }

  /// 해당 집단 목록 영역
  Widget _targetPathList(int sectionIndex) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: Container(
              padding: EdgeInsets.all(16.0),
              constraints: BoxConstraints(maxWidth: 1200),
              child: Column(
                children: [
                  TextField(
                    controller: textControllerList[sectionIndex],
                    onSubmitted: (value) async {
                      setState(() => isSectionDropping[sectionIndex] = true);
                      await _onSubmittedURI(sectionIndex, value);
                      setState(() {
                        isSectionDropping[sectionIndex] = false;
                        textControllerList[sectionIndex].clear();
                      });
                    },
                    decoration: InputDecoration(
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                      border: OutlineInputBorder(),
                      hintText: "(Group $sectionIndex) 추가할 경로를 입력하세요...",
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
                      suffixIcon: IconButton(
                        onPressed: () => clearTargetGroup(sectionIndex),
                        tooltip: "모두 비우기",
                        icon: Icon(Icons.cleaning_services)
                      ),
                    ),
                  ),
                  Expanded(
                    child: (pathGroupList[sectionIndex].isEmpty)
                    ? Center(child: Text("여기에 파일 또는 디렉토리를 드래그하세요..."),)
                    : ListView.builder(
                      itemCount: pathGroupList[sectionIndex].length,
                      itemBuilder: (context, index) {
                        return Tooltip(
                          message: '',
                          child: Column(
                            children: [
                              ListTile(
                                leading: Icon(Icons.insert_drive_file), // TODO: 하위의 모든 내용이 업로드되면 폴더/파일아이콘으로 변경
                                title: SelectableText(pathGroupList[sectionIndex][index]),
                                trailing: IconButton(
                                  onPressed: () => removeFromTargetGroup(sectionIndex, index),
                                  icon: Icon(Icons.delete),
                                ),
                              ),
                              const Divider(height: 0),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
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
    for (final pathGroup in pathGroupList) {
      if (pathGroup.isEmpty) {
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
    for (final pathGroup in pathGroupList) {
      if (pathGroup.isEmpty) {
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