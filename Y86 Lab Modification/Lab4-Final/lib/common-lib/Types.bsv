import Vector::*;

/* General datatype definitions */
// Byte : 1 byte (8 bits)
typedef 8 ByteSz;
typedef Bit#(ByteSz) Byte;

// Word : 4 byte (32 bits)
typedef 32 WordSz;
typedef Bit#(WordSz) Word;

// Quad : 8 byte (64 bits)
typedef 64 QuadSz;
typedef Bit#(QuadSz) Quad;

/* Basic datatypes for Y86_64 processor */
// Maximum instruction length : 10 byte (80 bits)
typedef 80 InstSz;
typedef Bit#(InstSz) Inst;

// Address field length : 8 byte (64 bits)
typedef 64 AddrSz;
typedef Bit#(AddrSz) Addr;

// Data field length : 8 byte (64 bits)
typedef 64 DataSz;
typedef Bit#(DataSz) Data;
