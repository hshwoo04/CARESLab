import Types::*;
import InstCacheTypes::*;
import DataCacheTypes::*;
import Vector::*;

//IMemory Types
typedef 26 AddrBits;
typedef Bit#(AddrBits) MemIndx;
typedef Bit#(26) MemorySize;
typedef Bit#(16) InstPacket;
typedef Bit#(48) Inst;

typedef 100 MemPenalty;

typedef 32 	MaxBurstLength;	//DDR3 RAM supports burst length up to 8 quad words (32 words)

typedef enum {Idle, IBusy, DBusy} MemStatus deriving(Eq, Bits);

typedef enum {Ld, St} MemOp deriving(Eq,Bits);

typedef struct {
	MemOp op;
	Addr addr;
	Data data;
} MemReq deriving(Eq, Bits);

typedef struct {
	MemOp op;
	Addr addr;
	DLine data;
	Bit#(TAdd#(1,TLog#(MaxBurstLength))) burstLength;
} DCacheMemReq deriving(Eq, Bits);

typedef struct {
	Addr upperAddr;
	Addr lowerAddr;
	InstLoadOption opt;	
} ICacheMemReq deriving(Eq, Bits);

typedef IWordsPerBlock IMemBurstLength;

typedef Vector#(IMemBurstLength, Data) IMemBurstLine;

typedef Bit#(TAdd#(1,TLog#(MaxBurstLength))) BurstCount;


