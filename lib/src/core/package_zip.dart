// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// The ZIP container of a package, read as Python's `zipfile` reads it.
///
/// Upstream reads a package with `zipfile`, and which archives it accepts,
/// which entries it sees, and which defects it reports all follow from that
/// module. The reader here ports the parts of `zipfile` that upstream reaches:
/// finding the end of central directory record (with ZIP64 and prepended
/// data), the central directory and its extra fields (ZIP64 sizes and the
/// Unicode Path field), the checks made when a member is opened, how
/// `ZipExtFile` reads a member through its decompressor, and the CRC check
/// after it's read. The decompressors are the ports in `py_decompress.dart`,
/// with the platform's zlib through `package:archive` where it gives the same
/// result faster; `package:archive` also writes the archive.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:creator_studio_document/src/core/errors.dart';
import 'package:creator_studio_document/src/core/package_json.dart';
import 'package:creator_studio_document/src/core/py_decompress.dart';
import 'package:creator_studio_document/src/core/py_repr.dart';
import 'package:creator_studio_document/src/core/resources.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

final _log = Logger('creator_studio_document.core.package');

/// Random access to the bytes of an archive.
@internal
abstract interface class ZipSource() {
  /// Creates the interface; sources implement it rather than extend it.
  this;

  /// The number of bytes.
  int get length;

  /// Returns up to [count] bytes from [offset], fewer at the end.
  ///
  /// The bytes are the caller's: they don't share memory with the source, so
  /// a stored member read from them stays as it is when the source's bytes
  /// change, and holding it doesn't hold the rest of the archive.
  Uint8List read(int offset, int count);

  /// Releases the source. Reading afterwards isn't allowed.
  void close();
}

/// A [ZipSource] over bytes in memory, which reads copies of them.
@internal
final class BytesZipSource(final Uint8List _bytes) implements ZipSource {
  /// Creates a source that reads [_bytes].
  this;

  @override
  int get length => _bytes.length;

  @override
  Uint8List read(int offset, int count) {
    if (offset < 0 || offset >= _bytes.length || count <= 0) {
      return Uint8List(0);
    }
    final end = offset + count > _bytes.length ? _bytes.length : offset + count;
    return _bytes.sublist(offset, end);
  }

  @override
  void close() {}
}

/// A defect that `zipfile` reports, which upstream turns into a
/// [DocumentPackageErrorKind.malformedArchive] error.
///
/// It stands for `zipfile.BadZipFile`, the `NotImplementedError` of an
/// unsupported feature, the `RuntimeError` of an encrypted member, and the
/// errors of the decompressors.
@internal
final class ZipFormatError(
  /// The message, as `zipfile` words it.
  final String message,
) implements Exception {
  /// Creates an error.
  this;

  @override
  String toString() => message;
}

// A seek before the start of the file, which Python reports as `OSError`.
final class _SeekError() implements Exception;

/// Runs [body], turning a defect in the archive into a
/// [DocumentPackageErrorKind.malformedArchive] error whose message ends with
/// [hint], as upstream's `_catching_zip_errors` does.
@internal
T catchingZipErrors<T>(T Function() body, [String hint = '']) {
  try {
    return body();
  } on ZipFormatError catch (e) {
    throw DocumentPackageError(
      DocumentPackageErrorKind.malformedArchive,
      '${e.message}$hint',
    );
  }
}

// ---------------------------------------------------------------------------
// Little-endian fields
// ---------------------------------------------------------------------------

int _u16(Uint8List b, int at) => b[at] | (b[at + 1] << 8);

int _u32(Uint8List b, int at) =>
    b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24);

int _u64(Uint8List b, int at) => _u32(b, at) | (_u32(b, at + 4) << 32);

bool _sig(Uint8List b, int at, List<int> sig) =>
    b.length >= at + 4 &&
    b[at] == sig[0] &&
    b[at + 1] == sig[1] &&
    b[at + 2] == sig[2] &&
    b[at + 3] == sig[3];

