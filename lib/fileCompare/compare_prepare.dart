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
  final List<FileItem> leftFiles;
  final List<FileItem> rightFiles;
  final Function() onCompareWithPath;
  final Function() onCompareWithAll;

  const ComparePreparePage({
    super.key,
    required this.leftFiles,
    required this.rightFiles,
    required this.onCompareWithPath,
    required this.onCompareWithAll,
  });

  @override
  State<ComparePreparePage> createState() => ComparePreparePageState();
}

class ComparePreparePageState extends State<ComparePreparePage> {
  late final List<FileItem> leftFiles;
  late final List<FileItem> rightFiles;
  // drag-over 상태 표시용 (UI 개선)
  bool leftDragging = false;
  bool rightDragging = false;
  bool isLeftDropping = false;
  bool isRightDropping = false;

  @override
  void initState() {
    super.initState();
    leftFiles = widget.leftFiles;
    rightFiles = widget.rightFiles;
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

  /// 좌측/우측 파일 목록을 보여주는 위젯
  Widget _buildFileList(List<FileItem> files, {required bool isLeft}) {
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
        if ((isLeft && isLeftDropping) || (!isLeft && isRightDropping)) ...[
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
    if (leftFiles.isEmpty || rightFiles.isEmpty) {
      showAlert(context, "양쪽 모두 업로드해주세요.");
      return;
    }
    widget.onCompareWithPath();
  }
  /// 버튼 클릭시 비교 수행, 전체 파일 비교
  Future<void> _onButtonCompareWithAll() async {
    if (leftFiles.isEmpty || rightFiles.isEmpty) {
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
          // 좌측 드롭 영역
          Expanded(
            child: DropTarget(
              onDragDone: (details) async {
                setState(() { isLeftDropping = true; });
                await _processDroppedItems(details.files, isLeft: true);
                setState(() { isLeftDropping = false; });
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
                      color: leftDragging
                        ? Theme.of(context).colorScheme.outline
                        : Theme.of(context).colorScheme.outlineVariant,
                      width: 2.0),
                ),
                child: _buildFileList(leftFiles, isLeft: true),
              ),
            ),
          ),
          // 우측 드롭 영역
          Expanded(
            child: DropTarget(
              onDragDone: (details) async {
                setState(() { isRightDropping = true; });
                await _processDroppedItems(details.files, isLeft: false);
                setState(() { isRightDropping = false; });
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
                      color: rightDragging
                        ? Theme.of(context).colorScheme.outline
                        : Theme.of(context).colorScheme.outlineVariant,
                      width: 2.0),
                ),
                child: _buildFileList(rightFiles, isLeft: false),
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
                child: Text("전체 파일 비교"),
              ),
            ),
          ],
        ),
      ),
    ]);
  }
}