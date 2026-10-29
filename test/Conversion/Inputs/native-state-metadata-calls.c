#include <stdint.h>

void metadata_sink(uint8_t *counter) { ++*counter; }
void state_sink(uint8_t *state, uint8_t value) { *state = value; }
