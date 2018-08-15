/*

Copyright (C) 2012 Muralidaran Vijayaraghavan <vmurali@csail.mit.edu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/


import Types::*;
import MemTypes::*;
import CacheTypes::*;
import Fifo::*;
import RegFile::*;
import Vector::*;

interface Cache;
	method Action req(MemReq r);
	method ActionValue#(Data) resp;

 	method ActionValue#(CacheMemReq) memReq;
 	method Action memResp(Line r);

	method Data getMissCnt;
	method Data getTotalReq;
endinterface

typedef enum {Ready, StartMiss, SendFillReq, WaitFillResp} CacheStatus deriving (Bits, Eq);

module mkCacheDirectMap(Cache);
  /* Organization of Direct Mapped Cache

     Cache Entry (Set Associativity 1)
     =================================
       ---------------------------------------------------------------------------------
       | Valid Bit(1) | Tag Bit(CacheTagSz) | Blocks[0:BlockOffsetSz-1] | Dirty Bit(1) |
       ---------------------------------------------------------------------------------

     Implementation details
     ======================

       dataArray  : Data blocks
       tagArray   : Tag of each block (Valid bit implemented as Maybe type)
       dirtyArray : Dirty bit of each block

     This module ignores set-associativity configurations noted at CacheTypes.bsv
  */
	RegFile#(CacheIndex, Line) 				        dataArray <- mkRegFileFull;
	RegFile#(CacheIndex, Maybe#(CacheIdxTag))		tagArray <- mkRegFileFull;
	RegFile#(CacheIndex, Bool) 				        dirtyArray <- mkRegFileFull;

  // Initialize Cache when boot up
	Reg#(Bit#(TAdd#(CacheIndexSz, 1)))   init <- mkReg(0);
	Reg#(CacheStatus) 		             status <- mkReg(Ready);

	Fifo#(1, Data)    hitQ <- mkBypassFifo;
	Reg#(MemReq)   missReq <- mkRegU;

	Fifo#(2, CacheMemReq) memReqQ <- mkCFFifo;
	Fifo#(2, Line) 		   memRespQ <- mkCFFifo;

	Reg#(Data) missCnt <- mkReg(0);
	Reg#(Data)  reqCnt <- mkReg(0);

	function CacheIndex getIdx(Addr addr);
    let idxShift = valueOf(TAdd#(CacheBlockOffsetSz, CacheByteOffsetSz));
    return truncate(addr >> idxShift);
  endfunction

	function CacheIdxTag getTag(Addr addr);
    let tagShift = valueOf(TAdd#(TAdd#(CacheBlockOffsetSz, CacheByteOffsetSz), CacheIndexSz));
    return truncate(addr >> tagShift);
  endfunction

	function CacheBlockOffset getOffset(Addr addr);
    let blockShift = valueOf(CacheByteOffsetSz);
    return truncate(addr >> blockShift);
  endfunction

	function Addr getBlockAddr(CacheIdxTag tag, CacheIndex idx);
    CacheBlockOffset blockOffset = 0;
		Addr addr = {tag, idx, blockOffset, 3'b000};
		return addr;
	endfunction

 	let inited = truncateLSB(init) == 1'b1;

  rule initialize(!inited);
		init <= init + 1;
		tagArray.upd(truncate(init), Invalid);
		dirtyArray.upd(truncate(init), False);
	endrule

	rule startMiss(status == StartMiss);
		let idx     = getIdx(missReq.addr);
		let tag     = getTag(missReq.addr);
		let offset  = getOffset(missReq.addr);
		let currTag = tagArray.sub(idx);
		let dirty   = dirtyArray.sub(idx);

		if(isValid(currTag) && dirty)
		begin
			let blockAddr = getBlockAddr(fromMaybe(?,currTag),idx);
			let data = dataArray.sub(idx);
			memReqQ.enq(CacheMemReq{op: St, addr: blockAddr, data:data, burstLength: fromInteger(valueOf(DataPerBlock))});
		end
		status <= SendFillReq;
  endrule

	rule sendFillReq(status == SendFillReq);
		let idx       = getIdx(missReq.addr);
		let tag       = getTag(missReq.addr);
		let blockAddr = getBlockAddr(tag,idx);

		memReqQ.enq(CacheMemReq{op: Ld, addr: blockAddr, data: ?, burstLength: fromInteger(valueOf(DataPerBlock))});
		status <= WaitFillResp;
	endrule

	rule waitFillResp(status == WaitFillResp && inited);
		let idx    = getIdx(missReq.addr);
		let tag    = getTag(missReq.addr);
		let offset = getOffset(missReq.addr);
		let data   = memRespQ.first;
		hitQ.enq(data[offset]);
		memRespQ.deq;

		tagArray.upd(idx,tagged Valid tag);
		dataArray.upd(idx,data);
		dirtyArray.upd(idx,False);

		status <= Ready;
	endrule

	method Action req(MemReq r) if (status == Ready && inited);
		/* Implement here */
		let idx     = getIdx(r.addr);
		let tag     = getTag(r.addr);
		let offset  = getOffset(r.addr);
		let currTag = tagArray.sub(idx);
		let dirty   = dirtyArray.sub(idx);

		Bool hit = isValid(currTag) ? (fromMaybe(?, currTag) == tag) : False;

		if (r.op == Ld) // Load
		begin
			if(hit)
			begin
				hitQ.enq(dataArray.sub(idx)[offset]);
			end
			else
			begin
				missReq <= r;
				status <= StartMiss;
			end
		end
		else // Store
		begin
			if(hit)
			begin
				//Loads the Line, and updates the targetted data.
				Line updData = dataArray.sub(idx);
				updData[offset] = r.data;
				dataArray.upd(idx,updData);
				dirtyArray.upd(idx,True);
			end
			else
			begin
				//Pin-point Store. Store not whole line, but a data.(can't know about the data around what we are storing)
				let newData = dataArray.sub(idx);
				newData[0] = r.data;
				memReqQ.enq(CacheMemReq{op: St, addr: r.addr, data:newData, burstLength: 1});
			end
		end

		/* Do not modify below here */
		if(!hit)
		begin
			missCnt <= missCnt + 1;
		end
		reqCnt <= reqCnt + 1;
	endmethod

	method ActionValue#(Data) resp;
		hitQ.deq;
		return hitQ.first;
	endmethod

	method ActionValue#(CacheMemReq) memReq;
		memReqQ.deq;
		return memReqQ.first;
	endmethod

	method Action memResp(Line r);
		memRespQ.enq(r);
	endmethod

	method Data getMissCnt;
		return missCnt;
	endmethod

	method Data getTotalReq;
		return reqCnt;
	endmethod
endmodule
module mkCacheSetAssociative (Cache);
        
	Vector#(CacheSets, RegFile#(CacheIndex, Line))              dataArray <- replicateM(mkRegFileFull);
	Vector#(CacheSets, RegFile#(CacheIndex, Maybe#(CacheSetTag)))  tagArray <- replicateM(mkRegFileFull);
	Vector#(CacheSets, RegFile#(CacheIndex, Bool))              dirtyArray <- replicateM(mkRegFileFull);
	RegFile#(CacheIndex, Maybe#(CacheSetOffset)) ruArray <- mkRegFileFull;

	Reg#(Bit#(TAdd#(SizeOf#(CacheIndex), 1))) init <- mkReg(0);
	Reg#(CacheStatus) status <- mkReg(Ready);
	Reg#(Maybe#(CacheSetOffset)) targetSet <- mkReg(Invalid);
	
	Fifo#(1, Data) hitQ <- mkBypassFifo;
	Reg#(MemReq) missReq <- mkRegU;

	Fifo#(2, CacheMemReq) memReqQ <- mkCFFifo;
	Fifo#(2, Line) memRespQ <- mkCFFifo;

	Reg#(Data) missCnt <- mkReg(0);
	Reg#(Data) reqCnt <- mkReg(0);

	function CacheIndex getIdx(Addr addr); 
    let idxShift = valueOf(TAdd#(CacheBlockOffsetSz, CacheByteOffsetSz));
    return truncate(addr >> idxShift);
  endfunction

	function CacheSetTag getTag(Addr addr);
    let tagShift = valueOf(TAdd#(TAdd#(CacheBlockOffsetSz, CacheByteOffsetSz), SizeOf#(CacheIndex)));
    return truncate(addr >> tagShift);
  endfunction

	function CacheBlockOffset getOffset(Addr addr);
    let blockShift = valueOf(CacheByteOffsetSz);
    return truncate(addr >> blockShift);
  endfunction

	function Addr getBlockAddr(CacheSetTag tag, CacheIndex idx);
		CacheBlockOffset def_offset = 0;
		Addr addr = {tag, idx, def_offset, 3'b000};
		return addr;
	endfunction

	function Maybe#(CacheSetOffset) checkHit(CacheSetTag tag, CacheIndex idx);
	//ret have the information if cache hit or not with validity, and if the set data exist or not when cache hit occured.
		Maybe#(CacheSetOffset) ret = Invalid;

		for(Integer i = 0; i< valueOf(CacheSets); i = i+1)
		begin
			let tagArrayVal = tagArray[i].sub(idx);

			if(isValid(tagArrayVal) && (fromMaybe(?,tagArrayVal) == tag) )
			begin
				ret = tagged Valid fromInteger(i);
			end
		end

		return ret;
	endfunction

	function Maybe#(CacheSetOffset) checkInvalid(CacheSetTag tag, CacheIndex idx);
	//If a set is invalid, return the set number with valid data
		Maybe#(CacheSetOffset) ret = Invalid;

		for(Integer i = 0; i < valueOf(CacheSets); i = i+1)
		begin
			if(!isValid(tagArray[i].sub(idx)))
			begin
				ret = tagged Valid fromInteger(i);
			end
		end

		return ret;
	endfunction

	function Maybe#(CacheSetOffset) findLRU(CacheSetTag tag, CacheIndex idx);
	//Approximate LRU Logic. Check the ruArray(Recently Used Array), find a set which is not most recently used.
	//Among the target sets, the latest one is selected in this logic.
		Maybe#(CacheSetOffset) ret = Invalid;

		for(Integer i = 0; i< valueOf(CacheSets); i = i+1)
		begin
			if(fromMaybe(?,ruArray.sub(idx)) == fromInteger(i))
			begin
				ret = tagged Valid fromInteger(i);
			end
		end

		return ret;
	endfunction

  	let inited = truncateLSB(init) == 1'b1;

	rule initialize(!inited);
		init <= init + 1;

		for(Integer i = 0; i< valueOf(CacheSets);i = i+1)
		begin	
			tagArray[i].upd(truncate(init), Invalid);
			dirtyArray[i].upd(truncate(init), False);
		end

		ruArray.upd(truncate(init), Invalid);
	endrule

	/* Implement rules */

	rule startMiss(status == StartMiss);
		let idx     = getIdx(missReq.addr);
		let tag     = getTag(missReq.addr);
		let offset  = getOffset(missReq.addr);
		
		Maybe#(CacheSetOffset) destSet = Invalid;

		let invalidTargetSet = checkInvalid(tag,idx);

		
		if(isValid(invalidTargetSet)) //If there is an invalid set, target that set
		begin
			destSet = invalidTargetSet;
		end
		else //else, if every set is valid, find a victim using approx. LRU policy
		begin
			let lru    = findLRU(tag,idx);
			let lruSet = fromMaybe(?,lru);
			if(isValid(lru))
			begin
				destSet = lru;
			end
			
			let dirty = dirtyArray[lruSet].sub(idx);
			let currTag = tagArray[lruSet].sub(idx);
			if(isValid(currTag) && dirty)
			begin
				let blockAddr = getBlockAddr(fromMaybe(?,currTag),idx);
				let data = dataArray[lruSet].sub(idx);
				memReqQ.enq(CacheMemReq{op: St, addr: blockAddr, data:data, burstLength: fromInteger(valueOf(DataPerBlock))});
			end
		end


		targetSet <= destSet;
		status <= SendFillReq;
	endrule

	rule sendFillReq(status == SendFillReq);
		let idx       = getIdx(missReq.addr);
		let tag       = getTag(missReq.addr);
		let blockAddr = getBlockAddr(tag,idx);

		memReqQ.enq(CacheMemReq{op: Ld, addr: blockAddr, data: ?, burstLength: fromInteger(valueOf(DataPerBlock))});
		status <= WaitFillResp;
	endrule

	rule waitFillResp(status == WaitFillResp && inited);
		let idx    = getIdx(missReq.addr);
		let tag    = getTag(missReq.addr);
		let offset = getOffset(missReq.addr);
		let data   = memRespQ.first;
		hitQ.enq(data[offset]);
		memRespQ.deq;

		if(isValid(targetSet))
		begin
			let target = fromMaybe(?,targetSet);

			tagArray[target].upd(idx,tagged Valid tag);
			dataArray[target].upd(idx,data);
			dirtyArray[target].upd(idx,False);
		end
		targetSet <= Invalid;
		status <= Ready;
	endrule

	method Action req(MemReq r) if (status == Ready && inited);
		let idx    = getIdx(r.addr);
		let tag    = getTag(r.addr);
		let offset = getOffset(r.addr);
		let hit = checkHit(tag, idx);
		/* Implement here */
	
		if(r.op == Ld)
		begin
			if(isValid(hit))
			begin
				let setNum = fromMaybe(?,hit);
				hitQ.enq(dataArray[setNum].sub(idx)[offset]);
				ruArray.upd(idx, hit);
			end
			else
			begin
				missReq <= r;
				status <= StartMiss;
			end	
		end
		else
		begin
			if(isValid(hit))
			begin
				let setNum = fromMaybe(?,hit);
				Line updData = dataArray[setNum].sub(idx);
				updData[offset] = r.data;
				
				dataArray[setNum].upd(idx,updData);
				dirtyArray[setNum].upd(idx,True);
				ruArray.upd(idx, hit); // Let's consider it.....
			end
			else
			begin
				Line newData = newVector;
				newData[0] = r.data;
				memReqQ.enq(CacheMemReq{op: St, addr: r.addr, data:newData, burstLength: 1});
			end
		end	



		/* Do not modify below here */
		if(!isValid(hit))
		begin
			missCnt <= missCnt + 1;
		end
		reqCnt <= reqCnt + 1;
	endmethod

	method ActionValue#(Data) resp;
		hitQ.deq;
		return hitQ.first;
	endmethod

	method ActionValue#(CacheMemReq) memReq;
		memReqQ.deq;
		return memReqQ.first;
	endmethod

	method Action memResp(Line r);
		memRespQ.enq(r);
	endmethod

	method Data getMissCnt;
		return missCnt;	
	endmethod

	method Data getTotalReq;
		return reqCnt;	
	endmethod
endmodule
module mkCache (Cache);

	//Use these two lines to make the cache direct mapped cache
	Cache cacheDirectMap <- mkCacheDirectMap;
	return cacheDirectMap;

	//Use these two lines to make the cache Set associative cache

	// Cache cacheSetAssociative <- mkCacheSetAssociative;
	// return cacheSetAssociative;

endmodule