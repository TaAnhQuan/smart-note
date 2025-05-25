part of 'editor_image.dart';

class PdfEditorImage extends EditorImage {
  Uint8List? pdfBytes;
  final int pdfPage;

  /// If the pdf needs to be loaded from disk, this is the File
  /// that the pdf will be loaded from.
  final File? pdfFile;

  final _pdfDocument = ValueNotifier<PdfDocument?>(null);

  static final log = Logger('PdfEditorImage');

  PdfEditorImage({
    required super.id,
    required super.assetCache,
    required this.pdfBytes,
    required this.pdfFile,
    required this.pdfPage,
    required super.pageIndex,
    required super.pageSize,
    super.invertible,
    super.backgroundFit,
    required super.onMoveImage,
    required super.onDeleteImage,
    required super.onMiscChange,
    super.onLoad,
    super.newImage,
    super.dstRect,
    required super.naturalSize,
    super.isThumbnail,
  })  : assert(
            !naturalSize.isEmpty, 'naturalSize must be set for PdfEditorImage'),
        assert(pdfBytes != null || pdfFile != null,
            'pdfFile must be set if pdfBytes is null'),
        super(
          extension: '.pdf',
          srcRect: Rect.zero,
        );

  factory PdfEditorImage.fromJson(
    Map<String, dynamic> json, {
    required List<Uint8List>? inlineAssets,
    bool isThumbnail = false,
    required String sbnPath,
    required AssetCache assetCache,
  }) {
    String? extension = json['e'] as String?;
    assert(extension == null || extension == '.pdf');

    final assetIndex = json['a'] as int?;
    final Uint8List? pdfBytes;
    File? pdfFile;
    if (assetIndex != null) {
      if (inlineAssets == null) {
        pdfFile =
            FileManager.getFile('$sbnPath${Editor.extension}.$assetIndex');
        pdfBytes = assetCache.get(pdfFile);
      } else {
        pdfBytes = inlineAssets[assetIndex];
      }
    } else {
      if (kDebugMode) {
        throw Exception('PdfEditorImage.fromJson: pdf bytes not found');
      }
      pdfBytes = Uint8List(0);
    }

    return PdfEditorImage(
      id: json['id'] ??
          -1, // -1 will be replaced by EditorCoreInfo._handleEmptyImageIds()
      assetCache: assetCache,
      pdfBytes: pdfBytes,
      pdfFile: pdfFile,
      pdfPage: json['pdfi'],
      pageIndex: json['i'] ?? 0,
      pageSize: Size.infinite,
      invertible: json['v'] ?? true,
      backgroundFit:
          json['f'] != null ? BoxFit.values[json['f']] : BoxFit.contain,
      onMoveImage: null,
      onDeleteImage: null,
      onMiscChange: null,
      onLoad: null,
      newImage: false,
      dstRect: Rect.fromLTWH(
        json['x'] ?? 0,
        json['y'] ?? 0,
        json['w'] ?? 0,
        json['h'] ?? 0,
      ),
      naturalSize: Size(
        json['nw'] ?? 0,
        json['nh'] ?? 0,
      ),
      isThumbnail: isThumbnail,
    );
  }

  @override
  Map<String, dynamic> toJson(OrderedAssetCache assets) {
    final json = super.toJson(
      assets,
    );

    // remove non-pdf fields
    json.remove('t'); // thumbnail bytes
    assert(!json.containsKey('a'));
    assert(!json.containsKey('b'));

    json['a'] = assets.add(pdfFile ?? pdfBytes!);
    json['pdfi'] = pdfPage;

    return json;
  }

  @override
  Future<void> firstLoad() async {
    assert(srcRect.isEmpty);
    assert(!naturalSize.isEmpty);

    if (dstRect.isEmpty) {
      final dstSize = pageSize != null
          ? EditorImage.resize(naturalSize, pageSize!)
          : naturalSize;
      dstRect = dstRect.topLeft & dstSize;
    }

    _pdfDocument.value ??= pdfFile != null
        ? await PdfDocument.openFile(pdfFile!.path)
        : await PdfDocument.openData(pdfBytes!);
  }

  @override
  Future<void> loadIn() async => await super.loadIn();

  @override
  Future<bool> loadOut() async => await super.loadOut();

  @override
  Future<void> precache(BuildContext context) async {
    if (_pdfDocument.value != null) return;

    final completer = Completer<void>();

    void onDocumentSet() {
      if (_pdfDocument.value == null) return;
      if (completer.isCompleted) return;
      completer.complete();
      _pdfDocument.removeListener(onDocumentSet);
    }

    _pdfDocument.addListener(onDocumentSet);
    return completer.future;
  }

  Future<String> extractPageText() async {
    try {
      await loadIn();
      final bytes = pdfBytes ?? await pdfFile!.readAsBytes();
      final document = await PdfDocument.openData(bytes);
      final StringBuffer extractedText = StringBuffer();
      final pageCount = document.pages.length;

      for (int pageIndex = 1; pageIndex <= pageCount; pageIndex++) {
        try {
          final page = document.pages.elementAt(pageIndex);
          final pageText = await page.loadText();

          if (pageIndex > 1) {
            extractedText.writeln('\n-- Page $pageIndex --\n');
          }
          extractedText.writeln(pageText.fullText);
        } catch (pageError) {
          print('Error extracting text from page $pageIndex: $pageError');
          extractedText.writeln('\n[Error reading page $pageIndex]\n');
        }
      }

      document.dispose();

      return extractedText.toString().trim();
    } catch (e) {
      print('PDF text extraction error $e');
      return 'Error: Unable to extract text from PDF -$e';
    }
  }

  @override
  Widget buildImageWidget({
    required BuildContext context,
    required BoxFit? overrideBoxFit,
    required bool isBackground,
    required bool invert,
  }) {
    return ValueListenableBuilder(
      valueListenable: _pdfDocument,
      builder: (context, pdfDocument, child) {
        if (pdfDocument == null) {
          return SizedBox.fromSize(size: srcRect.size);
        }
        return InvertWidget(
          invert: invert,
          child: PdfPageView(
            document: pdfDocument,
            pageNumber: pdfPage + 1,
            decoration: BoxDecoration(),
          ),
        );
      },
    );
  }

  @override
  PdfEditorImage copy() => PdfEditorImage(
        id: id,
        assetCache: assetCache,
        pdfBytes: pdfBytes,
        pdfPage: pdfPage,
        pdfFile: pdfFile,
        pageIndex: pageIndex,
        pageSize: Size.infinite,
        invertible: invertible,
        backgroundFit: backgroundFit,
        onMoveImage: onMoveImage,
        onDeleteImage: onDeleteImage,
        onMiscChange: onMiscChange,
        onLoad: onLoad,
        newImage: true,
        dstRect: dstRect,
        naturalSize: naturalSize,
        isThumbnail: isThumbnail,
      );
}
