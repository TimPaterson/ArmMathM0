//****************************************************************************
// fixed_dividef.s
//
// Created 5/1/2026 10:26:11 AM by Tim Paterson
//
//****************************************************************************

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"


	.global	__fixed_dividef

//*********************************************************************
// Fast fixed-point division
//
// Entry:
//	r0 = dividend p30
//	r1 = divisor x, 0.5 < x < 4 p30 (or 0.25 < x < 2 p31)
// Exit:
//	r0 = dividend / divisor p31
//
// p30 => 30 bits to right of binary point
//
//*********************************************************************

.set	GuessBase,	8
.set	GuessMax,	63	// max < 4


	.func	__fixed_dividef
__fixed_dividef:
	// r0 = y (dividend)
	// r1 = x (divisor)
	//
	// First compute 1/x for 0.5 < x < 4. That's a wide range so
	// we'll use a lookup table to get an estimate for Newton-Raphson
	// iteration of reciprocal.
	adr	r3, ReciprocalGuess - GuessBase
	lsrs	r2, r1, #32 - 6	// use top 6 bits
	ldrb	r2, [r2, r3]	// guess accurate to 4 bits p7

.if 1
	// Start Newton-Raphson iterations
	// error e = guess*x - 1
	// next = guess - guess*e
	//
	// r0 = y p30
	// r1 = x p30
	// r2 = guess p7
	lsrs	r3, r1, #5	// x p25
	muls	r3, r2		// e = guess * x - 1 p32
	asrs	r3, #7		// e p25
	muls	r3, r2		// guess * e p32
	asrs	r3, #17		// guess * e p15
	lsls	r2, #8		// guess p15
	subs	r2, r3		// guess -= guess * e = new guess p15

	// round two, gets us to 16 bits
.else
	// First round uses a cubic iteration, triples us to 12 bits
	// error e = guess*x - 1
	// next = guess - guess*(e - e^2)
	//
	// r0 = y p30
	// r1 = x p30
	// r2 = guess p7
	mov	r12, r0
	lsrs	r3, r1, #5	// x p25
	muls	r3, r2		// e = guess * x - 1 p32
	asrs	r0, r3, #16	// e p16
	muls	r0, r0		// e^2 p32
	subs	r3, r0		// e - e^2 p32
	asrs	r3, #7		// e - e^2 p25
	muls	r3, r2		// guess*(e - e^2) p32
	asrs	r3, #17		// guess*(e - e^2) p15
	lsls	r2, #8		// guess p15
	subs	r2, r3		// guess -= guess*(e - e^2) = new guess p15
	mov	r0, r12

	// For round 2 use Newton-Raphson iteration
.endif
	// error e = guess*x - 1
	// next = guess - guess*e
	// Gets us to 16 bits
	lsrs	r3, r1, #13	// x p17
	muls	r3, r2		// e = x*guess - 1 p32
	asrs	r3, #15		// e p17
	muls	r3, r2		// guess*e p32
	asrs	r3, #17		// guess*e p15
	subs	r2, r3		// final approximation of 1/x p15

	// r0 = y p30
	// r1 = x p30
	// r2 = approximation of 1/x p15
	//
	// q0 = y*guess, rough quotient (14+ bits)
	// rem = y - q0*x, exact remainder from q0
	// q1 = guess*rem, quotient from remainder (approx rem/x)
	// quo = q0 + q1
	asrs	r3, r0, #15	// y p15
	muls	r3, r2		// y*guess = approx quotient q0 p30
	asrs	r3, #15		// q0 p15
	lsrs	r1, #2		// x p28
	muls	r1, r3		// x*q0 p43
	lsls	r0, #13		// y p43
	subs	r0, r1		// y - x*q0 = rem p43
	asrs	r0, #14		// rem p29
	muls	r0, r2		// rem*guess = q1 p44
	lsls	r3, #16		// q0 p31
	asrs	r0, #13		// q1 p31
	adcs	r0, r3		// q = q0 + q1 with rounding p31
	bx	lr

	.endfunc


.macro	CalcGuess	index, max
	.byte		(0x2000/((\index) + (\index) + 1) + 1) / 2
.if	(\index) < \max
	CalcGuess	(\index) + 1, \max
.endif
.endm

	.align	2
ReciprocalGuess:
	CalcGuess	GuessBase, GuessMax
