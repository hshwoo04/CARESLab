import Types::*;
import Vector::*;

/*
*  Instruction cache - address analysis
*
*			  	  -------------------------------------------------------
*	Addr	  	 |        Block Number       |        ByteOffset         |      
*			  	  -------------------------------------------------------
*
*			      ---------------------------
*   BlockNumber  |      TAG      |   Index   |
*                 ---------------------------
*
*			      -----------------------------
*	ByteOffset   | WordOffsetBits |  WordBits* |
*				  -----------------------------
*
*	O Block Number 
*		Block number indicates the ID of the block in whole memory space.
*		- Index Bits
*			Number of bits for index filed is determined by the number of cache entries. 
*		- Tag Bits
*			All the remaining bits after allocating index bits and byte-offset bits are tag bits
*	
*	O ByteOffset
*		Indicates the byte offset within a instruction cache line.
*		- Word Bits*
*			WordBits indicates number of bits required to specify a byte within a word.
*			As word size is fixed to 32bits, WordBits is also a fixed value, 2.
*		- WordOffsetBits
*			WordOffsetBis indicates that the position of target word within a instruction cache line
*
*/


/* Cache Configuration	*/
//typedef 4 ICacheSets;
typedef 4 IWordsPerBlock;  
typedef 128 ICacheEntries;

/* Cache Line definition */
typedef Bit#(TMul#(IWordsPerBlock, DataSz)) ILine;			//ILine is defined as a long bits
typedef Vector#(2, ILine) 					DoubleILine;
typedef DoubleILine 						IMemResp;		//Memory request for I-cache will return adjacent two lines.
//typedef Bit#(TLog#(ICacheSets)) 			ICacheSetOffset;

typedef TLog#(SizeOf#(ILine))				ILineBitSz;
typedef Bit#(ILineBitSz)					ILineBitOffset;
typedef TSub#(SizeOf#(ILine), 1)			ILineMSB;

/* Address Analysis */
/* 1.  Number of bits for each fields */
	typedef TLog#(ICacheEntries)									IndexBits;
	typedef TLog#(IWordsPerBlock) 									WordOffsetBits;	//Not directly used
	typedef TLog#(DataByteSz)										WordBits;		//Fixed value, 2
	typedef TAdd#(WordOffsetBits, WordBits)							ByteOffsetBits;
	typedef TSub#(TSub#(AddrSz, IndexBits), ByteOffsetBits)			TagBits;
	typedef TAdd#(IndexBits, TagBits)								BlockNumberBits;

	//Extra type
/* 2. Bit types for each fields */
	typedef Bit#(TagBits)				ICacheTag;
	typedef Bit#(IndexBits)				ICacheIndex;
	typedef Bit#(ByteOffsetBits)		ICacheByteOffset;
	typedef Bit#(BlockNumberBits)		ICacheBlockNumber;

/* Cache hit analysis */
typedef enum {UpperMiss, LowerMiss, BothMiss, BothHit, SingleHit, SingleMiss} InstCacheMissStatus deriving(Bits, Eq);
typedef enum {Upper, Lower, Both, Nop} InstLoadOption deriving(Bits, Eq);
typedef TSub#(TMul#(IWordsPerBlock, DataByteSz),6)	CriticalByteOffset;	//If given byteOffset is larger than this, it will cross the cache line boundary.

/* Cache Status */
typedef enum {Ready, StartMiss, WaitMemResp, ReqPrefetch, WaitPrefetch} ICacheStatus deriving (Bits, Eq);

typedef struct {
	InstCacheMissStatus 		missStatus;
//	Maybe#(ICacheSetOffset) 	upperSet;
//	Maybe#(ICacheSetOffset) 	lowerSet;
	Addr						reqAddr;
	Addr						upperAddr;
	Addr						lowerAddr;
} InstMissStatus deriving(Bits, Eq);
