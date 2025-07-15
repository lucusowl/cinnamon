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
  diff,             // 다름
  onlyControl,      // 대조군에만 있음
  onlyExperimental, // 실험군에만 있음
}

/// 비교 상세 결과 객체
class CompareResult {
  CompareStatus status;
  FileItem? group0;
  FileItem? group1;

  CompareResult({
    required this.status,
    this.group0,
    this.group1,
  });
}

/// 예외처리용
class FileException implements Exception {
  final String message;
  FileException(this.message);

  @override
  String toString() => 'FileException: $message';
}