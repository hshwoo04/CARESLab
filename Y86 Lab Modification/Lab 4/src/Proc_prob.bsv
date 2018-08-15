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

/* Two staged processor
   ====================

   This version of Y86_64 processor has only two stages: fetch and execute-memory-writeback
   Also, this processor does not support pipelined execution of instructions.

   * implementation details
     pc       : program counter
     rf       : registers (15 normal registers in Y86_64)
     iMem     : memory containing all the instructions
     dMem     : memory containing all the data
     cop      : coprocessor of Y86_64 processor
     condFlag : condition codes (ZF, SF, OF)
     stat     : processor status (AOK, ADR, INS, HLT)
     stage    : current stage (non-pipelined, FSM implementation)
     f2e      : register passing fetched instruction to further stages
     statRedirect ; handles status
*/

/* TODO: modify here to add/remove stages */
typedef enum {Fetch, Execute} Stage deriving(Bits, Eq);

(*synthesize*)
module mkProc(Proc);
  Reg#(Addr)         pc         <- mkRegU;
  RFile              rf         <- mkRFile;
  IMemory            iMem       <- mkIMemory;
  DMemory            dMem       <- mkDMemory;
  Cop                cop        <- mkCop;

  Fifo#(1,ProcStatus) statRedirect <- mkBypassFifo;

  Reg#(CondFlag)     condFlag   <- mkRegU;
  Reg#(ProcStatus)   stat       <- mkRegU;
  Reg#(Stage)        stage      <- mkRegU;

  Reg#(Inst)         f2e        <- mkRegU;

  rule doFetch(cop.started && stat == AOK && stage == Fetch);
    let inst = iMem.req(pc);

    $display("Fetch : from Pc %d , expanded inst : %x, \n", pc, inst, showInst(inst));
    stage <= Execute;
    f2e <= inst;
  endrule

  rule doRest(cop.started && stat == AOK && stage == Execute);
    let inst   = f2e;

    //Decode
    let dInst = decode(inst, pc);

    $display("Decode : from Pc %d , expanded inst : %x, \n", pc, inst, showInst(inst));

    dInst.valA   = isValid(dInst.regA)? tagged Valid rf.rdA(validRegValue(dInst.regA)) : Invalid;
    dInst.valB   = isValid(dInst.regB)? tagged Valid rf.rdB(validRegValue(dInst.regB)) : Invalid;
    dInst.copVal = isValid(dInst.regA)? tagged Valid cop.rd(validRegValue(dInst.regA)) : Invalid;

    //Exec
    let eInst = exec(dInst, condFlag, pc);
    condFlag <= eInst.condFlag;

    $display("Exec : ppc %d", dInst.valP);

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
    let newStatus =
      case(iType)
        Unsupported : INS;
        Hlt         : HLT;
        default     : AOK;
      endcase;

    statRedirect.enq(newStatus);

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

    pc <= validValue(eInst.nextPc);
    stage <= Fetch;
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
    stage <= Fetch;
    pc <= startpc;
    stat <= AOK;
  endmethod
endmodule
