import 'package:cinnamon/fileCompare/compare_prepare.dart';
import 'package:cinnamon/fileCompare/compare_result_all.dart';
import 'package:cinnamon/fileCompare/compare_result_path.dart';
import 'package:cinnamon/fileCompare/model.dart';
import 'package:cinnamon/fileCompare/service.dart';
import 'package:flutter/material.dart';

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

  // 대조군과 실험군
  List<FileItem> controlGroup = [];
  List<FileItem> experimentalGroup = [];

  @override
  Widget build(BuildContext context) {
    late final Widget mainBodyWidget;
    switch (compareMode) {
      case CompareMode.path:
      mainBodyWidget = CompareResultPathPage(
        onBack: () {
          ServiceFileCompare().serviceReset(restart: true);
          setState(() => compareMode = CompareMode.none);
        },
        onReset: () {
          ServiceFileCompare().serviceReset();
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
          ServiceFileCompare().serviceReset();
          controlGroup.clear();
          experimentalGroup.clear();
          setState(() => compareMode = CompareMode.none);
        },
      );
      break;
      case CompareMode.none:
      mainBodyWidget = ComparePreparePage(
        onCompareWithPath: () {
          setState(() => compareMode = CompareMode.path);
        },
        onCompareWithAll: () {
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