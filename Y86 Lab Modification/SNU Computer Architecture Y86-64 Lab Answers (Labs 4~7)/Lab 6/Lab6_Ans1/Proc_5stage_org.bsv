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
	Inst inst;
	Addr pc;
	Addr ppc;
	Bool epoch;
} Fetch2Decode deriving (Bits, Eq);

typedef struct {
	DecodedInst dInst;
	Addr pc;
	Addr ppc;
	Bool epoch;
} Decode2Exec deriving (Bits,Eq);

typedef struct {
	Maybe#(ExecInst) eInst;
	Addr pc;
	Addr ppc;
} Exec2Mem deriving(Bits, Eq);

typedef struct {
	Maybe#(ExecInst) eInst;
	Addr pc;
} Mem2WB deriving(Bits, Eq);

(*synthesize*)
module mkProc(Proc);
  Reg#(Addr)     pc  <- mkRegU;
  RFile         rf  <- mkBypassRFile;
  IMemory     iMem  <- mkIMemory;
  DMemory     dMem  <- mkDMemory;
  Cop          cop  <- mkCop;

  Scoreboard#(4)  sb  <- mkPipelineScoreboard;

  Reg#(CC) 	 flags  <- mkReg(0);
  Reg#(Stat)  stat  <- mkReg(AOK);

  Reg#(Bool) fEpoch <- mkReg(False);
  Reg#(Bool) eEpoch <- mkReg(False);

  Fifo#(1,Fetch2Decode) f2d  <- mkPipelineFifo;
  Fifo#(1,Decode2Exec)  d2e  <- mkPipelineFifo;
  Fifo#(1,Exec2Mem)     e2m  <- mkPipelineFifo;
  Fifo#(1,Mem2WB)       m2w  <- mkPipelineFifo;

  Fifo#(1,Addr) exeRedir <- mkBypassFifo;
  Fifo#(1,Addr) memRedir <- mkBypassFifo;


  rule fin(cop.started && stat == HLT);
	$fwrite(stderr,"Program Finished, return Value : %d \n",(rf.rd1(eax)));
    $finish;
  endrule 

  rule insError(cop.started && stat == INS);
	$fwrite(stderr,"Executed unsupported instruction at pc %x. Exiting\n",pc);
	$finish;
  endrule


  rule doFetch(cop.started && stat == AOK);
	let realPc = ?;
	let newEpoch = ?;

	let exeR = exeRedir.notEmpty;
	let memR = memRedir.notEmpty;

	//priority : Mem Redir Pc < Exe Redir Pc < Pc

	if(memR)
	begin
		newEpoch = !fEpoch;
		realPc = memRedir.first;
	end
	else if (exeR)
	begin
		newEpoch = !fEpoch;
		realPc = exeRedir.first;
	end
	else
	begin
		newEpoch = fEpoch;
		realPc = pc;
	end

	if(memR) memRedir.deq;
	if(exeR) exeRedir.deq;

    let inst = iMem.req(realPc);
		let iCode  = getICode(inst);
		let opCode = getOpCode(inst);

	let pcPN 	   = pcIncrement(realPc, iCode);

	let validInst  = isValidInst(opCode);

//	if(!validInst)
//		stat <= INS;
//	else if(iCode == halt)
//		stat <= HLT;

	$display("\nFetch : PC(%d), Fetched %x\n ", realPc, showInst(inst));

	pc <= pcPN;
	fEpoch <= newEpoch;

	f2d.enq(Fetch2Decode{inst: inst, pc: realPc, ppc: pcPN, epoch: newEpoch});

endrule

rule doDecode(stat == AOK);
	let inst  = f2d.first.inst;
	let ipc   = f2d.first.pc;
	let ppc   = f2d.first.ppc;
	let epoch = f2d.first.epoch;

	let dInst = decode(inst);
	let dst   = dInst.dst;
	let src1  = dInst.src1;
	let src2  = dInst.src2;

	let stall = sb.search(src1, src2);

	if(!stall)
	begin

		f2d.deq;
		sb.insert(dst, (dInst.iType == Pop)? validReg(esp):Invalid);

		//Register Read
		dInst.rVal1  = isValid(dInst.src1)? tagged Valid rf.rd1(validRegValue(dInst.src1)) : Invalid;
	   	dInst.rVal2  = isValid(dInst.src2)? tagged Valid rf.rd2(validRegValue(dInst.src2)) : Invalid;
		dInst.copVal = isValid(dInst.src1)? tagged Valid cop.rd(validRegValue(dInst.src1)) : Invalid;
		
		d2e.enq(Decode2Exec{dInst:dInst, pc: ipc, ppc: ppc, epoch:epoch});
	end
	else
		$display("stall occured\n");