const _endArchive = [0x50, 0x4b, 0x05, 0x06];
const _endArchive64 = [0x50, 0x4b, 0x06, 0x06];
const _endArchive64Locator = [0x50, 0x4b, 0x06, 0x07];
const _centralDir = [0x50, 0x4b, 0x01, 0x02];

/// The signature that starts a local file header, and so every archive that
/// doesn't start with prepended data.
@internal
const zipLocalHeader = [0x50, 0x4b, 0x03, 0x04];

const _sizeEndCentDir = 22;
const _sizeEndCentDir64 = 56;
const _sizeEndCentDir64Locator = 20;
const _sizeCentralDir = 46;
const _sizeFileHeader = 30;
const _maxComment = 0xffff;
const _maxExtractVersion = 63;

const _maskEncrypted = 1 << 0;
const _maskCompressedPatch = 1 << 5;
const _maskStrongEncryption = 1 << 6;
const _maskUtfFilename = 1 << 11;

// ---------------------------------------------------------------------------
// End of central directory
// ---------------------------------------------------------------------------

final class _EndRecord() {
  bool zip64 = false;
  int diskNumber = 0;
  int diskStart = 0;
  int size = 0;
  int offset = 0;
  int location = 0;
}

// `_EndRecData`: the end of central directory record, or `null`.
_EndRecord? _endRecData(ZipSource src) {
  final filesize = src.length;
  if (filesize < _sizeEndCentDir) {
    return null;
  }
  var data = src.read(filesize - _sizeEndCentDir, _sizeEndCentDir);
  if (data.length == _sizeEndCentDir &&
      _sig(data, 0, _endArchive) &&
      data[20] == 0 &&
      data[21] == 0) {
    return _endRecData64(
      src,
      -_sizeEndCentDir,
      _unpackEnd(data, 0, filesize - _sizeEndCentDir),
    );
  }
  final maxCommentStart = filesize - _maxComment - _sizeEndCentDir > 0
      ? filesize - _maxComment - _sizeEndCentDir
      : 0;
  data = src.read(maxCommentStart, _maxComment + _sizeEndCentDir);
  for (var start = data.length - 4; start >= 0; start--) {
    if (!_sig(data, start, _endArchive)) {
      continue;
    }
    if (data.length - start < _sizeEndCentDir) {
      return null;
    }
    return _endRecData64(
      src,
      maxCommentStart + start - filesize,
      _unpackEnd(data, start, maxCommentStart + start),
    );
  }
  return null;
}

_EndRecord _unpackEnd(Uint8List data, int at, int location) => _EndRecord()
  ..diskNumber = _u16(data, at + 4)
  ..diskStart = _u16(data, at + 6)
  ..size = _u32(data, at + 12)
  ..offset = _u32(data, at + 16)
  ..location = location;

// `_EndRecData64`: [offset] is the record's position from the end of the
// file.
_EndRecord _endRecData64(ZipSource src, int offset, _EndRecord rec) {
  final filesize = src.length;
  final locatorAt = filesize + offset - _sizeEndCentDir64Locator;
  if (locatorAt < 0) {
    return rec;
  }
  var data = src.read(locatorAt, _sizeEndCentDir64Locator);
  if (data.length != _sizeEndCentDir64Locator ||
      !_sig(data, 0, _endArchive64Locator)) {
    return rec;
  }
  final diskno = _u32(data, 4);
  final disks = _u32(data, 16);
  if (diskno != 0 || disks > 1) {
    throw ZipFormatError('zipfiles that span multiple disks are not supported');
  }
  final recordAt = locatorAt - _sizeEndCentDir64;
  if (recordAt < 0) {
    // Python's second seek isn't guarded, so this is an `OSError`.
    throw _SeekError();
  }
  data = src.read(recordAt, _sizeEndCentDir64);
  if (data.length != _sizeEndCentDir64 || !_sig(data, 0, _endArchive64)) {
    return rec;
  }
  return rec
    ..zip64 = true
    ..diskNumber = _u32(data, 16)
    ..diskStart = _u32(data, 20)
    ..size = _u64(data, 40)
    ..offset = _u64(data, 48);
}

