/*

Copyright (C) 2012 Muralidaran Vijayaraghavan <vmurali@csail.mit.edu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/



/*
Prefetching instruction cache module for Y86 processor. Implemented by Hyoukjun Kwon <kwonhjs@snu.ac.kr> 

As the length of Y86 instruction is not fixed and Y86 instructions are not aligned in memory, misaligned read is 
common when processor tries to fetch next instruction. This characteristic makes the cachemodule complex.

*/

import Types::*;
import MemTypes::*;
import InstCacheTypes::*;
import Fifo::*;
import RegFile::*;
import Vector::*;

interface InstCache;
	method Action req(Addr reqAddr);
	method ActionValue#(Inst) resp;

  	method ActionValue#(ICacheMemReq) memReq;
  	method Action memResp(IMemResp r);
	
	method Data getMissCnt;
	method Data getTotalReq;
endinterface

module mkInstCache(InstCache);
	/*	Cache Array	*/
	RegFile#(ICacheIndex, ILine)       			dataArray 	<- mkRegFileFull;
	RegFile#(ICacheIndex, Maybe#(ICacheTag))  	tagArray 	<- mkRegFileFull;

	/* Status register */
	Reg#(Bit#(TAdd#(SizeOf#(ICacheIndex), 1))) 	init 	<- mkReg(0);
	Reg#(ICacheStatus) 							status 	<- mkReg(Ready);

	/* For prefetch */
	Reg#(Maybe#(Addr)) 		lastAccessed	<- mkReg(Invalid);
	Reg#(Maybe#(Addr))		preFetched		<- mkReg(Invalid);

	//A register to specify the working line when updates two lines during cache miss
	Reg#(Bool)				writePhase		<- mkReg(True);	

	/* Interface Fifos and registers */
	Fifo#(1, Inst) 			hitQ 			<- mkBypassFifo;
	Reg#(ICacheMemReq)		missReqQ		<- mkRegU;

	/* Interface between i-Cache and memories */
	Fifo#(2, ICacheMemReq) 	memReqQ 		<- mkCFFifo;
	Fifo#(2, IMemResp) 		memRespQ 		<- mkCFFifo;

	/* Benchmark register*/
	Reg#(Data) 				missCnt 		<- mkReg(0);
	Reg#(Data) 				reqCnt 			<- mkReg(0);

	/* LRU logic module */
