import 'package:flutter/material.dart';
import 'dart:io';

class AttachmentPreviewScreen extends StatefulWidget {
  final File file;
  final String type; // 'image' или 'file'

  const AttachmentPreviewScreen({
    super.key,
    required this.file,
    required this.type,
  });

  @override
  State<AttachmentPreviewScreen> createState() => _AttachmentPreviewScreenState();
}

class _AttachmentPreviewScreenState extends State<AttachmentPreviewScreen> {
  final _captionController = TextEditingController();

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  void _send() {
    Navigator.pop(context, _captionController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.file.path.split('/').last;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Отправка'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: widget.type == 'image'
                  ? InteractiveViewer(
                      child: Image.file(widget.file),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.insert_drive_file, size: 80),
                          const SizedBox(height: 16),
                          Text(
                            fileName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _captionController,
                      decoration: const InputDecoration(
                        hintText: 'Подпись (необязательно)...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}