/*
 * TimeTest.c
 *
 * Created: 8/3/2020 2:29:59 PM
 *  Author: Tim
 */ 

#include "TimeTest.h"
#include "Timer.h"
#include <math.h>
#include <stdio.h>


//*********************************************************************
// Timed test case drivers
//*********************************************************************

int TimeDbl2op(double op1, double op2, FcnDbl2op_t *pfn, const char *psz)
{
	int t = TimeDbl2opQ(op1, op2, pfn);
	printf("%s result: %.18g, time: %i\n", psz, pfn(op1, op2), t);
	return t;
}

int TimeDbl2opQ(double op1, double op2, FcnDbl2op_t *pfn)
{
	int		t1, t2;

	StartTimer();
	Dbl2opEmpty(op1, op2);
	t1 = GetTime();

	StartTimer();
	pfn(op1, op2);
	t2 = GetTime();
	return t2 - t1;
}

//*********************************************************************

int TimeFlt2op(float op1, float op2, FcnFlt2op_t *pfn, const char *psz)
{
	int t = TimeFlt2opQ(op1, op2, pfn);
	printf("%s result: %.9g, time: %i\n", psz, pfn(op1, op2), t);
	return t;
}

int TimeFlt2opQ(float op1, float op2, FcnFlt2op_t *pfn)
{
	int		t1, t2;

	StartTimer();
	Flt2opEmpty(op1, op2);
	t1 = GetTime();

	StartTimer();
	pfn(op1, op2);
	t2 = GetTime();
	return t2 - t1;
}

//*********************************************************************

int TimeDbl1op(double op, FcnDbl1op_t *pfn, const char *psz)
{
	int t = TimeDbl1opQ(op, pfn);
	printf("%s result: %.18g, time: %i\n", psz, pfn(op), t);
	return t;
}

int TimeDbl1opQ(double op, FcnDbl1op_t *pfn)
{
	int		t1, t2;

	StartTimer();
	Dbl1opEmpty(op);
	t1 = GetTime();

	StartTimer();
	pfn(op);
	t2 = GetTime();
	return t2 - t1;
}

//*********************************************************************

int TimeFlt1op(float op, FcnFlt1op_t *pfn, const char *psz)
{
	int t = TimeFlt1opQ(op, pfn);
	printf("%s result: %.9g, time: %i\n", psz, pfn(op), t);
	return t;
}

int TimeFlt1opQ(float op, FcnFlt1op_t *pfn)
{
	int		t1, t2;

	StartTimer();
	Flt1opEmpty(op);
	t1 = GetTime();

	StartTimer();
	pfn(op);
	t2 = GetTime();
	return t2 - t1;
}
