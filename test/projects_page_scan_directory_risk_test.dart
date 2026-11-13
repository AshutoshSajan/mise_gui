import 'package:flutter_test/flutter_test.dart';
import 'package:mise_gui/features/projects/presentation/projects_page.dart';

void main() {
  test('flags system and disk roots as risky scan directories', () {
    expect(
      scanDirectoryRiskForPath('/')?.message,
      contains('system root directory'),
    );
    expect(
      scanDirectoryRiskForPath('/Volumes/Macintosh HD')?.message,
      contains('macOS volume root'),
    );
    expect(
      scanDirectoryRiskForPath('/media/alex/Backup')?.message,
      contains('Linux mount root'),
    );
    expect(
      scanDirectoryRiskForPath(r'C:\')?.message,
      contains('Windows drive root'),
    );
    expect(
      scanDirectoryRiskForPath(r'\\server\share')?.message,
      contains('network share root'),
    );
  });

  test('does not flag normal project workspace directories', () {
    expect(scanDirectoryRiskForPath('/Users/alex/Projects'), isNull);
    expect(scanDirectoryRiskForPath('/home/alex/work/mise_gui'), isNull);
    expect(scanDirectoryRiskForPath(r'D:\Projects\mise_gui'), isNull);
  });
}