/// Returns whether [src] has an end of central directory record, as
/// `zipfile.is_zipfile` decides.
///
/// Throws [ZipFormatError] for a record of an archive that spans disks, which
/// `is_zipfile` lets escape.
@internal
bool isZipFile(ZipSource src) {
  try {
    return _endRecData(src) != null;
  } on _SeekError {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Central directory
// ---------------------------------------------------------------------------

/// One entry of the central directory, as `zipfile.ZipInfo` holds it.
@internal
final class ZipEntry._(
  /// The name as the central directory spells it, decoded.
  final String origFilename,

  /// The name, cut at its first NUL or taken from the Unicode Path field.
  var String filename,

  /// The bytes of the name.
  final Uint8List rawName,

  /// The general purpose flags.
  final int flagBits,

  /// The compression method.
  final int compressType,

  /// The CRC-32 of the content.
  final int crc,

  /// The size of the stored data.
  var int compressSize,

  /// The size of the content.
  var int fileSize,

  /// The offset of the local header.
  var int headerOffset,

  /// The external file attributes: the file mode in the high 16 bits.
  final int externalAttr,
) {
  // Where the next entry, or the central directory, starts.
  int? _endOffset;
}

// Code page 437 from 0x80 on; below that, it's ASCII.
const _cp437High =
    'Çüéâäàåçêëè'
    'ïîìÄÅÉæÆôöò'
    'ûùÿÖÜ¢£¥₧ƒá'
    'íóúñÑªº¿⌐¬½'
    '¼¡«»░▒▓│┤╡╢'
    '╖╕╣║╗╝╜╛┐└┴'
    '┬├─┼╞╟╚╔╩╦╠'
    '═╬╧╨╤╥╙╘╒╓╫'
    '╪┘┌█▄▌▐▀αßΓ'
    'πΣσµτΦΘΩδ∞φ'
    'ε∩≡±≥≤⌠⌡÷≈°'
    '∙·√ⁿ²■\u00a0';

String _cp437(Uint8List bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    out.writeCharCode(b < 0x80 ? b : _cp437High.codeUnitAt(b - 0x80));
  }
  return out.toString();
}

// A name in the archive: UTF-8 when its flag says so, else cp437. Python
// raises `UnicodeDecodeError` for bad UTF-8, which upstream lets escape;
// here it's a defect of the archive.
String _decodeName(Uint8List raw, int flags) {
  if (flags & _maskUtfFilename == 0) {
    return _cp437(raw);
  }
  try {
    return pyUtf8Decode(raw);
  } on PyJsonError catch (e) {
    throw ZipFormatError(e.message);
  }
}

// `_sanitize_filename` on POSIX: the name ends at its first NUL.
String _sanitize(String name) {
  final nul = name.indexOf('\u0000');
  return nul >= 0 ? name.substring(0, nul) : name;
}

Uint8List _slice(Uint8List data, int start, int count) {
  if (start >= data.length) {
    return Uint8List(0);
  }
  final end = start + count > data.length ? data.length : start + count;
  return Uint8List.sublistView(data, start, end);
}

/// An archive opened for reading, as `zipfile.ZipFile(fh)` opens it.
///
/// Creating it reads the central directory of [_src], and throws
/// [ZipFormatError] if it's missing or damaged.
@internal
final class ZipReader(final ZipSource _src) {
  this {
    _readContents();
  }

  /// Every entry, in central directory order, directories included.
  final List<ZipEntry> entries = [];

  void _readContents() {
    _EndRecord? end;
    try {
      end = _endRecData(_src);
    } on _SeekError {
      throw ZipFormatError('File is not a zip file');
    }
    if (end == null) {
      throw ZipFormatError('File is not a zip file');
    }
    final sizeCd = end.size;
    final offsetCd = end.offset;
    var concat = end.location - sizeCd - offsetCd;
    if (end.zip64) {
      concat -= _sizeEndCentDir64 + _sizeEndCentDir64Locator;
    }
    final startDir = offsetCd + concat;
    if (startDir < 0) {
      throw ZipFormatError('Bad offset for central directory');
    }
    final data = _src.read(startDir, sizeCd);
    var pos = 0;
    var total = 0;
    while (total < sizeCd) {
      final centdir = _slice(data, pos, _sizeCentralDir);
      pos += centdir.length;
      if (centdir.length != _sizeCentralDir) {
        throw ZipFormatError('Truncated central directory');
      }
      if (!_sig(centdir, 0, _centralDir)) {
        throw ZipFormatError('Bad magic number for central directory');
      }
      final extractVersion = centdir[6];
      final flags = _u16(centdir, 8);
      final nameLength = _u16(centdir, 28);
      final extraLength = _u16(centdir, 30);
      final commentLength = _u16(centdir, 32);
      final raw = Uint8List.fromList(_slice(data, pos, nameLength));
      pos += raw.length;
      final nameCrc = getCrc32(raw);
      final orig = _decodeName(raw, flags);
      final extra = _slice(data, pos, extraLength);
      pos += extra.length;
      pos += _slice(data, pos, commentLength).length;
      if (extractVersion > _maxExtractVersion) {
        throw ZipFormatError(
          'zip file version ${(extractVersion / 10).toStringAsFixed(1)}',
        );
      }
      final entry = ZipEntry._(
        orig,
        _sanitize(orig),
        raw,
        flags,
        _u16(centdir, 10),
        _u32(centdir, 16),
        _u32(centdir, 20),
        _u32(centdir, 24),
        _u32(centdir, 42),
        _u32(centdir, 38),
      );
      _decodeExtra(entry, extra, nameCrc);
      entry.headerOffset += concat;
      entries.add(entry);
      total += _sizeCentralDir + nameLength + extraLength + commentLength;
    }
    var endOffset = startDir;
    final byOffset = [...entries];
    // A stable sort, as Python's `sorted` is, walked from the end.
    _sortByOffset(byOffset);
    for (final entry in byOffset.reversed) {
      entry._endOffset = endOffset;
      endOffset = entry.headerOffset;
    }
  }

  // `ZipInfo._decodeExtra`.
  void _decodeExtra(ZipEntry entry, Uint8List extra, int nameCrc) {
    var at = 0;
    while (extra.length - at >= 4) {
      final tp = _u16(extra, at);
      final ln = _u16(extra, at + 2);
      if (ln + 4 > extra.length - at) {
        throw ZipFormatError(
          'Corrupt extra field ${tp.toRadixString(16).padLeft(4, '0')} '
          '(size=$ln)',
        );
      }
      final data = Uint8List.sublistView(extra, at + 4, at + 4 + ln);
      if (tp == 0x0001) {
        var d = 0;
        int need64(String field) {
          if (data.length < d + 8) {
            throw ZipFormatError(
              'Corrupt zip64 extra field. $field not found.',
            );
          }
          d += 8;
          return _u64(data, d - 8);
        }

        if (entry.fileSize == 0xffffffff) {
          entry.fileSize = need64('File size');
        }
        if (entry.compressSize == 0xffffffff) {
          entry.compressSize = need64('Compress size');
        }
        if (entry.headerOffset == 0xffffffff) {
          entry.headerOffset = need64('Header offset');
        }
      } else if (tp == 0x7075) {
        if (data.length < 5) {
          throw ZipFormatError('Corrupt unicode path extra field (0x7075)');
        }
        if (data[0] == 1 && _u32(data, 1) == nameCrc) {
          final String name;
          try {
            name = pyUtf8Decode(Uint8List.sublistView(data, 5));
          } on PyJsonError {
            throw ZipFormatError(
              'Corrupt unicode path extra field (0x7075): invalid utf-8 '
              'bytes',
            );
          }
          if (name.isNotEmpty) {
            entry.filename = _sanitize(name);
          } else {
            _log.warning('Empty unicode path extra field (0x7075)');
          }
        }
      }
      at += ln + 4;
    }
  }

  /// Returns the content of [entry], as `ZipFile.read(info)` returns it.
  ///
  /// Throws [ZipFormatError] if the member can't be read or fails its CRC
  /// check.
  Uint8List read(ZipEntry entry) {
    if (entry.headerOffset < 0) {
      // A central directory that starts later than its record says puts a
      // local header before the start of the archive. Python seeks there and
      // fails: with `OSError` (`EINVAL`) from a file, which upstream lets
      // escape as an error of the file system, and with `ValueError` from a
      // stream. Here it's the defect of the archive that it is.
      throw ZipFormatError('Truncated file header');
    }
    final header = _src.read(entry.headerOffset, _sizeFileHeader);
    if (header.length != _sizeFileHeader) {
      throw ZipFormatError('Truncated file header');
    }
    if (!_sig(header, 0, zipLocalHeader)) {
      throw ZipFormatError('Bad magic number for file header');
    }
    final localFlags = _u16(header, 6);
    final nameLength = _u16(header, 26);
    final extraLength = _u16(header, 28);
    final localRaw = Uint8List.fromList(
      _src.read(entry.headerOffset + _sizeFileHeader, nameLength),
    );
    if (entry.flagBits & _maskCompressedPatch != 0) {
      throw ZipFormatError('compressed patched data (flag bit 5)');
    }
    if (entry.flagBits & _maskStrongEncryption != 0) {
      throw ZipFormatError('strong encryption (flag bit 6)');
    }
    final localName = _decodeName(localRaw, localFlags);
    if (localName != entry.origFilename) {
      throw ZipFormatError(
        'File name in directory ${pyStringRepr(entry.origFilename)} and '
        'header ${_bytesRepr(localRaw)} differ.',
      );
    }
    final dataStart =
        entry.headerOffset + _sizeFileHeader + localRaw.length + extraLength;
    final endOffset = entry._endOffset;
    if (endOffset != null && dataStart + entry.compressSize > endOffset) {
      if (endOffset == entry.headerOffset) {
        _log.warning(
          'Overlapped entries: ${pyStringRepr(entry.origFilename)} '
          '(possible zip bomb)',
        );
      } else {
        throw ZipFormatError(
          'Overlapped entries: ${pyStringRepr(entry.origFilename)} '
          '(possible zip bomb)',
        );
      }
    }
    if (entry.flagBits & _maskEncrypted != 0) {
      // `ZipFile.read(info)` names the member by the `repr` of its `ZipInfo`.
      throw ZipFormatError(
        'File ${_zipInfoRepr(entry)} is encrypted, password required for '
        'extraction',
      );
    }
    if (!const {0, 8, 12, 14}.contains(entry.compressType)) {
      throw ZipFormatError('That compression method is not supported');
    }
    final stored = entry.compressSize > 0
        ? _src.read(dataStart, entry.compressSize)
        : Uint8List(0);
    if (entry.compressSize > 0 && stored.isEmpty) {
      // Python's `ZipExtFile` raises a bare `EOFError` here, which upstream
      // lets escape.
      throw ZipFormatError('Compressed file ended before the end of data');
    }
    // `ZipExtFile.read`: the decompressor gets all the stored data at once,
    // and its output is cut at the member's size.
    final Decompressed out;
    try {
      out = switch (entry.compressType) {
        0 => Decompressed(
          stored.length > entry.fileSize
              ? Uint8List.sublistView(stored, 0, entry.fileSize)
              : stored,
          false,
        ),
        8 => _inflate(stored, entry),
        12 => decodeBzip2(stored, entry.fileSize),
        _ => decodeZipLzma(stored, entry.fileSize),
      };
    } on DecompressError catch (e) {
      throw ZipFormatError(e.message);
    }
    final content = out.data;
    // The member ends when the decompressor's stream does, when its stored
    // data is all read, or when it has its size. Otherwise `ZipExtFile`
    // reads on, finds the end of the file, and raises `EOFError`.
    if (!out.ended &&
        stored.length < entry.compressSize &&
        content.length < entry.fileSize) {
      throw ZipFormatError('Compressed file ended before the end of data');
    }
    if (getCrc32(content) != entry.crc) {
      throw ZipFormatError(
        'Bad CRC-32 for file ${pyStringRepr(entry.filename)}',
      );
    }
    return content;
  }

  // Inflates through `package:archive` where it uses the platform's zlib,
  // which accepts and rejects what Python's zlib does. When zlib rejects the
  // data, when it gives more than the member's size, or when it matters
  // whether the stream ended, the port of zlib in `py_decompress.dart`
  // decodes it again, for zlib's message and Python's result.
  static Decompressed _inflate(Uint8List stored, ZipEntry entry) {
    if (_platformZlib) {
      try {
        final out = const ZLibDecoder().decodeBytes(
          stored,
          raw: true,
          throwOnError: true,
          maxOutputSize: entry.fileSize,
        );
        if (stored.length >= entry.compressSize ||
            out.length >= entry.fileSize) {
          return Decompressed(out, false);
        }
      } on FormatException {
        // Decoded again below.
      }
    }
    return inflateRaw(stored, entry.fileSize);
  }
}

// `package:archive` inflates with the platform's zlib where `dart:io` is.
const _platformZlib = bool.fromEnvironment('dart.library.io');

// Sorts [entries] by local header offset, keeping the order of equal ones.
void _sortByOffset(List<ZipEntry> entries) {
  final indexed = [for (var i = 0; i < entries.length; i++) (i, entries[i])]
    ..sort((a, b) {
      final byOffset = a.$2.headerOffset.compareTo(b.$2.headerOffset);
      return byOffset != 0 ? byOffset : a.$1.compareTo(b.$1);
    });
  for (var i = 0; i < indexed.length; i++) {
    entries[i] = indexed[i].$2;
  }
}

// `zipfile.compressor_names`.
const _compressorNames = {
  0: 'store',
  1: 'shrink',
  2: 'reduce',
  3: 'reduce',
  4: 'reduce',
  5: 'reduce',
  6: 'implode',
  7: 'tokenize',
  8: 'deflate',
  9: 'deflate64',
  10: 'implode',
  12: 'bzip2',
  14: 'lzma',
  18: 'terse',
  19: 'lz77',
  97: 'wavpack',
  98: 'ppmd',
};

// `ZipInfo.__repr__`, for an entry that isn't a directory.
String _zipInfoRepr(ZipEntry entry) {
  final out = StringBuffer('<ZipInfo filename=${pyStringRepr(entry.filename)}');
  if (entry.compressType != 0) {
    out.write(
      ' compress_type='
      '${_compressorNames[entry.compressType] ?? entry.compressType}',
    );
  }
  final hi = entry.externalAttr >>> 16;
  final lo = entry.externalAttr & 0xffff;
  if (hi != 0) {
    out.write(" filemode='${_filemode(hi)}'");
  }
  if (lo != 0) {
    out.write(' external_attr=0x${lo.toRadixString(16)}');
  }
  out.write(' file_size=${entry.fileSize}');
  if (entry.compressType != 0 || entry.fileSize != entry.compressSize) {
    out.write(' compress_size=${entry.compressSize}');
  }
  return (out..write('>')).toString();
}

// `stat.filemode`, as CPython's `_stat` module writes it on Linux. macOS's
// also names the whiteout type, 0o160000, `w`, where this writes `?`.
String _filemode(int mode) {
  final type = switch (mode & 0xf000) {
    0x8000 => '-',
    0x4000 => 'd',
    0xa000 => 'l',
    0x6000 => 'b',
    0x2000 => 'c',
    0x1000 => 'p',
    0xc000 => 's',
    _ => '?',
  };
  String bit(int mask, String c) => mode & mask != 0 ? c : '-';
  String exec(int x, int special, String set, String unset) =>
      mode & special != 0
      ? (mode & x != 0 ? set : unset)
      : (mode & x != 0 ? 'x' : '-');
  return '$type'
      '${bit(0x100, 'r')}${bit(0x80, 'w')}${exec(0x40, 0x800, 's', 'S')}'
      '${bit(0x20, 'r')}${bit(0x10, 'w')}${exec(0x8, 0x400, 's', 'S')}'
      '${bit(0x4, 'r')}${bit(0x2, 'w')}${exec(0x1, 0x200, 't', 'T')}';
}

// Python's `repr` of `bytes`.
String _bytesRepr(Uint8List bytes) {
  final hasSingle = bytes.contains(0x27);
  final quote = hasSingle && !bytes.contains(0x22) ? '"' : "'";
  final out = StringBuffer('b$quote');
  for (final b in bytes) {
    if (b == 0x5c) {
      out.write(r'\\');
    } else if (b == quote.codeUnitAt(0)) {
      out.write('\\$quote');
    } else if (b == 0x09) {
      out.write(r'\t');
    } else if (b == 0x0a) {
      out.write(r'\n');
    } else if (b == 0x0d) {
      out.write(r'\r');
    } else if (b < 0x20 || b >= 0x7f) {
      out.write('\\x${b.toRadixString(16).padLeft(2, '0')}');
    } else {
      out.writeCharCode(b);
    }
  }
  return (out..write(quote)).toString();
}

// ---------------------------------------------------------------------------
// The package's view of the archive
// ---------------------------------------------------------------------------

/// The prefix of the sidecar entries that macOS adds when it zips a folder.
@internal
const macosxPrefix = '__MACOSX/';

/// Returns every file entry by name, as upstream's `_zip_members` does: a
/// name without the UTF-8 flag that is valid UTF-8 reads as UTF-8, and a
/// later entry with a name replaces an earlier one in its place.
@internal
Map<String, ZipEntry> zipMembers(ZipReader zip) {
  final members = <String, ZipEntry>{};
  for (final info in zip.entries) {
    var name = info.filename;
    // A name that differs from the original came from the Unicode Path
    // field, and is already decoded.
    if (info.flagBits & _maskUtfFilename == 0 && name == info.origFilename) {
      try {
        name = pyUtf8Decode(info.rawName);
      } on PyJsonError {
        // Not UTF-8: the cp437 name stands.
      }
    }
    if (!name.endsWith('/')) {
      members[name] = info;
    }
  }
  return members;
}

/// Returns the folder that every entry lives under when an archive was zipped
/// from a folder rather than from its contents, such as `Deck/`, or `''`.
///
/// `__MACOSX/` sidecars don't count, and a `./` that starts every name is
/// part of the prefix.
@internal
String detectRootPrefix(Iterable<String> names) {
  var entries = [
    for (final n in names)
      if (!n.endsWith('/') && !n.startsWith(macosxPrefix)) n,
  ];
  if (entries.isEmpty) {
    return '';
  }
  final dotslash = entries.every((n) => n.startsWith('./')) ? './' : '';
  if (dotslash.isNotEmpty) {
    entries = [for (final n in entries) n.substring(2)];
  }
  final tops = {
    for (final n in entries)
      if (n.contains('/')) n.substring(0, n.indexOf('/')),
  };
  final rootsAtTop = entries.any((n) => !n.contains('/'));
  if (tops.length == 1 && !rootsAtTop) {
    return '$dotslash${tops.single}/';
  }
  return dotslash;
}

/// Returns the note that a malformed-archive message ends with when the
/// archive looks re-zipped, or `''`.
@internal
String rezipHint(Iterable<String> names, String prefix) {
  final evidence = [
    if (prefix.isNotEmpty)
      'entries live under ${pyStringRepr(prefix)}, not at the archive root',
    if (names.any((n) => n.startsWith(macosxPrefix)))
      '__MACOSX sidecars present',
  ];
  if (evidence.isEmpty) {
    return '';
  }
  return ' (archive was re-zipped: ${evidence.join(' and ')})';
}

/// Checks that [src] holds a ZIP archive, as upstream's `_probe_archive`
/// does. [name] names the source in messages.
@internal
void probeArchive(ZipSource src, String name) {
  final bool isZip;
  try {
    isZip = isZipFile(src);
  } on ZipFormatError catch (e) {
    // Upstream lets this `BadZipFile` escape.
    throw DocumentPackageError(
      DocumentPackageErrorKind.malformedArchive,
      e.message,
    );
  }
  if (isZip) {
    return;
  }
  final head = src.read(0, 4);
  if (_sig(head, 0, zipLocalHeader)) {
    throw DocumentPackageError(
      DocumentPackageErrorKind.malformedArchive,
      "$name has no ZIP central directory, so it's truncated",
    );
  }
  throw DocumentPackageError(
    DocumentPackageErrorKind.notAPackage,
    "$name isn't a ZIP package",
  );
}

/// Reads every entry under the archive's root folder, except the `__MACOSX/`
/// sidecars, as upstream's `_read_zip_stream` does.
@internal
Map<String, Uint8List> readZipEntries(ZipSource src) {
  final (zip, members) = catchingZipErrors(() {
    final zip = ZipReader(src);
    return (zip, zipMembers(zip));
  });
  final prefix = detectRootPrefix(members.keys);
  return catchingZipErrors(
    () => {
      for (final MapEntry(key: n, value: info) in members.entries)
        if (n.startsWith(prefix) && !n.startsWith(macosxPrefix))
          n.substring(prefix.length): zip.read(info),
    },
    rezipHint(members.keys, prefix),
  );
}

/// The lazy store's view of an archive: the `Data/` entries, read on demand.
///
/// Creating it reads the central directory of [_src], which the backend then
/// owns.
@internal
final class ZipBackend(final ZipSource _src) implements ResourceBackend {
  this {
    final (zip, members) = catchingZipErrors(() {
      final zip = ZipReader(_src);
      return (zip, zipMembers(zip));
    });
    _zip = zip;
    _members = members;
    _prefix = detectRootPrefix(members.keys);
    _hint = rezipHint(members.keys, _prefix);
    final dataPrefix = '$_prefix$dataDirPrefix';
    for (final MapEntry(key: member, value: info) in members.entries) {
      if (member.startsWith(macosxPrefix) || !member.startsWith(dataPrefix)) {
        continue;
      }
      final flat = member.substring(dataPrefix.length);
      if (isValidFlatName(flat)) {
        _map[flat] = info;
      }
    }
  }

  late final ZipReader _zip;
  late final Map<String, ZipEntry> _members;
  late final String _prefix;
  late final String _hint;
  final Map<String, ZipEntry> _map = {};
  bool _closed = false;

  @override
  Iterable<String> names() => _map.keys;

  @override
  Uint8List read(String name) {
    return catchingZipErrors(() => _zip.read(_map[name]!), _hint);
  }

  /// Returns the entry [name] under the archive's root folder, or `null`.
  Uint8List? member(String name) {
    final info = _members['$_prefix$name'];
    if (info == null) {
      return null;
    }
    return catchingZipErrors(() => _zip.read(info), _hint);
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _src.close();
  }
}

/// The folder that holds a package's resources, with its slash.
@internal
const dataDirPrefix = 'Data/';

// ---------------------------------------------------------------------------
// Writing
// ---------------------------------------------------------------------------

/// Returns a deflated ZIP archive of [entries], in order, as
/// `zipfile.ZipFile(path, "w", ZIP_DEFLATED)` writes it.
///
/// Throws [StateError] for an entry name that holds a lone surrogate, which
/// UTF-8 can't encode, as `zipfile` raises `UnicodeEncodeError`. The archive
/// encoder would write U+FFFD in its place, so two names that differ only
/// there would become one entry.
@internal
Uint8List writeZip(Map<String, Uint8List> entries) {
  final archive = Archive();
  for (final MapEntry(:key, :value) in entries.entries) {
    if (pyUtf8EncodeError(key) case final message?) {
      throw StateError(message);
    }
    archive.add(
      ArchiveFile.bytes(key, value)
        ..compression = CompressionType.deflate
        // `writestr` gives a member the mode 0o600.
        ..mode = 0x180,
    );
  }
  return ZipEncoder().encodeBytes(archive, level: 6);
}
