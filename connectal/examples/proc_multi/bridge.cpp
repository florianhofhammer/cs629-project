#include <errno.h>
#include <stdio.h>
#include "BridgeIndication.h"
#include "BridgeRequest.h"
#include "GeneratedTypes.h"
#include <time.h>
#include <pthread.h>
#include <semaphore.h>

#define POS_MOD(a, b) ((a) % (b) + (b)) % (b)

int ret_code = 0xdeadbeef;

static BridgeRequestProxy *bridgeRequestProxy = nullptr;
static sem_t sem_finish;

class Buffer {
public:
    Buffer() : count(0), head(0) {
        data = new char[SIZE];
        sem_init(&can_read, 0, 0);
    }
    ~Buffer() {
        delete [] data;
    }
    void enq(char c) {
        if (count < SIZE) {
            count++;
            data[head + count] = c;
            sem_post(&can_read);
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
            // wait to return something
            sem_wait(&can_read);
            return deq();
        }
    }
    bool empty() {
        return count == 0;
    }
    unsigned int head;
    unsigned int count;
    char * data;

    sem_t can_read;

    static const int SIZE = 1024;
};

static Buffer * uart_buf;

void * handle_input(void * arg) {
    while (true) {
        char c = getchar();
        uart_buf->enq(c);
    }
}

void * handle_timer(void * arg) {
    while (true) {
        usleep(1000);
        bridgeRequestProxy->timer_interrupt();
    }
}

class BridgeIndication : public BridgeIndicationWrapper
{
public:
    virtual void uartAvailReq() {
        bridgeRequestProxy->uartAvailResp(!uart_buf->empty());
    }

    virtual void uartTx(const uint8_t data) {
        putchar(data);
    }

    virtual void uartRxReq() {
        char c = uart_buf->deq();
        bridgeRequestProxy->uartRxResp(c);
    }

    virtual void finish(unsigned int ret) {
        ret_code = ret;
        printf("Finish: %d\n", ret);
        sem_post(&sem_finish);
    }
    BridgeIndication(unsigned int id) : BridgeIndicationWrapper(id) {}
};

int main(int argc, const char **argv)
{
    long actualFrequency = 0;
    long requestedFrequency = 1e9 / MainClockPeriod;

    sem_init(&sem_finish, 0, 0);

    BridgeIndication bridgeIndication(IfcNames_BridgeIndicationH2S);
    bridgeRequestProxy = new BridgeRequestProxy(IfcNames_BridgeRequestS2H);
    uart_buf = new Buffer();

    int status = setClockFrequency(0, requestedFrequency, &actualFrequency);
    fprintf(stderr, "Requested main clock frequency %5.2f, actual clock frequency %5.2f MHz status=%d errno=%d\n",
	    (double)requestedFrequency * 1.0e-6,
	    (double)actualFrequency * 1.0e-6,
	    status, (status != 0) ? errno : 0);

    pthread_t input_handler, timer_handler;

    // input handler thread
    // pthread_create(&input_handler, nullptr, *handle_input, nullptr);

    // timer interrupt thread
    pthread_create(&timer_handler, nullptr, *handle_timer, nullptr);

    // main thread chills
    printf("[Info] Main thread waiting\n");
    sem_wait(&sem_finish);
    printf("[Info] Main thread finishing\n");
    // pthread_cancel(input_handler);
    pthread_cancel(timer_handler);
    return ret_code;
}
