import 'package:flutter_test/flutter_test.dart';
import 'package:passport_reader/core/passport/passport_reader.dart';

void main() {
  test('classifies common chip errors', () {
    expect(
      PassportReader.classifyError(Exception('Security status not satisfied')),
      PassportReadFailure.wrongKey,
    );
    expect(
      PassportReader.classifyError(Exception('Polling tag timeout')),
      PassportReadFailure.timeout,
    );
    expect(
      PassportReader.classifyError(Exception('Tag was lost.')),
      PassportReadFailure.tagLost,
    );
    expect(
      PassportReader.classifyError(Exception('Something odd')),
      PassportReadFailure.unknown,
    );
  });
  test('a timeout after the chip was found means the connection dropped', () {
    expect(
      PassportReader.classifyError(
        Exception('Transceive timeout'),
        stage: ReadStage.readingPhoto,
      ),
      PassportReadFailure.tagLost,
    );
  });
}
