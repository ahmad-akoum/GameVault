#include "../windows/runner/input_activity.h"
#include "../windows/runner/dualsense_activity.h"
#include <cassert>
#include <iostream>
int main() {
  for (int mode=0;mode<4;++mode) {
    unsigned char r[78]{};
    const size_t size=mode==0?64:mode==1?10:78;
    r[0]=mode==2?0x31:0x01;
    const size_t a=mode==2?2:1, b=mode==2?9:mode==0?8:5, t=mode==2?6:mode==0?5:8;
    for(int i=0;i<4;++i)r[a+i]=128;
    r[b]=8;
    ControllerActivity activity;
    auto observe=[&](){ControllerSample s;assert(DecodeDualSense(r,size,s));return activity.Observe(s,{24,24,24,24},4,30,4);};
    assert(!observe());
    r[b+1]=1; assert(observe());
    for(int i=0;i<1000;++i){r[b+2]=static_cast<unsigned char>(i & 0xfc);assert(!observe());}
    r[b+1]=0;assert(observe());assert(!observe());
    for(int i=0;i<100;++i){r[a]=static_cast<unsigned char>(127+i%3);assert(!observe());}
    r[a]=170;assert(observe());r[a]=172;assert(!observe());r[a]=180;assert(observe());
    r[a]=128;assert(observe());
    r[t]=80;assert(observe());assert(!observe());r[t]=82;assert(!observe());r[t]=100;assert(observe());r[t]=0;assert(observe());
    r[b]=0;assert(observe());assert(!observe());r[b]=8;assert(observe());
  }
  ControllerActivity xinput;
  ControllerSample s; const std::array<int,4> zones{7849,7849,8689,8689};
  assert(!xinput.Observe(s,zones,1024,30,4));
  s.axes[0]=9000; assert(xinput.Observe(s,zones,1024,30,4));
  for(int i=0;i<100;++i){s.axes[0]=9000+i%200;assert(!xinput.Observe(s,zones,1024,30,4));}
  s.buttons=1;assert(xinput.Observe(s,zones,1024,30,4));assert(!xinput.Observe(s,zones,1024,30,4));
  s={};assert(xinput.Observe(s,zones,1024,30,4));xinput.Reset();assert(!xinput.Observe(s,zones,1024,30,4));
  MouseActivity mouse;
  assert(!mouse.Observe(false,0,0,0));assert(mouse.Observe(false,1,0,0));
  assert(mouse.Observe(false,0,0,1));assert(mouse.Observe(false,0,0,0x400));
  assert(!mouse.Observe(true,32000,32000,0));assert(!mouse.Observe(true,32000,32000,0));assert(mouse.Observe(true,32001,32000,0));
  assert(ObservedIdleSeconds(70000,10000,0,0)==60);
  assert(ObservedIdleSeconds(72000,10000,0,0)==62);
  assert(ObservedIdleSeconds(72000,71000,0,0)==1);
  assert(ObservedIdleSeconds(72000,10000,70000,0)==2);
  assert(ObservedIdleSeconds(72000,10000,0,71000)==1);
  std::cout<<"Input activity tests passed: unchanged states, noise, all DualSense layouts, XInput, mouse and idle clock\n";
}
