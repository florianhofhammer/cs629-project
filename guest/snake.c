/* Taken from https://github.com/Rank1AltAccount/csnake and heavily modified */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SNAKE_HEAD_CHAR 'O'
#define SNAKE_BODY_CHAR 'o'
#define SPACE_CHAR      ' '
#define WALL_CHAR       '#'
#define FOOD_CHAR       '@'

// Not all coordinates are supposed to be vec2d,
// it is used only where necessary to avoid memory management
typedef struct _vec2d {
    int x;
    int y;
} vec2d;

#define WIDTH  20
#define HEIGHT (WIDTH / 2)

char frameBuffer[WIDTH][HEIGHT];

int snakeSize = 0;

vec2d foodPos;
vec2d snake[WIDTH * HEIGHT];

int randInRange(const int lower, const int upper) {
    return (rand() % (upper - lower + 1)) + lower;
}

void clearConsole() {
    int i;

    for (i = 0; i < 2; i++) {
        putchar('\n');
    }
}

void clearBuffer() {
    int x;
    int y;

    memset(frameBuffer, WALL_CHAR, sizeof(frameBuffer));

    for (y = 1; y < HEIGHT - 1; y++) {
        for (x = 1; x < WIDTH - 1; x++) {
            frameBuffer[x][y] = SPACE_CHAR;
        }
    }
}

void drawFrame() {
    int x;
    int y;

    for (y = 0; y < HEIGHT; y++) {
        for (x = 1; x <= WIDTH; x++) {
            // x - 1 to avoid printing a new line on x == 0
            putchar(frameBuffer[x - 1][y]);

            if (x == WIDTH) {
                putchar('\n');
            }
        }
    }
}

void lose() {
    printf("Game lost!");

    exit(0);
}

int checkCollision(const int x, const int y) {
    // Collides with bounds
    if (x >= WIDTH - 1 || x <= 0 || y >= HEIGHT - 1 || y <= 0) {
        return 1;
    }

    int i;

    // Collides with body
    for (i = 0; i < snakeSize; i++) {
        if (x == snake[i].x && y == snake[i].y) {
            return 1;
        }
    }

    return 0;
}

void createFood() {
    int xfood = randInRange(1, WIDTH - 2);
    int yfood = randInRange(1, HEIGHT - 2);

    if (checkCollision(xfood, yfood)) {
        createFood();
    }

    foodPos.x = xfood;
    foodPos.y = yfood;
}

void snakeAddPart(const int x, const int y) {
    snake[snakeSize] = (vec2d){.x = x, .y = y};

    snakeSize++;
}

void snakeMove(const int xmove, const int ymove) {
    const int xNewHead = snake[0].x + xmove;
    const int yNewHead = snake[0].y + ymove;

    if (checkCollision(xNewHead, yNewHead)) {
        lose();
    }

    // Food eaten
    if (xNewHead == foodPos.x && yNewHead == foodPos.y) {
        snakeAddPart(snake[snakeSize].x, snake[snakeSize].y);

        createFood();
    }

    int i;

    for (i = snakeSize - 1; i >= 1; i--) {
        snake[i].x = snake[i - 1].x;
        snake[i].y = snake[i - 1].y;
    }

    snake[0].x = xNewHead;
    snake[0].y = yNewHead;
}

// Write game objects to buffer
void gameToBuffer() {
    frameBuffer[foodPos.x][foodPos.y] = FOOD_CHAR;

    int i;

    for (i = 0; i < snakeSize; i++) {
        if (i == 0) {
            frameBuffer[snake[i].x][snake[i].y] = SNAKE_HEAD_CHAR;
        } else {
            frameBuffer[snake[i].x][snake[i].y] = SNAKE_BODY_CHAR;
        }
    }
}

void init() {
    // Seed the generator
    srand(0);

    snakeAddPart(randInRange(1, WIDTH - 1), randInRange(1, HEIGHT - 1));
    snakeAddPart(snake[0].x, snake[0].y);
    snakeAddPart(snake[0].x, snake[0].y);

    createFood();
}

typedef enum dir_e {
    UP,
    DOWN,
    RIGHT,
    LEFT
} dir_t;

void tick() {
    dir_t direction = UP;

    while (1) {
        char c = getchar();
        /* On enter, redraw. Otherwise, move snake */
        switch (c) {
            case 'a':
            case 'h':
                direction = LEFT;
                break;
            case 'd':
            case 'l':
                direction = RIGHT;
                break;
            case 'w':
            case 'k':
                direction = UP;
                break;
            case 's':
            case 'j':
                direction = DOWN;
                break;
            case '\n':
                clearConsole();
                clearBuffer();
                gameToBuffer();
                drawFrame();
                continue;
            default:
                break;
        }

        switch (direction) {
            case UP:
                snakeMove(0, -1);
                break;
            case DOWN:
                snakeMove(0, 1);
                break;
            case LEFT:
                snakeMove(-1, 0);
                break;
            case RIGHT:
                snakeMove(1, 0);
                break;
        }
    }
}

int main() {
    init();
    tick();

    return 0;
}
