// automatically generated by the FlatBuffers compiler, do not modify
// swiftlint:disable all
// swiftformat:disable all

public struct NdbEventMeta: FlatBufferObject, Verifiable {

  static func validateVersion() { FlatBuffersVersion_23_5_26() }
  public var __buffer: ByteBuffer! { return _accessor.bb }
  private var _accessor: Table

  private init(_ t: Table) { _accessor = t }
  public init(_ bb: ByteBuffer, o: Int32) { _accessor = Table(bb: bb, position: o) }

  private enum VTOFFSET: VOffset {
    case receivedAt = 4
    case reactions = 6
    case quotes = 8
    case reposts = 10
    case zaps = 12
    case zapTotal = 14
    var v: Int32 { Int32(self.rawValue) }
    var p: VOffset { self.rawValue }
  }

  public var receivedAt: Int32 { let o = _accessor.offset(VTOFFSET.receivedAt.v); return o == 0 ? 0 : _accessor.readBuffer(of: Int32.self, at: o) }
  public var reactions: Int32 { let o = _accessor.offset(VTOFFSET.reactions.v); return o == 0 ? 0 : _accessor.readBuffer(of: Int32.self, at: o) }
  public var quotes: Int32 { let o = _accessor.offset(VTOFFSET.quotes.v); return o == 0 ? 0 : _accessor.readBuffer(of: Int32.self, at: o) }
  public var reposts: Int32 { let o = _accessor.offset(VTOFFSET.reposts.v); return o == 0 ? 0 : _accessor.readBuffer(of: Int32.self, at: o) }
  public var zaps: Int32 { let o = _accessor.offset(VTOFFSET.zaps.v); return o == 0 ? 0 : _accessor.readBuffer(of: Int32.self, at: o) }
  public var zapTotal: Int64 { let o = _accessor.offset(VTOFFSET.zapTotal.v); return o == 0 ? 0 : _accessor.readBuffer(of: Int64.self, at: o) }
  public static func startNdbEventMeta(_ fbb: inout FlatBufferBuilder) -> UOffset { fbb.startTable(with: 6) }
  public static func add(receivedAt: Int32, _ fbb: inout FlatBufferBuilder) { fbb.add(element: receivedAt, def: 0, at: VTOFFSET.receivedAt.p) }
  public static func add(reactions: Int32, _ fbb: inout FlatBufferBuilder) { fbb.add(element: reactions, def: 0, at: VTOFFSET.reactions.p) }
  public static func add(quotes: Int32, _ fbb: inout FlatBufferBuilder) { fbb.add(element: quotes, def: 0, at: VTOFFSET.quotes.p) }
  public static func add(reposts: Int32, _ fbb: inout FlatBufferBuilder) { fbb.add(element: reposts, def: 0, at: VTOFFSET.reposts.p) }
  public static func add(zaps: Int32, _ fbb: inout FlatBufferBuilder) { fbb.add(element: zaps, def: 0, at: VTOFFSET.zaps.p) }
  public static func add(zapTotal: Int64, _ fbb: inout FlatBufferBuilder) { fbb.add(element: zapTotal, def: 0, at: VTOFFSET.zapTotal.p) }
  public static func endNdbEventMeta(_ fbb: inout FlatBufferBuilder, start: UOffset) -> Offset { let end = Offset(offset: fbb.endTable(at: start)); return end }
  public static func createNdbEventMeta(
    _ fbb: inout FlatBufferBuilder,
    receivedAt: Int32 = 0,
    reactions: Int32 = 0,
    quotes: Int32 = 0,
    reposts: Int32 = 0,
    zaps: Int32 = 0,
    zapTotal: Int64 = 0
  ) -> Offset {
    let __start = NdbEventMeta.startNdbEventMeta(&fbb)
    NdbEventMeta.add(receivedAt: receivedAt, &fbb)
    NdbEventMeta.add(reactions: reactions, &fbb)
    NdbEventMeta.add(quotes: quotes, &fbb)
    NdbEventMeta.add(reposts: reposts, &fbb)
    NdbEventMeta.add(zaps: zaps, &fbb)
    NdbEventMeta.add(zapTotal: zapTotal, &fbb)
    return NdbEventMeta.endNdbEventMeta(&fbb, start: __start)
  }

  public static func verify<T>(_ verifier: inout Verifier, at position: Int, of type: T.Type) throws where T: Verifiable {
    var _v = try verifier.visitTable(at: position)
    try _v.visit(field: VTOFFSET.receivedAt.p, fieldName: "receivedAt", required: false, type: Int32.self)
    try _v.visit(field: VTOFFSET.reactions.p, fieldName: "reactions", required: false, type: Int32.self)
    try _v.visit(field: VTOFFSET.quotes.p, fieldName: "quotes", required: false, type: Int32.self)
    try _v.visit(field: VTOFFSET.reposts.p, fieldName: "reposts", required: false, type: Int32.self)
    try _v.visit(field: VTOFFSET.zaps.p, fieldName: "zaps", required: false, type: Int32.self)
    try _v.visit(field: VTOFFSET.zapTotal.p, fieldName: "zapTotal", required: false, type: Int64.self)
    _v.finish()
  }
}

