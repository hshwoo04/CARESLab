import Types::*;
import MemTypes::*;
import RegFile::*;
import Vector::*;

interface DMemory;
  method ActionValue#(MemResp) req(MemReq r);
endinterface

(*synthesize*)
module mkDMemory(DMemory);
  RegFile#(MemIndx, Data) dMem <- mkRegFileFullLoad("memory.vmh");

  method ActionValue#(MemResp) req(MemReq r);
    let idx = truncate(r.addr >> 3);
    let data = dMem.sub(idx);

    if(r.op == St)
    begin
      dMem.upd(idx, r.data);
    end

    return data;
  endmethod
endmodule
