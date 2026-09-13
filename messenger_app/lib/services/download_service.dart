import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class DownloadService {
  static Future<Map<String, dynamic>> downloadFile(String url, String fileName) async {
    try {
      // На Android 13+ (API 33+) специальное разрешение на запись не требуется
      // для скачивания в публичную папку через MediaStore, но на более старых
      // версиях может понадобиться разрешение на хранилище
      if (Platform.isAndroid) {
        final androidInfo = await Permission.storage.status;
        if (androidInfo.isDenied) {
          await Permission.storage.request();
        }
      }

      final directory = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory('${directory.path}/downloads');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      final savePath = '${downloadsDir.path}/$fileName';

      final dio = Dio();
      await dio.download(url, savePath);

      return {'success': true, 'path': savePath};
    } catch (error) {
      return {'success': false, 'error': 'Не удалось скачать файл: $error'};
    }
  }
}