import Vector::*;

typedef 8 ByteSz;
typedef Bit#(8) Byte;

typedef 48 InstSz;
typedef Bit#(InstSz) Inst;
typedef TDiv#(InstSz, ByteSz) InstByteSz;

typedef 32 AddrSz;
typedef Bit#(AddrSz) Addr;
typedef TDiv#(AddrSz, ByteSz) AddrByteSz;

typedef 32 DataSz;
typedef Bit#(DataSz) Data;
typedef TDiv#(DataSz, ByteSz) DataByteSz;
