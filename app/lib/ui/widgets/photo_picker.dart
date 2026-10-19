import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../strings.dart';
import '../theme.dart';

/// Adding profile photos (SPEC §9.17): camera or gallery, then every new photo
/// opens the crop / rotate editor before it is uploaded. Cancelling the editor
/// keeps the photo as it was taken — the agent can still edit or remove it
/// from the form until the profile is saved.
class PhotoPicker {
  PhotoPicker._();

  static final _picker = ImagePicker();
  static final _cropper = ImageCropper();

  /// Longest side handed to the editor; the server keeps at most 1280 px, so
  /// this only trims upload time without losing anything that is stored.
  static const double _maxSide = 2560;

  /// Camera or gallery, up to [remaining] photos, each run through the editor.
  /// Empty when the agent backs out.
  static Future<List<XFile>> pick(BuildContext context, {required int remaining}) async {
    if (remaining <= 0) return const [];
    final source = await _askSource(context, remaining);
    if (source == null) return const [];

    final List<XFile> picked;
    // pickMultiImage refuses a limit below 2, so one free slot is a single pick.
    if (source == ImageSource.camera || remaining == 1) {
      final shot = await _picker.pickImage(
        source: source,
        imageQuality: 92,
        maxWidth: _maxSide,
        maxHeight: _maxSide,
      );
      picked = shot == null ? const [] : [shot];
    } else {
      picked = await _picker.pickMultiImage(
        imageQuality: 92,
        maxWidth: _maxSide,
        maxHeight: _maxSide,
        limit: remaining,
      );
    }

    final out = <XFile>[];
    for (final file in picked.take(remaining)) {
      if (!context.mounted) break;
      out.add(await edit(context, file) ?? file);
    }
    return out;
  }

  /// Opens the editor on one photo; null when the agent cancels.
  static Future<XFile?> edit(BuildContext context, XFile file) async {
    final cropped = await _cropper.cropImage(
      sourcePath: file.path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 92,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: S.editPhoto,
          toolbarColor: AppColors.navy,
          toolbarWidgetColor: Colors.white,
          statusBarLight: false,
          activeControlsWidgetColor: AppColors.goldLight,
          // Free crop: the frame starts portrait but any shape is allowed.
          lockAspectRatio: false,
          initAspectRatio: _PhotoRatio.portrait,
          aspectRatioPresets: _PhotoRatio.presets,
        ),
        IOSUiSettings(title: S.editPhoto, aspectRatioPresets: _PhotoRatio.presets),
      ],
    );
    return cropped == null ? null : XFile(cropped.path);
  }

  static Future<ImageSource?> _askSource(BuildContext context, int remaining) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(S.addPhotos, style: theme.textTheme.titleMedium),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    S.photoEditHint,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text(S.takePhoto),
                  subtitle: const Text(S.takePhotoHint),
                  onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text(S.chooseFromGallery),
                  subtitle: Text(S.chooseFromGalleryHint(remaining)),
                  onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The editor's frame presets. uCrop shows [name] on its ratio tabs and picks
/// the starting one by name.
class _PhotoRatio implements CropAspectRatioPresetData {
  const _PhotoRatio(this.name, this.data);

  @override
  final String name;

  @override
  final (int, int)? data;

  static const portrait = _PhotoRatio('4:5', (4, 5));

  static const presets = <CropAspectRatioPresetData>[
    CropAspectRatioPreset.original,
    portrait,
    _PhotoRatio('3:4', (3, 4)),
    _PhotoRatio('Square', (1, 1)),
    _PhotoRatio('16:9', (16, 9)),
  ];
}
