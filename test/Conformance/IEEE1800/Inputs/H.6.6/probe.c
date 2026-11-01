static char buf[]="ab";
const char*f(void){return buf;}
void mutate(void){buf[0]='z';}
