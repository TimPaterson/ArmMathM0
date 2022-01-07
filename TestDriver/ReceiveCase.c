/*
 * ReceiveCase.c
 *
 * Created: 8/3/2020 3:31:36 PM
 *  Author: Tim
 */ 


#include "TimeTest.h"
#include "stdio.h"
#include <math.h>

#undef getchar	// let's use function version

// Receive test case from stdin.
// Input format:
//
// :tn <hex> <hex> o
//  ^^   ^     ^   ^
//  ||   |     |   \- operation char: +, -, *, /, # (sqrt)
//  ||   |     \- 2nd argument if required
//  ||   \- first argument, hex IEEE float or double
//  |\- number of arguments, 1 or 2
//  \- type, f = float, d = double
//
// Test may be followed by newline as everything up to next
// colon is ignored.


typedef union
{
	uint64_t	u64;
	float		f;
	double		d;
} AllTypes;


void ReceiveCase(bool fTime)
{
	int			typ;
	int			cArgs;
	int			op;
	unsigned	t;
	AllTypes	arg1;
	AllTypes	arg2;

	t = 0;
	typ = getchar();
	cArgs = getchar();

	scanf(" %llx ", &arg1.u64);
	if (cArgs == '2')
		scanf("%llx ", &arg2.u64);

	op = getchar();

	switch (typ)
	{
	case 'f':
		switch (cArgs)
		{
			case '1':
			{
				FcnFlt1op_t	*pfn;

				switch (op)
				{
				case '#':	// square root
					pfn = FSQRT;
					break;

				default:
					goto Exit;
				}

				if (fTime)
					t = TimeFlt1opQ(arg1.f, pfn);
				arg1.f = pfn(arg1.f);
			}
			break;

			case '2':
			{
				FcnFlt2op_t	*pfn;

				switch (op)
				{
				case '+':	// add
					pfn = FADD;
					break;

				case '-':	// subtract
					pfn = FSUB;
					break;

				case '*':	// multiply
					pfn = FMUL;
					break;

				case '/':	// divide
					pfn = FDIV;
					break;

				default:
					goto Exit;
				}

				if (fTime)
					t = TimeFlt2opQ(arg1.f, arg2.f, pfn);
				arg1.f = pfn(arg1.f, arg2.f);
			}
		}
	break;

	case 'd':
		switch (cArgs)
		{
			case '1':
			{
				FcnDbl1op_t	*pfn;

				switch (op)
				{
				case '#':	// square root
					pfn = DSQRT;
					break;

				default:
					goto Exit;
				}

				if (fTime)
					t = TimeDbl1opQ(arg1.d, pfn);
				arg1.d = pfn(arg1.d);
			}
			break;

			case '2':
			{
				FcnDbl2op_t	*pfn;

				switch (op)
				{
				case '+':	// add
					pfn = DADD;
					break;

				case '-':	// subtract
					pfn = DSUB;
					break;

				case '*':	// multiply
					pfn = DMUL;
					break;

				case '/':	// divide
					pfn = DDIV;
					break;

				default:
					goto Exit;
				}

				if (fTime)
					t = TimeDbl2opQ(arg1.d, arg2.d, pfn);
				arg1.d = pfn(arg1.d, arg2.d);
			}
		}
		break;
	}

Exit:
	// Send back results
	if (fTime)
		printf("@%llx T%u\n", arg1.u64, t);
	else
		printf("@%llx\n", arg1.u64);
}
