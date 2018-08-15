/*

Copyright (C) 2012 Muralidaran Vijayaraghavan <vmurali@csail.mit.edu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

import Types::*;
import MemTypes::*;
import InstCacheTypes::*;
import DataCacheTypes::*;
import RegFile::*;
import Fifo::*;
import Vector::*;

interface Memory;
	method Action iReq(ICacheMemReq r);
	method ActionValue#(IMemResp) iResp;
	method Action dReq(DCacheMemReq r);
	method ActionValue#(DMemResp) dResp;
endinterface

(* synthesize *)
module mkMemory(Memory);
	RegFile#(MemorySize, Data) mem <- mkRegFileWCFLoad("memory.vmh", 0, maxBound);

	Fifo#(2, ICacheMemReq) 	iMemReqQ 	<- mkCFFifo;
	Fifo#(2, IMemResp) 		iMemRespQ	<- mkCFFifo;

	Fifo#(2, DCacheMemReq) 	dMemReqQ 	<- mkCFFifo;
	Fifo#(2, DMemResp) 		dMemRespQ 	<- mkCFFifo;

	Reg#(BurstCount) 		iMemCnt 	<- mkReg(0);
	Reg#(BurstCount) 		dMemCnt 	<- mkReg(0);
	Reg#(Data) 				penaltyCnt 		<- mkReg(0);
	
	Vector#(2, Reg#(IMemBurstLine))	iMemTempData <- replicateM(mkRegU);
	Reg#(DMemResp) dMemTempData <- mkRegU;

	Reg#(MemStatus) memStatus 	<- mkReg(Idle);
	Reg#(Bool)		readPhase	<- mkReg(True);

	BurstCount initCount =	fromInteger(valueOf(IMemBurstLength));

	rule getDResp(memStatus == DBusy);
		$display("DResp");
		let req = dMemReqQ.first;
		let idx = truncate((req.addr >> 2) + zeroExtend(dMemCnt));
		let data = mem.sub(idx);
		if(dMemCnt == req.burstLength)
		begin
			if(penaltyCnt == 1)
			begin
				dMemCnt <= 0;
				penaltyCnt <= 0;
				memStatus <= Idle;
				dMemReqQ.deq;
				if(req.op == Ld)
				begin
					dMemRespQ.enq(dMemTempData);
				end
			end
			else
				penaltyCnt <= penaltyCnt + 1;
		end
		else
		begin
			if(req.op == St)
			begin
					mem.upd(idx, req.data[dMemCnt]);
					penaltyCnt <= 0;
			end
			//Load
			else
			begin
				let tempData = dMemTempData;
				tempData[dMemCnt] = data;
				dMemTempData <= tempData;
			end
			dMemCnt <= dMemCnt + 1;
			memStatus <= DBusy;
		end
	endrule

	rule getIResp(memStatus == IBusy);

		ICacheMemReq	req			= iMemReqQ.first;
		Addr 			upperAddr 	= req.upperAddr;
		Addr 			lowerAddr 	= req.lowerAddr;
		InstLoadOption	opt			= req.opt;


		MemIndx upperIdx = truncate((upperAddr >>2) + zeroExtend(initCount - iMemCnt));
		MemIndx lowerIdx = truncate((lowerAddr >>2) + zeroExtend(initCount - iMemCnt));
		
		Data data = (((opt == Both) && !readPhase)? 
					mem.sub(lowerIdx) : 
						((opt == Lower)? mem.sub(lowerIdx) : mem.sub(upperIdx)));

		$display("Memory : loaded %x",data);

		if(opt == Both)
		begin
			$display("Both");
			if(readPhase)
			begin
				$display("readPhase");
				if(iMemCnt == 0)
				begin
					$display("MemCnt = 0, initCount = %d",initCount);
					iMemCnt <= initCount;
					readPhase <= !readPhase;
				end
				else
				begin
					IMemBurstLine tempData = iMemTempData[0];
					$display("tempData[%d] = %x",iMemCnt, data);
					tempData[iMemCnt-1] = data;
					iMemTempData[0] <= tempData;
					iMemCnt <= iMemCnt - 1;
				end
			end
			else
			begin
				$display("!readPhase");
				if(iMemCnt == 0)
				begin
					iMemCnt <= initCount;
					readPhase <= !readPhase;
					iMemReqQ.deq;

					IMemResp resp = ?;
					
					$display("Double first line : %x",pack(iMemTempData[0]));
					$display("Double second line : %x", pack(iMemTempData[1]));
					resp[0] = pack(iMemTempData[0]);
					resp[1] = pack(iMemTempData[1]);
					memStatus <= Idle;
					iMemRespQ.enq(resp);
				end
				else
				begin
					IMemBurstLine tempData = iMemTempData[1];
					tempData[iMemCnt-1] = data;
					iMemTempData[1] <= tempData;
					iMemCnt <= iMemCnt - 1;

					$display("tempData[%d] = %x",iMemCnt, data);

				end
			end
		end
		else //If opt is not both
		begin
			$display("Single");
			if(iMemCnt == 0)
			begin
				$display("MemCnt = 0, initCount = %d",initCount);
				iMemCnt <= initCount;
				iMemReqQ.deq;
				IMemResp resp = ?;
				resp[0] = pack(iMemTempData[0]);
				resp[1] = pack(iMemTempData[1]);
				iMemRespQ.enq(resp);
				memStatus <= Idle;
				$display("Single first line : %x",pack(iMemTempData[0]));
			end
			else
			begin
				let tempData = iMemTempData[0];
				tempData[iMemCnt-1] = data;
				iMemTempData[0] <= tempData;
				iMemCnt <= iMemCnt - 1;
				$display("tempData[%d] = %x",iMemCnt, data);
			end
		end
	endrule

	method Action dReq(DCacheMemReq r) if (memStatus == Idle);
		dMemReqQ.enq(r);
		memStatus <= DBusy;
		dMemCnt <= 0;
	endmethod

	method Action iReq(ICacheMemReq r) if (memStatus == Idle);
		iMemReqQ.enq(r);
		memStatus <= IBusy;
		iMemCnt <= initCount;
	endmethod

	method ActionValue#(DMemResp) dResp;
		dMemRespQ.deq;
		return dMemRespQ.first;
	endmethod

	method ActionValue#(IMemResp) iResp;
		iMemRespQ.deq;
		IMemResp resp = ?;
		resp[0] = pack(iMemRespQ.first[0]);
		resp[1] = pack(iMemRespQ.first[1]);
		return resp;
	endmethod
endmodule
