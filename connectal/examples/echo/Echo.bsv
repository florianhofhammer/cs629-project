// Copyright (c) 2013 Nokia, Inc.
// Copyright (c) 2013 Quanta Research Cambridge, Inc.

// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
import FIFO::*;
import Vector::*;

// outgoing API
// what info can we send to the controller
interface EchoIndication;
    method Action heard(Bit#(32) v);
    method Action heard2(Bit#(16) a, Bit#(16) b);
    method Action uart_avail(); // ask if uart is non empty?
    method Action uart_get(); // request the uart byte
endinterface

// incoming API
// what info can we receive from the controller
interface EchoRequest;
   method Action say(Bit#(32) v);
   method Action say2(Bit#(16) a, Bit#(16) b);
   method Action setLeds(Bit#(8) v);
   method Action uart_avail_recv(Bit#(8) avail);
   method Action uart_recv(Bit#(8) data);
   method Action timer_interrupt();
endinterface

interface Echo;
   interface EchoRequest request;
endinterface

typedef struct {
	Bit#(16) a;
	Bit#(16) b;
} EchoPair deriving (Bits);

module mkEcho#(EchoIndication indication)(Echo);
    FIFO#(Bit#(32)) delay <- mkSizedFIFO(8);
    FIFO#(EchoPair) delay2 <- mkSizedFIFO(8);

    // FIFO#(Bit#(8)) uart_q <- mkSizedFIFO(8);

    Reg#(Bit#(8)) state <- mkReg(0);
    Reg#(Bit#(8)) counter <- mkReg(1);

    // outgoing API
    rule heard;
        delay.deq;
        indication.heard(delay.first);
        $display("$$$$$$$$$$$$$$$$$$$$$$$$ HEARD %d", delay.first);
    endrule

    rule heard2;
        delay2.deq;
        indication.heard2(delay2.first.b, delay2.first.a);
    endrule

    rule uart_avail if (state == 0 && counter == 0);
        // if (counter == 0) begin
        state <= 1;
        indication.uart_avail;
        counter <= 1;
        // end
    endrule

    rule uart_get if (state == 2);
        indication.uart_get;
    endrule
   
   // incoming API
   interface EchoRequest request;
      method Action say(Bit#(32) v);
	    delay.enq(v + 1);
      endmethod
      
      method Action say2(Bit#(16) a, Bit#(16) b);
	    delay2.enq(EchoPair { a: a + 2, b: b + 3});
      endmethod
      
      method Action setLeds(Bit#(8) v);
      endmethod

      method Action uart_recv(Bit#(8) data);
        // for now just throw it out
        state <= 0;
        delay2.enq(EchoPair { a: zeroExtend(data), b: zeroExtend(data) });
      endmethod

      method Action uart_avail_recv(Bit#(8) avail);
        // for now just throw it out
        if (avail == 0) state <= 0;
        else state <= 2;
        Bit#(16) extended = 'hFF00 | zeroExtend(avail);
        delay.enq(zeroExtend(extended));
      endmethod

      method Action timer_interrupt();
        counter <= 0;
      endmethod
   endinterface
endmodule
