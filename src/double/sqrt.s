
/*
 * sqrt.s
 *
 * Created: 11/15/2021 11:48:59 AM
 *  Author: Tim
 */ 

.syntax unified
.cpu cortex-m0plus
.thumb

.include "macros.inc"
.include "ieee.inc"
.include "options.inc"


//*********************************************************************
// macro to compute 64-bit square of 32-bit number
// pl can be same as x

.macro	sqr32	x, pl, ph, t1, t2
	uxth	\t1, \x
	muls	\t1, \t1	// t1 = low product
	uxth	\ph, \x
	lsrs	\t2, \x, #16
	muls	\ph, \t2	// ph = mid product
	muls	\t2, \t2	// t2 = hi product
	// add 2*mid product
	lsls	\pl, \ph, #17
	lsrs	\ph, \ph, #15
	adds	\pl, \t1
	adcs	\ph, \t2
.endm


// 64-bit IEEE floating-point square root
//
// Entry:
//	r1:r0 = input
// Exit:
//	r1:r0 = root
//
// The calculation will use Newton-Raphson iteration on inverse square root.
// The initial guess will be calculated by subtracting the upper mantissa bits
// from one of two constants -- one for [1, 2) and the other for [2, 4). The
// values were determined using a spreadsheet.
//
// [1, 2) Mlo = 1.2109375; Y0 = Mlo - X / 4; in hex, 0x9B p7 (0x9B / 0x80)
// [2, 4) Mhi = 0.96875;   Y0 = Mhi - X / 8; in hex, 0x7C p7 (0x7C / 0x80)
//
// The guess will have more than 4 bits of accuracy, allowing 4 iterations to
// get to the required accuracy. The notation p7 means there are 7 bits to the
// right of the binary point, and this notation is used throuout the comments.
//
// Mark Owen demonstrates in Qfplib (http://www.quinapalus.com) some clever
// arrangements that simplify the code for an iteration. First, the common
// representation of an iteration is refactored (x = input, y = guess for
// 1/sqrt(x)):
//
// next = 1.5*y - x*y^3/2  =  y - y*(x*y^2 - 1)/2
//
// Note that since y is a guess for 1/sqrt(x), the inner term x*y^2 will
// be close to 1. By computing this so the binary point is left of the
// 32-bit word, the integer portion just falls off.

.set	Mlo,	0x9B	// magic number for lo range, [1, 2)
.set	Mhi,	0x7C	// magic number for hi range, [2, 4)


	.func	__sqrt

.ifndef NO_DENORMALS
ZeroExp:
	// Is input zero?
	movs	r2, r1
	orrs	r2, r0
	beq	Exit
Denormal:
	// r1:r0 = input
	//
	// __dop1_normalize uses tailored calling convention
	// input: r1:r0 = op1
	// returns r4 = op1 exponent (< 0)
	// r5 trashed
	// all other registers preserved
	bl	__dop1_normalize
	b	Normalized
.endif

Special:
	lsls	r3, r1, #1	// strip sign
	bcc	Exit		// if not set, return input, +infinity or NAN
.ifdef NO_DENORMALS
	lsrs	r3, #MANT_BITS_HI64 + 1	// exponent tells if it's zero
.else
	orrs	r3, r0		// must be all zero to be zero
.endif
	beq	Exit		// input is -0, return it
	// negative input, return NAN
	ldr	r1, =#NAN64
	movs	r0, #0
Exit:
	pop	{r4-r7, pc}


ENTRY_POINT	__sqrt, sqrt
	push	{r4-r7, lr}
	ldr	r2, =INFINITY64
	cmp	r1, r2
	bhs	Special		// catch negative, infinity, NAN
	lsrs	r4, r1, #MANT_BITS_HI64	// input exponent
.ifdef NO_DENORMALS
	beq	Exit		// input == 0, return it
.else
	beq	ZeroExp
.endif
Normalized:
	lsls	r1, #EXP_BITS64
	lsrs	r1, #EXP_BITS64		// clear out exponent bits
	// Set implied bit
	movs	r2, #1
	lsls	r2, #MANT_BITS_HI64	// normalize, clearing exponent
	orrs	r1, r2

	// r1:r0 = input p52 (r1 p20)
	// r4 = exponent

	movs	r3, #Mlo	// assume [1, 2)
	lsrs	r2, r1, #15	// save top bits p5

	// Result exponent is current exponent / 2
	// Double the bias before halving. Implied bit position will get
	// added at end, so counteract it as well.
	ldr	r5, =#EXP_BIAS64 - 2
	adds	r4, r5
	asrs	r4, #1		// exp >>= 1
	bcc	1f		// was it even?
	lsl64const r0, r1, 1	// if not, shift left 1
	movs	r3, #Mhi	// input interval [2, 4)
