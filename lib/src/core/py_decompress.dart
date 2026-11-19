// Copyright © 2026 Apple Inc. and the creator_studio_document authors.
// Licensed under Apache License v2.0. For more information, see LICENSE.
// SPDX-License-Identifier: Apache-2.0
//
// Ported from apple/creator-studio-doc-format (Python).

/// The decompressors that Python's `zipfile` reads members with, as upstream
/// meets them.
///
/// `zipfile` hands a decompressor all of a member's data in one call and
/// takes what it gives back: zlib's raw inflate for deflate, libbzip2 for
/// bzip2, and liblzma's raw LZMA1 decoder behind `zipfile.LZMADecompressor`
/// for LZMA. None of them reports data that ends early; they give the output
/// they could decode, and `zipfile`'s CRC check decides. Each reports damage
/// with its own words: `Error -3 while decompressing data: <zlib's message>`,
/// `Invalid data stream`, `Corrupt input data`, and `Invalid or unsupported
/// options`. The decoders here follow those libraries step by step, so the
/// same data gives the same output, the same end of stream, and the same
/// error, at the same point.
///
/// Python asks zlib for at most 1 GiB per call, and stops reading a member
/// once it has its declared size; the decoders here stop at that point too,
/// for every method. Python asks libbzip2 and liblzma for everything at once,
/// so damage more than 1 GiB past a member's declared size is reported there
/// and not here.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart' show BZip2Decoder;
import 'package:meta/meta.dart';

/// An error that a decompressor reports, worded as Python words it.
@internal
final class DecompressError(
  /// The message.
  final String message,
) implements Exception {
  /// Creates an error.
  this;

  @override
  String toString() => message;
}

/// What a decompressor gives for one call: the first bytes of its output, up
/// to the size it was asked to keep, and whether its stream ended.
@internal
final class Decompressed(
  /// The output, up to the size asked for.
  final Uint8List data,

  /// Whether the decompressor reached the end of its stream.
  final bool ended,
) {
  /// Creates a result.
  this;
}

// The input ran out: Python's decompressors wait for more.
final class _NeedInput() implements Exception;

// The output reached the point where Python stops asking for more.
final class _Stop() implements Exception;

const _chunk = 1 << 30;

// The output of a decompressor: the first [_keep] bytes are kept, and the
// count of all of them is the position of the stream.
final class _Out(int keep) {
  final int _keep = keep < 0 ? 0 : keep;

  // `ZipExtFile` asks for 1 GiB at a time until it has the member's size.
  final int _stop = keep <= 0 ? _chunk : (keep + _chunk - 1) ~/ _chunk * _chunk;
  Uint8List _buf = Uint8List(0);
  int _len = 0;
  int total = 0;

  void add(int byte) {
    if (_len < _keep) {
      if (_len == _buf.length) {
        _grow();
      }
      _buf[_len++] = byte;
    }
    if (++total >= _stop) {
      throw _Stop();
    }
  }

  void _grow() {
    var size = _buf.length * 2;
    if (size < 1024) {
      size = 1024;
    }
    if (size > _keep) {
      size = _keep;
    }
    _buf = Uint8List(size)..setRange(0, _len, _buf);
  }

  Uint8List bytes() => _len == _buf.length
      ? _buf
      : Uint8List.fromList(Uint8List.sublistView(_buf, 0, _len));
}

// ---------------------------------------------------------------------------
// Deflate, as zlib's `inflate` decodes a raw stream
// ---------------------------------------------------------------------------

/// Inflates the raw deflate stream [input] as `zlib.decompressobj(-15)` does
/// when `zipfile` reads a member, keeping the first [keep] bytes.
///
/// Throws [DecompressError] with Python's message for data that zlib rejects.
@internal
Decompressed inflateRaw(Uint8List input, int keep) =>
    _Inflater(input, _Out(keep)).run();

const _lenBase = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, //
  35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
];
const _lenExtra = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, //
  3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
];
const _distBase = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, //
  257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289,
  16385, 24577,
];
const _distExtra = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, //
  7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
];
const _codeLengthOrder = [
  16,
  17,
  18,
  0,
  8,
  7,
  9,
  6,
  10,
  5,
  11,
  4,
  12,
  3,
  13,
  2,
  14,
  1,
  15,
];

