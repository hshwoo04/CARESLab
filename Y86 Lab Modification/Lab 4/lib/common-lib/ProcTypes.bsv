import Types::*;
import FShow::*;
import MemTypes::*;

/* Y86-64 Instruction Set Architecture
   ===================================

   1. Programmer-visible states
     1.1 Registers (15 Normal Registers)

       * each with 64 bit width
       -----------------------------------
       | asm. | reg. no. |   function    |
       |------|----------|----------------
       | %rax |   0000   |    generic    |
       | %rcx |   0001   |    generic    |
       | %rdx |   0010   |    generic    |
       | %rbx |   0011   |    generic    |
       | %rsp |   0100   | stack pointer |
       | %rbp |   0101   |    generic    |
       | %rsi |   0110   |    generic    |
       | %rdi |   0111   |    generic    |
       | %r8  |   1000   |    generic    |
       | %r9  |   1001   |    generic    |
       | %r10 |   1010   |    generic    |
       | %r11 |   1011   |    generic    |
       | %r12 |   1100   |    generic    |
       | %r13 |   1101   |    generic    |
       | %r14 |   1110   |    generic    |
       -----------------------------------

     1.2 Condition codes

       -----------------------------------
       |  ZF  | Zero Flag                |
       |  SF  | Sign Flag                |
       |  OF  | Overflow Flag            |
       -----------------------------------

     1.3 Status codes

       ------------------------------------------------
       | AOK | No problem encountered                 |
       | ADR | An addressing error has occurred       |
       | INS | An illegal instruction was encountered |
       | HLT | A halt instruction was encountered     |
       ------------------------------------------------

   2. Instruction Set

     * Maximum length: 10 bytes for Y86_64
     * Composition
       ------------------------------------
       |     Category      |  size (bits) |
       ------------------------------------
       | Instruction Code  |       4      |
       | Function code     |       4      |
       | Register no.      |       4      |
       | Immediate         |      64      |
       | Destination addr. |      64      |
       ------------------------------------

   3. Processor-related types and interfaces
*/

/* ***************************************************************************
   1. Programmer-visible states
   ***************************************************************************

   1.1 Register-related definitions
   --------------------------------

   RIndx    : generic register index
   RegType  : register type (Cop/Normal)
   FullIndx : register type + index

   functions
   validReg : get full index of normal register
   validCop : get full index of register
   validRegValue : get valid value of register

   register-related constants
   rax, rcx, rdx, rbx, rsp, rbp, rsi, rdi, r8, r9, r10, r11, r12, r13, r14
*/
typedef Bit#(4) RIndx;
typedef enum {Normal, CopReg} RegType deriving (Bits, Eq);
typedef struct {
  RegType regType;
  RIndx idx;
} FullIndx deriving (Bits, Eq);

