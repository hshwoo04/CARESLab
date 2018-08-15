import Types::*;
import Vector::*;

typedef 2 DCacheSets;
typedef 4 DWordsPerBlock;  // You can change this from 2 to 32. It must be a power of 2

// Do not modify below
typedef 32 DCacheEntries;  // Do not modify this constant
typedef Vector#(DWordsPerBlock, Data) DLine;
typedef DLine DMemResp;

typedef Bit#(TLog#(DWordsPerBlock)) 	DCacheBlockOffset;
typedef Bit#(TLog#(DCacheSets)) 		DCacheSetOffset;

/* Rows and tag size of cache should be modified considering block size and set-associativity of the cache */
typedef DCacheEntries DCacheRows;
typedef Bit#(TLog#(DCacheRows)) DCacheIndex;
typedef Bit#(TSub#(TSub#(TSub#(AddrSz, TLog#(DCacheRows)),SizeOf#(DCacheBlockOffset)),2)) DCacheTag;

