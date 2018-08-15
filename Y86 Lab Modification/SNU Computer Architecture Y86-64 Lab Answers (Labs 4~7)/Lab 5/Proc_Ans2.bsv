import Types::*;
import ProcTypes::*;
import MemTypes::*;
import RFile::*;
import IMemory::*;
import DMemory::*;
import Decode::*;
import Exec::*;
import Cop::*;
import Fifo::*;

typedef struct {
	Inst inst;
	Addr pc;
	Addr ppc;
	Bool epoch;
} Fetch2Decode deriving(Bits, Eq);

typedef struct {
	DecodedInst dInst;
	Addr ppc;
	Bool epoch;
} Decode2Exec deriving(Bits, Eq);


(*synthesize*)
module mkProc(Proc);
  Reg#(Addr)    pc  <- mkRegU;
  RFile         rf  <- mkRFile;
  IMemory     iMem  <- mkIMemory;
  DMemory     dMem  <- mkDMemory;
  Cop          cop  <- mkCop;

  Reg#(CondFlag) 	 condFlag	<- mkRegU;
  Reg#(ProcStatus)   stat		<- mkRegU;

  Fifo#(1,Addr)       execRedirect <- mkCFFifo;
  Fifo#(1,ProcStatus) statRedirect <- mkBypassFifo;

  Fifo#(2,Fetch2Decode)		f2d    	   <- mkCFFifo;
  Fifo#(2,Decode2Exec)		d2e		   <- mkCFFifo;

  Reg#(Bool) fEpoch <- mkRegU;
  Reg#(Bool) eEpoch <- mkRegU;

  rule doFetch(cop.started && stat == AOK);
      let realPc = execRedirect.notEmpty? execRedirect.first:pc;
	  let inst = iMem.req(realPc);
	  let ppc = nextAddr(realPc, getICode(inst));

	  let realfEpoch = execRedirect.notEmpty? !fEpoch : fEpoch;

	  $display("Fetch : from Pc %d , expanded inst : %x, \n", realPc, inst, showInst(inst)); 

	  if(execRedirect.notEmpty)
	  begin
		  execRedirect.deq;
	  end		  
	  
	  fEpoch <= realfEpoch;
	  pc <= ppc;
	  f2d.enq(Fetch2Decode{inst:inst, pc:realPc, ppc:ppc,  epoch:realfEpoch});
  endrule

  rule doDecode(cop.started && stat == AOK);
	  let inst   = f2d.first.inst;
	  let ipc 	 = f2d.first.pc;
	  let ppc    = f2d.first.ppc;
	  let iEpoch = f2d.first.epoch;
	  f2d.deq;

	  let dInst = decode(inst, ipc);

	  $display("Decode : from Pc %d , expanded inst : %x, \n", ipc, inst, showInst(inst)); 
	  d2e.enq(Decode2Exec{dInst: dInst, ppc: ppc, epoch: iEpoch});
  endrule

  rule doRest(cop.started && stat == AOK);
	  let dInst  = d2e.first.dInst;
	  let ppc    = d2e.first.ppc;
	  let iEpoch = d2e.first.epoch;
	  d2e.deq;


	  $display("Exec : ppc %d", ppc); 
	  if(iEpoch == eEpoch)
	  begin
		  //Decode 

	  	  dInst.valA   = isValid(dInst.regA)? tagged Valid rf.rdA(validRegValue(dInst.regA)) : Invalid;
   	  	  dInst.valB   = isValid(dInst.regB)? tagged Valid rf.rdB(validRegValue(dInst.regB)) : Invalid;
	  	  dInst.copVal = isValid(dInst.regA)? tagged Valid cop.rd(validRegValue(dInst.regA)) : Invalid;

		  //Exec
		  let eInst = exec(dInst, condFlag, ppc);
		  condFlag <= eInst.condFlag;

		  //Memory 
	      let iType = eInst.iType;
	      case(iType)
	 		MRmov, Pop, Ret :
   	 		begin
	   			let ldData <- (dMem.req(MemReq{op: Ld, addr: eInst.memAddr, data:?}));
		   		eInst.valM = Valid(little2BigEndian(ldData));
				$display("Loaded %d from %d",little2BigEndian(ldData), eInst.memAddr);
				if(iType == Ret)
				begin
					eInst.nextPc = eInst.valM;
				end
	   		end

			RMmov, Call, Push :
			begin
				let stData = (iType == Call)? eInst.valP : validValue(eInst.valA); 
		  		let dummy <- dMem.req(MemReq{op: St, addr: eInst.memAddr, data: big2LittleEndian(stData)});
				$display("Stored %d into %d",stData, eInst.memAddr);
			end
	  	  endcase

		  //Update Status
		  let newStatus = case(iType)
		  				      Unsupported : INS;
							  Hlt 		  : HLT;
							  default     : AOK;
						  endcase;

		  statRedirect.enq(newStatus);

		  if(eInst.mispredict)			
		  begin
		  	  eEpoch <= !eEpoch;
			  let redirPc = validValue(eInst.nextPc);
		   	  cop.incBPMissCnt();
			  $display("mispredicted, redirect %d ", redirPc);
			  execRedirect.enq(redirPc);
	 	  end


		  //WriteBack
		if(isValid(eInst.dstE))
		begin
			$display("On %d, writes %d   (wrE)",validRegValue(eInst.dstE), validValue(eInst.valE));
			rf.wrE(validRegValue(eInst.dstE), validValue(eInst.valE));
		end
		if(isValid(eInst.dstM))
		begin
			$display("On %d, writes %d   (wrM)",validRegValue(eInst.dstM), validValue(eInst.valM));
			rf.wrM(validRegValue(eInst.dstM), validValue(eInst.valM));
		end
		cop.wr(eInst.dstE, validValue(eInst.valE));
		
		case(eInst.iType)
			Call,Ret,Jmp 		     : cop.incInstTypeCnt(Ctr); // Control instructions
		    MRmov, RMmov, Push, Pop  : cop.incInstTypeCnt(Mem); // Mov instructions
		endcase	

	end
  endrule

  rule upd_Stat(cop.started);
	$display("Stat update");
  	statRedirect.deq;
    stat <= statRedirect.first;
  endrule

  rule statHLT(cop.started && stat == HLT);
	$fwrite(stderr,"Program Finished by halt\n");
    $finish;
  endrule 

  rule statINS(cop.started && stat == INS);
	$fwrite(stderr,"Executed unsupported instruction. Exiting\n");
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
