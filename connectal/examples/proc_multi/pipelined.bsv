import FIFO::*;
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
    KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
} E2W deriving (Eq, FShow, Bits);

// Scoreboard
interface Scoreboard;
    method Action insert(Bit#(5) dst);
    method Action remove1(Bit#(5) dst);
    method Action remove2(Bit#(5) dst);
    method Bool search1(Bit#(5) dst);
    method Bool search2(Bit#(5) dst);
    method Bool search3(Bit#(5) dst);
endinterface

module mkScoreboard(Scoreboard);
    Vector#(32, Ehr#(3, Bool)) regs <- replicateM(mkEhr(False));

    method Action insert(Bit#(5) dst);
        regs[dst][2] <= True;
    endmethod

    method Action remove1(Bit#(5) dst);
        regs[dst][1] <= False;
    endmethod

    method Action remove2(Bit#(5) dst);
        regs[dst][0] <= False;
    endmethod

    method Bool search1(Bit#(5) dst);
        return regs[dst][2];
    endmethod

    method Bool search2(Bit#(5) dst);
        return regs[dst][2];
    endmethod

    method Bool search3(Bit#(5) dst);
        return regs[dst][2];
    endmethod
endmodule

// Bypass register file
interface RFile;
    method Action wr(Bit#(5) idx, Bit#(32) data);
    method Bit#(32) rd1(Bit#(5) idx);
    method Bit#(32) rd2(Bit#(5) idx);
endinterface

module mkRFile(RFile);
    Vector#(32, Ehr#(2, Bit#(32))) rfile <- replicateM(mkEhr(0));

    method Action wr(Bit#(5) idx, Bit#(32) data);
        if (idx != 0) (rfile[idx])[0] <= data;
    endmethod
    method Bit#(32) rd1(Bit#(5) idx);
        return (rfile[idx])[1];
    endmethod
    method Bit#(32) rd2(Bit#(5) idx);
        return (rfile[idx])[1];
    endmethod
endmodule

(* synthesize *)
module mkpipelined(RVIfc);
    // Interface with memory and devices
    FIFO#(Mem) toImem <- mkBypassFIFO;
    FIFO#(Mem) fromImem <- mkBypassFIFO;
    FIFO#(Mem) toDmem <- mkBypassFIFO;
    FIFO#(Mem) fromDmem <- mkBypassFIFO;
    FIFO#(Mem) toMMIO <- mkBypassFIFO;
    FIFO#(Mem) fromMMIO <- mkBypassFIFO;

    // Registers
    Ehr#(3, Bit#(32)) pc <- mkEhr(32'h0000000);
    RFile rf <- mkRFile;
    // Scoreboard
    Scoreboard sb <- mkScoreboard;

    // Queues for pipeline stages
    FIFO#(F2D) f2d <- mkFIFO;
    FIFO#(D2E) d2e <- mkFIFO;
    FIFO#(E2W) e2w <- mkFIFO;
    // Epoch for squashing incorrectly predicted instructions
    Reg#(Bit#(1)) epoch <- mkReg(0);

    // Code to support Konata visualization
    String dumpFile = "output.log" ;
    let lfh <- mkReg(InvalidFile);
    Reg#(KonataId) fresh_id <- mkReg(0);
    Reg#(KonataId) commit_id <- mkReg(0);

    FIFO#(KonataId) retired <- mkFIFO;
    FIFO#(KonataId) squashed <- mkFIFO;

    Bool debug = False;
    Reg#(Bool) starting <- mkReg(True);

    // Debugging helpers (printing cycles sometimes helps)
    Reg#(Bit#(32)) cycle_count <- mkReg(0);
    rule tic;
	    cycle_count <= cycle_count + 1;
    endrule

    rule do_tic_logging;
        if (starting) begin
            let f <- $fopen(dumpFile, "w") ;
            lfh <= f;
            $fwrite(f, "Kanata\t0004\nC=\t1\n");
            starting <= False;
        end
        konataTic(lfh);
    endrule


    // Actual CPU pipeline stages start here
    rule fetch if (!starting);
        if (debug) begin $display("[CPU] [FETCH] cycle: %d", cycle_count); end
        let pc_fetched = pc[0];
        let pc_predicted = pc[0] + 4;
        let iid <- fetch1Konata(lfh, fresh_id, 0);
        labelKonataLeft(lfh, iid, $format("0x%x: ", pc_fetched));

        // Create memory request
        let req = Mem {byte_en : 0,
               addr : pc[0],
               data : 0};
        toImem.enq(req);
        pc[0] <= pc_predicted;
        // Enqueue current "instruction" identifier
        f2d.enq(F2D{pc: pc_fetched, ppc: pc_predicted, epoch: epoch, k_id: iid});
    endrule

    rule decode if (!starting);
        if (debug) begin $display("[CPU] [DECODE] cycle: %d", cycle_count); end
        let from_fetch = f2d.first();
        if (debug) begin $display("[CPU] [DECODE] k_id: %d, epoch: %d/%d", from_fetch.k_id, from_fetch.epoch, epoch); end
        let inPc = from_fetch.pc;
        let inPpc = from_fetch.ppc;
        let inEpoch = from_fetch.epoch;
        let resp = fromImem.first();
        let instr = resp.data;
        let dInst = decodeInst(instr);
        let rs1_idx = getInstFields(dInst.inst).rs1;
        let rs2_idx = getInstFields(dInst.inst).rs2;
        let rd_idx = getInstFields(dInst.inst).rd;
        // Check scoreboard
        let rs1_sb = dInst.valid_rs1 && sb.search1(rs1_idx);
        let rs2_sb = dInst.valid_rs2 && sb.search2(rs2_idx);
        let rd_sb = dInst.valid_rd && sb.search3(rd_idx);
        if (debug) begin $display("[CPU] [DECODE] Scoreboard results: %d=%d, %d=%d, %d=%d", rs1_idx, rs1_sb, rs2_idx, rs2_sb, rd_idx, rd_sb); end
        if (!rs1_sb && !rs2_sb && !rd_sb) begin
            // Scoreboard didn't signal issues => actually continue
            decodeKonata(lfh, from_fetch.k_id);
            labelKonataLeft(lfh, from_fetch.k_id, $format("DASM(%x)", instr));  // inserts the DASM id into the intermediate file
            f2d.deq();
            fromImem.deq();
            // Add destination register to scoreboard
            if (dInst.valid_rd) begin
                sb.insert(rd_idx);
            end
            // Get register values (might be trash if we don't actually use them but doesn't matter)
            let rs1 = rf.rd1(rs1_idx);
            let rs2 = rf.rd2(rs2_idx);
            // Send instruction on to execute
            d2e.enq(D2E{dinst: dInst, pc: inPc, ppc: inPpc, epoch:
                inEpoch, rv1: rs1, rv2: rs2, k_id: from_fetch.k_id});
        end
    endrule

    rule execute if (!starting);
        if (debug) begin $display("[CPU] [EXECUTE] cycle: %d", cycle_count); end
        let from_decode = d2e.first();
        d2e.deq();
        if (debug) begin $display("[CPU] [EXECUTE] k_id: %d, epoch: %d/%d", from_decode.k_id, from_decode.epoch, epoch); end
        let dInst = from_decode.dinst;
        let rv1 = from_decode.rv1;
        let rv2 = from_decode.rv2;
        let dPc = from_decode.pc;
        let dPpc = from_decode.ppc;
        let dEpoch = from_decode.epoch;
        executeKonata(lfh, from_decode.k_id);
        if (dEpoch == epoch) begin
            // Right epoch, so execute
            let imm = getImmediate(dInst);
            Bool mmio = False;
            let data = execALU32(dInst.inst, rv1, rv2, imm, dPc);
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
                let req = Mem {byte_en: type_mem,
                               addr: addr,
                               data: data};
                if (isMMIO(addr)) begin
                    if (debug) $display("[CPU] [EXECUTE @ %x] addr %x is MMIO", dPc, addr);
                    toMMIO.enq(req);
                    labelKonataLeft(lfh, from_decode.k_id, $format(" (MMIO)", fshow(req)));
                    mmio = True;
                end else begin
                    if (debug) $display("[CPU] [EXECUTE @ %x] addr %x is data", dPc, addr);
                    labelKonataLeft(lfh, from_decode.k_id, $format(" (MEM)", fshow(req)));
                    toDmem.enq(req);
                end
            end
            else if (isControlInst(dInst)) begin
                    labelKonataLeft(lfh, from_decode.k_id, $format(" (CTRL)"));
                    data = dPc + 4;
            end else begin
                labelKonataLeft(lfh, from_decode.k_id, $format(" (ALU)"));
            end
            let controlResult = execControl32(dInst.inst, rv1, rv2, imm, dPc);
            let nextPc = controlResult.nextPC;
            if (nextPc != dPpc) begin
                // Predicted PC was incorrect, update epoch and PC
                epoch <= epoch + 1;
                pc[2] <= nextPc;
            end
            if (debug) $display("[CPU] [EXECUTE] nextPC: %x, predicted PC: %x", nextPc, dPpc);
            // Send instruction on to writeback
            e2w.enq(E2W{mem_business: MemBusiness{isUnsigned: unpack(isUnsigned), size:
                size, offset: offset, mmio: mmio}, data: data, dinst: dInst, k_id:
                from_decode.k_id});
        end else begin
            // Wrong epoch, so squash instruction instead of executing it
            if (dInst.valid_rd) begin
                let rd_idx = getInstFields(dInst.inst).rd;
                sb.remove1(rd_idx);
            end
            squashed.enq(from_decode.k_id);
        end
    endrule

    rule writeback if (!starting);
        if (debug) begin $display("[CPU] [WRITEBACK] cycle: %d", cycle_count); end
        let from_execute = e2w.first();
        e2w.deq();
        let dInst = from_execute.dinst;
        let mem_business = from_execute.mem_business;
        let data = from_execute.data;

        writebackKonata(lfh, from_execute.k_id);
        // Retire the instruction
        retired.enq(from_execute.k_id);

        let fields = getInstFields(dInst.inst);
        if (isMemoryInst(dInst)) begin
            if (debug) $display("[CPU] [WRITEBACK] Memory inst: %s", dInst.inst[5] == 0 ? "read" : "write");
            let resp = ?;
            if (mem_business.mmio) begin
                if (debug) $display("[CPU] [WRITEBACK] MMIO");
                resp = fromMMIO.first();
                fromMMIO.deq();
            // Note: this is where we only expect a response on reads, not on
            // writes to the cache
            end else if (dInst.inst[5] == 0) begin
                if (debug) $display("[CPU] [WRITEBACK] Data");
                // only expect response on read
                resp = fromDmem.first();
                if (debug) $display("[CPU] [WRITEBACK] ", fshow(resp), " => %d", fields.rd);
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
        if (!dInst.legal) begin
            if (debug) $display("[CPU] [WRITEBACK] Illegal Inst, Drop and fault: ", fshow(dInst));
            // Updating PC order (EHR ports) is unclear to me, need to ask in class
            pc[1] <= 0;    // Fault
        end
        if (debug) $display("[CPU] [WRITEBACK] Data: %x", data);
        if (dInst.valid_rd) begin
            let rd_idx = fields.rd;
            sb.remove2(rd_idx);
            rf.wr(rd_idx, data);
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