//	ILRU iLRU <- mkICacheLRU;

	/////////////////////////////////////////////////////////////////////////////////////////////////////////////
	/* Constants */

	let iLineMSB = fromInteger(valueOf(ILineMSB));
	let criticalByteOfs = fromInteger(valueOf(CriticalByteOffset));
	let inited = truncateLSB(init) == 1'b1;	// Check if the MSB of init is 1 in the init rule
	
	/////////////////////////////////////////////////////////////////////////////////////////////////////////////
	/* Address analyzer  */

	function ICacheBlockNumber	getBlockNumber(Addr addr)	= truncateLSB(addr);
	function ICacheByteOffset 	getOffset(Addr addr)		= truncate(addr);
	
	function ICacheIndex		getIdx(Addr addr)			= truncate(addr >> fromInteger(valueOf(ByteOffsetBits)));
	function ICacheTag 			getTag(Addr addr)			= truncateLSB(addr);

	function Addr getBlockAddr(ICacheTag tag, ICacheIndex idx, ICacheBlockNumber offset);
		ICacheBlockNumber	bn  = {tag, idx} + offset;
		return {bn ,0};
	endfunction

	function ILineBitOffset getBitOffset(ICacheByteOffset ofs) = fromInteger(valueOf(ILineMSB)) - (zeroExtend(ofs) * 8);


	//////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//
	//
	//	Combinational Functions	
	//	1. Maybe#(ICacheSetOffset) findEmptySet(tag, idx)
	//		Returns Invalid if there's no empty set.
	//		Else, returns Valid (empty set number).
	//
	//	2. InstMissStatus checkHits(addr)
	//		Returns 
	//
	//	function Maybe#(ICacheOffset) checkBlockHit(ICacheTag tag, ICacheIndex idx);
	//
	//////////////////////////////////////////////////////////////////////////////////////////////////////////////

	/* Detect cache hit */

	/* Cache hit analysis *///
	/*
	function InstMissStatus checkHits(Addr addr);
		InstMissStatus ret = ?;

		ICacheTag 			upper_tag		= getTag(addr);
		ICacheIndex 		upper_idx		= getIdx(addr);
		ICacheByteOffset	ofs				= getOffset(addr);

		Addr 				upperBlockAddr	= getBlockAddr(upper_tag, upper_idx, 0);
		Addr 				lowerBlockAddr	= getBlockAddr(upper_tag, upper_idx, 1);

		ICacheTag			lower_tag		= getTag(lowerBlockAddr);
		ICacheIndex			lower_idx		= getIdx(lowerBlockAddr);

		let upperTag = tagArray.sub(upper_idx);
		let lowerTag = tagArray.sub(lower_idx);

//		Bool upperHit = isValid(upperTag) && (fromMaybe(?, upperTag) == upper_tag);
//		Bool lowerHit = isValid(lowerTag) && (fromMaybe(?, lowerTag) == lower_tag);
//		Bool upperHit = (fromMaybe(?,upperTag) == upper_tag);
//		Bool lowerHit = (fromMaybe(?,lowerTag) == lower_tag);
		

		Bool crossBoundary 	= (ofs > criticalByteOfs);	//Critical Addr = WordsPerBlock x 4 - 6

		if(!upperHit && !lowerHit)
		begin
			ret.missStatus = BothMiss;
		end
		else
		begin
			if(crossBoundary)
			begin
				if(upperHit)
					ret.missStatus = (lowerHit)? BothHit : LowerMiss;
				else
					ret.missStatus = (lowerHit)? UpperMiss : BothMiss;
			end
			else
			begin
					ret.missStatus = (upperHit)?	SingleHit : SingleMiss;
			end
		end	

		ret.reqAddr 	= addr;
		ret.upperAddr 	= upperBlockAddr;
		ret.lowerAddr 	= lowerBlockAddr;

		return ret;
	endfunction
*/
	function InstLoadOption getLoadOption(InstCacheMissStatus missStatus);

		InstLoadOption opt = (case(missStatus)
							  	UpperMiss, SingleMiss 	: Upper;
							  	LowerMiss 				: Lower;
							  	BothMiss				: Both;
							  	default 				: Nop;
						  	  endcase);
		return opt;
	endfunction

	//////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function Inst getInst(ICacheByteOffset ofs, ILine upperBlock, ILine lowerBlock);
		Inst inst = ?;
		ILineBitOffset bOfs = getBitOffset(ofs);

		if(ofs > criticalByteOfs)	//Need to be modified
		begin
			inst = (case(ofs - criticalByteOfs)
						1:	{upperBlock[39:0], lowerBlock[iLineMSB:iLineMSB- 7]};
						2:	{upperBlock[31:0], lowerBlock[iLineMSB:iLineMSB-15]};
						3:	{upperBlock[23:0], lowerBlock[iLineMSB:iLineMSB-23]};
						4:	{upperBlock[15:0], lowerBlock[iLineMSB:iLineMSB-31]};
						5:	{upperBlock[ 7:0], lowerBlock[iLineMSB:iLineMSB-39]};
					endcase);
		end
		else
		begin
			inst = upperBlock[bOfs:bOfs-47];
		end

		return inst;
	endfunction

	//////////////////////////////////////////////////////////////////////////////////////////////////////////////

	/* Module initialization  */
	

	rule initialize(!inited);
		init <= init + 1;
		
		//Mark every entry of tagArray Invalid
		tagArray.upd(truncate(init), Invalid);

	endrule
	
	//////////////////////////////////////////////////////////////////////////////////////////////////////////////

	/* Prefetch Logic */
