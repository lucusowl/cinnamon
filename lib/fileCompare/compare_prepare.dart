import 'dart:io';

import 'package:cinnamon/fileCompare/model.dart';
import 'package:cinnamon/fileCompare/util.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathlib;

/// 커스텀 colors
extension AppColors on ColorScheme {
  Color get overlayBackground => (brightness == Brightness.dark) ? const Color(0x33ffffff): const Color(0x33000000);
}

class ComparePreparePage extends StatefulWidget {
  final List<FileItem> controlGroup;
  final List<FileItem> experimentalGroup;
  final Function() onCompareWithPath;
  final Function() onCompareWithAll;

  const ComparePreparePage({
    super.key,
    required this.controlGroup,
    required this.experimentalGroup,
    required this.onCompareWithPath,
    required this.onCompareWithAll,
  });

  @override
  State<ComparePreparePage> createState() => ComparePreparePageState();
}

class ComparePreparePageState extends State<ComparePreparePage> {
  late final List<FileItem> controlGroup;
  late final List<FileItem> experimentalGroup;
  // drag-over 상태 표시용 (UI 개선)
  bool section0Dragging = false;
  bool section1Dragging = false;
  bool isSection0Dropping = false;
  bool isSection1Dropping = false;

  @override
  void initState() {
    super.initState();
    controlGroup = widget.controlGroup;
    experimentalGroup = widget.experimentalGroup;
  }

  /// 드롭된 URL(파일/디렉토리 경로)를 처리하여 파일 목록에 추가
  Future<void> _processDroppedItems(List<DropItem> urls, {required bool isControl}) async {
    List<FileItem> newFiles = [];
    List<FileItem> targetFiles = (isControl ? controlGroup: experimentalGroup);
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
      showAlert(context, "${duplicateFiles.length}개의 파일이 이미 업로드 되어있습니다.\n\n--- 중복된 파일 목록---\n${duplicateFiles.join('\n')}");
    }
    setState(() {
      targetFiles.addAll(newFiles);
    });
  }

  /// 각 집단 파일 목록을 보여주는 위젯
  Widget _buildFileList(List<FileItem> files, {required bool isControl}) {
    return Stack(
      children: [
        Column(
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
              child: (files.isEmpty)
                ? Container(
                    padding: EdgeInsets.all(8.0),
                    child: Text("여기에 파일 또는 디렉토리를 드래그하세요."),
                  )
                : ListView.separated(
                    separatorBuilder: (context, index) { return const Divider(height: 0); },
                    itemCount: files.length+1,
                    itemBuilder: (context, index) {
                      if (index == files.length) { return const Divider(height: 0); } // 최 하단에 구분선
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
        ),

        // 파일이 업로드 되고 있는 동안에는 대기 표시
        if ((isControl && isSection0Dropping) || (!isControl && isSection1Dropping)) ...[
          Positioned.fill(
            child: Container(
              color: Theme.of(context).colorScheme.overlayBackground,
              child: const Center(child: CircularProgressIndicator(),),
            ),
          ),
        ],
      ],
    );
  }

  /// 버튼 클릭시 비교 수행, 경로 기반 비교
  Future<void> _onButtonCompareWithPath() async {
    if (controlGroup.isEmpty || experimentalGroup.isEmpty) {
      showAlert(context, "양쪽 모두 업로드해주세요.");
      return;
    }
    widget.onCompareWithPath();
  }
  /// 버튼 클릭시 비교 수행, 중복 파일 검사
  Future<void> _onButtonCompareWithAll() async {
    if (controlGroup.isEmpty || experimentalGroup.isEmpty) {
      showAlert(context, "양쪽 모두 업로드해주세요.");
      return;
    }
    widget.onCompareWithAll();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(child: Row(
        children: [
          // 대조군 드롭 영역, Section0
          Expanded(
            child: DropTarget(
              onDragDone: (details) async {
                setState(() { isSection0Dropping = true; });
                await _processDroppedItems(details.files, isControl: true);
                setState(() { isSection0Dropping = false; });
              },
              onDragEntered: (_) {
                setState(() {
                  section0Dragging = true;
                });
              },
              onDragExited: (_) {
                setState(() {
                  section0Dragging = false;
                });
              },
              child: Container(
                margin: EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: section0Dragging
                        ? Theme.of(context).colorScheme.outline
                        : Theme.of(context).colorScheme.outlineVariant,
                      width: 2.0),
                ),
                child: _buildFileList(controlGroup, isControl: true),
              ),
            ),
          ),
          // 비교군 드롭 영역, Section1
          Expanded(
            child: DropTarget(
              onDragDone: (details) async {
                setState(() { isSection1Dropping = true; });
                await _processDroppedItems(details.files, isControl: false);
                setState(() { isSection1Dropping = false; });
              },
              onDragEntered: (_) {
                setState(() {
                  section1Dragging = true;
                });
              },
              onDragExited: (_) {
                setState(() {
                  section1Dragging = false;
                });
              },
              child: Container(
                margin: EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: section1Dragging
                        ? Theme.of(context).colorScheme.outline
                        : Theme.of(context).colorScheme.outlineVariant,
                      width: 2.0),
                ),
                child: _buildFileList(experimentalGroup, isControl: false),
              ),
            ),
          ),
        ],
      )),
      const Divider(height: 8, thickness: 2,),
      // 비교 버튼 및 결과 표시
      Padding(
        padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 16.0),
        child: Column(
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
                onPressed: _onButtonCompareWithAll,
                child: Text("중복 파일 검사"),
              ),
            ),
          ],
        ),
      ),
    ]);
  }
}