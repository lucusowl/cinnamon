import 'package:cinnamon/fileCompare/compare_prepare.dart';
import 'package:cinnamon/fileCompare/compare_result.dart';
import 'package:cinnamon/fileCompare/model.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('파일 비교'),
      ),
      body: (compareMode == CompareMode.none)
        ? ComparePreparePage(
            controlGroup: controlGroup,
            experimentalGroup: experimentalGroup,
            onCompareWithPath: () { setState(() => compareMode = CompareMode.path); },
            onCompareWithAll: () { setState(() => compareMode = CompareMode.all); },
          )
        : CompareResultPage(
            compareMode: compareMode,
            controlGroup: controlGroup,
            experimentalGroup: experimentalGroup,
            onBack: () { setState(() => compareMode = CompareMode.none); },
            onReset: () { setState(() => compareMode = CompareMode.none); },
          ),
    );
  }
}