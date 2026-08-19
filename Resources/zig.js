/* Minimal Zig grammar for highlight.js. */
hljs.registerLanguage('zig', function (hljs) {
  const KEYWORDS = {
    keyword:
      'const var fn pub return try catch defer errdefer if else while for ' +
      'switch break continue struct enum union error test comptime inline ' +
      'export extern packed align linksection threadlocal allowzero volatile ' +
      'async await suspend resume nosuspend noalias and or orelse unreachable ' +
      'usingnamespace anytype anyframe asm callconv opaque',
    literal: 'true false null undefined',
    type:
      'i8 u8 i16 u16 i32 u32 i64 u64 i128 u128 isize usize ' +
      'f16 f32 f64 f80 f128 bool void noreturn type anyerror anyopaque ' +
      'c_char c_short c_int c_long c_longlong c_ushort c_uint c_ulong ' +
      'c_ulonglong c_longdouble comptime_int comptime_float',
  };
  return {
    name: 'Zig',
    keywords: KEYWORDS,
    contains: [
      hljs.COMMENT('//', '$'),
      {
        className: 'string',
        begin: '"', end: '"',
        contains: [hljs.BACKSLASH_ESCAPE],
      },
      { className: 'string', begin: '\\\\\\\\', end: '$' }, // multiline string lines
      {
        className: 'string',
        begin: "'", end: "'",
        contains: [hljs.BACKSLASH_ESCAPE],
      },
      { className: 'meta', begin: '@[A-Za-z_]\\w*' }, // builtins like @import
      {
        className: 'number',
        begin:
          '\\b(0b[01_]+|0o[0-7_]+|' +
          '0x[0-9a-fA-F_]+(\\.[0-9a-fA-F_]+)?([pP][+-]?\\d+)?|' +
          '\\d[\\d_]*(\\.[\\d_]+)?([eE][+-]?\\d+)?)',
      },
      {
        beginKeywords: 'fn', end: '\\(', excludeEnd: true,
        contains: [{ className: 'title function_', begin: hljs.IDENT_RE }],
      },
    ],
  };
});