// A Huffman code as a table indexed by the next [bits] bits of input: each
// entry is `symbol << 4 | length`, or -1 where no code is.
final class _Huffman(final Int32List table, final int bits) {
  int get mask => (1 << bits) - 1;
}

// `inflate_table`: the code of [lens], or `null` when zlib rejects it. A code
// may be incomplete only if it has a single code of one bit, and a code
// length code not at all; a code with no symbols is accepted, and decoding it
// reads one bit and finds no symbol, except that a code length code with no
// symbols decodes length 0, as zlib's table for it does.
_Huffman? _huffman(List<int> lens, {bool codeLengths = false}) {
  final count = List.filled(16, 0);
  for (final len in lens) {
    count[len]++;
  }
  var max = 15;
  while (max >= 1 && count[max] == 0) {
    max--;
  }
  if (max == 0) {
    return _Huffman(Int32List(2)..fillRange(0, 2, codeLengths ? 1 : -1), 1);
  }
  var left = 1;
  for (var len = 1; len <= 15; len++) {
    left = (left << 1) - count[len];
    if (left < 0) {
      return null;
    }
  }
  if (left > 0 && (codeLengths || max != 1)) {
    return null;
  }
  final table = Int32List(1 << max)..fillRange(0, 1 << max, -1);
  final next = List.filled(16, 0);
  var code = 0;
  for (var len = 1; len <= max; len++) {
    next[len] = code;
    code = (code + count[len]) << 1;
  }
  for (var sym = 0; sym < lens.length; sym++) {
    final len = lens[sym];
    if (len == 0) {
      continue;
    }
    final c = next[len]++;
    var reversed = 0;
    for (var i = 0; i < len; i++) {
      reversed |= ((c >> i) & 1) << (len - 1 - i);
    }
    for (var i = reversed; i < table.length; i += 1 << len) {
      table[i] = sym << 4 | len;
    }
  }
  return _Huffman(table, max);
}

final _fixedLengths = _huffman([
  for (var i = 0; i < 144; i++) 8,
  for (var i = 144; i < 256; i++) 9,
  for (var i = 256; i < 280; i++) 7,
  for (var i = 280; i < 288; i++) 8,
])!;
final _fixedDistances = _huffman(List.filled(32, 5))!;

DecompressError _zlibError(String message) =>
    DecompressError('Error -3 while decompressing data: $message');

final class _Inflater(final Uint8List _in, final _Out _out) {
  int _pos = 0;
  int _bitBuf = 0;
  int _bitCount = 0;
  final Uint8List _window = Uint8List(1 << 15);
  int _windowPos = 0;

  Decompressed run() {
    var ended = false;
    try {
      int last;
      do {
        _need(3);
        last = _bits(1);
        switch (_bits(2)) {
          case 0:
            _stored();
          case 1:
            _codes(_fixedLengths, _fixedDistances);
          case 2:
            _dynamic();
          default:
            throw _zlibError('invalid block type');
        }
      } while (last == 0);
      ended = true;
    } on _NeedInput {
      // zlib waits for more input, and Python takes what it has.
    } on _Stop {
      // Python has all it asks for.
    }
    return Decompressed(_out.bytes(), ended);
  }

  void _fill(int n) {
    while (_bitCount < n && _pos < _in.length) {
      _bitBuf |= _in[_pos++] << _bitCount;
      _bitCount += 8;
    }
  }

  void _need(int n) {
    _fill(n);
    if (_bitCount < n) {
      throw _NeedInput();
    }
  }

  int _bits(int n) {
    _need(n);
    final value = _bitBuf & ((1 << n) - 1);
    _bitBuf >>= n;
    _bitCount -= n;
    return value;
  }

  // The next symbol of [code], or -1 for bits that no code starts with.
  int _decode(_Huffman code) {
    _fill(code.bits);
    final entry = code.table[_bitBuf & code.mask];
    if (_bitCount < code.bits && (entry < 0 || (entry & 15) > _bitCount)) {
      // The bits that decide aren't all there yet.
      throw _NeedInput();
    }
    if (entry < 0) {
      return -1;
    }
    _bitBuf >>= entry & 15;
    _bitCount -= entry & 15;
    return entry >> 4;
  }

  void _put(int byte) {
    _window[_windowPos] = byte;
    _windowPos = (_windowPos + 1) & 0x7fff;
    _out.add(byte);
  }

