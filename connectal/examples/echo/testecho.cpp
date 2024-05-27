/* Copyright (c) 2014 Quanta Research Cambridge, Inc
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

#include <errno.h>
#include <stdio.h>
#include "EchoIndication.h"
#include "EchoRequest.h"
#include "GeneratedTypes.h"
#include <time.h>
// #include <bits/semaphore.h>

#define POS_MOD(a, b) ((a) % (b) + (b)) % (b)

static EchoRequestProxy *echoRequestProxy = 0;
static sem_t sem_heard2;

class Buffer {
public:
    Buffer() : count(0), head(0) {
        data = new char[SIZE];
    }
    ~Buffer() {
        delete [] data;
    }
    void enq(char c) {
        if (count < SIZE) {
            count++;
            data[head + count] = c;
        } else {
            printf("Buffer full\n");
        }
    }
    char deq() {
        if (count > 0) {
            count--;
            head += POS_MOD(head, SIZE);
            return data[head + count];
        } else {
            printf("Buffer empty\n");
            return 0;
        }
    }
    bool empty() {
        return count == 0;
    }
    unsigned int head;
    unsigned int count;
    char * data;

    static const int SIZE = 1024;
};

static Buffer * uart_buf;

class EchoIndication : public EchoIndicationWrapper
{
public:
    virtual void heard(uint32_t v) {
        printf("heard an echo: %x\n", v);
	    echoRequestProxy->say2(v, 2*v);
    }
    virtual void heard2(uint16_t a, uint16_t b) {
        sem_post(&sem_heard2);
        printf("heard an echo2: %c %c\n", a, a);
    }
    virtual void uart_avail() {
        printf("uart_avail\n");
        echoRequestProxy->uart_avail_recv(!uart_buf->empty());
    }
    virtual void uart_get() {
        char c = uart_buf->deq();
        printf("uart_get :: %x %c\n", c, c);
        echoRequestProxy->uart_recv(c);
    }
    EchoIndication(unsigned int id) : EchoIndicationWrapper(id) {}
};

static void call_say(int v)
{
    printf("[%s:%d] %d\n", __FUNCTION__, __LINE__, v);
    echoRequestProxy->say(v);
    sem_wait(&sem_heard2);
}

static void call_say2(int v, int v2)
{
    echoRequestProxy->say2(v, v2);
    sem_wait(&sem_heard2);
}

int main(int argc, const char **argv)
{
    long actualFrequency = 0;
    long requestedFrequency = 1e9 / MainClockPeriod;

    EchoIndication echoIndication(IfcNames_EchoIndicationH2S);
    echoRequestProxy = new EchoRequestProxy(IfcNames_EchoRequestS2H);
    uart_buf = new Buffer();

    int status = setClockFrequency(0, requestedFrequency, &actualFrequency);
    fprintf(stderr, "Requested2 main clock frequency %5.2f, actual clock frequency %5.2f MHz status=%d errno=%d\n",
	    (double)requestedFrequency * 1.0e-6,
	    (double)actualFrequency * 1.0e-6,
	    status, (status != 0) ? errno : 0);

    // int v = 42;
    // printf("Saying %d\n", v);
    // call_say(v);
    // call_say(v*5);
    // call_say(v*17);
    // call_say(v*93);
    // call_say2(v, v*3);
    // printf("TEST TYPE: SEM\n");
    // echoRequestProxy->setLeds(9);

    time_t timer;
    time_t last_time = 0;
    unsigned const long interrupt_delay = 1; // second

    fprintf(stderr, "TEST START: UART\n");
    char c = (char) 0;
    while (true) {
        printf("> "); fflush(stdout);
        c = getchar();
        if (c == '#') {
            break;
        } else {
            uart_buf->enq(c);
        }
        printf("\n");
        time(&timer);
        if (timer - last_time > interrupt_delay) {
            // every second, send a timer interrupt, which forces a uart_avail
            last_time = timer;
            echoRequestProxy->timer_interrupt();
        }
    }
    return 0;
}
