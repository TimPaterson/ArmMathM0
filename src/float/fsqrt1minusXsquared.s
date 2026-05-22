//****************************************************************************
// fsqrt1minusXsquared.s
//
// Created 5/21/2026 10:44:32 AM by Tim Paterson
//
//****************************************************************************

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"


	.global	__fsqrt1minusXsquared

//*********************************************************************
// Computes sqrt(1 - x^2) for x near 1 (0.5 < x < 1).
// This turns a sine into a cosine and vice versa.
//
// WARNING!!: This function does not follow the standard
// calling convention!
//
// To maintain precision, the calculation uses
//
// x = 1 - d
// 1 - x^2 = 1 - (1 - d)^2 = 1 - (1 - 2d + d^2) = 2d - d^2
//
// Entry:
//	r1 = mantissa, implied bit set p32
// Exit:
//	r1 = result mantissa
//	r2 = exponent
//	r0, r3, r4 are destroyed
//*********************************************************************

.set	Mlo,	0x9B	// magic number for lo range, [1, 2)
.set	Mhi,	0x7C	// magic number for hi range, [2, 4)

	.func	__fsqrt1minusXsquared

__fsqrt1minusXsquared:
	negs	r1, r1		// d = 1 - x p32 (= 2d p31)
	movs	r2, #0		// -exponent
Normalize:
	adds	r2, #1
	adds	r1, r1
	bpl	Normalize
	// compute d^2 from 2 partial products
	lsrs	r3, r1, #16	// hi p16
	uxth	r0, r1		// lo p32
	muls	r0, r3		// hi * lo p48
	lsrs	r0, #16		// hi * lo p32 => 2 * hi * lo p31
	muls	r3, r3		// hi * hi p32
	lsrs	r3, #1		// p31
	adds	r3, r0		// d^2 p31
	lsrs	r3, r2
	subs	r1, r3		// 2d - d^2 p31
	bmi	StillNorm
	adds	r2, #1
	adds	r1, r1
StillNorm:
	// perform sqrt() as in sqrtf.s
	// r2 = -exponent
	// r1 = input mantissa with implied bit set, p31
	negs	r2, r2
	movs	r3, #Mhi	// assume [2, 4)
	lsrs	r0, r1, #26	// save top bits [1, 2) p5

	// exp >>= 1
	asrs	r2, #1
	bcs	1f		// was it odd?
	lsrs	r1, #1		// if not, add leading zero
	movs	r3, #Mlo	// input interval [1, 2)
1:
	// Compute guess by subtracting upper bits from magic number in r3
	subs	r3, r0

	// First iteration
	// r2 = exponent
	// r1 = input p30
	// r3 = guess p7, accurate to 4 bits
	lsrs	r0, r1, #12	// x p18
	muls	r0, r3		// x*y, p25
	muls	r0, r3		// x*y^2 p32
	// As described above, we now view r0 as signed and really have
	// x*y^2 - 1, p32
	asrs	r0, #9		// p23
	muls	r0, r3		// y*(x*y^2 - 1) p30 = y*(x*y^2 - 1)/2 p31
	lsls	r3, #24		// y p31
	subs	r3, r0		// y - y*(x*y^2 - 1)/2 p31
	lsrs	r3, #16		// p15

	// Do it again.
	movs	r0, r3		// y p15
	muls	r0, r0		// y^2 p30
	lsrs	r0, #13		// y^2 p17
	lsrs	r4, r1, #15	// x p15
	muls	r0, r4		// x*y^2 p32
	asrs	r0, #10		// p22
	muls	r0, r3		// y*(x*y^2 - 1) p37 = y*(x*y^2 - 1)/2 p38
	asrs	r0, #23		// p15
	subs	r3, r0		// y - y*(x*y^2 - 1)/2 p15

	// For the third iteration, we refactor again, taking into account
	// we don't want y (the next guess), but x*y (the actual root).
	// So it becomes:
	//
	// result = x*y - x*y*(x*y^2 - 1)/2  =  x*y - y*((x*y)^2 - x)/2
	// = x*y + y*(x - (x*y)^2)/2

	// last iteration left x p15 in r4
	muls	r4, r3		// x*y p30, approximate sqrt(x)
	lsrs	r4, #14		// x*y p16
	movs	r0, r4
	muls	r0, r0		// (x*y)^2 p32
	// With binary point at p32, we've dropped the integer bits.
	lsls	r1, #2		// drop upper bits on x as well, p32
	subs	r1, r0	// x - (x*y)^2 p32 = (x - (x*y)^2)/2 p33
	// The next step is to finish calculating the error term that will
	// be added to the root. Since our guess is pretty close by now,
	// the upper bits of this term are zero and we can use a binary
	// point well past 32 bits.
	asrs	r1, #6		// (x - (x*y)^2)/2 p27
	muls	r1, r3		// y*(x - (x*y)^2)/2 p42
	lsls	r4, #15		// x*y p31
	asrs	r1, #11		// y*(x - (x*y)^2)/2 p31
	adcs	r1, r4		// root p31
	adds	r2, #1
	bx	lr

	.endfunc
