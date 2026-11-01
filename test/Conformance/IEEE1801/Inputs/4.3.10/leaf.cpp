#include <systemc.h>
SC_MODULE(leaf) {
  sc_out<sc_logic> q;
  void drive() { q.write(SC_LOGIC_1); }
  SC_CTOR(leaf) { SC_METHOD(drive); }
};
