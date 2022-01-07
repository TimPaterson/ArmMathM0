/*
 * main.c
 *
 * Created: 6/14/2021 2:40:54 PM
 * Author : Tim
 */ 


#include "stdio.h"
#include "TimeTest.h"
#include "qfplib-full/qfplib-m0-full.h"
#include <math.h>

#undef getchar	// let's use function version

//*********************************************************************
// Hardware Interface
//*********************************************************************

// The following functions must be implemented in the hardware file
// The pointer passed to ReadByte and WriteByte is for their internal
// use and can be ignored.
void HardwareInit();
void WriteByte(void *pv, char c);
int ReadByte(void *pv);
// These two are expected to be inline in Timer.h
void StartTimer();
uint16_t GetTime();

// Set up a FILE struct that does I/O to the hardware device
FILE SerialIo = FDEV_SETUP_STREAM(WriteByte, ReadByte, _FDEV_SETUP_RW);

FDEV_STANDARD_STREAMS(&SerialIo, &SerialIo);	// stdout, stdin

//*********************************************************************
// Types for special tests
//*********************************************************************

typedef union
{
	float	f;
	int		i;
} fltint;

typedef union
{
	double		d;
	long long	l;
} dblint;

//*********************************************************************
// Main program
//*********************************************************************

int main(void)
{
    HardwareInit();

	printf("\nStarting up\n");
    while (1)
    {
		// Specific tests can be added here
		//TimeDbl1op(1.3, sqrt, "sqrt");

		while (1)
		{
			char	ch;

			ch = getchar();
			if (ch == ':')
				ReceiveCase(TIME_TEST);

			else if (ch == ' ' || ch == '\r')
				break;	// do tests again
		}
    }
}