/*
	rule triggerPrefetch(status == Ready && isValid(lastAccessed) && isValid(preFetched) && fromMaybe(?, lastAccessed) == fromMaybe(?, preFetched));
		
		status <= ReqPrefetch;

	endrule

	rule doPrefetch(status == ReqPrefetch);
		let prefetchedAddr = fromMaybe(?,preFetched);
		let idx = getIdx(prefetchedAddr);
		let tag = getTag(prefetchedAddr);

		Addr prefetchAddr = getBlockAddr(tag, idx, 1);
		preFetched <= Valid(prefetchAddr);
		memReqQ.enq(ICacheMemReq{upperAddr:prefetchAddr, lowerAddr: ?, opt:Upper});
		status <= WaitPrefetch;
	endrule

	rule fillPrefetch(status == WaitPrefetch);
		let prefetchAddr	= fromMaybe(?, preFetched);
		let tag 			= getTag(prefetchAddr);
		let idx				= getIdx(prefetchAddr);

		let iMemResp 	= memRespQ.first;
		let emptySet 	= findEmptySet(idx);

		//If there remains any Invalid Set, use it.
		//Or, find a target Set using pseudo LRU and replace it
//		ICacheSetOffset targetSet = isValid(emptySet)? fromMaybe(?, emptySet) : iLRU.findLRU();
//		ICacheSetOffset targetSet = isValid(emptySet)? fromMaybe(?, emptySet) : 0;
//		if(!isValid(emptySet))
//			iLRU.updateLRU(targetSet);

		//Update Cache array
		validArray.upd(idx, True);
		tagArray.upd(idx, tag);
		dataArray.upd(idx, iMemResp[0]);	

		memRespQ.deq;
		status <= Ready;
	endrule
*/
	//////////////////////////////////////////////////////////////////////////////////////////////////////////////

	/* Cache miss Logic */
	/*
	rule startMiss(status == StartMiss && inited);

//		let reqAddr = missReqQ.upperAddr;
//		let opt 	= missReqQ.opt;

//		let tag = getTag(reqAddr);
//		let idx = getIdx(reqAddr);

//		let upperAddr = getBlockAddr(tag, idx, 0);
//		let lowerAddr = getBlockAddr(tag, idx, 1);

		memReqQ.enq(missReqQ);
//		memReqQ.enq(ICacheMemReq{upperAddr: upperAddr, lowerAddr: lowerAddr, opt: opt});
		status <= WaitMemResp;

		////////////////////////////////////////////////
		hitQ.enq(0);
		status <= Ready;
	endrule
	*/


	rule waitMemResp(status == WaitMemResp && inited);
		let reqAddr 	= missReqQ.upperAddr;
		let opt			= missReqQ.opt;

		let iMemResp 	= memRespQ.first;

		let tag 		= getTag(reqAddr); 
		let idx			= getIdx(reqAddr);

		let lowerAddr 	= getBlockAddr(tag, idx, 1);
		let lowerIdx	= getIdx(lowerAddr);
		let lowerTag	= getTag(lowerAddr);

		//If there exists an empty set, the empty set takes priroity.
		//Else, find a vitim using LRU scheme
//		ICacheSetOffset targetSet = isValid(emptySet)? fromMaybe(?, emptySet) : iLRU.findLRU();
//		if(!isValid(emptySet))
//			iLRU.updateLRU(targetSet);


		Inst inst = ?;

		case(opt)
			Upper:
			begin
				$display("WaitMemResp : Upper");
				tagArray.upd(idx, Valid(tag));
				dataArray.upd(idx, iMemResp[0]);	
				inst = getInst(getOffset(reqAddr), iMemResp[0], dataArray.sub(lowerIdx));
			end

			Lower: // its probably a problem here, check tag and data arrays.
			begin
				$display("WaitMemResp : Lower");
				tagArray.upd(lowerIdx, Valid(lowerTag));
				dataArray.upd(lowerIdx, iMemResp[0]);
				inst = getInst(getOffset(reqAddr), dataArray.sub(idx), iMemResp[0]);
			end

			Both:
			begin
				$display("WaitMemResp : Both");
				//Updating two lines requires two cycles
				if(writePhase == True)
				begin
					tagArray.upd(idx, Valid(tag));
					dataArray.upd(idx, iMemResp[0]);	
					writePhase <= False;
				end
				else
				begin
					tagArray.upd(lowerIdx, Valid(lowerTag));
					dataArray.upd(lowerIdx, iMemResp[1]);
					writePhase <= True;
					inst = getInst(getOffset(reqAddr), iMemResp[0], iMemResp[1]);
				end
			end

			//This cannot occurr
			default:
			begin
