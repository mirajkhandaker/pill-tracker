import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../core/utils/prescription_parser.dart';

/// Reads the text on a prescription photo, on the device (no internet, the
/// photo never leaves the phone), as rows from top to bottom.
class TextScanService {
  const TextScanService();

  Future<List<String>> readRows(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      return groupIntoRows([
        for (final block in result.blocks)
          for (final line in block.lines)
            OcrLine(
              line.text,
              left: line.boundingBox.left,
              top: line.boundingBox.top,
              right: line.boundingBox.right,
              bottom: line.boundingBox.bottom,
            ),
      ]);
    } finally {
      await recognizer.close();
    }
  }
}
