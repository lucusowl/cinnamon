import 'dart:io';

import 'package:cinnamon/fileCompare/compare_prepare.dart';
import 'package:cinnamon/fileCompare/compare_result_all.dart';
import 'package:cinnamon/fileCompare/compare_result_path.dart';
import 'package:cinnamon/fileCompare/model.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathlib;

enum CompareMode {
  none, // 비교 없음
  path, // 경로 기반 비교
  all,  // 전체 대상 비교 = 중복 검사
}

class FileCompareScreen extends StatefulWidget {
  const FileCompareScreen({super.key});

  @override
  State<FileCompareScreen> createState() => _FileCompareScreenState();
}

class _FileCompareScreenState extends State<FileCompareScreen> {
  CompareMode compareMode = CompareMode.none;

  // 전체 그룹군 = 대조군, 실험군
  List<List<String>> pathGroupList = [[],[]];
  // 대조군과 실험군
  List<FileItem> controlGroup = [];
  List<FileItem> experimentalGroup = [];

  /// 비교 대상들을 모두 파일 그룹으로 변환
  /// TODO: 전역화 -> 대상으로 올리면 바로 작업이 시작될 수 있도록
  Future<List<FileItem>> _convertPathGroupToFileGroup(List<String> pathGroup) async {
    final List<FileItem> buffer = [];
    for (final String path in pathGroup) {
      final FileSystemEntityType fileEntityType = FileSystemEntity.typeSync(path);
      if (fileEntityType == FileSystemEntityType.directory) {
        await for (FileSystemEntity entity in Directory(path).list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final fileStat = await entity.stat();
            buffer.add(FileItem(
              fullPath: entity.path,
              fileName: entity.uri.pathSegments.last,
              fileSize: fileStat.size,
              accessed: fileStat.accessed,
              modified: fileStat.modified,
              relativePath: pathlib.relative(entity.path, from:path),
            ));
          }
        }
      } else if (fileEntityType == FileSystemEntityType.file) {
        final fileStat = await File(path).stat();
        buffer.add(FileItem(
          fullPath: path,
          fileName: pathlib.basename(path),
          fileSize: fileStat.size,
          accessed: fileStat.accessed,
          modified: fileStat.modified,
          relativePath: pathlib.relative(path, from:pathlib.basename(path)),
        ));
      } else if (fileEntityType == FileSystemEntityType.notFound) {
        // 대상이 존재하지 않음
        throw FileException('존재하지 않음: $path');
      } else {
        // 부적절한 파일 형식
        throw FileException('처리할 수 없는 파일 형식: $path');
      }
    }
    return buffer;
  }

  @override
  Widget build(BuildContext context) {
    late final Widget mainBodyWidget;
    switch (compareMode) {
      case CompareMode.path:
      mainBodyWidget = CompareResultPathPage(
        controlGroup: controlGroup,
        experimentalGroup: experimentalGroup,
        onBack: () {
          setState(() => compareMode = CompareMode.none);
        },
        onReset: () {
          for (final pathGroup in pathGroupList) pathGroup.clear();
          controlGroup.clear();
          experimentalGroup.clear();
          setState(() => compareMode = CompareMode.none);
        },
      );
      break;
      case CompareMode.all:
      mainBodyWidget = CompareResultAllPage(
        controlGroup: controlGroup,
        experimentalGroup: experimentalGroup,
        onBack: () {
          setState(() => compareMode = CompareMode.none);
        },
        onReset: () {
          for (final pathGroup in pathGroupList) pathGroup.clear();
          controlGroup.clear();
          experimentalGroup.clear();
          setState(() => compareMode = CompareMode.none);
        },
      );
      break;
      case CompareMode.none:
      mainBodyWidget = ComparePreparePage(
        pathGroupList: pathGroupList,
        onCompareWithPath: () async {
          final sw = Stopwatch()..start();
          await Future.wait([
            _convertPathGroupToFileGroup(pathGroupList[0]).then((ret) => controlGroup = ret),
            _convertPathGroupToFileGroup(pathGroupList[1]).then((ret) => experimentalGroup = ret),
          ]);
          sw.stop();
          debugPrint('변환시간: ${sw.elapsed.toString()}');
          setState(() => compareMode = CompareMode.path);
        },
        onCompareWithAll: () async {
          final sw = Stopwatch()..start();
          await Future.wait([
            _convertPathGroupToFileGroup(pathGroupList[0]).then((ret) => controlGroup = ret),
            _convertPathGroupToFileGroup(pathGroupList[1]).then((ret) => experimentalGroup = ret),
          ]);
          sw.stop();
          debugPrint('변환시간: ${sw.elapsed.toString()}');
          setState(() => compareMode = CompareMode.all);
        },
      );
      break;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('파일 비교')),
      body: mainBodyWidget
    );
  }
}