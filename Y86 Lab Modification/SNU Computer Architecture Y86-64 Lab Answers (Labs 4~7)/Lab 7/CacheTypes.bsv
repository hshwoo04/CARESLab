import Types::*;
import Vector::*;

/*
   Cache configurations
   ====================

   * Fundamental Parameters (CS:APP 3e, Fig. 6.26)
     S: Number of sets (should be power of 2)
     E: Number of lines per set
     B: Block size (bytes)
     m: Number of physical address bits

   * Implementation Parameters
     LinePerSet : number of cache lines per set
       - corresponds to E
     DataPerBlock : number of data in block
       - For Y86-32, DataPerBlock = 1 makes 32 bit block
       - For Y86-64, DataPerBlock = 1 makes 64 bit block
       - corresponds to (B/Data Size)

     cf. Fixed size implemantation of cache (in number of available data segments)
         number of sets automatically calculated.
         CacheSets * DataPerBlock cannot exceed CacheSize

         Number of Sets(S) = CacheSize / (LinePerSet * DataPerBlock)

         letting LinePerSet = 1 makes direct-mapped cache
*/

typedef 1 LinePerSet;
typedef 1 DataPerBlock;

// ---------------------------- DO NOT MODIFY BELOW --------------------------
typedef 32 CacheSize;  // Do not modify this constant
typedef Vector#(DataPerBlock, Data) Line;
typedef Line MemResp;

// Cache block size definitions
typedef TLog#(TDiv#(DataSz, SizeOf#(Byte))) CacheByteOffsetSz; 
typedef Bit#(CacheByteOffsetSz)   CacheByteOffset; 
typedef TLog#(DataPerBlock)    CacheBlockOffsetSz;
typedef Bit#(CacheBlockOffsetSz) CacheBlockOffset;

// Cache set size definitions for set-associative cache
typedef TDiv#(TDiv#(CacheSize, LinePerSet), DataPerBlock) CacheSets;
typedef TLog#(CacheSets)       CacheSetOffsetSz;
typedef Bit#(CacheSetOffsetSz)   CacheSetOffset;

// Cache index size definitions for direct-mapped cache
typedef TLog#(CacheSize)           CacheIndexSz;
typedef Bit#(CacheIndexSz)           CacheIndex;

/* Cache tag for set-associative cache
   cache tag size = AddrSz - CacheSetOffsetSz - CacheBlockOffsetSz - CacheByteOffsetSz */
typedef TSub#(TSub#(TSub#(AddrSz, CacheBlockOffsetSz), CacheIndexSz), CacheByteOffsetSz) CacheSetTagSz;
typedef Bit#(CacheSetTagSz)         CacheSetTag;

/* Cache tag for direct-mapped cache
   cache tag size = AddrSz - CacheIndexSz - CacheBlockOffsetSz - CacheByteOffsetSz */
typedef TSub#(TSub#(TSub#(AddrSz, CacheBlockOffsetSz), CacheIndexSz), CacheByteOffsetSz) CacheIdxTagSz;
typedef Bit#(CacheIdxTagSz)         CacheIdxTag;