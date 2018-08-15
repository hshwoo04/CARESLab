import Types::*;
import ProcTypes::*;
import Vector::*;

/* Instruction Decoding
   ====================

   * Maximum length: 10 bytes for Y86_64
   * Composition
      c: instruction Code*
      f: instruction Function code*
      a: register A*
      b: register B*
      m: Immediate value (little endian)
      d: Destination address* (little endian)
      -: end of instruction code (null)

      A*,B*,C*,D*,E,F* (capitalized words are HEX values)

      -------------------------------------------
      |  inst.  | HH HH HH HH HH HH HH HH HH HH |
      |  byte   | 01 02 03 04 05 06 07 08 09 10 |
      ------------------------------------------|
      |  common | cf XX XX XX XX XX XX XX XX XX |
      |---------|-------------------------------|
      |  halt   | 00 -- -- -- -- -- -- -- -- -- |
      |  nop    | 10 -- -- -- -- -- -- -- -- -- |
      |  rrmovq | 20 ab -- -- -- -- -- -- -- -- |
      |  irmovq | 30 Fb ii ii ii ii ii ii ii ii |
      |  rmmovq | 40 ab dd dd dd dd dd dd dd dd |
      |  mrmovq | 50 ab dd dd dd dd dd dd dd dd |
      |  opq    | 6f ab -- -- -- -- -- -- -- -- |
      |  jmp    | 7f dd dd dd dd dd dd dd dd -- |
      |  cmov   | 2f ab -- -- -- -- -- -- -- -- |
      |  call   | 80 dd dd dd dd dd dd dd dd -- |
      |  ret    | 90 -- -- -- -- -- -- -- -- -- |
      |  pushq  | A0 aF -- -- -- -- -- -- -- -- |
      |  popq   | B0 aF -- -- -- -- -- -- -- -- |
      -------------------------------------------

*/

