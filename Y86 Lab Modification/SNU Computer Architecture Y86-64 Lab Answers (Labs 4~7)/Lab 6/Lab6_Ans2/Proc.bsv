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
import Fifo::*;


typedef struct {
	Inst inst;
	Addr pc;
	Addr ppc;
	Bool epoch;
} Fetch2Decode deriving(Bits,Eq);

typedef struct {
	DecodedInst dInst;
	Addr ppc;
	Bool epoch;
} Decode2Execute deriving (Bits,Eq);

typedef Maybe#(ExecInst) Exec2Memory;
typedef Maybe#(ExecInst) Memory2WriteBack;

typedef Tuple2#(Maybe#(FullIndx), Maybe#(Data)) RedirData;

(*synthesize*)
module mkProc(Proc);
	//Basic elemnets
	Reg#(Addr)			pc 			<- mkRegU;
	RFile				rf  		<- mkBypassRFile;
	IMemory				iMem  		<- mkIMemory;
	DMemory				dMem  		<- mkDMemory;
	Reg#(CondFlag)		condFlag	<- mkRegU;
	Reg#(ProcStatus)	stat		<- mkRegU;
	Cop					cop 	 	<- mkCop;

	//Control hazard handling Elements
	Reg#(Bool) 		fEpoch 		<- mkRegU;
	Reg#(Bool) 		eEpoch 		<- mkRegU;
	Fifo#(1, ProcStatus) statRedirect <- mkBypassFifo;
	Fifo#(1, Bool) stallFifo <- mkPipelineFifo;

	Fifo#(1, Addr)	exeRedirect	<- mkBypassFifo;
	Fifo#(1, Addr)  memRedirect <- mkBypassFifo;
	Fifo#(1, RedirData) exe2DecRedirect <- mkBypassFifo;
	Fifo#(1, RedirData) mem2DecRedirectE <- mkBypassFifo;
	Fifo#(1, RedirData) mem2DecRedirectM <- mkBypassFifo;
	Fifo#(1, RedirData) mem2ExecRedirectE <- mkBypassFifo;
	Fifo#(1, RedirData) mem2ExecRedirectM <- mkBypassFifo;

	Fifo#(1, Fetch2Decode)   f2d  <- mkPipelineFifo;
	Fifo#(1, Decode2Execute) d2e  <- mkPipelineFifo;
	Fifo#(1, Exec2Memory)    e2m  <- mkPipelineFifo;
	Fifo#(1, Memory2WriteBack) m2w <- mkPipelineFifo;

	rule doFetch(cop.started && stat == AOK);
		let realPc = ?;
		let realfEpoch = ?;

		let memR = memRedirect.notEmpty;
		let exeR = exeRedirect.notEmpty;

		if(memR) // (memR && exeR) || memR
		begin
			memRedirect.deq;
			if(exeR)
				exeRedirect.deq;
			fEpoch <= !fEpoch;
			realPc = memRedirect.first;
			realfEpoch = !fEpoch;
		end
		else if(exeR)
		begin
			exeRedirect.deq;
			fEpoch <= !fEpoch;
			realPc = exeRedirect.first;
			realfEpoch = !fEpoch;
		end
		else
		begin
			realPc = pc;
			realfEpoch = fEpoch;
		end

		let inst = iMem.req(realPc);
		let ppc = nextAddr(realPc, getICode(inst));
		pc <= ppc;	
		$display("Fetch : from Pc %d , expanded inst : %x, \n", realPc, inst, showInst(inst)); 
		f2d.enq(Fetch2Decode{inst: inst, pc: realPc, ppc: ppc, epoch:realfEpoch});

	endrule

	rule doDecode(cop.started && stat == AOK);
		let inst  = f2d.first.inst;
		let ipc   = f2d.first.pc;
		let ppc   = f2d.first.ppc;
		let epoch = f2d.first.epoch;
		
		f2d.deq;

		let dInst = decode(inst, ipc);

		$display("Decode");

		//Temporal variables for redirected data
		let redirA = Invalid;
		let redirB = Invalid;

		//Current register values
		let rdA = isValid(dInst.regA)? Valid(rf.rdA(validRegValue(dInst.regA))) : Invalid;
		let rdB = isValid(dInst.regB)? Valid(rf.rdA(validRegValue(dInst.regB))) : Invalid;
		

		let exeRIndx = exe2DecRedirect.notEmpty? tpl_1(exe2DecRedirect.first) : Invalid;
		let exeRedir = exe2DecRedirect.notEmpty? tpl_2(exe2DecRedirect.first) : Invalid;

		let memRIndxE = mem2DecRedirectE.notEmpty? tpl_1(mem2DecRedirectE.first) : Invalid;
		let memRedirE = mem2DecRedirectE.notEmpty? tpl_2(mem2DecRedirectE.first) : Invalid;

		let memRIndxM = mem2DecRedirectM.notEmpty? tpl_1(mem2DecRedirectM.first) : Invalid;
		let memRedirM = mem2DecRedirectM.notEmpty? tpl_2(mem2DecRedirectM.first) : Invalid;

		if(exe2DecRedirect.notEmpty)
			exe2DecRedirect.deq;

		if(mem2DecRedirectE.notEmpty)
			mem2DecRedirectE.deq;

		if(mem2DecRedirectM.notEmpty)
			mem2DecRedirectM.deq;

		//(Exec -> Decode) proceeds (Mem -> Decode)
		if(isValid(dInst.regA) && isValid(exeRIndx) && (validRegValue(dInst.regA) == validRegValue(exeRIndx)))
		begin
			$display("exeRedirect, to regA. value : %d", validValue(exeRedir));
			redirA = exeRedir;
		end
		else
		begin
			//(Mem -> Decode, valE -> regA) and (Mem -> Decode, valM -> regA) never happens simultaneously
			if(isValid(dInst.regA) && isValid(memRIndxE) && (validRegValue(dInst.regA) == validRegValue(memRIndxE)))
			begin
				$display("memRedirectE, to regA. value : %d", validValue(memRedirE));
				redirA = memRedirE;
			end

			if(isValid(dInst.regA) && isValid(memRIndxM) && (validRegValue(dInst.regA) == validRegValue(memRIndxM)))
			begin
				$display("memRedirectM, to regA. value : %d", validValue(memRedirM));
				redirA = memRedirM;
			end
		end

		//Same structure as regA
		if(isValid(dInst.regB) && isValid(exeRIndx) && (validRegValue(dInst.regB) == validRegValue(exeRIndx)))
		begin
			$display("exeRedirect, to regB. value : %d", validValue(exeRedir));
			redirB = exeRedir;
		end
		else
		begin
			if(isValid(dInst.regB) && isValid(memRIndxE) && (validRegValue(dInst.regB) == validRegValue(memRIndxE)))
			begin
				$display("memRedirectE, to regB. value : %d", validValue(memRedirE));
				redirB = memRedirE;
			end

			if(isValid(dInst.regB) && isValid(memRIndxM) && (validRegValue(dInst.regB) == validRegValue(memRIndxM)))
			begin
				$display("memRedirectM, to regB. value : %d", validValue(memRedirM));
				redirB = memRedirM;
			end
		end

		//If there exists redirected data, it has the higer priority
		dInst.valA = isValid(redirA)? redirA : rdA;
		dInst.valB = isValid(redirB)? redirB : rdB;
		dInst.copVal = isValid(dInst.regA)? Valid(cop.rd(validRegValue(dInst.regA))) : Invalid;

		if(isValid(dInst.valA))
			$display("dInst.valA : %d on reg %d",validValue(dInst.valA), validRegValue(dInst.regA));

		if(isValid(dInst.valB))
			$display("dInst.valB : %d on reg %d",validValue(dInst.valB), validRegValue(dInst.regB));
		
		d2e.enq(Decode2Execute{dInst: dInst, ppc: ppc, epoch: epoch});

  endrule

  rule doExecute(cop.started && stat == AOK);
		let x		= d2e.first;
		let dInst	= x.dInst;	
		let ppc		= x.ppc;
		let inEp	= x.epoch;
		d2e.deq;
		$display("Exec");

		let redirA = Invalid;
		let redirB = Invalid;

		//mem2Exec-redirect E&M always come together.
		if(mem2ExecRedirectE.notEmpty)
		begin
			mem2ExecRedirectE.deq;
			mem2ExecRedirectM.deq;

			let redE = mem2ExecRedirectE.first;
			let redM = mem2ExecRedirectM.first;

			let redIndxE = tpl_1(redE);
			let redIndxM = tpl_1(redM);

			//Case 1 : both redirected indexes E & M are valid
			if(isValid(dInst.regA) && isValid(redIndxE) && isValid(redIndxM))
			begin
				//redIndxE proceeds the redIndxM
				redirA = ((validRegValue(dInst.regA) == validRegValue(redIndxE))? tpl_2(redE) : 
								((validRegValue(dInst.regA) == validRegValue(redIndxM))? tpl_2(redM) : Invalid));
			end
			//Case 2 : only redirected indexE is valid
			else if(isValid(dInst.regA) && isValid(redIndxE))
			begin
				redirA = ((validRegValue(dInst.regA) == validRegValue(redIndxE))? tpl_2(redE) : Invalid);
			end
			//Case 3 : only redirected indexM is valid
			else if(isValid(dInst.regA) && isValid(redIndxM))
			begin
				redirA = ((validRegValue(dInst.regA) == validRegValue(redIndxM))? tpl_2(redM) : Invalid);
			end

			//Same structure as regA
			if(isValid(dInst.regB) && isValid(redIndxE) && isValid(redIndxM))
			begin
				redirB = ((validRegValue(dInst.regB) == validRegValue(redIndxE))? tpl_2(redE) : 
								((validRegValue(dInst.regB) == validRegValue(redIndxM))? tpl_2(redM) : Invalid));
			end
			else if(isValid(dInst.regB) && isValid(redIndxE))
			begin
				redirB = ((validRegValue(dInst.regB) == validRegValue(redIndxE))? tpl_2(redE) : Invalid);
			end
			else if(isValid(dInst.regB) && isValid(redIndxM))
			begin
				redirB = ((validRegValue(dInst.regB) == validRegValue(redIndxM))? tpl_2(redM) : Invalid);
			end

		end

		let newvalA = isValid(redirA)? redirA : dInst.valA;
		let newvalB = isValid(redirB)? redirB : dInst.valB;

		dInst.valA = newvalA;
		dInst.valB = newvalB;

		if(inEp == eEpoch)
		begin
			let eInst = exec(dInst, condFlag, ppc);
			condFlag <= eInst.condFlag;

			if(eInst.mispredict)
			begin
				eEpoch <= !eEpoch;
				if(eInst.iType != Ret)
				begin
					exeRedirect.enq(validValue(eInst.nextPc));
				end
			end

			case(eInst.iType)
				Cmov : begin
						if(eInst.condSatisfied)
							exe2DecRedirect.enq(tuple2(eInst.dstE, eInst.valE));
					  	end
				default : exe2DecRedirect.enq(tuple2(eInst.dstE, eInst.valE));
			endcase

			if(isValid(eInst.dstE))
				$display("Exec redirects %d on reg %d, to decode stage",validValue(eInst.valE), validRegValue(eInst.dstE));


			e2m.enq(Valid(eInst));
		end
		else
		begin
			e2m.enq(Invalid);
		end 
	endrule

	rule doMemory(cop.started && stat == AOK);
			e2m.deq;
			$display("Memory");

			if(isValid(e2m.first))
			begin
				let eInst = validValue(e2m.first);

				let iType = eInst.iType;
				case(iType)
					MRmov, Pop, Ret: begin
						let ldData	<- (dMem.req(MemReq{op: Ld, addr: eInst.memAddr, data: ?}));
						eInst.valM = Valid(little2BigEndian(ldData));
						
						if(iType == Ret)
						begin
							memRedirect.enq(validValue(eInst.valM));
						end
					end
					RMmov, Call, Push: begin
						let stData = (iType == Call) ? eInst.valP : validValue(eInst.valA);
						let dummy <- dMem.req(MemReq{op: St, addr: eInst.memAddr, data: big2LittleEndian(stData)});
					end
				endcase


				if(isValid(eInst.dstE))
					$display("Memory sends %d to for %d",validValue(eInst.valE), validRegValue(eInst.dstE));

				if(isValid(eInst.dstM))
					$display("Memory sends %d to for %d",validValue(eInst.valM), validRegValue(eInst.dstM));

				mem2DecRedirectE.enq(tuple2(eInst.dstE, eInst.valE));
				mem2DecRedirectM.enq(tuple2(eInst.dstM, eInst.valM));
	
				mem2ExecRedirectE.enq(tuple2(eInst.dstE, eInst.valE));
				mem2ExecRedirectM.enq(tuple2(eInst.dstM, eInst.valM));

				let newStatus =	case(iType)
									Unsupported	: INS;
									Hlt			: HLT;
									default		: AOK;
								endcase;
				statRedirect.enq(newStatus);

				m2w.enq(Valid(eInst));
			end
			else
			begin
				m2w.enq(Invalid);
			end

	endrule

	rule doWriteBack(cop.started && stat == AOK);
		m2w.deq;
		$display("WriteBack");

		if(isValid(m2w.first))
		begin
			let eInst = validValue(m2w.first);

			if(isValid(eInst.dstE))
			begin
				rf.wrE(validRegValue(eInst.dstE), validValue(eInst.valE));
			end

			if(isValid(eInst.dstM))
			begin
				rf.wrM(validRegValue(eInst.dstM), validValue(eInst.valM));
			end

			cop.wr(eInst.dstE, validValue(eInst.valE));
		end

	endrule

	rule upd_Stat(cop.started);
		statRedirect.deq;
		stat <= statRedirect.first;
	endrule


	rule fin(cop.started && stat == HLT);
		$fwrite(stderr,"Program Finished by halt \n" );
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

	method Action hostToCpu(Bit#(64) startpc) if (!cop.started);
		cop.start;
		eEpoch <= False;
		fEpoch <= False;
		pc <= startpc;
		stat <= AOK;
	endmethod
endmodule
