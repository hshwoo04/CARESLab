import Types::*;
import MemTypes::*;
import InstCacheTypes::*;
import RegFile::*;
import Vector::*;
import Fifo::*;

interface ILRU;
	method ICacheSetOffset findLRU();
	method Action updateLRU(ICacheSetOffset lru_set);
endinterface

//TODO: Replace following scheme to support arbitrary number of sets(Current : fixed for 4 sets)
module mkICacheLRU(ILRU);
//	Vector#(4, Reg#(Bit#(1)))	lru_l3	<- replicateM(mkReg(0));
	Vector#(2, Reg#(Bit#(1)))	lru_l2	<- replicateM(mkReg(0));
	Reg#(Bit#(1)) 				lru_l1	<- mkReg(0);

	Fifo#(1,Bit#(1))			upd_l2	<- mkBypassFifo;
	Fifo#(1,Bit#(1))			upd_l1	<- mkBypassFifo;

	rule update;
		let l1 = upd_l1.first;
		let l2 = upd_l2.first;

		lru_l1 		<= (l1 == 1'b0)? 1'b1:1'b0;
		lru_l2[l1]	<= (l2 == 1'b0)? 1'b1:1'b0;

		upd_l1.deq;
		upd_l2.deq;

	endrule


	//Pseudo LRU Logic. It does not check if there remains empty set. Therefore search empty sets before use this function
	method ICacheSetOffset findLRU();

		let l1 = lru_l1;
		let l2 = lru_l2[l1];

		ICacheSetOffset lru_set = {l1, l2};

		//Fix tables
//		lru_l1 		<= reverseBits(l1);
//		lru_l2[l1] 	<= reverseBits(l2);

		return lru_set;
	endmethod

	method Action updateLRU(ICacheSetOffset lru_set);
		let l1 = lru_set[0];
		let l2 = lru_set[1];

//		lru_l1 		<= !l1;
//		lru_l2[l1] 	<= !l2;

		upd_l1.enq(l1);
		upd_l2.enq(l2);

	endmethod

endmodule