  void _stored() {
    _bitBuf >>= _bitCount & 7;
    _bitCount -= _bitCount & 7;
    final len = _bits(16);
    if (len != _bits(16) ^ 0xffff) {
      throw _zlibError('invalid stored block lengths');
    }
    for (var i = 0; i < len; i++) {
      if (_bitCount >= 8) {
        _put(_bits(8));
      } else if (_pos < _in.length) {
        _put(_in[_pos++]);
      } else {
        throw _NeedInput();
      }
    }
  }

  void _dynamic() {
    _need(14);
    final nlen = _bits(5) + 257;
    final ndist = _bits(5) + 1;
    final ncode = _bits(4) + 4;
    if (nlen > 286 || ndist > 30) {
      throw _zlibError('too many length or distance symbols');
    }
    final codeLengths = List.filled(19, 0);
    for (var i = 0; i < ncode; i++) {
      codeLengths[_codeLengthOrder[i]] = _bits(3);
    }
    final lencode =
        _huffman(codeLengths, codeLengths: true) ??
        (throw _zlibError('invalid code lengths set'));
    final lens = List.filled(nlen + ndist, 0);
    var have = 0;
    while (have < nlen + ndist) {
      final sym = _decode(lencode);
      if (sym < 16) {
        lens[have++] = sym;
        continue;
      }
      var len = 0;
      final int copy;
      if (sym == 16) {
        _need(2);
        if (have == 0) {
          throw _zlibError('invalid bit length repeat');
        }
        len = lens[have - 1];
        copy = 3 + _bits(2);
      } else if (sym == 17) {
        copy = 3 + _bits(3);
      } else {
        copy = 11 + _bits(7);
      }
      if (have + copy > nlen + ndist) {
        throw _zlibError('invalid bit length repeat');
      }
      lens.fillRange(have, have + copy, len);
      have += copy;
    }
    if (lens[256] == 0) {
      throw _zlibError('invalid code -- missing end-of-block');
    }
    final lengths =
        _huffman(lens.sublist(0, nlen)) ??
        (throw _zlibError('invalid literal/lengths set'));
    final distances =
        _huffman(lens.sublist(nlen)) ??
        (throw _zlibError('invalid distances set'));
    _codes(lengths, distances);
  }

