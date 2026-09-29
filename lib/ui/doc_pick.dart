import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme.dart';

/// A document picked on the phone (camera, photos or a PDF file).
typedef PickedDoc = ({Uint8List bytes, String name, String mime});

String _mime(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

/// Asks where the document comes from and returns it (null when cancelled). Photos are sent as JPEG,
/// scaled down so the AI reads them quickly.
Future<PickedDoc?> pickDoc(BuildContext context, {String title = 'إضافة مستند'}) async {
  final src = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final (k, icon, label) in [('camera', Icons.photo_camera_outlined, 'تصوير المستند'), ('gallery', Icons.photo_library_outlined, 'اختيار صورة'), ('file', Icons.picture_as_pdf_outlined, 'ملف PDF')])
          ListTile(leading: Icon(icon, color: C.primary), title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)), onTap: () => Navigator.pop(c, k)),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (src == null) return null;
  if (src == 'file') {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
    if (files.isEmpty) return null;
    final f = files.first;
    return (bytes: await f.readAsBytes(), name: f.name, mime: _mime(f.name));
  }
  final x = await ImagePicker().pickImage(source: src == 'camera' ? ImageSource.camera : ImageSource.gallery, maxWidth: 2400, imageQuality: 85);
  if (x == null) return null;
  final name = x.name.toLowerCase().endsWith('.heic') ? '${x.name.substring(0, x.name.length - 5)}.jpg' : x.name;
  return (bytes: await x.readAsBytes(), name: name, mime: _mime(name));
}
