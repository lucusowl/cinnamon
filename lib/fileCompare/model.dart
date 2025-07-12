/// 파일 정보를 담기 위한 클래스
class FileItem {
  final String fullPath;
  final String fileName;
  final int fileSize;
  final DateTime accessed;
  final DateTime modified;
  final String relativePath; // 드롭 시 기준 폴더로부터의 상대경로

  FileItem({
    required this.fullPath,
    required this.fileName,
    required this.fileSize,
    required this.accessed,
    required this.modified,
    required this.relativePath,
  });

  @override
  String toString() {
    return "$fileName ($relativePath)";
  }
}

/// 비교 결과 상태값
enum CompareStatus {
  same,             // 동일
  diffSize,         // 다름(크기)
  diffHash,         // 다름(내용)
  onlyControl,      // 대조군에만 있음
  onlyExperimental, // 실험군에만 있음
}

/// 비교 상세 결과 객체값
class CompareResult {
  final CompareStatus status;
  final String? controlGroupHash;
  final String? experimentalGroupHash;
  final FileItem? controlGroupItem;
  final FileItem? experimentalGroupItem;

  CompareResult({
    required this.status,
    this.controlGroupHash,
    this.experimentalGroupHash,
    this.controlGroupItem,
    this.experimentalGroupItem,
  });
}