function DecodedInst decode(Inst inst, Addr pc);
  DecodedInst dInst = ?;
  let iCode = inst[79:76];
  let ifun  = inst[75:72];
  let rA    = inst[71:68];
  let rB    = inst[67:64];
  let imm   = little2BigEndian(inst[63:0]);
  let dest  = little2BigEndian(inst[71:8]);

  case (iCode)
  // rrmovq is included in cmov
  halt, nop :
  begin
    dInst.iType =
      case(iCode)
        halt : Hlt;
        nop  : Nop;
      endcase;
    dInst.opqFunc = FNop;
    dInst.condUsed = Al;
    dInst.valP = pc + 1;
    dInst.dstE = Invalid;
    dInst.dstM = Invalid;
    dInst.regA = Invalid;
    dInst.regB = Invalid;
    dInst.valC = Invalid;
  end

  // rrmoval included in cmov
  irmovq :
  begin
    dInst.iType    = Rmov;
    dInst.opqFunc  = FNop;
    dInst.condUsed = Al;
    dInst.valP     = pc + 10;
    dInst.dstE     = validReg(rB);
    dInst.dstM     = Invalid;
    dInst.regA     = validReg(rA);
    dInst.regB     = validReg(rB);
    dInst.valC     = Valid(imm);
  end

  rmmovq :
  begin
    dInst.iType    = RMmov;
    dInst.opqFunc  = FAdd;
    dInst.condUsed = Al;
    dInst.valP     = pc + 10;
    dInst.dstE     = Invalid;
    dInst.dstM     = Invalid;
    dInst.regA     = validReg(rA);
    dInst.regB     = validReg(rB);
    dInst.valC     = Valid(imm);
  end

  mrmovq :
  begin
    dInst.iType    = MRmov;
    dInst.opqFunc  = FAdd;
    dInst.condUsed = Al;
    dInst.valP     = pc + 10;
    dInst.dstE     = Invalid;
    dInst.dstM     = validReg(rA);
    dInst.regA     = Invalid;
    dInst.regB     = validReg(rB);
    dInst.valC     = Valid(imm);
  end

  cmov : // includes rrmovq(cmov under no condition)
  begin
    dInst.iType    = Cmov;
    dInst.opqFunc  = FNop;
    dInst.condUsed =
      case(ifun)
        fNcnd : Al;
        fLe   : Le;
        fLt   : Lt;
        fEq   : Eq;
        fNeq  : Neq;
        fGe   : Ge;
        fGt   : Gt;
      endcase;
    dInst.valP = pc + 2;
    dInst.dstE = validReg(rB);
    dInst.dstM = Invalid;
    dInst.regA = validReg(rA);
    dInst.regB = Invalid;
    dInst.valC = Invalid;
  end

  opq :
  begin
    dInst.iType = Opq;
    dInst.opqFunc =
      case(ifun)
        addc : FAdd;
        subc : FSub;
        andc : FAnd;
        xorc : FXor;
      endcase;
    dInst.condUsed = Al;
    dInst.valP = pc + 2;
    dInst.dstE = validReg(rB);
    dInst.dstM = Invalid;
    dInst.regA = validReg(rA);
    dInst.regB = validReg(rB);
    dInst.valC = Invalid;
  end

  jmp :
  begin
    dInst.iType    = Jmp;
    dInst.opqFunc  = FNop;
    dInst.condUsed =
      case(ifun)
        fNcnd : Al;
        fLe   : Le;
        fLt   : Lt;
        fEq   : Eq;
        fNeq  : Neq;
        fGe   : Ge;
        fGt   : Gt;
      endcase;
    dInst.valP = pc + 9;
    dInst.dstE = Invalid;
    dInst.dstM = Invalid;
    dInst.regA = Invalid;
    dInst.regB = Invalid;
    dInst.valC = Valid(dest);
  end

  push :
  begin
    dInst.iType = Push;
    dInst.opqFunc = FSub;
    dInst.condUsed = Al;
    dInst.valP = pc + 2;
    dInst.dstE = validReg(rsp);
    dInst.dstM = Invalid;
    dInst.regA = validReg(rA);
    dInst.regB = validReg(rsp);
    dInst.valC = Invalid;
  end

  pop :
  begin
    dInst.iType = (rA == rsp)? Unsupported:Pop;
    dInst.opqFunc = FAdd;
    dInst.condUsed = Al;
    dInst.valP = pc + 2;
    dInst.dstE = validReg(rsp);
    dInst.dstM = validReg(rA);
    dInst.regA = validReg(rsp);
    dInst.regB = validReg(rsp);
    dInst.valC = Invalid;
  end

  call, ret :
  begin
    case(iCode)
      call:
      begin
        dInst.iType   = Call;
        dInst.opqFunc = FSub;
        dInst.valP    = pc + 9;
        dInst.valC    = Valid(dest);
        dInst.regA    = Invalid;
      end
      ret:
      begin
        dInst.iType   = Ret;
        dInst.opqFunc = FAdd;
        dInst.valP    = pc + 1;
        dInst.valC    = Invalid;
        dInst.regA    = validReg(rsp);
      end
    endcase

    dInst.condUsed = Al;
    dInst.dstE     = validReg(rsp);
    dInst.dstM     = Invalid;
    dInst.regB     = validReg(rsp);
  end

  copinst:
  begin
    dInst.iType =
      case(ifun)
        mtc0 : Mtc0; //Mtc0
        mfc0 : Mfc0; //Mfc0
      endcase;
    dInst.opqFunc = FNop;
    dInst.condUsed = Al;
    dInst.valP = pc + 2;
    dInst.dstE =
      case(ifun)
        mtc0 : validCop(rB);
        mfc0 : validReg(rB);
      endcase;
    dInst.dstM = Invalid;
    dInst.regA =
      case(ifun)
        mtc0 : validReg(rA);
        mfc0 : validCop(rA);
      endcase;
      dInst.regB = Invalid;
      dInst.valC = Invalid;
    end

  default:
  begin
    dInst.iType    = Unsupported;
    dInst.opqFunc  = FNop;
    dInst.condUsed = Al;
    dInst.valP     = pc + 1;
    dInst.dstE     = Invalid;
    dInst.dstM     = Invalid;
    dInst.regA     = Invalid;
    dInst.regB     = Invalid;
    dInst.valC     = Invalid;
  end
  endcase

  return dInst;
endfunction