endrule


rule doExec(cop.started && stat == AOK);
		d2e.deq;
		let dInst   = d2e.first.dInst;
		let ipc 	= d2e.first.pc;
		let ppc 	= d2e.first.ppc;
		let epoch 	= d2e.first.epoch;

		if(epoch == eEpoch)
		begin

			$display("\nExec : Executing Instruction at PC %d\n",ipc);

			let eInst = exec(dInst, dInst.rVal1, dInst.rVal2, pc, ppc, ppc, dInst.copVal, flags);
		
			flags <= eInst.flags;

			if(eInst.mispredict)
			begin
				eEpoch <= !eEpoch;
				if(eInst.eType != ERet)
					exeRedir.enq(eInst.addr);
			end

			e2m.enq(Exec2Mem{eInst:tagged Valid eInst, pc:ipc, ppc:ppc});

		end
		else
		begin
			if(dInst.iType == Pop)
				sb.remove2;
			e2m.enq(Exec2Mem{eInst: Invalid, pc:ipc, ppc:ppc});
		end
			
endrule	


rule doMemory(cop.started && stat == AOK);
	e2m.deq;
	let ipc 	= e2m.first.pc;
	let ppc		= e2m.first.ppc;

	if(isValid(e2m.first.eInst))
	begin
		let neweInst 	= validValue(e2m.first.eInst);

		case(neweInst.eType)
			EMrMov, EPop, ERet : 
			begin
				let tmp <- (dMem.req(MemReq{op: Ld, addr: neweInst.addr, data:?}));
				let ldData = convertEndian(tmp);
									
				case(neweInst.eType) 
					EMrMov, EPop : neweInst.data1 = tagged Valid ldData;
					ERet 	 	 : memRedir.enq(ldData);
									//eInst.addr = ldData <- not necessary
			  	endcase
			end

			ERmMov, ECall, EPush :
			begin
				let targAddr = case(neweInst.eType)
						   		 ECall : validValue(neweInst.data1);
								 EPush, ERmMov : neweInst.addr;
							   endcase;

				let targData = case(neweInst.eType)
								 ECall  : convertEndian(ppc);
								 EPush  : convertEndian(validValue(neweInst.data2));
								 ERmMov : convertEndian(validValue(neweInst.data1));
							   endcase;

			  	let d <- dMem.req(MemReq{op: St, addr: targAddr, data: targData});
			end
		endcase
		m2w.enq(Mem2WB{eInst:tagged Valid neweInst, pc:ipc});
	end
	else
		m2w.enq(Mem2WB{eInst:Invalid, pc:ipc});

endrule


rule doWriteBack(stat == AOK);

	m2w.deq;
	sb.remove1;	

	if(isValid(m2w.first.eInst))
	begin
		let eInst = validValue(m2w.first.eInst);
		let ipc   = m2w.first.pc;

		$display("WB: Register write opearation of instruction at pc %d\n",ipc);
	

		if(eInst.eType == EPop)
		begin
			rf.wr2(validRegValue(eInst.dst), validValue(eInst.data1), validValue(eInst.data2));
			sb.remove2;
		end
		else if(isValid(eInst.dst) && fromMaybe(?,eInst.dst).regType == Normal && eInst.cmpRes)
		begin
			rf.wr(validRegValue(eInst.dst), validValue(eInst.data1));	
			$display("write on %d, value %d",validRegValue(eInst.dst), validValue(eInst.data1));
		end
		cop.wr(eInst.dst, validValue(eInst.data1));	
	end
endrule

  method ActionValue#(Tuple3#(RIndx, Data, Data)) cpuToHost;
    let retV <- cop.cpuToHost;
    return retV;
  endmethod

  method Action hostToCpu(Bit#(64) startpc) if (!cop.started);
    cop.start;
    pc <= startpc;
  endmethod

endmodule