//				$display("[InstCache]: Wrong cache hit/miss determination ");
				$finish;
			end
	
		endcase

		ILineBitOffset bOfs = getBitOffset(getOffset(reqAddr));

		$display("iMemResp[0] : %x", iMemResp[0]);
		$display("iMemResp[1] : %x", iMemResp[1]);
		$display("Inst : %x",inst);

		if((opt != Both) || ((opt == Both) && (writePhase == False)))
		begin
			$display("enqueue inst : %x",inst);
			memRespQ.deq;
			hitQ.enq(inst);
			status <= Ready;
		end

		$display("WaitFillResp : Running");
	endrule


	//////////////////////////////////////////////////////////////////////////////////////////////////////////////


	/* Cache req service logic */
	/*
	 * Descrpition
	 * 	In this method, cache module checks if required instruction is on cache(cache hit) or not(cache miss).
	 *  There are complex cases depending on the required address due to the characteristics of Y86 ISA; variable
	 *	length instructions, and they are not aligned in memory.
	 *  
	 *
	 */
	
	method Action req(Addr reqAddr) if (status == Ready && inited);
		ICacheIndex 		upperIdx  		= getIdx(reqAddr);
		ICacheTag	 		upperTag  		= getTag(reqAddr);
		ICacheByteOffset 	offset 			= getOffset(reqAddr);
	
		Addr				upperBlockAddr	= {upperTag, upperIdx, 0}; //getBlockAddr(upperTag, upperIdx, 0);
		Addr 				lowerBlockAddr	= {{upperTag, upperIdx} +1, 0}; //getBlockAddr(upperTag, upperIdx, 1);

		$display("Req : upperBlockAddr : %d, lowerBlockAddr : %d", upperBlockAddr, lowerBlockAddr);

		ICacheIndex			lowerIdx		= getIdx(lowerBlockAddr);
		ICacheTag			lowerTag		= getTag(lowerBlockAddr);

		let uTagVal = tagArray.sub(upperIdx);
		let lTagVal = tagArray.sub(lowerIdx);

		Bool upperHit = (isValid(uTagVal) && (fromMaybe(?,uTagVal) == upperTag));
		Bool lowerHit = (isValid(lTagVal) && (fromMaybe(?,lTagVal) == lowerTag));
		
		let upperBlock = dataArray.sub(upperIdx);
		let lowerBlock = dataArray.sub(lowerIdx);

//		let hitStatus 	= checkHits(reqAddr);
//		let upperAddr	= hitStatus.upperAddr;
//		let lowerAddr	= hitStatus.lowerAddr;

		Bool crossBoundary 	= (offset > criticalByteOfs);	//Critical Addr = WordsPerBlock x 4 - 6

		InstCacheMissStatus miss = ?;
		
		if(!upperHit && !lowerHit)
		begin
			miss = BothMiss;
		end
		else
		begin
			if(crossBoundary)
			begin
				if(upperHit)
					miss = (lowerHit)? BothHit : LowerMiss;
				else
					miss = (lowerHit)? UpperMiss : BothMiss;
			end
			else
			begin
				miss = (upperHit)? SingleHit : SingleMiss;
			end
		end	

		InstLoadOption opt = getLoadOption(miss);


		//Resolve cache hit and miss cases
		case(miss)

			//BothHit case : Concat upper and lower words and return it immediately
			BothHit :
			begin
				$display("I-Cache hit : double, reqAddr : %d, tag : %d, idx : %d, offset : %d", reqAddr, upperTag, upperIdx, offset);
				$display("                      lowAddr : %d, tag : %d, idx : %d",lowerBlockAddr, lowerTag, lowerIdx);
				$display("uTagVal : %d, lTagVal", fromMaybe(?,uTagVal), fromMaybe(?,lTagVal));
				if(isValid(uTagVal))
					$display("U: Valid");
				else
					$display("U: Invalid");

				if(isValid(lTagVal))
					$display("L: Valid");
				else
					$display("L: Invalid");

//				$display("upperBlock : %x\nlowerBlock : %x", upperBlock, lowerBlock);	
				Inst inst = getInst(offset, upperBlock, lowerBlock);
				hitQ.enq(inst);
			end

			//SingleHit case : Concat words blocks and return it immediately
			SingleHit :
			begin
				$display("I-Cache hit : single, reqAddr : %d, tag : %d, idx : %d, offset : %d", reqAddr, upperTag, upperIdx, offset);
				Inst inst = getInst(offset, upperBlock, ?);
				hitQ.enq(inst);
			end

			//Cache miss case : Send miss request and change cache status into startMiss
			default:
			begin
				$display("I-Cache miss, reqAddr : %d, tag: %d, idx : %d, offset : %d",reqAddr, upperTag, upperIdx, offset);
				missReqQ <= ICacheMemReq{upperAddr: reqAddr, lowerAddr: lowerBlockAddr, opt: opt};
				memReqQ.enq(ICacheMemReq{upperAddr: upperBlockAddr, lowerAddr: lowerBlockAddr, opt: opt});
				status <= WaitMemResp;
			end
		endcase

		lastAccessed <= Valid(reqAddr);

		if(opt != Nop)
			missCnt <= missCnt + 1;
		
		reqCnt <= reqCnt + 1;

	endmethod

	method ActionValue#(Inst) resp;
		hitQ.deq;
		return hitQ.first;
	endmethod

  	method ActionValue#(ICacheMemReq) memReq;
		memReqQ.deq;
		return memReqQ.first;
	endmethod

  	method Action memResp(DoubleILine r);
		memRespQ.enq(r);
	endmethod

	method Data getMissCnt;
		return missCnt;
	endmethod

	method Data getTotalReq;
		return reqCnt;
	endmethod

endmodule
