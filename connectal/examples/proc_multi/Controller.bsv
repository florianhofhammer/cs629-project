import RVUtil::*;
import BRAM::*;
import multicycle::*; // TODO:
import FIFO::*;
typedef Bit#(32) Word;

typedef enum {
    MMIOIdle,
    WaitingAvail,
    WaitingData
} MMIOState deriving (Bits, Eq, FShow);

// outgoing API; requests to the bridge
interface BridgeIndication;
    // uart
    method Action uartAvailReq();
    method Action uartTx(Bit#(8) data);
    method Action uartRxReq();

    // exit
    method Action finish(Bit#(32) data);
endinterface

// incoming API; requests from the bridge
interface BridgeRequest;
    // uart
    method Action uartAvailResp(Bit#(8) avail);
    method Action uartRxResp(Bit#(8) data);

    // timer
    method Action timer_interrupt();
endinterface

interface Controller;
    interface BridgeRequest request;
endinterface

module mkController#(BridgeIndication indication)(Controller);
    // Instantiate the dual ported memory
    BRAM_Configure cfg = defaultValue();
    cfg.loadFormat = tagged Hex "mem.vmh";
    BRAM2PortBE#(Bit#(28), Word, 4) bram <- mkBRAM2ServerBE(cfg);

    RVIfc rv_core <- mkmulticycle; // TODO:
    Reg#(Mem) ireq <- mkRegU;
    Reg#(Mem) dreq <- mkRegU;
    FIFO#(Mem) mmioreq <- mkFIFO;
    let debug = True;
    Reg#(Bit#(32)) cycle_count <- mkReg(0);

    Reg#(MMIOState) mmio_state <- mkReg(MMIOIdle);

    FIFO#(Mem) uartAvailReq <- mkFIFO;
    FIFO#(Mem) uartDataReq <- mkFIFO;

    FIFO#(Bit#(8)) uartAvailResp <- mkFIFO;
    FIFO#(Bit#(8)) uartDataResp <- mkFIFO;

    rule tic;
	    cycle_count <= cycle_count + 1;
    endrule

    rule requestI;
        let req <- rv_core.getIReq;
        if (debug) $display("Get IReq", fshow(req));
        ireq <= req;
            bram.portB.request.put(BRAMRequestBE{
                    writeen: req.byte_en,
                    responseOnWrite: True,
                    address: truncate(req.addr >> 2),
                    datain: req.data});
    endrule

    rule responseI;
        let x <- bram.portB.response.get();
        let req = ireq;
        if (debug) $display("Get IResp ", fshow(req), fshow(x));
        // indication.uartTx('h69); // 'i'
        req.data = x;
            rv_core.getIResp(req);
    endrule

    rule requestD;
        let req <- rv_core.getDReq;
        dreq <= req;
        if (debug) $display("Get DReq", fshow(req));
        bram.portA.request.put(BRAMRequestBE{
          writeen: req.byte_en,
          responseOnWrite: True,
          address: truncate(req.addr >> 2),
          datain: req.data});
    endrule

    rule responseD;
        let x <- bram.portA.response.get();
        let req = dreq;
        // indication.uartTx('h64); // 'd'
        if (debug) $display("Get IResp ", fshow(req), fshow(x));
        req.data = x;
            rv_core.getDResp(req);
    endrule
  
    rule requestMMIO if (mmio_state == MMIOIdle);
        let req <- rv_core.getMMIOReq;
        if (debug) $display("Get MMIOReq", fshow(req));
        case (req.addr)
            'hf000_fff0: begin
                // overloaded address from labs
                if (req.byte_en == 'h0) begin
                    // Reading from UART
                    mmio_state <= WaitingData;
                    uartDataReq.enq(req);
                    indication.uartRxReq();
                end
                else begin
                    // Writing to UART
                    indication.uartTx(req.data[7:0]);
                end

                mmioreq.enq(req);
            end
            'hf000_fff4: begin
                // no op
                mmioreq.enq(req);
            end
            'hf000_fff8: begin
                // Exiting Simulation
                if (req.data == 0) begin
                        $fdisplay(stderr, "  [0;32mPASS[0m");
                        $fdisplay(stderr, "  cycle: %d", cycle_count);
                end
                else
                    begin
                        $fdisplay(stderr, "  [0;31mFAIL[0m (%0d)", req.data);
                    end

                mmioreq.enq(req); // doesn't matter but eh
                // $fflush(stderr);
                // $finish;
                $display("Voluntarily Exiting simulation");
                indication.finish(req.data);
            end
            'hf000_0000: begin
                if (req.byte_en == 'h0) begin
                    // Reading from UART
                    mmio_state <= WaitingData;
                    uartDataReq.enq(req);
                    indication.uartRxReq();
                end
                else begin
                    // Writing to UART
                    indication.uartTx(req.data[7:0]);
                    mmioreq.enq(req);
                end
            end
            'hf000_0005: begin
                // Checking if UART is available
                indication.uartAvailReq();
                uartAvailReq.enq(req);
                mmio_state <= WaitingAvail;
            end
            default: begin 
                mmioreq.enq(req);
            end
        endcase
    endrule

    rule uartAvailRespMMIO if (mmio_state == WaitingAvail);
        let req = uartAvailReq.first();
        uartAvailReq.deq();
        let avail = uartAvailResp.first();
        uartAvailResp.deq();

        let newReq = Mem {
            addr: req.addr,
            data: zeroExtend(avail),
            byte_en: req.byte_en
        };
        if (debug) $display("Avail Response: ", fshow(newReq));

        mmioreq.enq(newReq);
        mmio_state <= MMIOIdle;
    endrule

    rule uartDataRespMMIO if (mmio_state == WaitingData);
        let req = uartDataReq.first();
        uartDataReq.deq();
        let data = uartDataResp.first();
        uartDataResp.deq();

        let newReq = Mem {
            addr: req.addr,
            data: zeroExtend(data),
            byte_en: req.byte_en
        };
        if (debug) $display("Data Response: ", fshow(newReq));
        
        mmioreq.enq(newReq);
        mmio_state <= MMIOIdle;
    endrule

    rule responseMMIO;
        let req = mmioreq.first();
        mmioreq.deq();
        if (debug) $display("Put MMIOResp", fshow(req));
        rv_core.getMMIOResp(req);
    endrule

    // bridge interface
    interface BridgeRequest request;
        method Action uartAvailResp(Bit#(8) avail);
            uartAvailResp.enq(avail);
        endmethod
        method Action uartRxResp(Bit#(8) data);
            uartDataResp.enq(data);
        endmethod
        method Action timer_interrupt();
            // do nothing for now
        endmethod
    endinterface
    
endmodule
