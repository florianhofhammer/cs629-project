import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import RegFile::*;
import RVUtil::*;
import Vector::*;
import KonataHelper::*;
import Printf::*;
import Ehr::*;

typedef struct { Bit#(4) byte_en; Bit#(32) addr; Bit#(32) data; } Mem deriving (Eq, FShow, Bits);

interface RVIfc;
    method ActionValue#(Mem) getIReq();
    method Action getIResp(Mem a);
    method ActionValue#(Mem) getDReq();
    method Action getDResp(Mem a);
    method ActionValue#(Mem) getMMIOReq();
    method Action getMMIOResp(Mem a);
endinterface
typedef struct { Bool isUnsigned; Bit#(2) size; Bit#(2) offset; Bool mmio; } MemBusiness deriving (Eq, FShow, Bits);

function Bool isMMIO(Bit#(32) addr);
    Bool x = case (addr) 
        32'hf000fff0: True;
        32'hf000fff4: True;
        32'hf000fff8: True;
        default: False;
    endcase;
    return x;
endfunction

typedef struct { Bit#(32) pc;
                 Bit#(32) ppc;
                 Bit#(1) epoch; 
                 KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
             } F2D deriving (Eq, FShow, Bits);

typedef struct { 
    DecodedInst dinst;
    Bit#(32) pc;
    Bit#(32) ppc;
    Bit#(1) epoch;
    Bit#(32) rv1; 
    Bit#(32) rv2; 
    KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
    } D2E deriving (Eq, FShow, Bits);

typedef struct { 
    MemBusiness mem_business;
    Bit#(32) data;
    DecodedInst dinst;
    Bool to_work;
    KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
} E2W deriving (Eq, FShow, Bits);

(* synthesize *)
module mkpipelined(RVIfc);
    // Interface with memory and devices
    FIFOF#(Mem) toImem <- mkBypassFIFOF;
    FIFOF#(Mem) fromImem <- mkBypassFIFOF;
    FIFOF#(Mem) toDmem <- mkBypassFIFOF;
    FIFOF#(Mem) fromDmem <- mkBypassFIFOF;
    FIFOF#(Mem) toMMIO <- mkBypassFIFOF;
    FIFOF#(Mem) fromMMIO <- mkBypassFIFOF;

    Bool debug = False;

	// Code to support Konata visualization
    String dumpFile = "output.log" ;
    let lfh <- mkReg(InvalidFile);
	Reg#(KonataId) fresh_id <- mkReg(0);
	Reg#(KonataId) commit_id <- mkReg(0);

	FIFOF#(KonataId) retired <- mkFIFOF;
	FIFOF#(KonataId) squashed <- mkFIFOF;

    
    Reg#(Bool) starting <- mkReg(True);

    // new variables

    // epochs
    Reg#(Bit#(1)) fetch_epoch <- mkReg(0);
    Reg#(Bit#(1)) epoch[2] <- mkCReg(2, 0);

    // fetching
    Reg#(Bit#(32)) pc_exec[2] <- mkCReg(2, 32'h0000000);
    Reg#(Bit#(32)) pc_fetch <- mkReg(32'h0000000);

    // pipelining
    FIFOF#(F2D) f2d <- mkFIFOF;
    FIFOF#(D2E) d2e <- mkFIFOF;
    FIFOF#(E2W) e2w <- mkFIFOF;

    // register file scoreboard checks
    Vector#(32, Reg#(Bit#(32))) rf <- replicateM(mkReg(0));
    Vector#(32, FIFOF#(Bool)) scoreboard <- replicateM(mkFIFOF);

	rule do_tic_logging;
        if (starting) begin
            let f <- $fopen(dumpFile, "w") ;
            lfh <= f;
            $fwrite(f, "Kanata\t0004\nC=\t1\n");
            starting <= False;
        end
		konataTic(lfh);
	endrule
		
    rule fetch if (!starting);

        Bit#(32) pc_fetched = (fetch_epoch == epoch[1]) ? pc_fetch : pc_exec[1];
        fetch_epoch <= epoch[1];
        let to_fetch = pc_fetched + 4; // all predictions here
        pc_fetch <= to_fetch;

        // Below is the code to support Konata's visualization
		let iid <- fetch1Konata(lfh, fresh_id, 0);
        labelKonataLeft(lfh, iid, $format("0x%x: ", pc_fetched));
        
        // send a new request
	    if(debug) $display("Fetch %x", pc_fetched);
        labelKonataLeft(lfh, iid, $format("0x%x: ", pc_fetched));
        let req = Mem {byte_en : 0,
			   addr : pc_fetched,
			   data : 0};
        toImem.enq(req);

        // forward the request
        f2d.enq(F2D{ pc: pc_fetched, ppc: to_fetch, epoch: epoch[1], k_id: iid});
    endrule

    rule decode if (!starting);
        let from_fetch = f2d.first();

        // peek and see if we want to wait
        let resp = fromImem.first();
        let instr = resp.data;
        let decodedInst = decodeInst(instr);
        if (debug) $display("[Decode] ", fshow(decodedInst));
        let fields = getInstFields(instr);
        let rs1_idx = fields.rs1;
        let rs2_idx = fields.rs2;
        let rd_idx  = fields.rd;
        decodeKonata(lfh, from_fetch.k_id);

        if (!scoreboard[rs1_idx].notEmpty() && !scoreboard[rs2_idx].notEmpty()) begin
            // we are good to go
            fromImem.deq();
            f2d.deq();
            // mark register on scoreboard
            if (rd_idx != 0) scoreboard[rd_idx].enq(True);

            let rs1 = (rs1_idx == 0 ? 0 : rf[rs1_idx]);
            let rs2 = (rs2_idx == 0 ? 0 : rf[rs2_idx]);

            // labelKonataLeft(lfh, from_fetch.k_id, fshow(decodedInst));
            
            d2e.enq(D2E{ dinst: decodedInst, 
                        pc: from_fetch.pc, 
                        ppc: from_fetch.ppc, 
                        epoch: from_fetch.epoch, 
                        rv1: rs1, 
                        rv2: rs2, 
                        k_id: from_fetch.k_id});
        end
        else begin
            if (debug) $display("[Decode] [Stalling] on %h %h", rs1_idx, rs2_idx, fshow(from_fetch.k_id));
        end

    endrule

    rule execute if (!starting);
        let from_decode = d2e.first();
        d2e.deq();
        executeKonata(lfh, from_decode.k_id);

        let dInst = from_decode.dinst;
        let current_id = from_decode.k_id;
        let rv1 = from_decode.rv1;
        let rv2 = from_decode.rv2;
        let pc = from_decode.pc;
        if (debug) $display("[Execute] ", fshow(dInst));

        if (from_decode.epoch == epoch[0]) begin
            let imm = getImmediate(dInst);
            Bool mmio = False;
            let data = execALU32(dInst.inst, rv1, rv2, imm, pc);
            let isUnsigned = 0;
            let funct3 = getInstFields(dInst.inst).funct3;
            let size = funct3[1:0];
            let addr = rv1 + imm;
            Bit#(2) offset = addr[1:0];
            if (isMemoryInst(dInst)) begin
                // Technical details for load byte/halfword/word
                let shift_amount = {offset, 3'b0};
                let byte_en = 0;
                case (size) matches
                2'b00: byte_en = 4'b0001 << offset;
                2'b01: byte_en = 4'b0011 << offset;
                2'b10: byte_en = 4'b1111 << offset;
                endcase
                data = rv2 << shift_amount;
                addr = {addr[31:2], 2'b0};
                isUnsigned = funct3[2];
                let type_mem = (dInst.inst[5] == 1) ? byte_en : 0;
                let req = Mem {byte_en : type_mem,
                        addr : addr,
                        data : data};
                if (isMMIO(addr)) begin 
                    if (debug) $display("[Execute] MMIO", fshow(req));
                    toMMIO.enq(req);
                    labelKonataLeft(lfh, current_id, $format(" (MMIO)", fshow(req)));
                    mmio = True;
                end else begin 
                    labelKonataLeft(lfh, current_id, $format(" (MEM)", fshow(req)));
                    toDmem.enq(req);
                end
            end
            else if (isControlInst(dInst)) begin
                    labelKonataLeft(lfh, current_id, $format(" (CTRL)"));
                    data = pc + 4;
            end else begin 
                labelKonataLeft(lfh, current_id, $format(" (ALU)"));
            end
            let controlResult = execControl32(dInst.inst, rv1, rv2, imm, pc);
            let nextPc = controlResult.nextPC;
            labelKonataLeft(lfh, current_id, $format(" (JUMP Pr %h Ex %h)", from_decode.ppc, nextPc));
            if (from_decode.ppc != nextPc) begin
                pc_exec[0] <= nextPc;
                epoch[0] <= ~epoch[0];
            end

            e2w.enq(E2W{ mem_business: MemBusiness{isUnsigned: isUnsigned != 0, size: size, offset: offset, mmio: mmio}, 
                         data: data, 
                         dinst: dInst, 
                         to_work: True,
                         k_id: from_decode.k_id});
        end
        else begin
            labelKonataLeft(lfh, current_id, $format(" (SQUASHED)"));
            if (debug) $display("[Execute] [Discard]", fshow(from_decode.k_id));
            squashed.enq(from_decode.k_id);
            squashKonata(lfh, from_decode.k_id);
            e2w.enq(E2W{ mem_business: ?, 
                         data: ?, 
                         dinst: dInst,
                         to_work: False,
                         k_id: from_decode.k_id});
        end
    endrule

    rule writeback if (!starting);
        let from_execute = e2w.first();
        e2w.deq();
        let dInst = from_execute.dinst;
        let current_id = from_execute.k_id;
        let data = from_execute.data;
        let mem_business = from_execute.mem_business;
        let to_work = from_execute.to_work;
        let fields = getInstFields(dInst.inst);

        if (debug) $display("[Writeback] ", fshow(dInst));

        retired.enq(current_id);
        writebackKonata(lfh, from_execute.k_id);

        // remove scoreboard mark
        if (fields.rd != 0) scoreboard[fields.rd].deq();

        if (to_work) begin

            if (isMemoryInst(dInst)) begin // (* // write_val *)
                let resp = ?;
                if (mem_business.mmio) begin 
                    resp = fromMMIO.first();
                    fromMMIO.deq();
                end else begin 
                    resp = fromDmem.first();
                    fromDmem.deq();
                end
                let mem_data = resp.data;
                mem_data = mem_data >> {mem_business.offset ,3'b0};
                case ({pack(mem_business.isUnsigned), mem_business.size}) matches
                3'b000 : data = signExtend(mem_data[7:0]);
                3'b001 : data = signExtend(mem_data[15:0]);
                3'b100 : data = zeroExtend(mem_data[7:0]);
                3'b101 : data = zeroExtend(mem_data[15:0]);
                3'b010 : data = mem_data;
                endcase
            end
            if(debug) $display("[Writeback]", fshow(dInst));
            if (!dInst.legal) begin
                if (debug) $display("[Writeback] Illegal Inst, Drop and fault: ", fshow(dInst));
                pc_exec[1] <= 0;	// Fault
            end
            if (dInst.valid_rd) begin
                let rd_idx = fields.rd;
                if (rd_idx != 0) begin rf[rd_idx] <= data; end
            end
        end
	endrule
		

	// ADMINISTRATION:

    rule administrative_konata_commit;
		    retired.deq();
		    let f = retired.first();
		    commitKonata(lfh, f, commit_id);
	endrule
		
	rule administrative_konata_flush;
		    squashed.deq();
		    let f = squashed.first();
		    squashKonata(lfh, f);
	endrule
		
    method ActionValue#(Mem) getIReq();
		toImem.deq();
		return toImem.first();
    endmethod
    method Action getIResp(Mem a);
    	fromImem.enq(a);
    endmethod
    method ActionValue#(Mem) getDReq();
		toDmem.deq();
		return toDmem.first();
    endmethod
    method Action getDResp(Mem a);
		fromDmem.enq(a);
    endmethod
    method ActionValue#(Mem) getMMIOReq();
		toMMIO.deq();
		return toMMIO.first();
    endmethod
    method Action getMMIOResp(Mem a);
		fromMMIO.enq(a);
    endmethod
endmodule