  void _codes(_Huffman lengths, _Huffman distances) {
    for (;;) {
      var sym = _decode(lengths);
      if (sym < 0) {
        throw _zlibError('invalid literal/length code');
      }
      if (sym < 256) {
        _put(sym);
        continue;
      }
      if (sym == 256) {
        return;
      }
      sym -= 257;
      if (sym >= 29) {
        throw _zlibError('invalid literal/length code');
      }
      final len = _lenBase[sym] + _bits(_lenExtra[sym]);
      final dsym = _decode(distances);
      if (dsym < 0 || dsym >= 30) {
        throw _zlibError('invalid distance code');
      }
      final dist = _distBase[dsym] + _bits(_distExtra[dsym]);
      if (dist > _out.total) {
        throw _zlibError('invalid distance too far back');
      }
      for (var i = 0; i < len; i++) {
        _put(_window[(_windowPos - dist) & 0x7fff]);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// LZMA, as `zipfile.LZMADecompressor` and liblzma decode it
// ---------------------------------------------------------------------------

DecompressError _lzmaOptions() =>
    DecompressError('Invalid or unsupported options');

DecompressError _lzmaCorrupt() => DecompressError('Corrupt input data');

/// Decodes the LZMA data [input] of a ZIP member as `zipfile` does, keeping
/// the first [keep] bytes.
///
/// `zipfile.LZMADecompressor` gives nothing until it has the 4-byte header
/// and the properties it announces, and more; then liblzma decodes the raw
/// LZMA1 stream. Throws [DecompressError] with Python's message for data
/// that liblzma rejects.
@internal
Decompressed decodeZipLzma(Uint8List input, int keep) {
  if (input.length <= 4) {
    return Decompressed(Uint8List(0), false);
  }
  final propsSize = input[2] | input[3] << 8;
  if (input.length <= 4 + propsSize) {
    return Decompressed(Uint8List(0), false);
  }
  // `lzma._decode_filter_properties(FILTER_LZMA1, ...)`.
  if (propsSize != 5 || input[4] > (4 * 5 + 4) * 9 + 8) {
    throw _lzmaOptions();
  }
  var byte = input[4];
  final pb = byte ~/ 45;
  byte -= pb * 45;
  final lp = byte ~/ 9;
  final lc = byte - lp * 9;
  if (lc + lp > 4) {
    throw _lzmaOptions();
  }
  var dictSize = input[5] | input[6] << 8 | input[7] << 16 | input[8] << 24;
  // liblzma's dictionary: at least 4 KiB, in steps of 16 bytes.
  if (dictSize < 4096) {
    dictSize = 4096;
  }
  dictSize = (dictSize + 15) & ~15;
  return _Lzma(input, 9, _Out(keep), lc, lp, pb, dictSize).run();
}

final class _Lzma(
  final Uint8List _in,
  var int _pos,
  final _Out _out,
  final int _lc,
  final int _lp,
  final int _pb,
  final int _dictSize,
) {
  int _range = 0xffffffff;
  int _code = 0;

  Uint8List _window = Uint8List(0);
  int _windowPos = 0;

  late final _literal = _probs(0x300 << (_lc + _lp));
  final _isMatch = _probs(12 << 4);
  final _isRep = _probs(12);
  final _isRepG0 = _probs(12);
  final _isRepG1 = _probs(12);
  final _isRepG2 = _probs(12);
  final _isRep0Long = _probs(12 << 4);
  final _posSlot = _probs(4 << 6);
  final _posSpecial = _probs(1 + 128 - 14);
  final _align = _probs(16);
  final _matchLen = _probs(2 + 16 * 8 * 2 + 256);
  final _repLen = _probs(2 + 16 * 8 * 2 + 256);

  static Uint16List _probs(int n) => Uint16List(n)..fillRange(0, n, 1024);

  Decompressed run() {
    var ended = false;
    try {
      _init();
      ended = _decode();
    } on _NeedInput {
      // liblzma waits for more input, and Python takes what it has.
    } on _Stop {
      // Python has all it asks for, here.
    }
    return Decompressed(_out.bytes(), ended);
  }

  // `rc_read_init`: five bytes, the first of them zero.
  void _init() {
    for (var i = 0; i < 5; i++) {
      if (_pos >= _in.length) {
        throw _NeedInput();
      }
      final byte = _in[_pos++];
      if (i == 0 && byte != 0) {
        throw _lzmaCorrupt();
      }
      _code = ((_code << 8) | byte) & 0xffffffff;
    }
  }

  void _normalize() {
    if (_range < 0x1000000) {
      if (_pos >= _in.length) {
        throw _NeedInput();
      }
      _range = (_range << 8) & 0xffffffff;
      _code = ((_code << 8) | _in[_pos++]) & 0xffffffff;
    }
  }

  int _bit(Uint16List probs, int i) {
    _normalize();
    final prob = probs[i];
    final bound = (_range >>> 11) * prob;
    if (_code < bound) {
      _range = bound;
      probs[i] = prob + ((2048 - prob) >> 5);
      return 0;
    }
    _range -= bound;
    _code -= bound;
    probs[i] = prob - (prob >> 5);
    return 1;
  }

  int _tree(Uint16List probs, int base, int bits) {
    var m = 1;
    for (var i = 0; i < bits; i++) {
      m = (m << 1) + _bit(probs, base + m);
    }
    return m - (1 << bits);
  }

  int _reverseTree(Uint16List probs, int base, int bits) {
    var m = 1;
    var symbol = 0;
    for (var i = 0; i < bits; i++) {
      final bit = _bit(probs, base + m);
      m = (m << 1) + bit;
      symbol |= bit << i;
    }
    return symbol;
  }

  int _direct(int bits) {
    var result = 0;
    for (var i = 0; i < bits; i++) {
      _normalize();
      _range >>>= 1;
      if (_code >= _range) {
        _code -= _range;
        result = (result << 1) | 1;
      } else {
        result <<= 1;
      }
    }
    return result;
  }

  int _length(Uint16List probs, int posState) {
    if (_bit(probs, 0) == 0) {
      return _tree(probs, 2 + posState * 8, 3);
    }
    if (_bit(probs, 1) == 0) {
      return 8 + _tree(probs, 2 + 128 + posState * 8, 3);
    }
    return 16 + _tree(probs, 2 + 256, 8);
  }

  int _distance(int len) {
    final lenState = len < 3 ? len : 3;
    final posSlot = _tree(_posSlot, lenState << 6, 6);
    if (posSlot < 4) {
      return posSlot;
    }
    final directBits = (posSlot >> 1) - 1;
    var dist = (2 | (posSlot & 1)) << directBits;
    if (posSlot < 14) {
      dist += _reverseTree(_posSpecial, dist - posSlot, directBits);
    } else {
      dist += _direct(directBits - 4) << 4;
      dist += _reverseTree(_align, 0, 4);
    }
    return dist & 0xffffffff;
  }

  // The number of bytes a match may reach back over.
  int get _full => _out.total < _dictSize ? _out.total : _dictSize;

  // The byte [distance] bytes back, 1 being the last one.
  int _get(int distance) {
    var at = _windowPos - distance;
    if (at < 0) {
      at += _window.length;
    }
    return _window[at];
  }

  void _put(int byte) {
    if (_windowPos == _window.length) {
      if (_window.length < _dictSize) {
        var size = _window.length * 2;
        if (size < 1 << 16) {
          size = 1 << 16;
        }
        if (size > _dictSize) {
          size = _dictSize;
        }
        _window = Uint8List(size)..setRange(0, _windowPos, _window);
      } else {
        _windowPos = 0;
      }
    }
    _window[_windowPos++] = byte;
    _out.add(byte);
  }

  // Returns whether the stream ended with its end marker.
  bool _decode() {
    var state = 0;
    var rep0 = 0;
    var rep1 = 0;
    var rep2 = 0;
    var rep3 = 0;
    final pbMask = (1 << _pb) - 1;
    final lpMask = (1 << _lp) - 1;
    for (;;) {
      final posState = _out.total & pbMask;
      if (_bit(_isMatch, (state << 4) + posState) == 0) {
        final prev = _out.total > 0 ? _get(1) : 0;
        final base =
            0x300 * (((_out.total & lpMask) << _lc) + (prev >> (8 - _lc)));
        var symbol = 1;
        if (state >= 7) {
          var matchByte = _get(rep0 + 1);
          do {
            final matchBit = (matchByte >> 7) & 1;
            matchByte <<= 1;
            final bit = _bit(_literal, base + ((1 + matchBit) << 8) + symbol);
            symbol = (symbol << 1) | bit;
            if (matchBit != bit) {
              break;
            }
          } while (symbol < 0x100);
        }
        while (symbol < 0x100) {
          symbol = (symbol << 1) | _bit(_literal, base + symbol);
        }
        _put(symbol & 0xff);
        state = state < 4 ? 0 : (state < 10 ? state - 3 : state - 6);
        continue;
      }
      int len;
      if (_bit(_isRep, state) != 0) {
        if (_full == 0) {
          throw _lzmaCorrupt();
        }
        if (_bit(_isRepG0, state) == 0) {
          if (_bit(_isRep0Long, (state << 4) + posState) == 0) {
            state = state < 7 ? 9 : 11;
            _put(_get(rep0 + 1));
            continue;
          }
        } else {
          final int dist;
          if (_bit(_isRepG1, state) == 0) {
            dist = rep1;
          } else {
            if (_bit(_isRepG2, state) == 0) {
              dist = rep2;
            } else {
              dist = rep3;
              rep3 = rep2;
            }
            rep2 = rep1;
          }
          rep1 = rep0;
          rep0 = dist;
        }
        len = _length(_repLen, posState);
        state = state < 7 ? 8 : 11;
      } else {
        rep3 = rep2;
        rep2 = rep1;
        rep1 = rep0;
        len = _length(_matchLen, posState);
        state = state < 7 ? 7 : 10;
        rep0 = _distance(len);
        if (rep0 == 0xffffffff) {
          // The end marker: the range coder must end on it.
          _normalize();
          if (_code != 0) {
            throw _lzmaCorrupt();
          }
          return true;
        }
        if (rep0 >= _full) {
          throw _lzmaCorrupt();
        }
      }
      for (var i = len + 2; i > 0; i--) {
        _put(_get(rep0 + 1));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// bzip2, as libbzip2 decodes it
//
// A port, altered for Dart, of libbzip2's decompress.c and huffman.c,
// copyright (C) 1996-2019 Julian R Seward; see NOTICE for its license.
// ---------------------------------------------------------------------------

DecompressError _bzip2Error() => DecompressError('Invalid data stream');

/// Decodes the bzip2 stream [input] as `bz2.BZ2Decompressor` does, keeping
/// the first [keep] bytes.
///
/// Throws [DecompressError] with Python's message for data that libbzip2
/// rejects.
@internal
Decompressed decodeBzip2(Uint8List input, int keep) =>
    _Bzip2(input, _Out(keep)).run();

final _bzip2CrcTable = () {
  final table = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var c = i << 24;
    for (var k = 0; k < 8; k++) {
      c = (c & 0x80000000) != 0 ? ((c << 1) ^ 0x04c11db7) : c << 1;
      c &= 0xffffffff;
    }
    table[i] = c;
  }
  return table;
}();

const _maxGroups = 6;
const _maxAlphaSize = 258;
const _maxCodeLen = 23;
const _maxSelectors = 18002;
const _groupSize = 50;

final class _Bzip2(final Uint8List _in, final _Out _out) {
  int _pos = 0;
  int _bitBuf = 0;
  int _bitCount = 0;

  // The state that libbzip2 keeps from one block to the next.
  int _blockSize100k = 0;
  Uint32List _tt = Uint32List(0);
  final _seqToUnseq = Uint8List(256);
  final _selectorMtf = Uint8List(_maxSelectors);
  final _selector = Uint8List(_maxSelectors);
  final _len = [for (var i = 0; i < _maxGroups; i++) Uint8List(_maxAlphaSize)];
  final _limit = [
    for (var i = 0; i < _maxGroups; i++) Int32List(_maxAlphaSize),
  ];
  final _base = [for (var i = 0; i < _maxGroups; i++) Int32List(_maxAlphaSize)];
  final _perm = [for (var i = 0; i < _maxGroups; i++) Int32List(_maxAlphaSize)];
  final _minLens = Int32List(_maxGroups);
  int _combinedCrc = 0;

  Decompressed run() {
    var ended = false;
    try {
      ended = _stream();
    } on _NeedInput {
      // libbzip2 waits for more input, and Python takes what it has.
    } on _Stop {
      // Python has all it asks for, here.
    }
    return Decompressed(_out.bytes(), ended);
  }

  int _bits(int n) {
    while (_bitCount < n) {
      if (_pos >= _in.length) {
        throw _NeedInput();
      }
      _bitBuf = ((_bitBuf << 8) | _in[_pos++]) & 0xffffffff;
      _bitCount += 8;
    }
    final value = (_bitBuf >> (_bitCount - n)) & ((1 << n) - 1);
    _bitCount -= n;
    _bitBuf &= (1 << _bitCount) - 1;
    return value;
  }

  int _byte() => _bits(8);

  int _u32() => (_byte() << 24) | (_byte() << 16) | (_byte() << 8) | _byte();

  bool _stream() {
    if (_byte() != 0x42 || _byte() != 0x5a || _byte() != 0x68) {
      throw _bzip2Error();
    }
    _blockSize100k = _byte() - 0x30;
    if (_blockSize100k < 1 || _blockSize100k > 9) {
      throw _bzip2Error();
    }
    _tt = Uint32List(_blockSize100k * 100000);
    for (;;) {
      final magic = _byte();
      if (magic == 0x17) {
        for (final b in const [0x72, 0x45, 0x38, 0x50, 0x90]) {
          if (_byte() != b) {
            throw _bzip2Error();
          }
        }
        if (_u32() != _combinedCrc) {
          throw _bzip2Error();
        }
        return true;
      }
      if (magic != 0x31) {
        throw _bzip2Error();
      }
      for (final b in const [0x41, 0x59, 0x26, 0x53, 0x59]) {
        if (_byte() != b) {
          throw _bzip2Error();
        }
      }
      final storedCrc = _u32();
      final blockCrc = _block();
      if (blockCrc != storedCrc) {
        throw _bzip2Error();
      }
      _combinedCrc =
          (((_combinedCrc << 1) | (_combinedCrc >>> 31)) & 0xffffffff) ^
          blockCrc;
    }
  }

  // Decodes and writes out one block, and returns its CRC.
  int _block() {
    final randomised = _bits(1) == 1;
    final origPtr = (_byte() << 16) | (_byte() << 8) | _byte();
    if (origPtr > 10 + 100000 * _blockSize100k) {
      throw _bzip2Error();
    }

    final inUse16 = [for (var i = 0; i < 16; i++) _bits(1) == 1];
    final inUse = List.filled(256, false);
    for (var i = 0; i < 16; i++) {
      if (inUse16[i]) {
        for (var j = 0; j < 16; j++) {
          if (_bits(1) == 1) {
            inUse[i * 16 + j] = true;
          }
        }
      }
    }
    var nInUse = 0;
    for (var i = 0; i < 256; i++) {
      if (inUse[i]) {
        _seqToUnseq[nInUse++] = i;
      }
    }
    if (nInUse == 0) {
      throw _bzip2Error();
    }
    final alphaSize = nInUse + 2;

    final nGroups = _bits(3);
    if (nGroups < 2 || nGroups > _maxGroups) {
      throw _bzip2Error();
    }
    var nSelectors = _bits(15);
    if (nSelectors < 1) {
      throw _bzip2Error();
    }
    for (var i = 0; i < nSelectors; i++) {
      var j = 0;
      while (_bits(1) == 1) {
        j++;
        if (j >= nGroups) {
          throw _bzip2Error();
        }
      }
      if (i < _maxSelectors) {
        _selectorMtf[i] = j;
      }
    }
    if (nSelectors > _maxSelectors) {
      nSelectors = _maxSelectors;
    }
    final pos = [for (var v = 0; v < nGroups; v++) v];
    for (var i = 0; i < nSelectors; i++) {
      var v = _selectorMtf[i];
      final tmp = pos[v];
      while (v > 0) {
        pos[v] = pos[v - 1];
        v--;
      }
      pos[0] = tmp;
      _selector[i] = tmp;
    }

    for (var t = 0; t < nGroups; t++) {
      var curr = _bits(5);
      for (var i = 0; i < alphaSize; i++) {
        for (;;) {
          if (curr < 1 || curr > 20) {
            throw _bzip2Error();
          }
          if (_bits(1) == 0) {
            break;
          }
          curr += _bits(1) == 0 ? 1 : -1;
        }
        _len[t][i] = curr;
      }
    }
    for (var t = 0; t < nGroups; t++) {
      var minLen = 32;
      var maxLen = 0;
      for (var i = 0; i < alphaSize; i++) {
        final l = _len[t][i];
        if (l > maxLen) {
          maxLen = l;
        }
        if (l < minLen) {
          minLen = l;
        }
      }
      _createDecodeTables(t, minLen, maxLen, alphaSize);
      _minLens[t] = minLen;
    }

    // The MTF values.
    final eob = nInUse + 1;
    final nblockMax = 100000 * _blockSize100k;
    var groupNo = -1;
    var groupPos = 0;
    var gSel = 0;
    final unzftab = Int32List(256);
    final mtf = Uint8List.fromList([for (var i = 0; i < 256; i++) i]);
    var nblock = 0;

    int mtfVal() {
      if (groupPos == 0) {
        groupNo++;
        if (groupNo >= nSelectors) {
          throw _bzip2Error();
        }
        groupPos = _groupSize;
        gSel = _selector[groupNo];
      }
      groupPos--;
      final limit = _limit[gSel];
      final base = _base[gSel];
      var zn = _minLens[gSel];
      var zvec = _bits(zn);
      for (;;) {
        if (zn > 20) {
          throw _bzip2Error();
        }
        if (zvec <= limit[zn]) {
          break;
        }
        zn++;
        zvec = (zvec << 1) | _bits(1);
      }
      final at = zvec - base[zn];
      if (at < 0 || at >= _maxAlphaSize) {
        throw _bzip2Error();
      }
      return _perm[gSel][at];
    }

    var nextSym = mtfVal();
    for (;;) {
      if (nextSym == eob) {
        break;
      }
      if (nextSym == 0 || nextSym == 1) {
        var es = -1;
        var n = 1;
        do {
          if (n >= 2 * 1024 * 1024) {
            throw _bzip2Error();
          }
          es += (nextSym + 1) * n;
          n *= 2;
          nextSym = mtfVal();
        } while (nextSym == 0 || nextSym == 1);
        es++;
        final uc = _seqToUnseq[mtf[0]];
        unzftab[uc] += es;
        while (es > 0) {
          if (nblock >= nblockMax) {
            throw _bzip2Error();
          }
          _tt[nblock++] = uc;
          es--;
        }
        continue;
      }
      if (nblock >= nblockMax) {
        throw _bzip2Error();
      }
      // `nextSym - 1` indexes the MTF list; libbzip2 keeps 256 entries.
      final nn = (nextSym - 1) & 0xff;
      final uc = mtf[nn];
      mtf.setRange(1, nn + 1, mtf);
      mtf[0] = uc;
      final unseq = _seqToUnseq[uc];
      unzftab[unseq]++;
      _tt[nblock++] = unseq;
      nextSym = mtfVal();
    }

    if (origPtr >= nblock) {
      throw _bzip2Error();
    }
    for (var i = 0; i < 256; i++) {
      if (unzftab[i] > nblock) {
        throw _bzip2Error();
      }
    }
    final cftab = Int32List(257);
    for (var i = 1; i <= 256; i++) {
      cftab[i] = unzftab[i - 1] + cftab[i - 1];
    }
    for (var i = 0; i <= 256; i++) {
      if (cftab[i] < 0 || cftab[i] > nblock) {
        throw _bzip2Error();
      }
    }
    for (var i = 0; i < nblock; i++) {
      final uc = _tt[i] & 0xff;
      _tt[cftab[uc]] |= i << 8;
      cftab[uc]++;
    }
    return _output(nblock, origPtr, randomised);
  }

  // `BZ2_hbCreateDecodeTables`.
  void _createDecodeTables(int t, int minLen, int maxLen, int alphaSize) {
    final length = _len[t];
    final limit = _limit[t];
    final base = _base[t];
    final perm = _perm[t];
    var pp = 0;
    for (var i = minLen; i <= maxLen; i++) {
      for (var j = 0; j < alphaSize; j++) {
        if (length[j] == i) {
          perm[pp++] = j;
        }
      }
    }
    for (var i = 0; i < _maxCodeLen; i++) {
      base[i] = 0;
    }
    for (var i = 0; i < alphaSize; i++) {
      base[length[i] + 1]++;
    }
    for (var i = 1; i < _maxCodeLen; i++) {
      base[i] += base[i - 1];
    }
    for (var i = 0; i < _maxCodeLen; i++) {
      limit[i] = 0;
    }
    var vec = 0;
    for (var i = minLen; i <= maxLen; i++) {
      vec += base[i + 1] - base[i];
      limit[i] = vec - 1;
      vec <<= 1;
    }
    for (var i = minLen + 1; i <= maxLen; i++) {
      base[i] = ((limit[i - 1] + 1) << 1) - base[i];
    }
  }

  // `unRLE_obuf_to_output`: writes the block out, and returns its CRC.
  int _output(int nblock, int origPtr, bool randomised) {
    var tPos = _tt[origPtr] >> 8;
    var used = 0;
    var rNToGo = 0;
    var rTPos = 0;
    var crc = 0xffffffff;

    int next() {
      tPos = _tt[tPos];
      var k = tPos & 0xff;
      tPos >>= 8;
      if (randomised) {
        if (rNToGo == 0) {
          rNToGo = BZip2Decoder.bz2RNums[rTPos];
          rTPos = (rTPos + 1) & 511;
        }
        rNToGo--;
        k ^= rNToGo == 1 ? 1 : 0;
      }
      used++;
      return k;
    }

    void emit(int byte, int count) {
      for (var i = 0; i < count; i++) {
        crc = ((crc << 8) & 0xffffffff) ^ _bzip2CrcTable[(crc >> 24) ^ byte];
        _out.add(byte);
      }
    }

    // A run of [outLen] copies of [outCh] waits to be written; a read that
    // takes [used] to [end] has read past the block, and is dropped.
    final end = nblock + 1;
    var outLen = 0;
    var outCh = 0;
    var k0 = next();
    for (;;) {
      emit(outCh, outLen);
      if (used == end) {
        break;
      }
      if (used > end) {
        throw _bzip2Error();
      }
      outLen = 1;
      outCh = k0;
      var k1 = next();
      if (used == end) {
        continue;
      }
      if (k1 != k0) {
        k0 = k1;
        continue;
      }
      outLen = 2;
      k1 = next();
      if (used == end) {
        continue;
      }
      if (k1 != k0) {
        k0 = k1;
        continue;
      }
      outLen = 3;
      k1 = next();
      if (used == end) {
        continue;
      }
      if (k1 != k0) {
        k0 = k1;
        continue;
      }
      outLen = next() + 4;
      k0 = next();
    }
    return crc ^ 0xffffffff;
  }
}
