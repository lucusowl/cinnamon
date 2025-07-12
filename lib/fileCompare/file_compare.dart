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

  // 좌측과 우측 파일 목록 저장
  List<FileItem> leftFiles = [];
  List<FileItem> rightFiles = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('파일 비교'),
      ),
      body: (compareMode == CompareMode.none)
        ? ComparePreparePage(
            leftFiles: leftFiles,
            rightFiles: rightFiles,
            onCompareWithPath: () { setState(() => compareMode = CompareMode.path); },
            onCompareWithAll: () { setState(() => compareMode = CompareMode.all); },
          )
        : CompareResultPage(
            compareMode: compareMode,
            leftFiles: leftFiles,
            rightFiles: rightFiles,
            onBack: () { setState(() => compareMode = CompareMode.none); },
            onReset: () { setState(() => compareMode = CompareMode.none); },
          ),
    );
  }
}