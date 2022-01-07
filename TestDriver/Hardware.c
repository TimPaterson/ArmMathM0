/*
 * Hardware.c
 *
 * This is the hardware interface for Microchip SAM C MCUs
 *
 * Created: 1/7/2022 11:13:38 AM
 *  Author: Tim
 */ 


#include "sam.h"
#include "sam_spec.h"
#include "TimeTest.h"


// Set up clock speed
#if TIME_TEST
#define	SLOW_CLOCK	// go slow enough for no wait states
#define F_CPU		16000000
#else
#define F_CPU		48000000
#endif

// Serial I/O
// If you change SERCOM number, you still must manage the pin MUX yourself.
#define BAUD_RATE	500000
#define SERCOM_NUM	3		// must be a literal digit, not an expression
//#define SERCOM_NUM	1		// must be a literal digit, not an expression
// helper macros
#define __SERIAL_OUT(port)	SERCOM##port
#define _SERIAL_OUT(port)	__SERIAL_OUT(port)
#define SERIAL_OUT			_SERIAL_OUT(SERCOM_NUM)
#define __SERCOM_GCLK(port)	SERCOM##port##_GCLK_ID_CORE
#define _SERCOM_GCLK(port)	__SERCOM_GCLK(port)
#define SERCOM_GCLK_ID		_SERCOM_GCLK(SERCOM_NUM)
#define __SERCOM_MCLK(port)	MCLK_APBCMASK_SERCOM##port
#define _SERCOM_MCLK(port)	__SERCOM_MCLK(port)
#define SERCOM_MCLK			_SERCOM_MCLK(SERCOM_NUM)

//*********************************************************************
// Initialization Helpers
//*********************************************************************

enum RxPad
{
	RXPAD_Pad0,
	RXPAD_Pad1,
	RXPAD_Pad2,
	RXPAD_Pad3
};

enum TxPad
{
	TXPAD_Pad0,
	TXPAD_Pad2,
	TXPAD_Pad0_RTS_Pad2_CTS_Pad3,
	TXPAD_Pad0_TE_Pad2
};

//*********************************************************************

void StartClock()
{
#ifdef SLOW_CLOCK
	OSCCTRL->CAL48M.reg = NVM_SOFTWARE_CAL->CAL48M_5V;
	OSCCTRL->OSC48MDIV.reg = 3 - 1;	// divide by 3 for 16 MHz
#else
	// Two wait states needed for 48MHz operation
	NVMCTRL->CTRLB.reg = NVMCTRL_CTRLB_RWS(2) | NVMCTRL_CTRLB_MANW;

	// Initialize 48MHz clock
	OSCCTRL->CAL48M.reg = NVM_SOFTWARE_CAL->CAL48M_5V;
	OSCCTRL->OSC48MDIV.reg = 0;		// Bump it to 48 MHz
#endif
}

//*********************************************************************

uint16_t CalcBaudRate(uint32_t rate, uint32_t clock)
{
	uint32_t	quo;
	uint32_t	quoBit;

	rate *= 16;		// actual clock frequency
	// Need 17-bit result of rate / clock
	for (quo = 0, quoBit = 1 << 16; quoBit != 0; quoBit >>= 1)
	{
		if (rate >= clock)
		{
			rate -= clock;
			quo |= quoBit;
		}
		rate <<= 1;
	}
	// Round
	if (rate >= clock)
		quo++;
	return (uint16_t)-quo;
}

//*********************************************************************

void HardwareInit()
{
	StartClock();

	// Set up serial port

	SERCOM_USART_CTRLA_Type	serCtrlA;

	// Enable clock
	MCLK->APBCMASK.reg |= SERCOM_MCLK;

	// Clock it with GCLK0
	GCLK->PCHCTRL[SERCOM_GCLK_ID].reg = GCLK_PCHCTRL_GEN_GCLK0 |
		GCLK_PCHCTRL_CHEN;

	// This must be changed if SERCOM number is changed or 
	// alternate pins are used.
	PORT->Group[0].WRCONFIG.reg =
			PORT_WRCONFIG_WRPMUX |
			PORT_WRCONFIG_PMUX(MUX_PA24C_SERCOM3_PAD2) |
			PORT_WRCONFIG_PMUXEN |
			PORT_WRCONFIG_WRPINCFG |
			PORT_WRCONFIG_HWSEL |	// using pins in upper half (PA16 - PA31)
#if SERCOM_NUM == 3
			PORT_WRCONFIG_PINMASK((PORT_PA24 | PORT_PA25) >> 16);
#else
			PORT_WRCONFIG_PINMASK((PORT_PA16 | PORT_PA17) >> 16);
#endif

	SERIAL_OUT->USART.BAUD.reg = CalcBaudRate(BAUD_RATE, F_CPU);

	// standard 8,N,1 parameters
	serCtrlA.reg = 0;
	serCtrlA.bit.DORD = 1;		// LSB first
	serCtrlA.bit.MODE = 1;		// internal clock
#if SERCOM_NUM == 3
	serCtrlA.bit.RXPO = RXPAD_Pad3;
	serCtrlA.bit.TXPO = TXPAD_Pad2;
#else
	serCtrlA.bit.RXPO = RXPAD_Pad1;
	serCtrlA.bit.TXPO = TXPAD_Pad0;
#endif
	serCtrlA.bit.ENABLE = 1;
	SERIAL_OUT->USART.CTRLA.reg = serCtrlA.reg;
	SERIAL_OUT->USART.CTRLB.reg = SERCOM_USART_CTRLB_TXEN | SERCOM_USART_CTRLB_RXEN;

	// Set up counter to time execution

	MCLK->APBCMASK.reg |= MCLK_APBCMASK_TC0;
	GCLK->PCHCTRL[TC0_GCLK_ID].reg = GCLK_PCHCTRL_GEN_GCLK0 | GCLK_PCHCTRL_CHEN;
	TC0->COUNT16.CTRLA.reg = TC_CTRLA_ENABLE;
	TC0->COUNT16.CTRLBSET.reg = TC_CTRLBSET_CMD_STOP;
}

//*********************************************************************
// Device File I/O
//*********************************************************************

void WriteByte(void *pv, char c)
{
	if (c == '\n')
		WriteByte(pv, '\r');
	while (!SERIAL_OUT->USART.INTFLAG.bit.DRE);
	SERIAL_OUT->USART.DATA.reg = c;
}

inline bool IsByteReady()
{
	return SERIAL_OUT->USART.INTFLAG.bit.RXC;
}

int ReadByte(void *pv)
{
	while (!IsByteReady());
	return SERIAL_OUT->USART.DATA.reg;
}

