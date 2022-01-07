/*
 * Timer.h
 *
 * This is the hardware timer for Microchip SAM C MCUs
 *
 * Created: 8/3/2020 2:48:27 PM
 *  Author: Tim
 */ 


#ifndef TIMER_H_
#define TIMER_H_

#include "sam.h"


//****************************************************************************
// Timer
//****************************************************************************

inline void StartTimer()
{
	while (TC0->COUNT16.SYNCBUSY.reg);
	TC0->COUNT16.CTRLBSET.reg = TC_CTRLBSET_CMD_RETRIGGER;
}

inline uint16_t GetTime()
{
	int		res;

	TC0->COUNT16.CTRLBSET.reg = TC_CTRLBSET_CMD_READSYNC;
	while (TC0->COUNT16.SYNCBUSY.reg);
	res = TC0->COUNT16.COUNT.reg;
	TC0->COUNT16.CTRLBSET.reg = TC_CTRLBSET_CMD_STOP;
	return res;
}


#endif /* TIMER_H_ */