function Maybe#(FullIndx) validReg(RIndx idx) = Valid(FullIndx{regType: Normal, idx: idx});
function Maybe#(FullIndx) validCop(RIndx idx) = Valid(FullIndx{regType: CopReg, idx: idx});
function RIndx validRegValue(Maybe#(FullIndx) idx) = validValue(idx).idx;

RIndx rax =  0;
RIndx rcx =  1;
RIndx rdx =  2;
RIndx rbx =  3;
RIndx rsp =  4;
RIndx rbp =  5;
RIndx rsi =  6;
RIndx rdi =  7;
RIndx  r8 =  8;
RIndx  r9 =  9;
RIndx r10 = 10;
RIndx r11 = 11;
RIndx r12 = 12;
RIndx r13 = 13;
RIndx r14 = 14;

/* 1.2 Condition Code-related definitions
   --------------------------------------

   CondFlag : condition flags (ZF, SF, OF)
*/
typedef struct {Bool zf; Bool sf; Bool of;} CondFlag deriving(Bits, Eq);

/* 1.3 Status code-related definitions
   -----------------------------------

   ProcStatus : status codes (AOK, ADR, INS, HLT)
*/
typedef enum {AOK, ADR, INS, HLT} ProcStatus deriving(Bits,Eq);

/* ***************************************************************************
   2. Instruction Set (Y86_64)
   ***************************************************************************

   --------------------------------------------
   |     Category      |   type  | size (bits) |
   --------------------------------------------
   | Instruction Code  |  ICode  |      4      |
   | Function code     |  FCode  |      4      |
   | Register no.      |  RIndx  |      4      |
   | Immediate         |  Data   |     64      |
   | Destination addr. |  Addr   |     64      |
   --------------------------------------------
*/
typedef Bit#(8) OpCode;
typedef Bit#(4) ICode;
typedef Bit#(4) FCode;

/* IType (instruction code types)
   ------------------------------

     --------------------------------------------------------|
     |       Category       | Operations | ICode |   FCode   |
     ---------------------------------------------------------
     | Miscellaneous        | Halt       |   0   |     X     |
     |                      | Nop        |   1   |     X     |
     ---------------------------------------------------------
     | Move                 | CMov       |   2   |  CondUsed |
     |                      | IRMov      |   3   |   Nop(0)  |
     |                      | RMMov      |   4   |   Nop(0)  |
     |                      | MRMov      |   5   |   Nop(0)  |
     ---------------------------------------------------------
     | Logical/Arithmetic   | Opq        |   6   |  OpqFunc  |
     ---------------------------------------------------------
     | Conditional Jump     | Jmp        |   7   |  CondUsed |
     ---------------------------------------------------------
     | Function call & ret  | Call       |   8   |   Nop(0)  |
     |                      | Ret        |   9   |   Nop(0)  |
     ---------------------------------------------------------
     | Stack                | Push       |   A   |   Nop(0)  |
     |                      | Pop        |   B   |   Nop(0)  |
     ---------------------------------------------------------
     | Coprocessor Ops.     | Mtc0/Mfc0  |   C   |  CopFunc  |
     ---------------------------------------------------------

*/
typedef enum {Unsupported, Rmov, Opq, RMmov, MRmov, Cmov, Jmp, Push, Pop, Call, Ret, Hlt, Nop, Mtc0, Mfc0 } IType deriving(Bits,Eq);
ICode halt     =  0;
ICode nop      =  1;
ICode cmov     =  2;
ICode irmovq   =  3;
ICode rmmovq   =  4;
ICode mrmovq   =  5;
ICode opq      =  6;
ICode jmp      =  7;
ICode call     =  8;
ICode ret      =  9;
ICode push     = 10;
ICode pop      = 11;
ICode copinst  = 12;

/* FType (function code types)
   ------------------------------

   * Condition codes (CondUsed)
     -------------------------------------------|
     |  Code  | Desc.                 | op. no. |
     --------------------------------------------
     |  Ncnd  | Always (No condition) |    0    |
     |  Le    | Less than OR equal    |    1    |
     |  Lt    | Less than             |    2    |
     |  Eq    | Equal to              |    3    |
     |  Neq   | Not equal to          |    4    |
     |  Ge    | Greater than OR equal |    5    |
     |  Gt    | Greater than          |    6    |
     --------------------------------------------

   * Operation Function codes (OpqFunc)
     --------------------------------------------
     |  Code  | Desc.                 | op. no. |
     --------------------------------------------
     |  Addc  | Addition              |    0    |
     |  Subc  | Subtraction           |    1    |
     |  Andc  | Bitwise And           |    2    |
     |  Xorc  | Bitwise Xor           |    3    |
     --------------------------------------------

   * Coprocessor Function codes (CopFunc)
     --------------------------------------------
     |  Code  | Desc.                 | op. no. |
     --------------------------------------------
     |  Mtc0  | MTC0                  |    0    |
     |  Mfc0  | MFC0                  |    1    |
     --------------------------------------------
*/
typedef enum {Al, Eq, Neq, Lt, Le, Gt, Ge} CondUsed deriving(Bits, Eq);
FCode fNcnd    = 0;
FCode fLe      = 1;
FCode fLt      = 2;
FCode fEq      = 3;
FCode fNeq     = 4;
FCode fGe      = 5;
FCode fGt      = 6;

typedef enum {FNop, FAdd, FSub, FAnd ,FXor} OpqFunc deriving(Bits, Eq);
FCode addc     = 0;
FCode subc     = 1;
FCode andc     = 2;
FCode xorc     = 3;

typedef enum {Mtc0, Mfc0} CopFunc deriving(Bits, Eq);
FCode mtc0     = 0;
FCode mfc0     = 1;

/* ***************************************************************************
   3. Processor-related types and interfaces
   ***************************************************************************

   * Processor Interface
     hostToCpu: start processor with the given startpc
     cpuToHost: interact with coprocessor register(copReg) values(value)
                and get current timestamp(instNo)

   * implementation details
     OpsRes : Logical/Arithmetic operation result
       OpsRes.first  = operation conditional flag (ZF, SF, OF)
       opsRes.second = calculated result (Data)

*/
interface Proc;
  method ActionValue#(Tuple3#(RIndx, Data, Data)) cpuToHost;
  method Action hostToCpu(Addr startpc);
endinterface

typedef Tuple2#(CondFlag, Data) OpqRes;

typedef struct{
  IType   iType;
  OpqFunc opqFunc;
  CondUsed  condUsed;
  Addr valP;
  Maybe#(FullIndx) dstE;
  Maybe#(FullIndx) dstM;
  Maybe#(FullIndx) regA;
  Maybe#(FullIndx) regB;
  Maybe#(Data) valA;
  Maybe#(Data) valB;
  Maybe#(Data) valC;
  Maybe#(Data) copVal;
} DecodedInst deriving(Bits,Eq);

typedef struct{
  IType iType;
  Maybe#(FullIndx) dstE;
  Maybe#(FullIndx) dstM;
  Maybe#(Data) valE;
  Maybe#(Data) valA;
  Maybe#(Data) valC;
  Maybe#(Data) valM;
  Addr valP;
  CondFlag condFlag;
  Bool condSatisfied;
  Bool mispredict;
  Addr memAddr;
  Maybe#(Addr) nextPc;
  Maybe#(Data) copVal;
} ExecInst deriving(Bits,Eq);

function ICode getICode(Inst inst);
  return inst[79:76];
endfunction

function OpCode getOpCode(Inst inst);
  return inst[79:72];
endfunction

function Addr nextAddr(Addr pc, Bit#(4) iCode);
  let offset =
    case(iCode)
      halt, nop, ret : 1;
      cmov, opq, push, pop, copinst : 2;
      jmp, call : 9;
      irmovq, rmmovq, mrmovq : 10;
      default : 1;
    endcase;
  return pc + offset;
endfunction

function Bool isValidInst(OpCode opCode);
  let iCode = opCode[7:4];
  let fCode = opCode[3:0];

  let res =
    case(iCode)
      halt, nop, irmovq, rmmovq, mrmovq, call, ret, push, pop : (fCode == 0);
      cmov, jmp : ((fCode >=0) && (fCode <7));
      opq : ((fCode >= 0) && (fCode <4));
      copinst : ((fCode ==0) || (fCode ==1));
      default : False;
    endcase;

  return res;
endfunction

/* Helper functions
   ----------------

   reverseEndian, big2LittleEndian, little2BigEndian: reversing endian (Data -> Data)
   showInst: pretty-printing instructions
*/

function Data reverseEndian(Data target);
  return {target[7:0],target[15:8],target[23:16],target[31:24], target[39:32],
    target[47:40], target[55:48], target[63:56]};
endfunction
function Data big2LittleEndian(Data target) = reverseEndian(target);
function Data little2BigEndian(Data target) = reverseEndian(target);

function Fmt showInst(Inst inst);
  Fmt retv = fshow("");

  let iCode = inst[79:76];
  let fCode = inst[75:72];
  let regA  = inst[71:68];
  let regB  = inst[67:64];
  let vals  = reverseEndian(inst[63:0]);
  let dest  = reverseEndian(inst[71:8]);

  case(iCode)
  halt :
    retv = fshow ("halt");

  nop :
    retv = fshow ("nop");

  irmovq :
    retv = fshow("irmovq $") + fshow(vals) + fshow(",  %") + fshow(regB);

  rmmovq :
    retv = fshow("rmmovq %") + fshow(regA) + fshow (", ") + fshow(vals)  + fshow("(%") + fshow(regB) + fshow(")");

  mrmovq :
    retv = fshow("mrmovq ") + fshow(vals)  + fshow("(%") + fshow(regB) + fshow(")") + fshow(", %") + fshow(regA);

  cmov :
  begin
    case(fCode)
      fNcnd :
        retv = fshow("rrmovq %") + fshow(regA) + fshow(", %") + fshow(regB);
      default :
      begin
        retv = fshow("cmov");
        retv = retv + (case(fCode)
                  fLe  : fshow("le %");
                fLt  : fshow("l %");
                fEq  : fshow("e %");
                fNeq : fshow("ne %");
                fGe  : fshow("ge %");
                fGt  : fshow("g %");
               endcase);
        retv = retv + fshow(regA) + fshow(", %") + fshow(regB);
      end
    endcase
  end

  opq :
  begin
    retv = case(fCode)
        addc : fshow("addq %");
        subc : fshow("subq %");
        andc : fshow("andq %");
        xorc : fshow("xorq %");
        endcase;

    retv = retv + fshow(regA) + fshow(", %") + fshow(regB);
  end

  jmp :
  begin
    retv = fshow("j");
    retv = retv + (case(fCode)
             fNcnd : fshow("mp $");
             fLe   : fshow("le $");
             fLt   : fshow("l $");
             fEq   : fshow("e $");
             fNeq  : fshow("ne $");
             fGe   : fshow("ge $");
             fGt   : fshow("g $");
           endcase);
    retv = retv + fshow(dest);
  end

  push :
    retv = fshow("push %") + fshow(regA);

  pop :
    retv = fshow("pop %") + fshow(regA);

  ret :
    retv = fshow("ret");

  call :
    retv = fshow("call ") + fshow(dest);

  copinst :
  begin
    retv = case(fCode)
        mtc0 : fshow("mtc0 %");
        mfc0 : fshow("mfc0 %");
         endcase;
    retv = retv + fshow(regA) + fshow(", %") + fshow(regB);
  end

  default :
    retv = fshow("Unsupported Instruction");
  endcase

  return retv;
endfunction