1:
	// Compute guess by subtracting upper bits from magic number in r3
	subs	r3, r2
	lsls	r4, #MANT_BITS_HI64
	mov	r12, r4		// save final exponent

	// First iteration
	// r1:r0 = input p52 (r1 p20) interval [1, 4)
	// r3 = guess p7, accurate to 4 bits
	// r12 = final exponent
	lsrs	r2, r1, #2	// x p18
	muls	r2, r3		// x*y, p25
	muls	r2, r3		// x*y^2 p32
	// As described above, we now view r2 as signed and really have
	// x*y^2 - 1, p32
	asrs	r2, #9		// p23
	muls	r2, r3		// y*(x*y^2 - 1) p30 = y*(x*y^2 - 1)/2 p31
	lsls	r3, #24		// y p31
	subs	r3, r2		// y - y*(x*y^2 - 1)/2 p31
	lsrs	r3, #15		// p16

	// Do it again.
	movs	r2, r3		// y p16
	muls	r2, r2		// y^2 p32
	lsrs	r2, #14		// y^2 p18
	lsrs	r5, r1, #2	// x p18
	muls	r2, r5		// x*y^2 p36 => x*y^2 - 1 p36
	asrs	r2, #15		// p21
	muls	r2, r3		// y*(x*y^2 - 1) p37 = y*(x*y^2 - 1)/2 p38
	asrs	r2, #22		// p16
	subs	r3, r2		// y - y*(x*y^2 - 1)/2 p16
	// if result is exactly 1, reduce it so next y^2 doesn't overflow
	lsrs	r2, r3, #16	// integer bit to LSB
	subs	r3, r2		// if non-zero, subtract 1 to get 0xFFFF

	// Third iteration needs to preserve more accuracy
	// r1:r0 = x p52 (r1 p20, up to 2 integer bits)
	// r3 = y p16
	// r12 = final exponent
	movs	r2, r3		// y p16
	muls	r3, r2		// y^2 p32
	// collect upper 32 bits of input
	lsls	r1, #10
	lsrs	r5, r0, #32 - 10
	orrs	r1, r5		// x p30

	mul32x32 r3, r1, r3, r4, r5, r6, r7	// r4:r3 = x*y^2 p62
	// shift off the leading 1 and upper fraction bits
	lsrs	r3, #20
	lsls	r4, #32 - 20
	orrs	r3, r4		// x*y^2 - 1 p42
	// 32x16 multiply of above term with y p16
	// low 16 tossed, so result is p42*p16=p58 >> 16 = p42
	uxth	r4, r3
	muls	r4, r2
	asrs	r3, #16
	muls	r3, r2
	lsrs	r4, #16
	adds	r3, r4		// y*(x*y^2 - 1) p42 = y*(x*y^2 - 1)/2 p43
	asrs	r3, #12		// y*(x*y^2 - 1)/2 p31
	lsls	r2, #15		// y p31
	subs	r2, r3		// y - y*(x*y^2 - 1)/2 p31

	// For the fourth iteration, we refactor again, taking into account
	// that we don't want y (the next guess), but x*y (the actual root).
	// So it becomes:
	//
	// result = x*y - x*y*(x*y^2 - 1)/2  =  x*y - y*((x*y)^2 - x)/2
	// = x*y + y*(x - (x*y)^2)/2

	// r0 = x low bits, p52
	// r1 = x hi bits, p30 (10 bits overlap r0)
	// r2 = y p31
	// r12 = final exponent
	mul32x32hi r1, r2, r3, r5, r6, r7
	sqr32	r3, r4, r5, r6, r7	// r5:r4 = (x*y)^2 p58
	lsls	r6, r0, #6	// lo x p58
	lsrs	r7, r1, #4	// hi x p26
	subs	r6, r4
	sbcs	r7, r5		// x - (x*y)^2 p58
	// use lo result, but pull in a few upper bits
	lsrs	r6, #4
	lsls	r7, #32 - 4
	orrs	r6, r7		// x - (x*y)^2 p54
	mul32sx32 r6, r2, r6, r2, r4, r5, r7	// y*(x - (x*y)^2 p85 = (y*(x - (x*y)^2)/2 p86

	// r2 = (y*(x - (x*y)^2)/2 p54
	// r3 = x*y p29
	// r12 = final exponent
	lsrs	r4, r3, #9	// x*y hi bits p20
	lsls	r3, #32 - 9	// r4:r3 = x*y p52

	// Result will be accurate, but rounding is tricky because
	// the error, no matter how small, can straddle a rounding boundary.
	// First check to see if it does by looking at the rounding bit and
	// the guard bit below it:
	//
	// 00 - never round up
	// 01 - maybe round up
	// 10 - maybe round up
	// 11 - always round up
	//
	// This is tested by adding 1 to the guard bit. This will leave the
	// rounding and guard bits:
	//
	// 01 - never round up
	// 10 - maybe round up
	// 11 - maybe round up
	// 00 - already rounded up
	//
	// So if the round bit ends up 1, we need to calculate the final 
	// remainder for rounding.

	adds	r2, #1		// add to guard bit at p54
	asrs	r1, r2, #31	// sign extend
	asrs	r2, #2		// low bits p52
	bcs	ComputeRemainder
	adds	r0, r2, r3
	adcs	r1, r4
	add	r1, r12
	pop	{r4-r7, pc}

ComputeRemainder:
	// Add 1/2 LSB to result, then see if that's too big or too small by
	// squaring it and comparing with x. Only low bits need comparing, the
	// upper ones must be the same.
	adds	r2, r3
	adcs	r1, r4		// r1:r2 = unrounded root
	movs	r5, r1
	lsls	r3, r2, #1
	adcs	r5, r5		// r5:r3 = root p53 (r5 p21)
	adds	r3, #1		// bump by half a bit
	// root * root requires mid and low products
	muls	r5, r3		// mid product p74
	sqr32	r3, r3, r4, r6, r7	// r4:r3 = (root + 0.5)^2 p106 (r4 p74)
	adds	r4, r5		// sum mid + upper lo
	adds	r4, r5		// mid used twice
	lsls	r3, r0, #22	// x p74 (10 bits left)
	subs	r4, r3		// (root + 0.5)^2 - x
	asrs	r4, #31		// extend sign of result
	subs	r0, r2, r4	// add 1 if negative
	sbcs	r1, r4
	add	r1, r12
	pop	{r4-r7, pc}

	.endfunc
