/*

Copyright (C) 2012 Muralidaran Vijayaraghavan <vmurali@csail.mit.edu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/


import Types::*;
import MemTypes::*;
import DataCacheTypes::*;
import Fifo::*;
import RegFile::*;
import Vector::*;

interface DataCache;
	method Action req(MemReq r);
	method ActionValue#(Data) resp;

  	method ActionValue#(DCacheMemReq) memReq;
  	method Action memResp(DLine r);
	
	method Data getMissCnt;
	method Data getTotalReq;
endinterface


typedef enum {Ready, StartMiss, SendFillReq, WaitFillResp} DCacheStatus deriving (Bits, Eq);

module mkCacheDirectMap(DataCache);
	RegFile#(DCacheIndex, DLine) 				dataArray 	<- mkRegFileFull;
	RegFile#(DCacheIndex, Maybe#(DCacheTag))  	tagArray 	<- mkRegFileFull;
	RegFile#(DCacheIndex, Bool) 				dirtyArray 	<- mkRegFileFull;

	Reg#(Bit#(TAdd#(SizeOf#(DCacheIndex), 1))) 	init 		<- mkReg(0);
	Reg#(DCacheStatus) 						  	status 		<- mkReg(Ready);

	Fifo#(1, Data) hitQ <- mkBypassFifo;
	Reg#(MemReq)   missReq <- mkRegU;

	Fifo#(2, DCacheMemReq) memReqQ  <- mkCFFifo;
	Fifo#(2, DLine) 		  memRespQ <- mkCFFifo;

	Reg#(Data) missCnt <- mkReg(0);
	Reg#(Data) reqCnt <- mkReg(0);

	// Two bits from LSB is always 2'b0 ; because PC has 4-alligned address. So ignore the two bits.
	function DCacheIndex getIdx(Addr addr) = truncate(addr >> (2+fromInteger(valueOf(SizeOf#(DCacheBlockOffset)))));
	function DCacheTag getTag(Addr addr) = truncateLSB(addr);
	function DCacheBlockOffset getOffset(Addr addr) = truncate(addr>>2);

	function Addr getBlockAddr(DCacheTag tag, DCacheIndex idx);
		DCacheBlockOffset def_offset = 0;
		Addr addr = {tag, idx, def_offset, 2'b0};
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
			memReqQ.enq(DCacheMemReq{op: St, addr: blockAddr, data:data, burstLength: fromInteger(valueOf(DWordsPerBlock))});
		end
		status <= SendFillReq;
	endrule

	rule sendFillReq(status == SendFillReq);
		let idx       = getIdx(missReq.addr);
		let tag       = getTag(missReq.addr);
		let blockAddr = getBlockAddr(tag,idx);

		memReqQ.enq(DCacheMemReq{op: Ld, addr: blockAddr, data: ?, burstLength: fromInteger(valueOf(DWordsPerBlock))});
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
// Need to add fit condition


		status <= Ready;
	endrule

	method Action req(MemReq r) if (status == Ready && inited);
		let idx     = getIdx(r.addr);
		let tag     = getTag(r.addr);
		let offset  = getOffset(r.addr);
		let currTag = tagArray.sub(idx);
		let dirty   = dirtyArray.sub(idx);

		Bool hit = isValid(currTag)? (fromMaybe(?,currTag) == tag):False;

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

				DLine updData = dataArray.sub(idx);
				updData[offset] = r.data;
				dataArray.upd(idx,updData);
				dirtyArray.upd(idx,True);
			end
			else
			begin
				//Pin-point Store. Store not whole line, but a data.(can't know about the data around what we are storing)
				let newData = dataArray.sub(idx);
				newData[0] = r.data;
				memReqQ.enq(DCacheMemReq{op: St, addr: r.addr, data:newData, burstLength: 1});
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

	method ActionValue#(DCacheMemReq) memReq;
		memReqQ.deq;
		return memReqQ.first;
	endmethod

	method Action memResp(DLine r);
		memRespQ.enq(r);
	endmethod

	method Data getMissCnt;
		return missCnt;	
	endmethod

	method Data getTotalReq;
		return reqCnt;	
	endmethod
endmodule

module mkCacheSetAssociative (DataCache);
        
	Vector#(DCacheSets, RegFile#(DCacheIndex, DLine))              	dataArray 	<- replicateM(mkRegFileFull);
	Vector#(DCacheSets, RegFile#(DCacheIndex, Maybe#(DCacheTag)))  	tagArray 	<- replicateM(mkRegFileFull);
	Vector#(DCacheSets, RegFile#(DCacheIndex, Bool))              	dirtyArray 	<- replicateM(mkRegFileFull);
	RegFile#(DCacheIndex, Maybe#(DCacheSetOffset)) 					ruArray 	<- mkRegFileFull;

	Reg#(Bit#(TAdd#(SizeOf#(DCacheIndex), 1))) init <- mkReg(0);
	Reg#(DCacheStatus) status <- mkReg(Ready);
	Reg#(Maybe#(DCacheSetOffset)) targetSet <- mkReg(Invalid);
	
	Fifo#(1, Data) hitQ <- mkBypassFifo;
	Reg#(MemReq) missReq <- mkRegU;

	Fifo#(2, DCacheMemReq) memReqQ <- mkCFFifo;
	Fifo#(2, DLine) memRespQ <- mkCFFifo;

	Reg#(Data) missCnt <- mkReg(0);
	Reg#(Data) reqCnt <- mkReg(0);

	function DCacheIndex getIdx(Addr addr) = truncate(addr >> (2+fromInteger(valueOf(SizeOf#(DCacheBlockOffset)))));
	function DCacheTag getTag(Addr addr) = truncateLSB(addr);
	function DCacheBlockOffset getOffset(Addr addr) = truncate(addr>>2);

	function Addr getBlockAddr(DCacheTag tag, DCacheIndex idx);
		DCacheBlockOffset def_offset = 0;
		Addr addr = {tag, idx, def_offset, 2'b0};
		return addr;
	endfunction

	function Maybe#(DCacheSetOffset) checkHit(DCacheTag tag, DCacheIndex idx);
	//ret have the information if cache hit or not with validity, and if the set data exist or not when cache hit occured.
		Maybe#(DCacheSetOffset) ret = Invalid;

		for(Integer i = 0; i< valueOf(DCacheSets); i = i+1)
		begin
			let tagArrayVal = tagArray[i].sub(idx);

			if(isValid(tagArrayVal) && (fromMaybe(?,tagArrayVal) == tag) )
			begin
				ret = tagged Valid fromInteger(i);
			end
		end

		return ret;
	endfunction

	function Maybe#(DCacheSetOffset) checkInvalid(DCacheTag tag, DCacheIndex idx);
	//If a set is invalid, return the set number with valid data	
		Maybe#(DCacheSetOffset) ret = Invalid;

		for(Integer i = 0; i < valueOf(DCacheSets); i = i+1)
		begin
			if(!isValid(tagArray[i].sub(idx)))
			begin
				ret = tagged Valid fromInteger(i);
			end
		end

		return ret;
	endfunction

	function Maybe#(DCacheSetOffset) findLRU(DCacheTag tag, DCacheIndex idx);
	//Approximate LRU Logic. Check the ruArray(Recently Used Array), find a set which is not most recently used.
	//Among the target sets, the latest one is selected in this logic.
		Maybe#(DCacheSetOffset) ret = Invalid;

		for(Integer i = 0; i< valueOf(DCacheSets); i = i+1)
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

		for(Integer i = 0; i< valueOf(DCacheSets);i = i+1)
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
		
		Maybe#(DCacheSetOffset) destSet = Invalid;

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
				memReqQ.enq(DCacheMemReq{op: St, addr: blockAddr, data:data, burstLength: fromInteger(valueOf(DWordsPerBlock))});
			end
		end


		targetSet <= destSet;
		status <= SendFillReq;
	endrule

	rule sendFillReq(status == SendFillReq);
		let idx       = getIdx(missReq.addr);
		let tag       = getTag(missReq.addr);
		let blockAddr = getBlockAddr(tag,idx);

		memReqQ.enq(DCacheMemReq{op: Ld, addr: blockAddr, data: ?, burstLength: fromInteger(valueOf(DWordsPerBlock))});
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
				DLine updData = dataArray[setNum].sub(idx);
				updData[offset] = r.data;
				
				dataArray[setNum].upd(idx,updData);
				dirtyArray[setNum].upd(idx,True);
				ruArray.upd(idx, hit); // Let's consider it.....
			end
			else
			begin
				DLine newData = newVector;
				newData[0] = r.data;
				memReqQ.enq(DCacheMemReq{op: St, addr: r.addr, data:newData, burstLength: 1});
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

	method ActionValue#(DCacheMemReq) memReq;
		memReqQ.deq;
		return memReqQ.first;
	endmethod

	method Action memResp(DLine r);
		memRespQ.enq(r);
	endmethod

	method Data getMissCnt;
		return missCnt;	
	endmethod

	method Data getTotalReq;
		return reqCnt;	
	endmethod
endmodule

module mkDataCache (DataCache);
	DataCache cacheDirectMap <- mkCacheDirectMap;
	return cacheDirectMap;
//	DataCache cacheSetAssociative <- mkCacheSetAssociative;
//	return cacheSetAssociative;

endmodule
