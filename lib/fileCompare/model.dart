/// 파일 정보를 담기 위한 클래스
class FileItem {
  final String fullPath;     // 절대경로
  final String relativePath; // 드롭 시 기준 폴더로부터의 상대경로
  final int fileSize;        // 파일크기
  final DateTime accessed;   // 최근접속시각
  final DateTime modified;   // 최근변경시각

  FileItem({
    required this.fullPath,
    required this.relativePath,
    required this.fileSize,
    required this.accessed,
    required this.modified,
  });

  @override
  String toString() {
    return "$fullPath ($relativePath)";
  }
}

/// 비교 결과 상태값
enum CompareStatus {
  before,           // 비교중
  same,             // 동일
  diff,             // 다름
  onlyControl,      // 대조군에만 있음
  onlyExperimental, // 실험군에만 있음
  error,            // 오류
}