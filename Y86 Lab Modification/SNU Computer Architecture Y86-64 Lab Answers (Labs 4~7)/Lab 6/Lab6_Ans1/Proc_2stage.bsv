import Types::*;
import ProcTypes::*;
import MemTypes::*;
import RFile::*;
import IMemory::*;
import DMemory::*;
import Decode::*;
import Exec::*;
import Cop::*;
import Status::*;
import AddrPred::*;
import Fifo::*;
import Scoreboard::*;

typedef struct {
	DecodedInst dInst;
	Addr ppc;
	Bool epoch;
} Decode2Execute deriving (Bits,Eq);

(*synthesize*)
module mkProc(Proc);
	//Basic elemnets
	Reg#(Addr)		pc 			<- mkRegU;
	RFile			rf  		<- mkBypassRFile;
	IMemory			iMem  		<- mkIMemory;
	DMemory			dMem  		<- mkDMemory;
	Reg#(CondFlag)	condFlag	<- mkRegU;
	Reg#(Stat)		stat		<- mkRegU;
	Cop				cop 	 	<- mkCop;

	//Control hazard handling Elements
	Reg#(Bool) 		fEpoch 		<- mkRegU;
	Reg#(Bool) 		eEpoch 		<- mkRegU;
	Fifo#(1, Addr)	pcRedirect	<- mkBypassFifo;
	Scoreboard#(1)	sb			<- mkScoreboard;	

	Fifo#(1, Decode2Execute) d2e  <- mkPipelineFifo;

	rule doFetch(cop.started && stat == AOK);
		let inst = iMem.req(pc);
		if(pcRedirect.notEmpty) 
		begin
			pcRedirect.deq;

			fEpoch 	<= !fEpoch;
			pc		<= pcRedirect.first;	
		end
		else
		begin
			let dInst	= decode(inst, pc);
			let ppc		= nexAddr(pc);	

			let stall	=	(sb.search1(dInst.regA) || sb.search2(dInst.regB)
							|| sb.search3(dInst.dstE) || sb.search4(dInst.dstM));
			if(!stall)
			begin
				dInst.valA	= rf.rdA(dInst.regA);
				dInst.valB	= rf.rdB(dInst.regB);
				d2e.enq(Decode2Execute{dInst: dInst, ppc: ppc, epoch: fEpoch});
				sb.insertE(dInst.dstE);
				sb.insertM(dInst.dstM);

				pc	<= ppc;
			end
		end
	endrule

	rule doExecute(cop.started && stat == AOK);
		let x		= d2e.first;
		let dInst	= x.dInst;	
		let ppc		= x.ppc;
		let inEp	= x.epoch;

		if(inEp == eEpoch)
		begin
			let eInst = exec(dInst, condFlag, ppc);
			condFlag <= eInst.condFlag;

			let iType = eInst.iType;
			case(iType)
				MrMov, Pop, Ret: begin
					let ldData	<- (dMem.req(MemReq{op: Ld, addr: eInst.memAddr, data: ?}));
					eInst.valM = Valid(little2BigEndian(ldData));
				end
				RmMov, Call, Push: begin
					let stData = (iType == Call) ? eInst.valP : validValue(eInst.valA);
					let dummy <- dMem.req(MemReq{op: St, addr: eInst.memAddr, data: big2LittleEndian(stData)});
				end
			endcase

			let newStatus = 
			case(iType)
				Unsupported	: Ins;
				Hlt			: HLT;
				default		: AOK;
			endcase;

			if(eInst.mispredict)
			begin
				pcRedirect.enq(eInst.nextPC);
				eEpoch	<= !inEp;
			end

			if(isValid(eInst.dstE))
			begin
				rf.wrE(eInst.dstE, dInst.valE);
			end

			if(isValid(eInst.dstM))
			begin
				rf_wrM(eInst.dstM, eInst.valM);
			end
		end

		d2e.deq;
		sb.remove;
	endrule

	rule fin(cop.started && stat == HLT);
		$fwrite(stderr,"Program Finished, return Value : %d \n",(rf.rd1(eax)));
		$finish;
	endrule 

	rule insError(cop.started && stat == INS);
		$fwrite(stderr,"Executed unsupported instruction at pc %x. Exiting\n",pc);
		$finish;
	endrule

	method ActionValue#(Tuple3#(RIndx, Data, Data)) cpuToHost;
		let retV <- cop.cpuToHost;
		return retV;
	endmethod

	method Action hostToCpu(Bit#(32) startpc) if (!cop.started);
		cop.start;
		eEpoch <= False;
		fEpoch <= False;
		pc <= startpc;
		stat <= AOK;
	endmethod
endmodule
